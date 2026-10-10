# KilnWatch — orchestrator handover #4 (2026-10-10): Phase 4 mid-flight

You are taking over as **orchestrator** for KilnWatch, probably in **OpenAI Codex** (the user is saving Claude credits). This file is deliberately short. It covers what changed since handover #3 and what to do next.

For anything not covered here, read:
- **`14-orchestrator-handover.md`** (Phase 4 design, §3);
- **`11-orchestrator-handover.md`** (role, binding rules, AWS live state, model facts, review lessons, and §1a "Running in Codex").

Both still apply unless this file says otherwise. All three are snapshots: check `git status`, `git log` and the files themselves before you act.

---

## 1. Rules (unchanged, short form)

- **Your job.** You orchestrate; you don't build. You review the builder's evidence yourself (rerun tests, `git diff`, a leak scan, look at screenshots), write **one** builder prompt at a time into `App/docs/prompts/NN-*.md`, and give the user a **full pre-prompt** to paste.
  - **Builders run in Codex too.** Say in each message whether to use a **new** or the **same** chat; the default is new.
  - Builder prompts must be tool-neutral and say which commands need network approval.
- **No agents.** No sub-agents or parallel agents unless the user explicitly asks.
- **Explicit go for every gate:** deploy, commit, push, stage, any AWS write, any phase start. "Running the prompt = the go for exactly its listed scope" has worked well; keep using it and state the scope inside the prompt.
- **The user:**
  - casual, sometimes Hinglish;
  - wants terse replies, plain language and **one** recommendation;
  - owns both AWS accounts and makes every decision;
  - signs in to AWS only in their own terminal: `aws login --profile <p> --region <r>`. Never ask for or print secrets.
- **The repo is PUBLIC.** Never put these in tracked files:
  - **either** account ID, or ARNs that contain them;
  - the API URL or ID, or the RDS host;
  - emails, tfvars, `backend.hcl` or plans.

  Private values live in `.local/` and `AWS/terraform.tfvars`, both ignored.
- **Product.** Never use "illegal". A kiln is "Flagged by satellite · pending inspection". Missing data is never shown as zero. The type is "unverified". The model score is not accuracy.
- **Infrastructure.** No `terraform destroy`. No untargeted apply while CloudFront is blocked. Never widen IAM, security groups or the bucket policy. Never touch the provider lock (`hashicorp/aws 6.68.0`).

## 2. Since handover #3

| Step | Prompt | Status |
|---|---|---|
| 4A preflight + local build | 15 | Done, and reviewed by the orchestrator. |
| 4A deploy | 16 | Done, and reviewed. Assistant live, cap 50, a gross budget added. Bedrock blocked. |
| 4A Bedrock via second account | 16b | **Done, and reviewed by the Claude orchestrator** (tests 71 run / 62 pass / 9 skip rerun, lock unchanged, leak scan of 22 files 0 hits for both accounts, API host and ID). 12/12 live answers were 200 with no fallback; the fake-ID question was caught and regenerated; all answers were honest. Fixtures are now complete, including `normal_answer.json` and `fallback.synthetic.json`. §4 is kept as a reference. |
| This handover | 17 | — |
| **Next: Phase 4B iOS Ask** | **18** (to write) | See §5. |

**User decisions made in this stretch:**
- Ask is **public with no login**; the users are inspectors in the app.
- **Daily cap of 50 questions per UTC day.** The demo only needs to work **2–3 days**, so cost is a non-issue.
- **One assistant, shared with the resident portal.** The user was told to tell the AWS teammate; the portal adds its own authenticated route to the **same** Lambda later. Ask whether the message was sent and whether there's any portal news.
- **Model: Amazon Nova 2 Lite**, global profile `global.amazon.nova-2-lite-v1:0`, with reasoning **off**. Why not Claude: the Anthropic use-case form fails with an account-level error, and AWS promotional credits exclude Marketplace (third-party) models.
- **Bedrock through the user's second AWS account** while the main account is blocked (prompt 16b).

## 3. Live state (main account, `ap-south-1`)

- **Previous resources:** the 73 from before are unchanged. CloudFront is still blocked, and the registry runner is still on.
- **8 new assistant resources** (prompt 16):
  - Lambda `kilnwatch-assistant`: Python 3.12, outside the VPC, reads only the public API, 28 s timeout;
  - its own IAM role;
  - log group (14 days);
  - DynamoDB `kilnwatch-assistant-daily` (an atomic daily counter, TTL);
  - integration, route `POST /ask` (no auth) and Lambda permission.

  The stage gives `POST /ask` rate 1, burst 2. In practice this is loose: 20 parallel requests got only 2 × 429. The cap is the real guard. The toggle lives in the ignored `terraform.tfvars` (`enable_assistant = true`, model ID).
- **Code:** `AWS/assistant/{handler,core,tools,validator}.py`, `AWS/assistant.tf`, `AWS/scripts/package_assistant.py`, `AWS/tests/test_assistant.py` and `AWS/tests/public_hapur.json` (39 trimmed records, no host).
  - **Python tests:** 65 run, 56 pass, 9 skipped (opt-in PostGIS), before 16b.
- **Response contract:** in `App/docs/api-contract.md`, the "Phase 4A — Ask" section.
  - **200:** `{answer, citations[], steps[{tool,label,summary,ok}], fallback, disclaimer}`.
  - **Errors:** nested `{"error":{"code","message","retryable"}}`:
    - 400 `invalid_request`;
    - 429 `daily_cap_reached`;
    - 503 `assistant_unavailable` (the counter), `upstream_unavailable` (the public API) or `model_unavailable`.
  - **API Gateway throttling:** 429 with `{"message":"Too Many Requests"}` and **no** `error.code`.
- **Validator:** every `KW-…` in the answer must come from a tool result in this request; rule-ID shapes are rejected; banned **stems** (`illegal|unlawful|violat`, matched at a word start). On failure it regenerates once, then returns a fixed fallback that contains no model text.
- **Logs:** counts and latencies only. Verified live: a sentinel question and its coordinates are absent from the logs.
- **Budgets:** `kilnwatch-monthly-50` (net of credits) and `kilnwatch-monthly-gross-50` (gross). Both alert at 80% actual and 100% forecast.
- **Main-account blocks:**
  - CloudFront: "account must be verified";
  - Bedrock: `ValidationException: Operation not allowed`, even in the console playground. AWS's own article calls this an account security restriction that only Support can lift.

  One Support case ("Account verification request to create CloudFront distributions") was **unassigned after 10 hours**. The user was told to add Bedrock to it and try Chat.
- **Recorded fixtures for prompt 18** are in `.local/phase-4/live/fixtures/`: `daily_cap_reached`, `invalid_request`, `model_unavailable` and `gateway_throttled`. 16b should add a **normal answer** and a **fallback** (a synthetic fallback must be named `*.synthetic.json`).

## 4. Reviewing the 16b report (do this first)

Check these yourself, not just the report's claims:
- [ ] `PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v` passes; expect more than 65 tests and 9 skips.
- [ ] `git diff --quiet AWS/.terraform.lock.hcl` passes.
- [ ] **The leak scan finds 0 matches for both account IDs, the API host and the API ID** in every modified or untracked tracked-path file:
  - the main account ID comes from `.local/integration-2b/outputs.json` (a secret ARN, field 4);
  - the API host comes from `api_base_url`;
  - the second account ID comes from `assistant_bedrock_role_arn` in the ignored tfvars.

  Never print any of them.
- [ ] The role in the second account:
  - trust is **only** the main `kilnwatch-assistant-lambda` role ARN;
  - the inline policy is **only** `bedrock:InvokeModel` on the profile ARN plus its destination model ARNs;
  - no `*`;
  - the identity used was not root.
- [ ] The main-account plan was **0 add / 2 change / 0 destroy**: the Lambda plus its policy, with `sts:AssumeRole` on only that ARN.
- [ ] The code caches the assumed-role client **with expiry** and re-assumes under 5 minutes; no env vars means the old path; the validator label defaults to `'none'`.
- [ ] **Read all 12 live answers yourself.** Look for:
  - banned stems, or "confirmed"/"compliant" claims;
  - invented routes, owners, health, legal or distance claims;
  - shortened IDs;
  - missing-data honesty: rules not evaluated, exposure not assessed, images not published.

  If the trick questions ("Is this kiln illegal?", "dangerous for my kids?", "nearest school?") produce poor but validator-passing text, consider a small `prompt`/system-prompt tweak prompt before iOS.
- [ ] The normal and fallback fixtures exist, and the log check shows 0 question text.

**If 16b failed**, for example because the second account is also blocked: fall back to the demo plan. iOS Ask runs on recorded and synthetic fixtures with an honest "Ask isn't available right now" live state, and the scripted Sample-data Ask stays for fixture mode. Don't burn time on workarounds.

**Switch-back, once the main account is unblocked:**
1. clear `assistant_bedrock_role_arn` and `assistant_bedrock_region` in tfvars;
2. run a targeted apply on `aws_lambda_function.assistant[0]` and `aws_iam_role_policy.assistant[0]`;
3. after the hackathon, delete `kilnwatch-assistant-bedrock` in the second account.

## 5. Next: prompt 18, Phase 4B iOS Ask

**Decisions from the 16b review, to put into prompt 18 as a small backend Step 0** (one targeted apply of `aws_lambda_function.assistant[0]` only, expecting 0/1/0, plus a re-run of 2–3 live questions):
- **The system prompt asks for plain text, with no markdown.** Question 10 came back with `**bold**`. iOS renders plain text, and also strips stray `**` defensively.
- **Add one line to the system prompt:** "Don't suggest actions or contacts beyond what KilnWatch shows; say what data is missing instead." Question 8 ended with mild advice to contact local authorities.
- **Second-account budget:** Bedrock now bills to a teammate's second account, which has no alarm. The user should get that teammate's OK and create a small (about $10) budget there in the console. That's a user action, not a builder action. The 50/day cap remains the hard limit.

The second account belongs to a teammate. In docs, refer to them by role only (for example "the second account's owner"); never write their name.

Scope: handover 14 §3.2, with these updates:
- **Core.** `KilnWatchCore` gets `ask(question:kilnId:lat:lon:)` on the existing public, token-free client.
  - URL: `KILNWATCH_PUBLIC_API_URL` + `/ask`. No new config key.
  - Codable types for the 200 body and the nested error.
  - Tests use **identifier-free copies** of the `.local/phase-4/live/fixtures/*` bodies. Strip anything host-like.
- **Errors mapped to honest UI copy:**
  - 400: the question is too long or invalid;
  - 429 with `daily_cap_reached`: "Ask has reached today's limit";
  - 429 with no `error.code` (API Gateway throttling): "Too many questions, wait a moment";
  - 503 `model_unavailable` with `retryable:false`: "Ask isn't available right now";
  - other 503s: retryable;
  - offline: the composer is disabled;
  - `fallback:true`: show the fixed text plus the citation chips, without the reveal animation.
- **UI (`App/KilnWatch/Features/Ask/AskView.swift`, now a scripted `AskScript`):**
  - in live mode, show the server `steps` as the trace (an honest waiting state while the single request is in flight; there's no streaming);
  - citation chips use real IDs and push the real kiln detail;
  - every answer shows the disclaimer;
  - the word-by-word reveal may animate already-validated text, and is off under Reduce Motion;
  - the empty-state prompts are ones the real data can answer;
  - "Ask about this kiln" on the detail screen pre-fills the ID;
  - in fixture mode or with no URL: keep the scripted demo, labelled **Sample data**, never mixed with live data;
  - the 500-character limit is enforced in the composer.
- **Binding:** `DESIGN.md`; light and dark; AX3/AX5; Reduce Motion; zero warnings in the root build; core `swift test` green; UI tests where stable.
  - Native beta tab-bar elements are flaky under XCUITest on iOS 27: accept one manual Simulator check and don't loop.
  - Screenshots go in `App/docs/screens/phase-4/`, and **you look at them yourself**.
- **Live calls from the builder:** a handful against the real `/ask` is fine, at about $0.003 each, but they count toward the 50/day cap. Tell the builder to read today's counter first and use at most about 10.
- After 18, offer an optional polish prompt (like 13) and then a **commit** on the user's go, with a leak scan first.

## 5a. Teammates pushed a rules engine and exposure (read `AWS/rules/README.md` and `HANDOVER.md`)

- **New since `fb60572`:** `AWS/rules/`, with cited v1 thresholds in `rules_v1.json`.
  - A UP 2026 amendment sets habitation at 800 m and kiln spacing at 1 km. That settles the old 800 vs 1,000 m conflict, but only from **secondary sources**. School, highway and rail thresholds are marked unverified.
  - **HRSL population exposure** within 800 m.
  - `registry.cli validate-assessment` / `apply-assessment`, and migration `002_assessment.sql`, which adds an assessor role.
  - App fixtures and `Violation.evidenceUrl` (now optional) changed.
- **Local Hapur result:** 36 of 39 kilns flagged, 52 flags in total, with a median exposure of 4,228 people. Some near-zero distances suggest false-positive detections.
- **None of this is in RDS yet** (no migration or apply was run). The live API still returns `rules_assessment: not_evaluated` and `exposure: null`.
- **Rechecked on the Mac after the merge** (the teammate couldn't, because they're on Windows): root build succeeded, core `swift test` passed 35 tests, and Python ran 91 tests with 10 skips.
- **When the assessment is applied to RDS** (a separate, explicitly approved deploy step, through the runner and SSM), Ask must change at the same time, or it will contradict the data:
  - `tools.trim` must pass the violations (rule ID, distance, status) and the exposure counts;
  - the validator must allow rule IDs **that appear in this request's tool results**;
  - the system prompt's "rules not evaluated / exposure not assessed / never cite a rule ID" lines must become conditional;
  - the iOS "Rules not evaluated" and "Population exposure not assessed" states must render real data.

  Product language stays: "flagged by satellite, pending inspection" and "siting signal", never a legal verdict. Ask the user whether to do this before or after prompt 18. My recommendation: **after**. Ship iOS Ask on the current live data first, then a combined "apply assessment + Ask and app update" step.

## 6. Git state

- **Phase 4A is committed and pushed** (`2e7470f`, rebased on the teammates' rules-engine commits; the leak scan of the outgoing diff was clean).
- Only `App/docs/screens/phase-2/*.log` are untracked; they're old, so leave them.

## 7. Open items

- **User:**
  - the Support case (CloudFront + Bedrock);
  - the message to the AWS teammate about the shared assistant;
  - the AWS teammate's IAM user (no admin or billing; "IAM access to Billing" is now activated on the main account, so keep billing permissions off that user).
- **After the hackathon** (ask before doing any of it):
  - `enable_assistant=false`;
  - delete the second-account role;
  - remove the runner (`create_registry_runner=false`, part of prompt 09 Part B);
  - remove the teammate's IAM user;
  - decide on the always-on about $38/month.
- **Still open from 14 §4:**
  - the siting-rule conflict (800 m vs 1,000 m);
  - Phase 5 sign-in;
  - Phase 6 Hindi and accessibility;
  - real routing;
  - the ML team mate's items.

## 8. Lessons from this stretch

- **Builders report honestly but miss things; rerun and read.** The 4A builder's whole-word banned list let "illegalities" pass, and its test asserted that as "fine". The cause was ambiguous wording in our prompt ("words that merely contain them don't"). Be precise about matching rules.
- **HTTP API stage throttling is approximate.** Use a hard counter for cost safety.
- **`ValidationException: Operation not allowed`** from Bedrock means an account security restriction. Only Support can lift it, and it isn't IAM or model access. Don't retry in loops.
- **Padlocks on every region** in the console's selector only mean you're on a global service page (Billing). That's normal.
- **Credits:** AWS promotional credits exclude Marketplace fees, so Anthropic-on-Bedrock likely isn't covered and first-party Nova is.
- **The user likes:** a full copy-paste pre-prompt for every builder prompt, a "new or same chat" note, and step-by-step console instructions when they have to click something.

## 9. Your first response to the user

1. Confirm you've read this file, plus 14 and 11 (at least §1, §1a and §7 of 11), and checked `git status` and `log`.
2. 16b is already reviewed (§2). Don't redo the review; at most, rerun the tests and the leak scan.
3. Phase 4A is already committed and pushed. Raise §5a in one line (recommend: rules and exposure go live after iOS Ask), then write **prompt 18** (Phase 4B iOS Ask, with the small backend Step 0 from §5) and its full pre-prompt.
