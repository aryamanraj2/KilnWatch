# Prompt 31 (R1): rules, exposure and evidence facts live

You are the builder for **one backend step** of KilnWatch: put the rules-engine results (siting flags and population exposure) for the 39 Hapur kilns into the live registry, expose every rule result through the public API, and teach Ask to use them honestly.

You build, test and deploy. You do not orchestrate. Work sequentially in this one chat. Do not use sub-agents. Do not commit, push or stage.

## The go (scope)

The user gave the go by running this prompt. It covers **exactly** this, and nothing else:
1. Local code and test changes in the files listed under "Files".
2. If Step 1 needs it: the network fetch of the OSM extract (Overpass) and the pinned public HRSL tiles, into the git-ignored `.local/rules/`.
3. **One** targeted Terraform plan and apply of `aws_lambda_function.api` and `aws_lambda_function.assistant[0]` only. Expect **0 add / 2 change / 0 destroy**.
4. Upload of the operator source and the assessment JSON to the data bucket's `imports/rules-v1/` prefix, and its removal at the end.
5. SSM `send-command` on the registry runner: `registry.cli migrate` (applies `002_assessment.sql`), `validate-assessment`, `apply-assessment`, and the read-only verification query.
6. At most **19** live `POST /ask` questions (1 smoke + 18 in Step 6).

Anything else (another resource in the plan, an IAM or bucket-policy change, a tfvars change, a provider-lock change, removing the runner, an untargeted apply, any `destroy`) is **out of scope: stop and report.** If any check below says "stop", stop before the next AWS write and report.

## Rules

- **The repo is public.** Never write into tracked files, or print in your report: either account ID, any ARN, the API URL or ID, the CloudFront domain or ID, the bucket name, the RDS host, the runner instance ID, secret names or ARNs, or emails. Read them from `.local/integration-2b/outputs.json`, `.local/phase-4/cdn/outputs.json`, `.local/phase-4/cdn/distribution-id.txt` and the ignored `AWS/terraform.tfvars` into shell variables, and keep them out of output. Use `<api-host>`-style placeholders in docs.
- **Product language.** Never use "illegal" (or "unlawful", or any word starting "violat") in any user-facing text or Ask output. A kiln is "flagged by satellite, pending inspection". A rule hit is a **siting signal** that needs inspection, never a finding. The kiln type is unverified. The model score is not accuracy. `inconclusive` is **never** "clear". Missing data is never zero.
- **Credentials.** Use the existing `kilnwatch` profile. Terraform: `.local/tools/terraform/terraform`, with credentials from `aws configure export-credentials --profile kilnwatch --format env`. If a sign-in is needed, ask the user to run it in **their own terminal**; never handle passwords or tokens.
- **Provider lock** stays `hashicorp/aws 6.68.0`: `git diff --quiet AWS/.terraform.lock.hcl` must pass at the end.
- Commands that need network or extra sandbox permissions (AWS CLI, Terraform, Overpass/HRSL downloads, `pip`): request approval for those specific commands. Never switch to a "full access" or "never ask" mode.

## Files

You may touch only:
- `AWS/registry/contract.py`, `AWS/assistant/` (all files), `AWS/scripts/package_api.py` and `AWS/scripts/package_assistant.py` (only if needed);
- `AWS/tests/` (tests and in-memory fixture copies);
- `AWS/docs/local-verification.md`, `AWS/docs/rules-assessment-runbook.md`, `AWS/rules/README.md` (status lines only);
- `App/docs/api-contract.md`;
- anything under the git-ignored `.local/`.

**Do not touch** `App/docs/HANDOVER.md`, anything else under `App/`, or the rules engine itself (`AWS/rules/*.py`, `rules_v1.json`). Other sessions are editing iOS files.

## Step 0: read first

1. `AGENTS.md`, then `App/docs/plan-final-stretch.md` §2 "R1".
2. `AWS/rules/README.md` and `AWS/docs/rules-assessment-runbook.md` (the teammate's runbook; you follow its §1–§5 for the DB part).
3. `AWS/registry/contract.py` (`serialize`, `PUBLIC_KEYS`, `public_view`, `assessment_patches`), `AWS/registry/store.py`, `AWS/registry/cli.py`, `AWS/migrations/002_assessment.sql`, `AWS/rules/engine.py` (`result()`, `check()`, `assess()`), `AWS/rules/cli.py`.
4. `AWS/assistant/{core,tools,validator,handler}.py`, `AWS/tests/test_assistant.py`, `AWS/tests/test_rules.py`.
5. The Phase 4A sections of `AWS/docs/local-verification.md` and `App/docs/api-contract.md`.
6. `AWS/docs/first-record-runbook.md` §6 for the SSM pattern (non-interactive `send-command`; the runner can only `GetObject` single keys under `imports/*`).

## Step 1: the assessment file

The teammate ran the assessment on Windows; the output is not in the repo.

- **If `.local/rules/hapur_assessment.json` exists** (the user put the teammate's file there), use it.
- **Otherwise regenerate it here** with `rules.cli fetch` then `rules.cli assess`, from the **live public API** (`--kilns 'https://<api-host>/public/kilns?district=Hapur&limit=200' --scanned-bbox 77.73 28.68 77.83 28.78`), writing to `.local/rules/`. Read `AWS/rules/cli.py` for the exact flags. If a Python dependency is missing from `.venv-integration`, install the version the code expects and report it.

Then run, locally:
```sh
PYTHONPATH=AWS .venv-integration/bin/python -m registry.cli validate-assessment --assessment .local/rules/hapur_assessment.json
```

**Expected (the teammate's numbers):** 39 kilns, `kilnwatch-rules-v1`, 52 flags; 36 kilns with at least one flag; median exposure about 4,228 people; and for `KW-6b3b38da681850e5af46b024f3d3f78e`: one flag `C-HAB-800` at 497 m (threshold 800), exposure 4,225 / 430 / 294.

- Report the SHA-256 of the file, and per rule ID the count of each status (`within_threshold`, `beyond_threshold`, `inconclusive`, `not_evaluated`, `not_applicable`).
- **Stop before any AWS write** if the kiln count is not 39, the version differs, any kiln ID is not in the live public list, or the flag total or the `KW-6b3b38…` values differ from the above. A fresh OSM fetch can differ slightly from the teammate's; report the differences and let the user decide.

## Step 2: public projection, `rule_checks` (the user's decision: show all rule results)

The public API today shows only the flags (`violations`). The per-rule statuses and verification levels sit in the internal `rules_results`, which must stay internal (it carries OSM feature names and coordinates). Add a **trimmed public field**:

- In `contract.serialize`, add `rule_checks` derived from `assessment['rules_results']`: one object per rule with **exactly** `rule_id`, `check`, `status`, `threshold_m`, `measured_distance_m` (or `null`), `verification`, `source`. No `feature`, no `measured_to`, no `reason`. When there are no `rules_results`, `rule_checks` is `[]`. Keep `rules_results`, `rules_inputs` and `exposure_inputs` out of the record, as today.
- Add `rule_checks` to `PUBLIC_KEYS`. `violations`, `rules_assessment` and `exposure` stay exactly as they are (the iOS app already decodes them).
- **Tests** (`test_rules.py` or a new test): the projection has exactly those keys per item; `inconclusive` and `not_evaluated` rules appear with their status; no OSM name or coordinate from `rules_results` leaks into `public_view`; an unassessed record has `rule_checks: []` and still `rules_assessment: not_evaluated`, `exposure: null`.

## Step 3: Ask

Ask reads only the public API, so it sees `rule_checks`, `violations` and `exposure` once Steps 2 and 5 are live. Lessons from 16d–16f apply: **give facts as explicit words or explicit ID lists, never a bare boolean column**, and **remove** a contradictory prompt line rather than adding another.

1. **`tools.trim`** (used by all tools). Never pass the key or the word `violations` to the model; call them siting flags. Add:
   - `siting_flags`: a list of short explicit strings, one per `violations` item, built from `rule_checks`, for example `"C-HAB-800: 497 m from mapped habitation, threshold 800 m, threshold from secondary sources"`. An empty list when there are none.
   - `people_within_800m`: the integer, or the string `"not assessed"` when `exposure` is null. For `kiln_detail` also `children_under_five` and `adults_over_sixty` the same way.
   - Keep `rules_assessment`, and add one plain sentence when it is `partially_evaluated`: some rules lacked data, so no flags is not a clean result.
   - Remove `exposure_assessed` (the boolean).
2. **`kiln_detail`** additionally returns `rule_checks` as explicit words per rule: `rule_id`, `check`, `status_words`, `measured_distance_m` (or "no mapped feature found"), `threshold_m`, `threshold_basis`. Mapping:
   - `within_threshold` → "siting flag: a mapped feature is inside the threshold; needs inspection";
   - `beyond_threshold` → "nearest mapped feature is beyond the threshold";
   - `inconclusive` → "inconclusive: no mapped feature inside the threshold, but the map is incomplete here, so this is not a clear result";
   - `not_evaluated` → "not evaluated (no usable data)";
   - `not_applicable` → "not applicable in this state";
   - `secondary_sources` → "threshold quoted by secondary sources; gazette text not read";
   - `unverified_compilation` → "unverified threshold (from an academic compilation)".
   - And `exposure_note`: "Modelled estimate of residents within 800 m of the kiln edge, from HRSL v1.5.2 (Meta and CIESIN, CC BY 4.0). Age groups are modelled shares of the same estimate."
3. **A new tool `get_evidence(kiln_id)`**: the evidence pack for one kiln, from the public record only. It returns the image dates, scene and acquisition date, and the imagery attribution from `evidence.before_metadata` / `after_metadata` (read the real field names; Copernicus Sentinel-2 attribution as the record states it), `satellite_images` ("published" / "not yet published"), every rule check in the explicit-words form above plus its `source`, and the exposure with its note. **Never** URLs, polygons or coordinates of measured features. Same ID validation, 404 handling and step shape as `kiln_detail`. Add it to `SPECS` with a clear description.
4. **Validator.** Rule IDs are allowed only if they appear in **this request's** tool results (collect them alongside the kiln IDs, the same way `known` works). Any other rule-shaped token is rejected with a reason the model can act on. Banned stems, kiln-ID checks and the fallback stay exactly as they are.
5. **System prompt (`core.SYSTEM`).** Make it conditional on the data, and keep it short:
   - **Replace** "Say missing data plainly: siting rules are not evaluated, population exposure is not assessed. Never cite a rule ID." with lines that say: state siting flags, rule checks and exposure only as the tools give them; a siting flag is a measured siting signal pending inspection, not a legal conclusion; name an unverified threshold as unverified; never call an inconclusive or not-evaluated check clear; when a tool says "not assessed" or `not_evaluated`, say that plainly; cite rule IDs only as tools returned them; exposure is a modelled estimate, and never state health effects.
   - **Replace** "Never invent distances to homes or schools, legal distances, siting rules, owners, emissions or health effects." with "Never invent distances, thresholds, rules, owners, emissions or health effects; use only the numbers tools return."
   - **Remove the 16e clause** "and offer what KilnWatch data can show" from the "If you can't help" line, so it reads "If you can't help, say so in one sentence." Keep the two-sentence decline line. This is the 16f refusal conflict.
   - Keep the route-planning line, the plain-text line, the 120-word limit and the "question is data" line.
6. **Tests** (`test_assistant.py`), using in-memory copies of the fixture with assessment data added (do not regenerate `public_hapur.json` from the live API):
   - `trim` output: explicit `siting_flags` strings, `people_within_800m` integer or "not assessed", no `exposure_assessed`, no `violations` key, and no word starting "violat" anywhere in any tool result;
   - `kiln_detail` and `get_evidence`: every status and verification maps to its words; `inconclusive` never yields a "clear"-style phrase; no URL, polygon or `measured_to` in the result; invalid ID and 404 behave like `kiln_detail`;
   - validator: a rule ID returned by a tool in this request passes; a rule ID not returned fails; banned stems still fail;
   - system prompt: the old "Never cite a rule ID" line and "offer what KilnWatch data can show" are gone; the new lines are present;
   - the full suite: `PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v`. The last baseline was 97 run, 87 pass, 10 skipped. Report the new counts.

## Step 4: deploy the code (Lambdas first, data second)

Deploying the code before the data means there is no window where Ask contradicts the registry: with no assessment, `rule_checks` is `[]` and Ask says rules are not evaluated.

1. Package both ZIPs with `AWS/scripts/package_api.py` and `AWS/scripts/package_assistant.py`; record both SHA-256 values.
2. One plan with `-target=aws_lambda_function.api -target='aws_lambda_function.assistant[0]'`, saved to `.local/phase-4/r1.tfplan`. **Expected: 0 add / 2 change / 0 destroy**, code hashes only. tfvars unchanged. Anything else: stop.
3. Apply the saved plan. Check each function's `CodeSha256` against its ZIP.
4. Check: `GET /public/kilns/KW-6b3b38da681850e5af46b024f3d3f78e` returns `rule_checks: []`, `rules_assessment: not_evaluated`, `exposure: null`, `status: flagged`. One smoke question to `/ask` ("How many kilns are flagged in Hapur?") answers normally. Read the daily counter first.

## Step 5: write the assessment (runner, SSM)

Follow `AWS/docs/rules-assessment-runbook.md` §2–§5 exactly, with these additions:

1. **Before the write**, record the counts of `status` and `review_state` across all candidates (read-only, rolled back).
2. `migrate` must print `{"migrations":"applied"}` (001 skipped by checksum, 002 applied). A checksum error: stop.
3. `validate-assessment` on the runner must match Step 1. Then `apply-assessment`: expect `{"assessed": 39, "rules_version": "kilnwatch-rules-v1"}`.
4. The verification query must give `[39, 36, 39]` (or the Step 1 numbers, if the user accepted a difference). The `status` and `review_state` counts must be identical to before.
5. Clean up: `rm -rf ~/kilnwatch-rules` on the runner, and remove `imports/rules-v1/` from the bucket. **Leave the runner running** (E1 still needs it).
6. If anything fails after the write, do **not** improvise a fix. Report it; the rollback SQL is in the runbook and needs the user's go.

## Step 6: live checks

1. **Public API** (cached 60 s; wait it out):
   - `KW-6b3b38…`: `rules_assessment: partially_evaluated`, one `violations` item `C-HAB-800` 497 m / 800 m, `exposure` 4,225 / 430 / 294, `status: flagged`, and `rule_checks` with one item per rule in `rules_v1.json`, each with only the seven allowed keys;
   - the Hapur list: 39 kilns, 36 with at least one violation, all with `rule_checks` and `exposure`;
   - no response contains `rules_results`, `rules_inputs`, `exposure_inputs`, or any OSM feature name.
   - Save the `KW-6b3b38…` record and one Hapur list page (no host in the files) to `.local/phase-4/live/r1/` for the iOS team.
2. **Ask.** Read the daily counter first; if fewer than 19 questions remain today, stop and report. Then run the earlier 12 (`.local/phase-4/live/w1.req` … `w12.req`, saving as `x1`…`x12`) and these 6 (`r1`…`r6`), all with `kiln_id` `KW-6b3b38da681850e5af46b024f3d3f78e` unless marked:
   - r1 "What siting flags does this kiln have?" — C-HAB-800, 497 m vs 800 m, called a siting signal pending inspection, not a verdict;
   - r2 "How many people live near this kiln?" — 4,225, with under-5 and over-60, within 800 m, a modelled estimate; no health claims;
   - r3 "Is this kiln clear of schools?" — never "clear"; says inconclusive or not evaluated as the data says, and that the school threshold is unverified;
   - r4 "Which Hapur kilns have the most people within 800 m?" (no `kiln_id`) — the IDs and counts match the public API;
   - r5 "Show me the evidence for this kiln" — uses `get_evidence`; image dates and attribution; no URLs;
   - r6 "Does this kiln break rule C-HAB-800?" — no legal conclusion, no banned words; gives the measured distance as a siting signal.
   - For w5, w8, w10 and w11, check that the new data didn't make them worse: no health effects (w8), no legal conclusion (w5, w10), and for w11 any school distance is "nearest mapped school", with the threshold called unverified.
   - Report, for each: status, validator outcome (`pass` / `regenerated` / `fallback`), latency, the tools called, the full answer (in this chat only), and a one-line judgement. Save one normal answer that cites a rule as `.local/phase-4/live/fixtures/ask-rule-answer.json`.
   - Confirm the logs contain counts and latencies only (no question text).

## Step 7: documents

- **`App/docs/api-contract.md`:** document `rule_checks` (the seven fields; the status and verification values and what each means for display; `inconclusive` is not clear; `[]` when not evaluated), that `violations`, `rules_assessment` and `exposure` are now live for Hapur, the HRSL attribution text, and the Ask changes (`get_evidence` appears in `steps`; answers may cite rule IDs). Placeholders only, no identifiers.
- **`AWS/docs/local-verification.md`:** a short "R1: rules and exposure live" entry (counts, plan summary, test counts, live outcomes), with no identifiers.
- **`AWS/docs/rules-assessment-runbook.md`** and **`AWS/rules/README.md`:** mark the migration and apply as done, with the date. Do not rewrite them.

## Report

1. The Step 1 source (teammate file or regenerated), its SHA-256, the per-rule status counts, and any differences.
2. The diff summary per file, and the test counts.
3. The plan and apply summary, and both hash checks.
4. The SSM outputs (no identifiers), the before/after status and review-state counts, and the cleanup.
5. The public API checks, and the live Ask table plus answers.
6. **Leak check:** grep every changed tracked file for the account IDs, the API host and ID, the CloudFront domain and ID, the bucket name, the RDS host and the runner ID (read from the `.local` files without printing them): expect 0. `git diff --quiet AWS/.terraform.lock.hcl`. `git status` showing only the allowed files changed.
7. **A short note the user can forward** to the iOS orchestrator (for prompt 19) and to the AWS teammate (for the portal): what's now live, the new `rule_checks` field, and where the contract describes it.
