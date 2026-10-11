# Prompt 43: resident inspection requests (backend + portal + iOS)

You are the **lead builder** for one cross-lane feature. **Sub-agents are allowed for this prompt only** (the user asked for it), with the lane split in §2. Don't commit, push or stage. The repo is public.

**Goal:** close the resident side of the loop.

> A resident opens a flagged kiln on the portal → taps **Request an inspection** → picks their concerns → the request is stored → the kiln shows "N residents asked for an inspection" on the portal **and in the inspector app**.

Today the portal only builds a draft to copy or print; nothing reaches inspectors. After this prompt it does, honestly labelled: requests are anonymous, **not verified**, one per browser per kiln, and a request never changes a kiln's status.

**Read first:** `AGENTS.md`; `App/docs/prompts/42-orchestrator-handover.md` §1–§4; `App/docs/api-contract.md` "Integration 2C", "POST /verdicts" and the public-read `include=inspected` notes; `App/docs/prompts/39-verdicts-backend.md` (the pattern this copies); `App/docs/prompts/37-portal-hosting.md` (portal upload); `App/docs/DESIGN.md` (binding for iOS); `Web/ResidentPortal/README.md` and `Web/ResidentPortal/docs/DESIGN.md` (binding for the portal).

**The user gave the go by running this prompt.** The scope is exactly:

1. **Code:** migration `AWS/migrations/004_requests.sql`; `POST /requests` in the existing verdicts Lambda (`AWS/verdicts/`); the public-read aggregate in `AWS/registry/` + `AWS/lambda/api_handler.py`; `registry.cli reset-requests`; Terraform in `AWS/verdicts.tf` gated by a new `enable_requests` (default `false`); the portal (`Web/ResidentPortal/`); the iOS app (`App/KilnWatch/`, `App/Packages/KilnWatchCore/`); docs.
2. **Runner (SSM, still up):** apply migration 004; read-only and rolled-back checks.
3. **One targeted plan and apply** (§5). Expected: **1–2 to add** (the `POST /requests` route, plus an integration only if the verdicts one can't be reused), **in-place changes** to the verdicts Lambda code, the API Lambda code and the stage throttle. Nothing else; anything else, stop.
4. **Live checks** (§5), then **one portal re-upload** (build, two-pass `s3 sync`, invalidate `/*`) as in 37.
5. **One clean-up write:** `reset-requests` for the kiln used in the live check, so the demo starts at zero.

**Out of scope:** Cognito or any sign-in; the Ask and route Lambdas (**don't redeploy them**); CORS (POST and `content-type` are already allowed); the CDN; the provider lock (`hashicorp/aws 6.68.0`); `destroy`; untargeted applies; VPC endpoints; route priority by requests (later); free-text notes, names, phone numbers or precise locations.

## 1. The contract (lead writes this first, before any sub-agent starts)

Add a section **"Inspection requests (43)"** to `App/docs/api-contract.md`, then treat it as frozen for the lanes (they build to it and must not edit it).

**`POST /requests`**, public, no auth, `Content-Type: application/json`, body ≤ 4 KB, unknown or duplicate keys → 400:

```json
{
  "kiln_id": "KW-<32 lowercase hex>",
  "client_id": "<UUID v4 the browser generates once and keeps>",
  "concerns": ["smoke_or_ash", "near_homes"],
  "distance_band": "under_1km",
  "lang": "en"
}
```

- `concerns`: 1–4 unique values from `smoke_or_ash`, `near_homes`, `near_school_or_hospital`, `other`.
- `distance_band` (self-reported, where the resident lives): `under_1km`, `1_to_5km`, `over_5km`, `not_said`.
- `lang`: `en` or `hi`.
- The kiln must exist (any status). Unknown full ID → **404**, not counted.
- **One request per `client_id` per kiln.** New → **201**. The same pair again → **200** with `"created": false` and the current aggregate (no 409, no counting).
- **Daily cap: 300 new requests per UTC day**, counted in RDS in the insert transaction (like `verdict_days`). Cap → **429** `daily_cap_reached` (`retryable: true`). DB failure → **503** `registry_unavailable`. Errors use the usual nested `{"error": {"code","message","retryable"}}`.
- Stage throttle 1 request/s, burst 2 (the `/verdicts` group).

**Response (201/200):**

```json
{
  "kiln_id": "KW-…",
  "created": true,
  "resident_requests": {
    "count": 12,
    "within_1km": 8,
    "concerns": {"smoke_or_ash": 9, "near_homes": 7, "near_school_or_hospital": 2, "other": 1},
    "last_request_on": "2026-10-11"
  }
}
```

**Public read:** `GET /public/kilns` (both shapes, with and without `include=inspected`) and `GET /public/kilns/{id}` gain the same `resident_requests` object on every kiln. With no requests it's `{"count": 0, "within_1km": 0, "concerns": {all four: 0}, "last_request_on": null}`: zero here is a real count, not missing data. `last_request_on` is a date only (IST), never a time. Never expose the client hash, `lang` or row IDs. Same `max-age=60`; say in the contract that the count can lag up to about two minutes, while the POST response is always fresh.

**Honest limits (write them in the contract):** anyone can send requests by clearing their browser storage, within the daily cap; requests are anonymous and unverified; a request is a signal for inspectors, never a finding, and never changes `status` or `review_state`.

Also save one realistic recorded response (synthetic IDs, sanitized hosts) as a fixture both client lanes use, e.g. `Web/ResidentPortal/tests/fixtures/requests-*.json` and `App/Packages/KilnWatchCore/Tests/KilnWatchCoreTests/RequestFixtures/`.

## 2. Lanes and sub-agents

| Lane | Who | Owns (only these paths) |
|---|---|---|
| Contract, AWS, deploy, integration, final report | **You, the lead** | `AWS/`, `App/docs/api-contract.md`, `AWS/docs/`, `.local/requests/` |
| Portal | Sub-agent **P** | `Web/ResidentPortal/` (except deploy) |
| iOS | Sub-agent **I** | `App/KilnWatch/`, `App/Packages/KilnWatchCore/`, `App/docs/DESIGN.md`, `App/docs/HANDOVER.md`, `App/docs/screens/phase-8/` |

Rules for sub-agents (put these in each sub-agent's brief):
- Build **only to the frozen contract and fixtures**. Never edit the contract or another lane's paths.
- **Never** run the AWS CLI, Terraform, SSM, or any request to the live API or CDN; never deploy, stage or commit. Live checks are the lead's job.
- Sub-agent I is the **only** one that uses Xcode or the Simulator. Sub-agent P uses Playwright only.
- Each returns: files changed, test counts, screenshot paths, open issues.
- You may split the AWS lane further (e.g. a sub-agent for tests), but all AWS actions stay with you.

Start P and I right after §1 is frozen; build the AWS lane in parallel; integrate at the end.

## 3. AWS lane (lead)

**Migration `004_requests.sql`** (transactional, idempotent like 001–003):
- `kilnwatch.inspection_requests`: `request_id uuid PRIMARY KEY DEFAULT gen_random_uuid()` (or generated in the Lambda), `kiln_id` FK to candidates, `client_hash text` (sha256 hex of the `client_id`; never store the raw ID), `concerns text[]` with a check that it's a non-empty subset of the four values, `distance_band` (check), `lang` (check), `created_at timestamptz DEFAULT now()`, `UNIQUE (kiln_id, client_hash)`, an index on `kiln_id`.
- `kilnwatch.request_days (day date PRIMARY KEY, count int CHECK (count BETWEEN 0 AND 300))`.
- Role `kilnwatch_request_writer` (NOLOGIN): `SELECT` on candidates; `SELECT, INSERT` on inspection_requests; `SELECT, INSERT, UPDATE` on request_days. **No** update on candidates. Grant it to the existing login `kilnwatch_verdicts` (reuse the login and secret; no new secret).
- Reader: `GRANT SELECT (kiln_id, concerns, distance_band, created_at) ON kilnwatch.inspection_requests TO kilnwatch_reader`. Never `client_hash` or `lang`.

**Lambda:** route `POST /requests` to the existing verdicts Lambda; dispatch on `routeKey`. Keep `POST /verdicts` byte-for-byte the same (its tests stay green). Validation exactly as §1; the cap and insert in one transaction; dedupe via the unique constraint (`ON CONFLICT DO NOTHING`, then return the aggregate with `created: false`). Logs: counts, status code and latency only; no kiln ID, client ID or hash.

**Public read:** one aggregate query (no N+1) joined into both list shapes and the detail. Keep the allowlist approach in `public_view`. **Ask and route must not change:** check that `AWS/assistant/tools.py` `trim` drops the new key (add a test that proves it); don't touch the route Lambda.

**Operator:** `registry.cli reset-requests --kiln <full-id> --confirm` deletes that kiln's request rows (day counter untouched). Without `--confirm` or with a bad ID it refuses.

**Tests:** every validation branch; 201, 200 duplicate (not counted), 404 not counted, cap 300 → 429; DB failure → 503; log privacy; the public aggregate shape and zero state; default and `include=inspected` reads both carry it; `trim` drops it; `/verdicts` unchanged; the migration grants (opt-in PostGIS test like 003's); `reset-requests`. Full suite last: **211 run, OK, 16 skipped**. Report the new counts.

## 4. Client lanes

**Portal (sub-agent P).** Copy and layout follow `Web/ResidentPortal/docs/DESIGN.md`; every string in English and Hindi through the existing `t()`; phone-first.
- On the kiln record page: a primary **"Request an inspection"** button. The existing draft/export flow stays as a secondary "Prepare a written request".
- The request step: concerns as checkboxes (at least one), "Where do you live?" as the four distance bands, one privacy line: "Anonymous. We store your answers and a random code from this browser, not your name, phone or location." Then **Send request**.
- After sending: "Your request was added. 12 residents have asked for an inspection of this kiln." plus "Inspectors see this count in the KilnWatch inspector app. A request doesn't guarantee an inspection and doesn't change the kiln's status."
- Already sent from this browser (store `client_id` and the kiln IDs in `localStorage`, wrapped in try/catch): show "You asked for an inspection on 11 Oct" and the count; no second send.
- The record and the area list show the count when > 0 ("12 inspection requests · not verified").
- Errors: 429 "Today's request limit is reached. Try again tomorrow."; 503/network "Couldn't send. Your answers are kept; try again."; 404 "This kiln record is no longer available."
- Fixture mode: the flow works against fixtures with the existing sample labelling; nothing is sent.
- Checks: `npm run typecheck`, `npm test`, `npm run build`, `test:e2e:live` on Chromium (mocked, as the README says). Screenshots (light, phone width 390 + one desktop, one Hindi) in `Web/ResidentPortal/docs/screens/requests/`.

**iOS (sub-agent I).** `DESIGN.md` is binding; the app only **shows** requests, it never sends them.
- KilnWatchCore: decode `resident_requests` (optional, so older cached records still decode), with tests from the fixture.
- Kiln detail: a "Resident requests" section after exposure: "12 inspection requests" (`.monospacedDigit()`), "8 say they live within 1 km · not verified", the concerns as plain words with counts, "Last request 11 Oct". Neutral ink only: no status colours, no clay. Zero → "No resident requests yet". Symbol `person.2`.
- Kilns list rows: "12 requests" in `inkSecondary` when > 0.
- Update DESIGN §10 (Kiln and Kilns rows) and add a short `HANDOVER.md` entry.
- Checks: `swift test` (last: 99) and the root `xcodebuild` from `AGENTS.md`, zero warnings. Two screenshots (kiln detail with requests from a stub, Kilns list), light only, in `App/docs/screens/phase-8/`. Keep testing light: no dark/AX matrix.

## 5. Deploy and live checks (lead, after the lanes pass)

**Credentials:** the user has run `aws login` for both `kilnwatch` and `kilnwatch-bedrock` before starting. Check both resolve (masked: `sed -E 's/[0-9]{12}/<acct>/g'`), `kilnwatch` ends `user/aryaman`. If either fails, stop and ask; never sign in yourself. Terraform: `.local/tools/terraform/terraform`, main credentials via `aws configure export-credentials --profile kilnwatch --format env`; the `aws.cdn` provider needs the second session.

1. **Runner:** apply 004 via SSM (the 39 pattern; scripts and private outputs in `.local/requests/`). Read-only checks: tables and exact grants; the 39 candidates' checksum unchanged. **Rolled-back test:** as `kilnwatch_verdicts`, insert one request, assert the aggregate, run `reset-requests` inside the same transaction, **roll back**; checksum unchanged, `request_days` empty.
2. **Terraform:** set `enable_requests = true` in the ignored tfvars; one targeted plan saved to `.local/requests/requests.tfplan`; read it against the expected list in the scope; apply that saved plan; check the live `CodeSha256` values match the ZIPs.
3. **Live:**
   - bad body → 400; unknown full kiln ID → 404 (not counted);
   - **one** real request on a flagged Hapur kiln → 201, aggregate count 1; the same body again → 200, `created: false`, count still 1;
   - `GET /public/kilns/{id}` shows `resident_requests.count` 1 (allow the cache); the default list still has 38 flagged kilns; `include=inspected` 39; Ask and route Lambdas untouched (no calls to them);
   - CORS preflight for `POST /requests` from the portal origin succeeds (read the origin from `.local/portal/outputs.json` without printing it).
4. **Portal re-upload** (37's procedure: `npm run build` with the ignored `.env.production.local`, two-pass `s3 sync`, invalidate `/*`), then open the hosted record page on a phone-width browser and confirm the button and count render (read-only; don't send a second request).
5. **iOS live read:** with the simulator on the live config, open the same kiln and capture the requests section showing 1.
6. **Clean-up:** `reset-requests --kiln <that id> --confirm` on the runner; confirm the public count is back to 0.

## 6. Rules

- **Never write or print** account IDs, ARNs, the API URL or ID, CloudFront domains, bucket or table names, the RDS host, the runner ID, passwords or emails. Private values go to `.local/requests/` only.
- **Product language:** never "illegal", "unlawful" or "violation". A kiln is "Flagged by satellite · pending inspection". Requests are "inspection requests", anonymous and not verified; never say a request was sent to the government or to any authority, only to KilnWatch inspectors.
- On macOS, archives use `COPYFILE_DISABLE=1 tar --no-xattrs`.

## 7. Docs and report

- `api-contract.md` (§1, marked live with the date), `AWS/docs/local-verification.md` "43: inspection requests" (no identifiers), the runbook (the reset command and the kill switch `enable_requests = false`, a targeted apply, needs a go), `App/docs/HANDOVER.md` (iOS entry), `Web/ResidentPortal/docs/HANDOVER.md` (portal entry).

**Report (one, from the lead):**
- per lane: files changed, test counts, screenshots;
- the migration and runner checks; the plan and apply summaries and hashes; the live checks; the portal upload and invalidation; the clean-up;
- which sub-agents ran and what each did;
- leak check: grep every changed file for every identifier from `.local` and the tfvars (expect 0); `git diff --quiet AWS/.terraform.lock.hcl`; grep the app and portal for the banned words;
- open limits: unverified anonymous requests within a cap of 300 a day; one per browser per kiln; no route priority yet; no sign-in.
