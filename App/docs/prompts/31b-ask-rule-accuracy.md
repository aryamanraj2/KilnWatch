# Prompt 31b: Ask — rank by exposure, and say thresholds right

You are the builder for **one small backend step** of KilnWatch. It follows prompt 31 (R1), which is live. Same setup, same rules: no sub-agents, no commit, push or stage; the repo is public, so never print or write account IDs, ARNs, the API URL, the CloudFront domain, the bucket name, the RDS host, the runner ID or emails.

The R1 live check found three wrong or weak answers. Fix the **data shape and wording**, not the model:
1. **r4 "Which Hapur kilns have the most people within 800 m?"** named the 7th kiln as the 3rd. The model had to sort 39 table rows itself. The true top 3 are 25,701, 20,838 and 17,872 people.
2. **r6 "Does this kiln break rule C-HAB-800?"** called C-HAB-800's threshold "unverified". It is `secondary_sources`. The current words ("threshold quoted by secondary sources; gazette text not read") read as unverified.
3. **r5 "Show me the evidence"** left out the Copernicus attribution, which `get_evidence` does return.
4. Also **w11 "How far is the nearest school?"** said "I don't have data about schools", which is now false: school checks exist per kiln.

**The user gave the go by running this prompt.** The scope is exactly:
1. the `AWS/assistant/` changes and tests;
2. a targeted apply of `aws_lambda_function.assistant[0]` only (expect 0 add / 1 change / 0 destroy);
3. at most **5** live questions.

**Touch only** `AWS/assistant/`, `AWS/tests/test_assistant.py`, `AWS/docs/local-verification.md` and, if a field changes, `App/docs/api-contract.md` (the Ask section only). Other sessions are editing iOS files.

## Step 1: code

1. **Server-side ranking (`list_flagged_kilns`).** Add an optional `sort_by` input with the values `"people_within_800m"` and `"default"`. With `"people_within_800m"`:
   - sort all fetched kilns by `exposure.people`, highest first, with "not assessed" kilns last (never treated as zero), **before** applying `limit`;
   - add a `rank` column (1, 2, 3 …) to the rows;
   - add a top-level `order` field: "Sorted by people_within_800m, highest first; rank 1 has the most people."
   - Update the tool description so the model knows to use it for "most people" or "most exposed" questions. Invalid values are an invalid-input result, like the other inputs.
2. **Threshold wording (`tools.py`).**
   - `secondary_sources` → "sourced threshold: quoted by court records, legal digests or news reports (not an unverified threshold)";
   - `unverified_compilation` → "unverified threshold (from an academic compilation)".
   - Apply the same distinction in `FLAG_BASIS` for `siting_flags`, for example "sourced threshold (secondary sources)" and "unverified threshold".
3. **System prompt (`core.SYSTEM`).** Edit or replace existing lines; don't stack contradictory ones:
   - Extend the unverified-threshold line: call a threshold unverified **only** when the tool says "unverified threshold".
   - Add: "When you describe satellite images, include the attribution the tool gives."
   - Add: "Distances to habitation, schools, orchards, highways, railways and other kilns are per kiln, in rule checks. If the question names no kiln and the inspector is not viewing one, say which kiln is needed."
4. **Tests:**
   - with `sort_by` on an in-memory fixture with exposure added, the order is correct and not-assessed kilns come last; `limit` applies after sorting; `rank` and `order` are present; an invalid `sort_by` is an invalid input;
   - the new verification words; no `secondary_sources` wording contains "unverified" except in the explicit "(not an unverified threshold)";
   - the system prompt has the new lines;
   - the full suite: `PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v` (last run: 105 run, 95 pass, 10 skipped). Report the counts.

## Step 2: deploy (Lambda only)

1. Run `AWS/scripts/package_assistant.py` and record the SHA-256.
2. Plan with `-target='aws_lambda_function.assistant[0]'`, saved to `.local/phase-4/r1b.tfplan`. **Expect 0 add / 1 change / 0 destroy** (the code hash only). tfvars unchanged. Anything else: stop.
3. Apply the saved plan and check that `CodeSha256` matches the ZIP.

## Step 3: live check (at most 5; read today's counter first)

If fewer than 5 questions remain today, stop and report: the counter resets daily, and the user will rerun this step later.

1. r4 "Which Hapur kilns have the most people within 800 m?" (no `kiln_id`): the top 3 must match the public API ranking (25,701 / 20,838 / 17,872), and it should use `sort_by`.
2. r6 "Does this kiln break rule C-HAB-800?" (`kiln_id` `KW-6b3b38da681850e5af46b024f3d3f78e`): no legal conclusion, no banned words, 497 m against 800 m, and it must **not** call the threshold unverified.
3. r5 "Show me the evidence for this kiln" (same `kiln_id`): image dates plus the Copernicus attribution, no URLs.
4. w11 "How far is the nearest school?" (no `kiln_id`): it must not say there is no school data; it asks which kiln.
5. w11 again, with `kiln_id` `KW-6b3b38…`: inconclusive or the nearest mapped school as the data says, the threshold called unverified, never "clear".

For each, report the status, the validator outcome, the latency, the tools and their inputs, the full answer (in this chat only) and a one-line judgement. Confirm the logs hold counts and latencies only.

## Step 4: documents and report

- **`AWS/docs/local-verification.md`:** a short "R1b: Ask rule accuracy (31b)" entry, with no identifiers.
- **`App/docs/api-contract.md`:** only if a response field visible to clients changed. `steps` labels for `list_flagged_kilns` may stay the same.

Report:
1. The diff summary and the test counts.
2. The plan and apply summary, and the hash check.
3. The live table and answers.
4. **Leak check:** grep the changed files for the account IDs, the API host and ID, the CloudFront domain and ID, the bucket name and the RDS host (read from the `.local` files without printing them): expect 0. `git diff --quiet AWS/.terraform.lock.hcl`. Confirm you touched no other files.
