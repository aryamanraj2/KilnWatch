# Prompt 32b: Ask route answers — estimates and order, made deterministic

You are the builder for **one small backend step**. It follows prompt 32 (P1), which is live. Same setup and rules: no sub-agents; don't commit, push or stage; the repo is public, so never print or write identifiers.

The P1 live check found two wording problems in `plan_route` answers:
1. **Times without "estimate".** Two of the four route answers gave ETAs ("KW-… at 09:13") without saying they are estimates. The tool string says "(estimate)" after the time, and the model drops it.
2. **Road order read as ranking.** With `priority: people`, the planner picks the 8 kilns with the most people, then visits them in road order. The answer to "Which kilns should I visit first for the most exposed people?" presented the road order as the exposure order: stop 1 has 9,332 people, while the most exposed kiln (25,701) is stop 6.

Fix both in the **data and the validator**, not by adding more prompt lines.

**The user gave the go by running this prompt.** The scope is exactly:
1. changes to `AWS/assistant/tools.py`, `AWS/assistant/validator.py`, `AWS/assistant/core.py` (only where they call these) and their tests;
2. a targeted apply of `aws_lambda_function.assistant[0]` only (expect 0 add / 1 change / 0 destroy);
3. at most **3** live `/ask` questions (each makes one route plan, so the route counter goes up by up to 3).

**Touch only** `AWS/assistant/`, `AWS/tests/test_assistant.py`, `AWS/scripts/package_assistant.py` (only if needed) and `AWS/docs/local-verification.md`. Other sessions are editing iOS files. Don't change the route Lambda.

## Step 1: code

1. **In the time itself (`plan_route` result).** Write every stop time as "estimated arrival 09:13", and the finish as "estimated finish 14:52". No bare times.
2. **The selection and the order, explicit.** Add one top-level sentence to the `plan_route` result, built from the request:
   - for `people`: "These are the N kilns with the most people within 800 m. The visiting order follows road travel time, not the people ranking. Ranked by people: KW-… (25,701), KW-… (20,838), …";
   - for `flags`, the same with siting flags;
   - for `kiln_ids`: "These are the kilns you named, in road order."
   The ranked list comes from the plan's own stops, sorted by the request's priority.
3. **The validator (deterministic).** When `plan_route` ran in this request and the answer contains a clock time (`\b\d{1,2}:\d{2}\b`), the answer must also contain a word starting "estimat". Otherwise it fails with a reason the model can act on ("Call the times estimates, for example 'estimated arrival 09:13'."). That gives one regeneration, then the fallback, as today. Pass the "plan_route ran" fact from `core.py` the same way the known IDs are passed.
4. **Tests:**
   - every time in the tool result is preceded by "estimated";
   - the ranking sentence is correct for `people` and `flags` and absent from the visiting order;
   - the validator fails a timed answer without "estimat" only when `plan_route` ran, and passes it otherwise (a non-route answer with a time is untouched);
   - the full suite (last run: 136 run, 126 pass, 10 skipped). Report the counts.

## Step 2: deploy (assistant Lambda only)

Package the assistant and record the SHA-256. One plan with `-target='aws_lambda_function.assistant[0]'`, saved to `.local/phase-4/p1b.tfplan`: **expect 0 add / 1 change / 0 destroy**, the code hash only; anything else, stop. Apply the saved plan and check that `CodeSha256` matches the ZIP.

## Step 3: live check (at most 3; read both counters first)

1. "Plan tomorrow in Hapur": every time is called estimated; the stops match the tool.
2. "Which kilns should I visit first for the most exposed people?": it names the most exposed kilns by people (25,701 first) and keeps that separate from the road order, or explains the difference.
3. "Plan a route starting near 28.7306, 77.7759 with 4 stops": times estimated, facts exact.

For each, report the status, the validator outcome, the latency, the tools, the full answer (in this chat only) and a judgement. Confirm the logs hold counts and latencies only.

## Step 4: documents and report

Add a short "P1b: route answer wording (32b)" entry to `AWS/docs/local-verification.md`, with no identifiers.

Report: the diff summary and test counts; the plan and apply summary and the hash check; the live table and answers; the leak check (grep the changed files for the identifiers read from the `.local` files without printing them: expect 0; `git diff --quiet AWS/.terraform.lock.hcl`; only the allowed files touched).
