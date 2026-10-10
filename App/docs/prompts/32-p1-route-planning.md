# Prompt 32 (P1): route planning v1, `POST /routes/plan` and Ask `plan_route`

You are the builder for **one backend step** of KilnWatch: a real inspection route for a district, using road travel times from Amazon Location Service, in the route contract the iOS Today tab already reads. Ask gets a `plan_route` tool on top of it.

You build, test and deploy. You do not orchestrate. Work sequentially in this one chat. No sub-agents. Do not commit, push or stage.

## The go (scope)

The user gave the go by running this prompt. It covers **exactly** this:
1. **Preflight: already done** in the first run (it passed; the results are in `.local/phase-4/p1/`). Don't repeat it. At most 1 extra Amazon Location call, only if you need to check a response shape.
2. Local code and tests in the files listed under "Files".
3. **One** Terraform plan and apply that **adds** the route planner (a Lambda, its role and policy, a log group, the API integration, route and permission) and changes **only** the API stage's route settings for the new route, plus `aws_lambda_function.assistant[0]` (the code hash). Nothing else may change or be destroyed.
4. One line in the ignored `AWS/terraform.tfvars`: `enable_route_planner = true`. Back up the file first, to `.local/phase-4/terraform.tfvars.pre-p1`.
5. At most **6** live `POST /routes/plan` calls and at most **6** live `/ask` questions.

**Stop and report, without building further, if:**
- the worst-case cost at the daily cap is over **$20 a month** (see Step 1);
- the plan contains anything else.

No IAM widening beyond the two `geo-routes` actions named below. No change to the provider lock (`hashicorp/aws 6.68.0`). No untargeted surprises and no `destroy`.

## Rules

- **The repo is public.** Never write into tracked files, or print, either account ID, any ARN, the API URL or ID, the CloudFront domain or ID, the bucket name, the RDS host or emails. Read them from the `.local/` outputs and the ignored tfvars into shell variables. Use placeholders in docs.
- **Product language.** Never "illegal", "unlawful" or any word starting "violat" in user-facing text. A kiln is "flagged by satellite, pending inspection". A rule hit is a siting signal. ETAs are **estimates** from road travel times without live traffic. An access point is the kiln centroid, **not** a verified entrance. Missing exposure is never zero.
- **Credentials:** the `kilnwatch` profile; Terraform at `.local/tools/terraform/terraform` with `aws configure export-credentials --profile kilnwatch --format env`. Sign-ins only in the user's own terminal.
- Request approval for the specific network or AWS commands that need it. Never use a "full access" mode.

## Files

You may touch only:
- **new:** `AWS/route/` (the planner package), `AWS/route.tf`, `AWS/scripts/package_route.py`, `AWS/tests/test_route.py`;
- `AWS/variables.tf` (new variables only), `AWS/outputs.tf` (a non-secret output only, if needed), `AWS/api.tf` (the stage route settings only, if that's where they live);
- `AWS/assistant/`, `AWS/assistant.tf` (only the environment variable for the route URL, if needed), `AWS/scripts/package_assistant.py`, `AWS/tests/test_assistant.py`;
- `AWS/docs/local-verification.md` and `App/docs/api-contract.md`;
- anything under the ignored `.local/`.

Do **not** touch `App/` (other than the API contract), the registry, the rules engine or the API Lambda.

## Step 0: read first

1. `AGENTS.md`, then `App/docs/plan-final-stretch.md` §2 "P1".
2. `App/docs/api-contract.md`: `GET /routes/today` (the route JSON, the "Phase 2 optional additions": `route_id`, `depart`, `budget_min`, `service_min`, `access`, `legs`) and the R1 section.
3. `App/Packages/KilnWatchCore/Sources/KilnWatchCore/Models.swift` (`Route`, `Stop`, `InspectionSheet`, `RoadAccess`, `RouteLeg`, `RouteGeometry`) and `Fixtures/route_today.json`. **The output must decode into these exact types.** Note that `InspectionSheet.peopleExposed` is a required `Int`.
4. `AWS/assistant/{core,tools,validator,handler}.py` and `AWS/assistant.tf`: the pattern to copy (Lambda outside the VPC, reads the public API, an atomic DynamoDB daily counter, privacy-safe logs, nested `{"error":{code,message,retryable}}` errors).
5. The Amazon Location Routes v2 docs for `CalculateRouteMatrix` and `CalculateRoutes`: the request limits, `RoutingBoundary`, which options keep a request in the **Core** pricing tier, and the IAM actions and resource. Also the Routes pricing page.

## Step 1: preflight and cost (the preflight is done; recheck the cost only)

**The user's decision after the first run (option A):** at most **8** kilns per plan and a daily cap of **15** plans. The matrix is (start + 8 kilns) origins × 8 kilns destinations = **72 cells**, which fits the Unbounded limits (≤ 15 origins, ≤ 100 cells), so no `RoutingBoundary` geometry is needed. That is about $0.0365 a plan and $16.43 a month at the worst case. The start is never a destination, because there is no return leg.


1. (Done in the first run; for reference only.) With the AWS CLI (`aws geo-routes …`, `--region ap-south-1`, `--profile kilnwatch`), make a 2×2 `calculate-route-matrix` call between two real Hapur kiln centroids (from the public API), travel mode Car, Core-tier options only. Then one `calculate-routes` call with 3 waypoints, asking for the leg geometry. Save the responses to `.local/phase-4/p1/` and report the durations and distances.
2. **Cost.** Restate it with these numbers: a 9 × 8 matrix plus one `CalculateRoutes` call per plan, at a cap of 15 plans a day for 30 days. **Stop if it is over $20 a month.**

## Step 2: the planner (pure Python, no new dependencies)

`AWS/route/`, with the handler and the solver split so the solver can be tested without AWS:

**Request:** `POST /routes/plan`, JSON body:
- `district` (required, same validation as the public API);
- `start` `{lat, lon}` (optional; the default is the mean of the selected kilns' centroids, labelled in the response as "Default start: centre of the selected kilns");
- `depart` (optional RFC 3339; the default is tomorrow 09:00 Asia/Kolkata);
- `budget_min` (optional, 60–720, default 480);
- `max_stops` (optional, 1–8, default 8);
- `priority`: `"people"` (default: most people within 800 m first) or `"flags"` (most siting flags first, then people). **There is no "schools first":** no Hapur kiln has a school flag today (every school check is inconclusive), so it would be misleading;
- `kiln_ids` (optional, ≤ 8 full IDs; when given, plan exactly these, no selection).

Unknown keys, a bad shape, or a body over 4 KB give 400 `invalid_request`.

**Plan:**
1. Read the district's kilns from the public API (as the assistant does). Kilns with `exposure: null` are never ranked as zero: they go last under `people`, and are excluded if the sheet would need a number (report how many). Today all 39 have exposure.
2. Choose candidates by priority (at most 8), get one Core-tier, Unbounded matrix with origins = start + candidates and destinations = candidates (Car, no traffic; never more than 100 cells), then order them with nearest-neighbour + 2-opt on driving time. Add a fixed `service_min` of 35 per stop. Drop the lowest-priority stop and re-solve until the total (driving plus service) fits `budget_min` and the count is ≤ `max_stops`. It must be deterministic: same input, same output. No OR-Tools.
3. One `CalculateRoutes` call over the final order for the leg distances, durations and geometry. If that call fails, return the plan **without** `legs` rather than fail, because the contract allows that.
4. **Response (exactly the route contract):**
   - `district`, `generated_at`, `route_id` (e.g. `plan-<date>-<district>-<short hash of the inputs>`), `depart`, `budget_min`;
   - `stops[]`: `order` (1-based), `kiln_id`, `eta` (RFC 3339, `+05:30`), `service_min`, `access` `{lat, lon, note: "Kiln centroid, not a verified entrance · confirm on site"}`, and `sheet`:
     - `rules_flagged`: the rule IDs in `violations`;
     - `people_exposed`: the exposure count;
     - `on_site_checks`: a short fixed list from the flags, for example "Distance to the nearest home" for C-HAB-800, "Distance to the nearest kiln" for C-KILN-1K, "Distance to the national highway" for UP-NH-300, "Distance to the railway" for UP-RAIL-200, plus always "Kiln type: fixed chimney or zigzag" and "Is the kiln firing?". P2 will enrich this; don't build P2 here.
   - `legs[]`: one per stop including start-to-first, with `to_kiln_id`, `distance_m`, `duration_s`, and `geometry` as a GeoJSON LineString `[lon, lat]`, simplified to at most ~200 points per leg;
   - `kilns[]`: the full **public** records of the stops;
   - one extra top-level `notes` array of plain strings: the default start (when used), that ETAs come from road times without live traffic, and that the kilns are flagged by satellite and pending inspection. Check that the app tolerates unknown keys; if it doesn't, leave `notes` out and put the notes in the contract instead.
5. **Errors:**
   - 400 `invalid_request`;
   - 404 `no_kilns` (nothing flagged in that district, or no `kiln_ids` found);
   - 429 `daily_cap_reached`;
   - 503 `routing_unavailable` (Amazon Location failed) or `upstream_unavailable` (the public API failed).
   - Never echo provider error text.
6. **Cap:** reuse the assistant's DynamoDB daily-counter pattern. Use either the same table with a distinct key (`route#YYYY-MM-DD`) or a new table, whichever needs the smaller IAM grant. Cap = `var.route_daily_cap`, default **15**.
7. **Logs:** counts and latencies only (stops, matrix cells, Location ms, total ms). No coordinates, kiln lists or bodies.

## Step 3: infrastructure (`AWS/route.tf`)

- Gated by `var.enable_route_planner` (default `false`).
- Lambda `kilnwatch-route`: Python 3.12, outside the VPC, ~15 s timeout, environment `PUBLIC_API_BASE_URL`, the counter table and the cap.
- **Its own role:** basic logs, `dynamodb:UpdateItem` on the counter key only, and **only** `geo-routes:CalculateRouteMatrix` and `geo-routes:CalculateRoutes` on the AWS-managed routes provider resource for `ap-south-1`. Nothing else.
- A log group with 14 days' retention, the API integration, the route `POST /routes/plan` (no auth, the same as the public demo routes), the Lambda permission, and a stage route throttle like `POST /ask`'s (rate 1, burst 2). The cap is the real guard.
- Package with `AWS/scripts/package_route.py`, following `package_assistant.py`.
- `terraform validate`, then one plan with targets for the new route resources, the stage, and `aws_lambda_function.assistant[0]`, saved to `.local/phase-4/p1.tfplan`. **Expected:** only new route resources added; changes only to the stage route settings and the assistant code hash; **0 destroy.** Report the exact counts; anything else, stop. Apply the saved plan and check that both `CodeSha256` values match their ZIPs.

## Step 4: Ask

1. **A new tool `plan_route`:** its inputs are `district`, `priority`, `max_stops`, and optional `start_lat`/`start_lon` (fill these from the inspector's location when the request has one). It calls `POST /routes/plan` through the same API base and returns, for the model, the ordered stops as explicit strings, for example "Stop 1: KW-… at 09:40 (estimate), 25,701 people within 800 m, siting flags C-HAB-800, C-KILN-1K", plus the total driving time and the notes. Never polygons, geometry or URLs. The step label is "Planning a route"; the summary is "N stops". `daily_cap_reached` and `routing_unavailable` become a plain error result, not a crash.
2. **System prompt.** **Replace** the line "Route planning is not available yet. Say so, and never invent a route or a visiting order. Listing the kilns nearest a point, sorted by distance_m from a tool, is fine." with: use `plan_route` for route or visit-order questions; state the stops, order and times exactly as returned; call the times estimates; never invent a route, a stop or a time.
3. **The two leftovers from 31b:**
   - in the rule-check words, make each check's sentence carry its basis inline (for example "School distance: inconclusive …; the 1000 m threshold is an unverified threshold"), so a one-check answer can't drop "unverified";
   - in `get_evidence`, add `attribution_text` with the exact attribution string, and the prompt line "quote attribution_text exactly".
4. **Tests:** the tool's validation and its explicit-string output; the error mapping; the system prompt has the new route line and not the old one; the inline basis; the attribution.

## Step 5: tests

`AWS/tests/test_route.py`, with no network:
- **The solver:** on small known matrices, 2-opt removes a crossing; the result is deterministic; the budget and `max_stops` are respected; a single stop works.
- **The planner,** with a fake Location client and a fake public API:
  - `people` and `flags` ordering of the selection, and null exposure never ranked as zero;
  - the response has exactly the contract keys;
  - `order` is 1-based and contiguous;
  - every stop's `kiln_id` is in `kilns`;
  - there is one leg per stop including start-to-first;
  - geometry is valid `[lon, lat]`;
  - ETAs are increasing and in `+05:30`;
  - when `CalculateRoutes` fails, the plan comes back without `legs`.
- **The handler:** 400 cases, the 4 KB limit, the cap (429), 404, the 503 mapping, and no provider text in errors.
- **The full suite:** `PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v` (last run: 107 run, 97 pass, 10 skipped). Report the counts.
- If Swift is available, decode a saved live plan with KilnWatchCore's `Route` in a **temporary** script outside `App/`, and report the result. Don't add files to `App/`.

## Step 6: live checks (read both counters first)

**Routes (at most 6):**
1. Hapur, `priority: people`, the default start and depart, budget 480, `max_stops` 8;
2. the same with `priority: flags`;
3. with a start point near Hapur town (`28.7306, 77.7759`) and `max_stops` 5;
4. `kiln_ids` with 3 known IDs;
5. an invalid body (400);
6. spare.

For each: the status, the stop count, the total driving and service minutes against the budget, whether the ETAs are increasing, the legs present, and the latency. Look at the order on a map-like sanity check: the leg distances are plausible and there are no long back-and-forth jumps. Save plans 1 and 3 to `.local/phase-4/live/p1/` (no host) for the iOS team.

**Ask (at most 6):**
- "Plan tomorrow in Hapur": it uses `plan_route`, the stops and times match the tool, and the times are called estimates;
- "Plan a route starting near 28.7306, 77.7759 with 4 stops";
- "Which kilns should I visit first for the most exposed people?";
- the old w7, "Plan my route for today";
- w11 with `kiln_id` `KW-6b3b38…`: it must now say the school threshold is unverified;
- r5, "Show me the evidence for this kiln": the attribution quoted exactly.

For each, report the status, the validator outcome, the latency, the tools, the full answer (in the chat only) and a judgement. Confirm both log groups hold counts and latencies only.

## Step 7: documents

- **`App/docs/api-contract.md`:** a new section, "P1: `POST /routes/plan` (live)": the request fields and defaults, the response (the same `Route` shape as `GET /routes/today`, plus `notes`), the errors, the cap and throttle, what "estimate" and the access note mean, and that `GET /routes/today` (signed-in) is still not built. Placeholders only.
- **`AWS/docs/local-verification.md`:** a "P1: route planning" entry (preflight, cost, plan and apply summary, tests, live results), with no identifiers.

## Report

1. The preflight results and the cost calculation (per plan and worst-case monthly).
2. The diff summary per file, and the test counts.
3. The plan and apply summary (exact add/change/destroy and what changed), the hash checks, and the tfvars backup.
4. The live route table, plus Ask answers.
5. **Leak check:** grep every changed or new tracked file for the account IDs, the API host and ID, the CloudFront domain and ID, the bucket name and the RDS host (read from the `.local` files without printing them): expect 0. `git diff --quiet AWS/.terraform.lock.hcl`. Confirm you touched only the allowed files.
6. **A short note the user can forward** to the iOS orchestrator for prompt 20 (live Today): the endpoint, the request, what the response contains, the saved samples in `.local/phase-4/live/p1/`, and the caveats (estimates; centroid access points).
