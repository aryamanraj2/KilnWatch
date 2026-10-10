# Prompt 16b: Phase 4A — Bedrock through the user's second AWS account, then live answers

You are the builder for **one step** of KilnWatch Phase 4. The `assistant` Lambda (`POST /ask`) is deployed in the main account (`ap-south-1`) and works up to the model call. The main account has an **account-level Bedrock block** (`ValidationException: Operation not allowed`, even in the console playground), and an AWS Support case is open.

The user has a **second AWS account of their own** where Bedrock works in the playground. This step makes the Lambda call Bedrock **through a narrowly scoped role in that second account**. Everything else stays in the main account: the Lambda, the API, the DynamoDB cap and the logs. Then it runs the live answer checks that prompt 16 Step 5 skipped.

**The user gave the go by running this prompt.** The scope is exactly the following:
1. one IAM role in the second account;
2. a small code change;
3. a targeted apply in the main account that changes only the assistant Lambda and its policy;
4. up to 2 smoke calls and the 12 live questions.

Work sequentially in this chat. Do not use sub-agents. Do not commit, push or stage. Do not change iOS code. No `terraform destroy`, no untargeted apply, no provider-lock change.

## Read first

- `AGENTS.md`
- `App/docs/prompts/16-phase-4a-ask-deploy.md`, especially Step 5, which you will run here
- `AWS/assistant/*`, `AWS/assistant.tf`, `AWS/variables.tf`, `AWS/tests/test_assistant.py`
- `.local/phase-4/` (the prompt 15 and 16 outputs)

## Ground rules

- **Two profiles.**
  - `kilnwatch` is the main account. Check that it is IAM user `aryaman`.
  - The second account's profile name comes from the user, for example `kilnwatch-bedrock`. **Check that its identity is not root.** If it's root, stop and ask the user to create an admin IAM user in that account's console and sign in with it.
  - The user signs in to both **in their own terminal** (`aws login --profile <name> --region <region>`). Never ask for or print keys, passwords or tokens.
- **Identifiers.** Never print or write either account ID, any ARN that contains one, the API URL or ID, or emails into tracked files or the chat. Put them in files under `.local/phase-4/` and in the **ignored** `AWS/terraform.tfvars` only.
- **Tight permissions on both sides.** The second-account role can do **only** `bedrock:InvokeModel` on the chosen model, and **only** the main account's `kilnwatch-assistant-lambda` role can assume it. No `"*"` resources, no `bedrock:*`, and no long-lived access keys anywhere.
- **Product language.** Never use "illegal" outside the banned-stem constant and its tests.

## Step 0 — ask the user two things

1. The second account's CLI profile name, and that they've signed in to it.
2. The region where Nova 2 Lite answered in the playground. Prefer `ap-south-1` with `global.amazon.nova-2-lite-v1:0`. Any region is fine, because the Lambda can call Bedrock in another region.

## Step 1 — prove Bedrock works in the second account (read-only, plus at most 2 calls)

1. Run `sts get-caller-identity` with that profile. Check that it isn't root, and redirect the output to `.local/phase-4/second/identity.json`.
2. Run `bedrock list-inference-profiles` and `get-inference-profile` for the chosen model in the chosen region. Save the output under `.local/phase-4/second/`. Record the profile ID and its destination model ARNs.
3. Make **one** `Converse` call with the user's profile, using a single trivial tool and a fixed test string, to prove tool use works. Report the latency and tokens. If it fails, stop and report. A second call is allowed only to retry a clear client-side mistake.

## Step 2 — the role in the second account (AWS CLI, outside Terraform)

The second account has no Terraform state. Create the role with the CLI, and keep the JSON policies in `.local/phase-4/second/`.

1. Read the main account's assistant role ARN: `aws iam get-role --role-name kilnwatch-assistant-lambda --profile kilnwatch`, into a file. Don't print it.
2. Create the role `kilnwatch-assistant-bedrock` in the second account:
   - **Trust policy:** `Principal: {"AWS": "<that exact role ARN>"}`, `Action: sts:AssumeRole`. Nothing else.
   - **Max session duration:** keep the default (1 h).
3. Attach an **inline** policy that allows `bedrock:InvokeModel` on only:
   - the second account's inference-profile ARN for the chosen profile;
   - the destination foundation-model ARNs from `get-inference-profile`, including the region-less `arn:aws:bedrock:::foundation-model/...` ARN for a global profile.
4. Read the role back and summarise both policies with the account IDs redacted.
5. Note for the docs: if the main role is ever deleted and recreated, this trust policy breaks (AWS stores the role's unique ID) and must be re-saved.

## Step 3 — code change (`AWS/assistant/core.py`) and tests

1. Add two optional environment variables:
   - `BEDROCK_ROLE_ARN`: when set, the Lambda calls `sts.assume_role(RoleArn=…, RoleSessionName='kilnwatch-assistant', DurationSeconds=900)` and builds the `bedrock-runtime` client from the temporary credentials;
   - `BEDROCK_REGION`: when set, the `bedrock-runtime` client uses that region instead of the Lambda's own.

   When neither is set, the behaviour is exactly as it is today. That's the switch-back path.
2. **Credential refresh.** `default_bedrock()` is cached with `functools.cache` today, so a warm Lambda would keep expired temporary credentials. Replace the cache with one that stores the client **and its expiry**, and assumes the role again when fewer than 5 minutes remain. Keep it a few lines; no new dependencies.
3. **Errors.** An `AssumeRole` failure becomes `ModelUnavailable`: retryable for throttling, not for access denied. Never echo AWS error text, as before.
4. **The validator label.** It should default to `'none'` and become `'pass'` only when an answer passes, so that blocked calls no longer log `validator: "pass"`. This answers open question 3 from prompt 16.
5. **Tests**, with stub STS and Bedrock clients and no network:
   - no environment variables means no STS call;
   - with the role variable, the role is assumed once and reused;
   - it re-assumes near expiry;
   - `BEDROCK_REGION` is applied;
   - an `AssumeRole` access denial becomes 503 `model_unavailable` with no AWS text;
   - the validator label is `'none'` when the model fails.

   Run `PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v`; all tests must pass. Then run `python AWS/scripts/package_assistant.py` and record the SHA.

## Step 4 — Terraform (main account), targeted

1. Add these variables:
   - `assistant_bedrock_role_arn`: string, default `""`, validated as empty or an IAM role ARN;
   - `assistant_bedrock_region`: string, default `""`.
2. Make these conditional in `AWS/assistant.tf`:
   - when the role ARN is set, the assistant policy gains `sts:AssumeRole` on **only** that ARN. Keep the existing same-account Bedrock statement, so switching back needs no IAM change;
   - the Lambda environment adds `BEDROCK_ROLE_ARN` and `BEDROCK_REGION` only when they're non-empty, for example with `merge()`.
3. Put both values in the **ignored** `AWS/terraform.tfvars`, never in tracked files.
4. `fmt`, `validate`, then a plan with `-target=aws_lambda_function.assistant[0]` and `-target=aws_iam_role_policy.assistant[0]`, saved to `.local/phase-4/cross-account.tfplan`.
   - **Expected:** 0 to add, 2 to change (the Lambda code/env and the policy), 0 to destroy. If anything else appears, stop.
   - Show the summary in the chat, with ARNs redacted.
5. Apply that saved plan. Read back the Lambda's environment variable **names** and the policy's action list.

## Step 5 — live answers

Run prompt 16 **Step 5** ("If it works"), with these changes:
- the Step 1 call above already covers the smoke call;
- go straight to the **4 normal and 8 adversarial questions** through `POST /ask`;
- estimate the cost first (about $0.04 typical, worst under $0.40). The cost now bills to the **second account**.

Report the full table and your judgement of each answer, as prompt 16 asks.

Also:
- **Fixtures.** Save the missing fixtures into `.local/phase-4/live/fixtures/`: one **normal answer** (for example the "How many kilns are flagged in Hapur?" response) and one **fallback**. If no live question produces a fallback, build the fallback body from a unit-test run of the real code path and name it `fallback.synthetic.json`, so it's clearly not live.
- **Logs.** Search the main account's assistant log group for one of the question texts. Expect 0 matches. Show one log line, which should now show `validator: "pass"` or `"regenerated"`.
- **The cap.** Read today's counter value, without changing it, so the user knows how many questions remain today.

## Step 6 — documents and report

- **`AWS/docs/local-verification.md`:** the cross-account setup, with no IDs. The **switch-back steps**:
  1. clear the two tfvars values;
  2. run a targeted apply on the same 2 addresses;
  3. delete `kilnwatch-assistant-bedrock` in the second account after the hackathon.

  Plus the live results.
- **`App/docs/HANDOVER.md`:** one line, "Bedrock is served through the user's second account until the main account is unblocked."
- **`App/docs/api-contract.md`:** no change unless the response shape changed (it shouldn't).

Report, keeping **synthetic tests**, **Terraform**, and **live checks** separate:
1. Step 1 results: the identity type (not the ID), the profile, the smoke call latency and tokens.
2. The role summary, with both policies redacted.
3. The code diff summary, the test counts and the ZIP SHA.
4. The plan and apply summary, and the read-backs.
5. The 12-question table, your judgement of each answer, the log check and today's counter.
6. **Leak check:**
   - `git status --short`;
   - grep every changed and new tracked file for **both** account IDs, the API host and the API ID: expect 0;
   - `git diff --quiet AWS/.terraform.lock.hcl`.
7. Open questions, at most 3.
