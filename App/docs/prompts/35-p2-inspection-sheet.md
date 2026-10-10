# Prompt 35 (P2): Ask `inspection_sheet` tool, and the "which kilns have images?" fix

You are the builder for **one small backend step**. It follows R1, P1 (32, 32b) and E1 (33), which are live. Work sequentially in this one chat. No sub-agents. Don't commit, push or stage. The repo is public, so never print or write identifiers.

Read first: `AGENTS.md`, `App/docs/prompts/30-aws-orchestrator-handover.md` §1 and §4, `App/docs/prompts/32b-route-answer-wording.md` (the deploy pattern you repeat), `App/docs/api-contract.md` ("Phase 4A — Ask", "R1", "P1"), then `AWS/assistant/` (`tools.py`, `core.py`, `validator.py`), `AWS/route/planner.py` (`CHECKS`, `ALWAYS`, `sheet()`) and `AWS/tests/test_assistant.py`.

Two jobs:
1. **`inspection_sheet(kiln_id)`:** a deterministic one-page brief for one kiln, the "inspection sheet" from the concept (p.9). Ask uses it when asked for a sheet, a brief or what to check at a kiln or route stop.
2. **The E1 fallback:** "Which flagged kilns in Hapur have satellite images?" now falls back. All 39 have images, so `images_published_only_for` lists 39 full IDs, the model tries to repeat them all, and it runs out of answer length (`maxTokens` 600) twice. Fix it in the **data shape**, not with more prompt lines.

**The user gave the go by running this prompt.** The scope is exactly:
1. changes to `AWS/assistant/tools.py`, `AWS/assistant/core.py` (the tool list and at most two system-prompt lines) and `AWS/tests/test_assistant.py`;
2. a targeted apply of `aws_lambda_function.assistant[0]` only (expect 0 add / 1 change / 0 destroy);
3. at most **6** live `/ask` questions (the cap is 100 a day), of which at most **1** may plan a route (the route cap is 15 a day).

**Touch only** those files, `AWS/scripts/package_assistant.py` (only if needed), `AWS/docs/local-verification.md` and the Ask section of `App/docs/api-contract.md`. Don't change the route Lambda, the validator's rules, the cap, `maxTokens`, Terraform files or the tfvars. Other sessions edit iOS files; leave `App/` code alone.

## Step 1: code

1. **`inspection_sheet` tool** (`tools.py`). It takes `kiln_id` (full ID, same check as `kiln_detail`) and reads `/public/kilns/{id}`, the same way as `get_evidence`. It returns explicit strings, never booleans or status codes, and no URLs, polygons or coordinates:
   - `kiln_id`, and `status`: "Flagged by satellite, pending inspection".
   - `kiln_type`: "predicted <type>, unverified · confirm on site" (the model score stays out).
   - `siting_flags`: the existing `trim()` flag lines (measured distance, threshold, threshold basis).
   - `checks_to_confirm`: one line for each rule check that is `inconclusive` or `not_evaluated`, built from its `check` label, for example "Distance to habitation: inconclusive, map data incomplete · measure on site". Never "clear".
   - `on_site_checks`: the **same list the route planner puts in a stop's sheet**: the flag-derived checks from `CHECKS` (or the rule check's label), de-duplicated, then `ALWAYS`. `tools.py` can't import `route/` (each Lambda ZIP holds one folder), so copy `CHECKS` and `ALWAYS`, and add a test that imports both modules and asserts they are equal. Then the two lists can't drift.
   - `people_within_800m`, `children_under_five`, `adults_over_sixty` ("not assessed" when null, never 0), plus `EXPOSURE_NOTE` when assessed.
   - `imagery`: "before <date>, after <date>" from the image metadata, or "not yet published", plus `attribution_text`.
   - `rules_note` (`PARTIAL_NOTE`) when `partially_evaluated`.
   - Step: `{"tool": "inspection_sheet", "label": "Preparing the inspection sheet for KW-xxxx…", "summary": "Ready", "ok": true}`. Not found: `summary: "Not found"`, as `get_evidence` does.

   Add its tool spec to `SPECS`, with this description: "One kiln's inspection sheet: siting flags with measured distances, checks to confirm on site, people exposed and the imagery. Use it when asked for a sheet, a brief or what to check at a kiln or route stop."
2. **System prompt** (`core.py`): add at most one line, "For an inspection sheet, call inspection_sheet and give its parts in order; keep 'confirm on site' and 'not assessed' as written." Remove nothing else.
3. **Images in lists** (`image_fields`):
   - When **every** shown kiln has images, return `satellite_images: "published for all N kilns listed"` and **no** ID list.
   - When none have images: "not yet published for any kiln listed".
   - Otherwise keep `images_published_only_for` with the IDs, as today.
   - Update the one system-prompt line about `images_published_only_for` so it covers the new string, in the same words. Edit that line, don't add a new one.
4. **Tests:**
   - the sheet for a flagged kiln, a zero-flag partially evaluated kiln (no "clear", the partial note present), a kiln with null exposure ("not assessed", no 0), with and without images, and not found;
   - `on_site_checks` equal to `route/planner.py` `sheet()` for the same record, plus the `CHECKS`/`ALWAYS` equality test;
   - `image_fields` returns the all / none / some shapes;
   - no URL, `http` or coordinate pair in any tool result;
   - the full suite (last run: 145 run, 135 pass, 10 skipped). Report the counts.

## Step 2: deploy (assistant Lambda only)

Package the assistant and record the SHA-256. Make one plan with `-target='aws_lambda_function.assistant[0]'`, saved to `.local/phase-4/p2.tfplan`. **Expect 0 add / 1 change / 0 destroy**, with only the code hash changing; if anything else changes, stop. Apply the saved plan and check that `CodeSha256` matches the ZIP. Credentials: the `kilnwatch` profile; sign-ins happen only in the user's own terminal.

## Step 3: live check (at most 6; read the Ask counter first and last)

1. "Which flagged kilns in Hapur have satellite images?" No fallback; it says all 39 have images.
2. "Give me the inspection sheet for KW-6b3b38da681850e5af46b024f3d3f78e". It must have:
   - C-HAB-800 at 497 m against 800 m;
   - 4,225 people, 430 under 5, 294 over 60;
   - checks to confirm, and on-site checks;
   - the image dates and the exact attribution.
3. With `kiln_id` set to a zero-flag partially evaluated Hapur kiln (find it from the public list): "What should I check at this kiln?" It must say no flags measured, that some rules could not be checked, and never "clear".
4. "Plan a route from 28.7306, 77.7759 with 4 stops, and give me the inspection sheet for the first stop." Times are called estimated; the sheet matches stop 1. This is the only route plan.
5. With `kiln_id` set: "Is this kiln illegal? Give me its sheet." No banned word, and no verdict.
6. Spare: rerun one failure once, or skip it.

For each, report the status, the validator outcome (pass / regenerated / fallback), the latency, the tools, the full answer (in this chat only) and a judgement. Confirm the logs hold counts and latencies only.

## Step 4: documents and report

- `AWS/docs/local-verification.md`: a short "P2: inspection sheet (35)" entry, with no identifiers.
- `App/docs/api-contract.md`, Ask section: add `inspection_sheet` to the tool list with its step label, and note that list results now say "published for all N kilns listed" when every kiln has images. The response shape is unchanged; the iOS client shows step labels as given.

Report:
- the diff summary and test counts;
- the plan and apply summary and the hash check;
- the live table and answers, and the counters before and after;
- the leak check: grep the changed files for the identifiers read from the `.local` files without printing them (expect 0), `git diff --quiet AWS/.terraform.lock.hcl`, and only the allowed files touched.
