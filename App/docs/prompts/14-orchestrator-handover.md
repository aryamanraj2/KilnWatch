# KilnWatch — orchestrator handover #3 (2026-10-10): Phase 4 "Ask"

You are taking over as **orchestrator** for KilnWatch. The previous orchestrator chat got too long. You may be running in **Claude Code or OpenAI Codex**. If you're in Codex, §1a of handover #2 applies.

This file covers what changed since handover #2 and the full plan for the next step, **Phase 4 (Ask)**. It does **not** repeat everything:
- **`11-orchestrator-handover.md` is still required reading.** It holds your role, the binding rules, the AWS live state, the model and registry facts, the open items and the review lessons. Unless this file says otherwise, all of it still applies.
- Both files are snapshots. Check `git status`, `git log` and the files themselves before you act.

The user wants to **start Phase 4 now.**

---

## 1. The rules, short version (full text in 11 §1 and §1a)

- **Your job.** You orchestrate; you don't build. Review the builder's evidence, write one builder prompt at a time into `App/docs/prompts/NN-*.md`, and explain things simply. The user runs each prompt in a separate builder chat and pastes back the report. You check the report yourself before moving on: screenshots, `git status`/diff, a scan for identifiers, quick test reruns.
- **No agents.** No sub-agents, parallel agents or auditors unless the user explicitly asks in that turn. The Phase 3 overnight sub-agent run was a one-time exception and is over.
- **Explicit go for every gate.** Never deploy, commit, push, stage, retrain, rerun inference, or start a phase or AWS change without the user's explicit go for that scope. **Phase 4 counts as started**: the user said "we will do phase 4 right now". Every **AWS deploy inside Phase 4 still needs its own go**.
- **Names.** Use **AWS teammate** (the user's friend, who builds the resident portal) and **ML team mate**. They are humans; never message them yourself.
- **The user** owns the AWS account and makes every decision. They write casually, sometimes in Hinglish. They want terse chat replies, plain language and one clear recommendation. Documents and prompts are written in normal prose.
- **Never use "illegal"** in the app, the portal or any agent output. Until an inspector records a verdict, a kiln is "Flagged by satellite · pending inspection". Missing data is never shown as zero. The model's type prediction is always "unverified".
- **The repo is PUBLIC.** Never put these in tracked files:
  - the account ID, ARNs that contain it, the RDS hostname or the API URL;
  - emails, tokens, `terraform.tfvars`, `backend.hcl` or Terraform plans.
- **Secrets.** The user signs in to AWS in their own terminal (`aws login --profile kilnwatch --region ap-south-1`; IAM user `aryaman`, never root). Never ask for or print passwords, keys or tokens.
- **Infrastructure limits.** No `terraform destroy`. Never widen IAM, security groups or the bucket policy. Never expose RDS. Never casually upgrade the provider lock (`hashicorp/aws 6.68.0`).

## 2. What changed since handover #2

| Step | Prompt | Status |
|---|---|---|
| Phase 3: iOS on the public API, no sign-in | 12 (overnight, sub-agents once) | Done. Commit `66e764f`, pushed. Report: `App/docs/screens/phase-3/overnight-report.md` |
| Phase 3 polish | 13 | Done and reviewed by the orchestrator. Commit `fb60572`, pushed. Report: `App/docs/screens/phase-3/polish-report.md` |
| This handover | 14 | — |

**What the app does now (Phase 3 + polish):**
- **Startup.** No sign-in. It loads the **39 real Hapur kilns** from `GET /public/kilns?district=Hapur` with paging.
- **Configuration.** The API URL is only in the ignored `App/Config/Public.xcconfig`; the tracked template is `Public.xcconfig.example`. `App/Config/Base.xcconfig` does `#include? "Public.xcconfig"` and uses `App/Config/PublicInfo.plist`.
  - With a URL, the app shows "Live data". Without one, it shows explicitly labelled "Sample data" fixtures.
  - The two are never mixed in one list. Kilns are not persisted on the device.
- **Kilns tab.** Search and filter. Honest states for loading, empty, offline, 429 with backoff and Retry, and 503 with Retry.
- **Kiln detail.**
  - The title is a short ID; the full ID sits underneath and is selectable.
  - Shows "Predicted FCBK · unverified", the badge, "Model score 0.32" (with a note that it isn't a rule check), the imagery dates, and "Satellite images not yet published" (live URLs are null until CloudFront exists).
  - Shows "Rules not evaluated" and "Population exposure not assessed".
  - The mini-map fits the footprint, drawn as a clay outline with an 8 pt dot.
  - Ends with "Sign-in coming soon. Inspection actions aren't available yet."
- **Today tab.** All 39 real pins (22 pt, 44 pt tap targets) and "Route planning isn't available yet". Tapping a pin opens the detail.
- **Fixtures.** The nine-stop fixture route demo still works when fixtures are in use.
- **Tests and build:** core 34 tests, 33 pass and 1 opt-in skip; root build with zero warnings; 8 UI test methods pass. Spoken VoiceOver, a physical device, and live imagery have never been tested.
- **Ask tab:** still **scripted**. `App/KilnWatch/Features/Ask/AskView.swift` has `AskScript` with canned answers, fake `[KW-0412]` citation chips and a "play" animation. That is what Phase 4 replaces.

**Unchanged:**
- AWS is still at 73 of 75 resources; CloudFront is blocked until the account is verified (Support case). Part B of prompt 09 is still pending, and the registry runner is still on (about $0.42/day).
- The portal is with the AWS teammate (prompt 10). Its progress is unknown to this chat.
- The hackathon deadline is **still unknown**. Ask the user.

## 3. Phase 4: what "Ask" should be (the recommended design; confirm with the user first)

`build-plan.md` describes Phase 4 as a "Streaming agent endpoint, tool-call trace, tappable citation chips". `DESIGN.md` line 117 specs the Ask screen. The original research (`App/docs/research/agent-streaming.md`) recommended AgentCore Runtime plus SSE with an inspector JWT. **Reality has changed since then**: there is no app sign-in until Phase 5, AgentCore is disabled, the region is `ap-south-1`, and the only real data is 39 flagged records with no rules, exposure or routes. So I recommend the following.

### 3.1 Backend: one small `assistant` Lambda, shared with the portal later

- **Location:** outside the VPC. **It reads data only through the existing public API over HTTPS**, never RDS.
  - It needs no VPC endpoint. A Bedrock runtime interface endpoint would cost about $15/month for two availability zones, and there is no NAT gateway.
  - It needs no database credentials or new database role, and it can only ever see public, flagged-only, allowlisted data.
- **Route:** `POST /ask` on the existing HTTP API, **no auth**, because the app has no sign-in. Request: `{question, kiln_id?, lat?, lon?}`. English only; Hindi is Phase 6.
- **Model:** Bedrock `Converse` with **tool use**, temperature ≤ 0.2, `maxTokens` about 600, and at most about 4 tool rounds.
  - The model ID or inference profile available in `ap-south-1` must be confirmed read-only in the preflight. Don't assume one.
  - `AWS/agent/agent.py` defaults to `us-west-2` and a Sonnet ID; treat that as a reference only.
  - The user must enable model access in the Bedrock console themselves, if needed.
- **Tools,** each a thin wrapper over the public API:
  - `list_flagged_kilns(district, limit)`
  - `kilns_near(lat, lon, radius_m)`
  - `kiln_detail(kiln_id)`
  - These are the tool-call trace the UI shows. **No routing tool and no rule tool**, because neither exists yet.
- **System prompt:** adapt prompt 10's R5 rules.
  - Never say illegal or violation; use "flagged by satellite, pending inspection".
  - State missing data plainly: rules not evaluated, exposure not assessed, imagery not published.
  - The type is unverified. The model score is not accuracy or a rule check.
  - No health, emission or legal claims. Agents never record verdicts.
  - Route planning isn't available yet, so say so and never invent a route.
- **Citation validator,** deterministic and run before returning:
  - every `KW-…` ID in the answer must have come from a tool result in this request;
  - any rule-ID pattern is rejected, because the rules list is empty;
  - banned words fail the answer.
  - On failure, regenerate once with the reason. If it fails again, return the safe fallback text and nothing invented.
- **Response:** **no streaming in v1.** HTTP APIs can't stream, and the portal made the same choice. Return one JSON body:
  - `steps: [{tool, label, summary, ok}]`, with server-written labels such as "Searching flagged kilns" and "39 found";
  - `answer` (validated text);
  - `citations: [kiln_id]`;
  - `disclaimer`.
  - SSE or AgentCore streaming is a later, separate decision.
- **Abuse and cost controls.** These are mandatory because this is a public route that costs money per call, and the URL can be pulled out of the app.
  - Stage throttling on `POST /ask`: about 1 request/second, burst 2.
  - Question length ≤ 500 characters.
  - A **hard global daily cap**, for example 300 questions/day. A Lambda outside the VPC can't reach RDS, so the cheapest correct counter is **one DynamoDB on-demand table with an atomic `UpdateItem` counter per UTC day and a TTL**. That breaks prompt 10's "no DynamoDB unless RDS truly cannot serve it" rule, and the reason applies here, so say so in the prompt.
  - When the cap is reached, return 429 with a clear message.
  - **No Lambda reserved concurrency;** it fails on new accounts.
  - Logs carry counts and latencies only, never question text or locations.
  - Check the existing $50/month budget alert covers this.
- **Sharing with the portal.** The AWS teammate's R5 plans its own `assistant` Lambda with resident auth. Tell the user to tell the AWS teammate that this one exists. The portal can later add an authenticated route to the **same** Lambda instead of building a second assistant. **Don't let two assistants get built.**
- **Code layout:** `AWS/assistant/` (handler, tools, validator, prompt) plus Terraform in `AWS/assistant.tf`, gated by a new `enable_assistant` variable (default `false`).
  - Packaging should match `AWS/scripts/package_api.py`. **boto3 is already in the Lambda runtime; add no new dependencies.**
  - The old Strands/AgentCore code in `AWS/agent/` stays untouched.

### 3.2 iOS: wire the existing Ask screen to the endpoint

- **Core client.** `KilnWatchCore` gets `ask(question:kilnId:lat:lon:) async throws -> AskAnswer` on the public, token-free client from Phase 3, plus Codable types and tests with recorded fixtures.
  - Errors: 400, 429 (rate-limited and daily cap, as separate messages), 503, offline, and the validator-fallback answer.
- **UI.**
  - **Live mode:** `AskView` calls the endpoint. It shows the `steps` trace while waiting (an honest "Searching flagged kilns…"), then the answer. Citation chips are real IDs that push the real kiln detail. Every answer carries the disclaimer.
  - **Text reveal:** the word-by-word reveal may animate *already-validated* text locally; it's off under Reduce Motion.
  - **Prompts:** the empty-state example prompts are replaced with ones the real data can answer, for example "How many kilns are flagged in Hapur?", "Which flagged kilns are nearest Hapur town?", "Explain KW-6b3b38…".
  - **"Ask about this kiln"** on the detail screen pre-fills a question with that ID.
  - **Offline:** the composer is disabled, as in `DESIGN.md`.
  - **Without an Ask URL or in fixture mode:** keep the scripted `AskScript` demo, clearly labelled Sample data, never mixed with live data.
- **Configuration:** the Ask URL is the same `KILNWATCH_PUBLIC_API_URL` base (`/ask` path), so there's no new secret and no new config key unless the builder needs one.
- **Binding requirements:** `DESIGN.md`; light and dark; AX3/AX5; Reduce Motion; zero warnings; screenshots into `App/docs/screens/phase-4/`.

### 3.3 Recommended prompt sequence (one at a time, each with a stop point)

1. **Prompt 15: Phase 4A preflight and local build** (no deploy).
   - **Read-only AWS checks:** Bedrock models and inference profiles in `ap-south-1` (`aws bedrock list-foundation-models` / `list-inference-profiles`), model-access status, and dated per-token prices plus a cost-per-question estimate.
   - **Local build:** the handler, tools, validator and Terraform. Unit tests mock Bedrock and the public API.
   - **Validator tests:** adversarial questions, for example "Is this kiln illegal?", "Who owns it?", "Plan my route", "Is it dangerous for my kids?", and an injected fake `KW-` ID.
   - **Terraform offline checks:** `fmt`, `validate`, and a plan **read-only** with `-target` while CloudFront is blocked. Show the plan; don't apply.
   - **Report:** the model choice, the cost estimate and the plan.
2. **Prompt 16: Phase 4A deploy** (only on the user's go).
   - Apply with `-target`.
   - Live checks: normal questions; adversarial questions (a small fixed set, about 10, with a cost estimate first); oversize input returns 400; throttling and daily-cap configuration read back; no question text in the logs.
3. **Prompt 17: Phase 4B iOS Ask** on the live endpoint, with recorded fixtures for tests and screenshots.
4. Optional polish prompt, like 13.

You may merge 15 and 16 if the user wants speed; the deploy still needs an explicit go.

### 3.4 Decisions to put to the user before prompt 15 (one short message, with your recommendation)

1. **Public Ask with no login,** protected by throttling plus a hard daily cap (recommended for the demo). The alternative is to wait for Phase 5 sign-in.
2. **Daily cap number,** for example 300/day, and whether the $50 budget stays.
3. **One shared assistant with the portal** (recommended). The user tells the AWS teammate.
4. **The hackathon deadline,** and whether CloudFront verification has come through. If it has, run Part B of prompt 09 first or in between; it's quick and the app is ready for images.

## 4. Still open (from 11 §5, updated)

- **User:**
  - the AWS Support case for CloudFront;
  - an IAM user (with MFA) for the AWS teammate, plus privately sharing the API URL, `backend.hcl` and tfvars;
  - the deadline.
- **AWS teammate:** the portal (prompt 10, R0–R7), then Part B after verification, and later an API Gateway 5xx alarm.
- **ML team mate:** the Kaggle run identity and score linkage, interpretation of the evidence pair, review of type confusion, and more AOI/district scans.
- **Product:** the siting-rule conflict (800 m vs 1,000 m, and the school rule IDs) must be resolved from official text before any rules engine is built. Until then, nothing shows a legal distance.
- **Later phases:**
  - Phase 5: Cognito sign-in (PKCE, `ASWebAuthenticationSession`, Keychain), verdict capture, outbox sync, a test inspector user;
  - Phase 6: Hindi, VoiceOver, AX5, app icon, TestFlight;
  - also: real route planning (Amazon Location + OR-Tools), the rules and exposure engine, automated scene inference, the review console.

## 5. Lessons added in this stretch

- **Look at the screenshots yourself.** The Phase 3 report was honest but missed the wrapped title and the content showing under the back button. You only catch that by looking at the images.
- **Reported numbers can differ from the prompt.** The reference kiln's score is **0.32**, not the 0.82 the prompt used as an example, and the builder correctly kept the real value. Treat any example value in a prompt as illustrative.
- **Native beta tab-bar elements are flaky under XCUITest** (iOS 27). Accept one manual Simulator check plus a recorded "harness failure"; don't let builders loop.
- **Leak-scan cheaply before any commit:** grep the pending files for the API host prefix and the account ID, both taken from the ignored local files, without printing them. Sentinel's public `amazonaws.com` bucket URLs in fixtures are fine; they are public scene sources.

## 6. Your first response to the user

1. Confirm you've read this file, `11-orchestrator-handover.md`, `App/docs/HANDOVER.md`, `DESIGN.md` (the Ask section) and `research/agent-streaming.md`, and checked `git status`/`log`.
2. In one short message, ask §3.4's four decisions, with your recommendation.
3. On their answers, write **prompt 15** (Phase 4A preflight and local build, no deploy) and stop for review.
