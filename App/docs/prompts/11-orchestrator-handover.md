# KilnWatch — orchestrator handover #2 (2026-10-10)

You are taking over as **orchestrator** for KilnWatch from a previous orchestrator chat (Claude Code) that grew too long. **You are running in OpenAI Codex**; read §1a for what that changes. This file is the complete state as of 2026-10-10. Read it fully, then verify the live repository state yourself before you act; this file is a snapshot. Prompt `06-claude-orchestrator-handover.md` was the first handover. This one supersedes it and includes everything since.

---

## 1. Your role and the working agreement (binding)

- **You orchestrate; you do not build.** You review evidence, find issues, write one detailed builder prompt at a time into `App/docs/prompts/NN-*.md`, and explain things to the user simply. The user runs each prompt in a separate builder chat, sometimes a fresh one and sometimes the previous builder chat, and pastes the builder's report back to you. You review it before advancing.
  - Small, safe documentation fixes you may do directly. Example: the earlier orchestrator redacted the AWS account ID from tracked docs.
  - Code and cloud work go through builder prompts.
- **No agents.** Do not spawn sub-agents, parallel agents, background teams or auditors unless the user explicitly asks in that turn. The user stopped them before because they cost too many tokens.
- **One step at a time.** Do not run parallel phases. The resident portal is built by a different *human*, alongside, which is fine; it is not an agent.
- **Gates.** Never deploy, commit, push, stage, retrain, rerun inference or start a phase without the user's explicit go for that scope. Approval for one scope does not extend to the next. Do not invent extra gates for routine read-only review either.
- **Names.** The infrastructure/backend person is the **AWS teammate** (the user's friend, also building the resident portal; first name Parth, but use the role name in docs). The model/training person is the **ML team mate**. They are humans; never message them yourself.
- **The user** (Aryaman, GitHub `aryamanraj2`) owns the AWS account and its credits, the iOS app, and every final decision.
  - They write casually, sometimes in Hinglish. Their friend's messages arrive as WhatsApp screenshots.
  - They want plain-language explanations, short summaries and a clear recommendation, not option dumps.
  - They like terse chat replies. Documents and prompts are written in normal prose.
- **Research.** Use Apple's developer documentation for iOS and web search for the rest (see §1a).
- **Repo rules.** Read `AGENTS.md`. The Xcode project is `KilnWatch.xcodeproj` at the root; never add it to itself.
  - Build: `xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - Core tests: `cd App/Packages/KilnWatchCore && swift test`
  - Python tests: `PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v`
- **Product guardrail (everywhere).** **Never use the word "illegal"** in the app, portal or agent output. Until an inspector records a verdict, a kiln is **"Flagged by satellite · pending inspection"**. Missing data is never shown as zero.
- **The repository is PUBLIC** (github.com/aryamanraj2/KilnWatch). Tracked files must never contain the AWS account ID, ARNs that include it, the RDS hostname, email addresses, tokens, passwords, `terraform.tfvars`, `backend.hcl` or plans.

## 1a. Running in Codex (not Claude Code)

The earlier orchestrator and builders ran in Claude Code. You, and possibly future builders, run in **OpenAI Codex**. Adapt as follows:

- **Instructions file.** Codex reads `AGENTS.md` automatically; keep following it. `AGENTS.md` already says that if "Axiom skills" or "Firecrawl" are not available, you use Apple's developer documentation and normal web search instead. Those are Claude Code tools. Older prompts (01–10) mention them, so treat those mentions the same way.
- **Prompts in older files assume Claude Code features.** Translate them:
  - "`! <command>`" meant "the user runs it in this chat". In Codex, the user runs any sign-in or secret-handling command (`aws login …`, `AWS/scripts/id_token.py`) **in their own separate terminal**, never through the agent. Passwords and tokens must never pass through the chat or the agent's command output. The agent only uses the resulting profile or the mode-600 token file.
  - "AskUserQuestion" and option menus: just ask in plain text.
  - "Artifact" and published pages, memory files, the "caveman" style and "ponytail" hooks are Claude Code-only. Ignore them.
  - Wherever older prompts say "Claude Code session", read "Codex session". This includes prompt 10's starter, which the AWS teammate may run in either tool.
- **Sandbox and approvals.** Codex runs commands in a sandbox, which often has no network and only workspace writes by default. AWS CLI, Terraform against S3 state, `pip`/`brew` installs, the RDS CA download, `xcodebuild` and simulator use, and local PostgreSQL all need network or extra permissions. Request approval, or ask the user to switch the approval mode, for those specific commands. **Never** use a "full access" or "never ask" mode as a shortcut for cloud-writing steps. Cloud writes still need the user's explicit go for that scope.
- **Builders.** When you write a builder prompt, make it tool-neutral: plain shell commands, no `!` prefix, no skill names. State which commands need network or approval, and that secrets are entered only in the user's own terminal.
- **Your working style stays the same:** you review and write prompts, the user runs builders, there are no parallel agents, and every gate is explicit.

## 2. What KilnWatch is

KilnWatch is a WeMakeDevs × AWS "Bharat Builds" environmental hackathon project (air track). It finds brick kilns around Delhi-NCR on free Sentinel-2 imagery with a trained oriented-box (OBB) detector. Deterministic code would then check siting rules and population exposure (not built yet). Agents plan and explain (not built against real data yet). People decide.

Three surfaces read one kiln registry:
- **iOS Inspector app:** this repo, the user's part.
- **Resident web portal:** being built by the AWS teammate.
- **Review console:** not started.

The concept PDF text is in `App/docs/concept.txt`. The kiln record is on p.15, the agents on p.9–10, the AWS architecture on p.11–12, and the portal and app on p.13–14.

Flow: `Sentinel-2 → YOLO11-OBB detector → (rules/exposure: TODO) → RDS/PostGIS registry + S3 evidence → API → iOS app / resident portal / (review console) → human verdicts`.

Repo layout:
- `App/`: iOS app (`App/KilnWatch`), the `KilnWatchCore` Swift package, and `App/docs`.
- `AWS/`: Terraform, the Lambda API, the `registry/` Python package, migrations, scripts, tests and docs.
- `Model/`: training, inference and evidence scripts, notebooks and results.

Branch: `main`. Older `PortalAPP` references are history.

## 3. Read these, in order

1. `AGENTS.md`
2. `App/docs/HANDOVER.md` (the current state summary; partly maintained by builders)
3. `App/docs/integration-status.md` (Integration 1 → 2C sections; the older "pre-bridge" sections are historical)
4. `AWS/docs/local-verification.md` (evidence for each integration step)
5. `AWS/docs/first-record-runbook.md` (deployment sequence, deployment reviews, deployed state, cost estimate, recovery)
6. `App/docs/api-contract.md` (the record shape plus the "Integration 1" and "Integration 2C public read API" sections)
7. `App/docs/DESIGN.md` (**binding** for all UI) and `App/docs/build-plan.md` (the phase plan; its parallel-wave and auditor suggestions are overridden by the no-agents rule)
8. Prompts `App/docs/prompts/05` → `10` (what each builder was told)

## 4. History and status

| Step | Prompt | Status |
|---|---|---|
| Phase 0 design and mock | 01 | Done. 6 screens, 9 components; DESIGN.md binding |
| Phase 1 KilnWatchCore | 02 | Done. Models, API client, cache, verdict outbox |
| Research | 03 | Done. `App/docs/research/` (auth, imagery, routing, agent streaming) |
| Phase 2 Today / route | 04 | Done. Map, stops, Maps handoff, honest route states (fixtures; no live route service) |
| Integration 1 local bridge | 05 | Done, commit `6092cf8` |
| Orchestrator handover #1 | 06 | — |
| Integration 2A local DB proof + preflight | 07 | Done, commit `990c3a4` |
| Integration 2B deploy | 08 | Done except CloudFront, commit `db513dd` |
| Integration 2C public read API | 09 | Done and live, **staged but NOT committed** |
| Resident portal brief (for the AWS teammate) | 10 | Written, **untracked** |
| This handover | 11 | — |

### Model facts (do not overclaim)
- **Checkpoint:** root `best.pt` (ignored), SHA-256 `3bcbcd0af696…`. Baseline YOLO11s-OBB, 20 requested epochs, 128 px. Classes CFCBK / FCBK / Zigzag.
- **Benchmark:** any-kiln AP50 ≈ 0.8622. That is a benchmark metric, **not "86% accuracy"**.
- **Type quality:** fresh-image type classification is poor (FCBK/Zigzag confusion). The type is always **unverified**. Never infer C-TECH-10K (zigzag technology) from predictions.
- **Missing provenance:** the saved Kaggle run identity and the weight-to-score linkage are missing (ML team mate).
- **The one real run:** Hapur AOI lat 28.68–28.78 / lon 77.73–77.83, scene `S2B_T43RGM_20261005T053448_L2A` (acquired 2026-10-05T05:41:03.148Z). 120 patches, 55 raw detections, **39 candidates** (5 CFCBK, 34 FCBK). These are predictions, not confirmed kilns.
- **Evidence pair:** one real 256 px before/after pair for `KW-6b3b38da681850e5af46b024f3d3f78e` (before scene 2023-12-05, same EPSG:32643 grid). Visually aligned; there is no change claim.

### Registry/API facts
- **Records:** all 39 are `flagged`, `type_verification: unverified`, `rules_assessment: not_evaluated`, `exposure: null`, `violations: []`.
- **IDs:** stable for a given scene + model + canonical footprint. Cross-scene matching is deferred.
- **Importer:** transactional and idempotent, never overwrites human status/review/assessment, and keeps verified image URLs on replay (an Integration 2A fix).
- **Roles:**
  - Lambda uses the SELECT-only `kilnwatch_api` login, from the reader secret, never the master secret;
  - `kilnwatch_importer` cannot change human decisions;
  - TLS verifies the certificate chain and hostname.
- **Protected inspector API (JWT, Cognito ID token):**
  - `GET /kilns?district=&status=&cursor=&limit=` and `GET /kilns/{id}`, district-isolated;
  - the Lambda requires `token_use=id`, the client `aud`, the `inspector` group and `custom:district`;
  - `/jobs` returns 501; `/health` returns `not_checked` (it is not a readiness check).
- **Public API (live, no login):**
  - `GET /public/kilns?lat&lon&radius_m` (100–5000 m, default 2000, max 50 results, sorted by `distance_m`);
  - `GET /public/kilns?district&cursor&limit` (keyset paging);
  - `GET /public/kilns/{id}`.
  - Projection is an allowlist; `review_state` and `provenance` are dropped. **Only `status='flagged'`, enforced in SQL.**
  - `cache-control: public, max-age=60`; throttled at 10 rps with a burst of 20 per route.
  - Live check: near Hapur town at 2 km returns 1 kiln; at 5 km, 22 kilns; the district list returns 39.

### AWS live state (account owned by the user; region `ap-south-1` Mumbai)
- **Access:** CLI profile `kilnwatch`, IAM user `aryaman`, **never root**. The user signs in themselves, in their own terminal: `aws login --profile kilnwatch --region ap-south-1` (see §1a). Never ask for or print passwords, keys or tokens.
- **Terraform state:** in S3 bucket `kilnwatch-tfstate-<account-id>-ap-south-1` (versioned, encrypted, public access blocked, TLS-only, native `use_lockfile`).
  - `AWS/backend.hcl` and `AWS/terraform.tfvars` are ignored and local only.
  - Terraform 1.16.5 is at `.local/tools/terraform`.
  - Provider lock: `hashicorp/aws 6.68.0`. **Never upgrade it casually.**
- **Deployed: 73 of 75 resources.**
  - VPC with public and private subnets, and no NAT;
  - RDS PostgreSQL 17.9 with PostGIS 3.5.6: private, encrypted, `deletion_protection=true`, 7-day backups, final snapshot on, `rds.force_ssl=1` (with `apply_method = "pending-reboot"` pinned to stop a perpetual diff), `log_statement=none`;
  - Secrets Manager: the RDS-managed master secret, the reader secret, and an interface endpoint in 2 AZs;
  - Lambda API (Python 3.12, x86_64, in the VPC; egress only to RDS and the endpoint), with a log group retaining 14 days;
  - HTTP API with a JWT authorizer (inspector pool) and stage throttling;
  - Cognito inspector pool (admin-create only, immutable `custom:district`, `inspector` group); **no users created**;
  - S3 data bucket (private; `imports/` holds the import inputs);
  - ECR, ECS and Step Functions scaffolding (unused, never started);
  - SNS and a Lambda errors alarm;
  - the **registry runner** (EC2 t3.micro, SSM only, no inbound; about $0.42/day), still running.
- **Missing: the CloudFront distribution and its evidence bucket policy.** AWS returned `AccessDenied: Your account must be verified before you can add new CloudFront resources`. The user must have a **Support case open** (Account and billing). When AWS verifies the account, the remaining work is prompt 09 **Part B**:
  1. an untargeted apply (2 to add);
  2. publish the 2 PNGs with `upload_evidence.py` and verify them with `verify_publication.py`;
  3. re-import with `--publication-receipt` on the runner via SSM `send-command`;
  4. the CloudFront denial probe;
  5. remove the runner with `create_registry_runner=false` (expect 5 to destroy and 1 to change).
  - After publication, the opt-in Swift test (`KILNWATCH_REAL_CONTRACT_LIST`) expects null image URLs and must be updated.
  - Until CloudFront exists, use Terraform `-target` for unrelated changes. A full apply retries CloudFront and fails.
- **Budget:** `kilnwatch-monthly-50` (USD 50/month, emails the user at 80% actual and 100% forecast).
- **Cost:** about **$38/month always-on**, mostly the Secrets Manager endpoint (about $19) and RDS (about $15 + $2.6), plus the runner until it is removed. The 2A estimate came from the AWS Price List API. Use this plus the runbook for any cost questions.
- **Private values:** non-secret identifiers (API base URL, pool/client IDs, issuer) are only in ignored `.local/integration-2b/outputs.json`. Output names: `api_base_url`, `cognito_user_pool_id`, `cognito_app_client_id`, `cognito_issuer`, `evidence_base_url` (absent until CloudFront), `data_bucket_name`, `rds_endpoint`, `registry_*_secret_arn`, `registry_runner_id`.

### Local tools and artifacts (this Mac only; ignored by Git, preserve them)
- **Model and evidence:**
  - `best.pt`, `args.yaml` and `scores.json` at the repo root;
  - `.local/integration-1/`: the GeoJSON (SHA `b1e9d177f68d…`), scene JSONs, `evidence/` with 2 PNGs and `manifest.json`, previews;
  - `.local/integration-2a|2b|2c/`: plans, live response bodies, TLS throwaway keys, outputs.
- **Environments and builds:** `.venv-integration/` (Python 3.13); `AWS/build/api_handler.zip` (the deployed SHA `f4fc23cb…` after 2C).
- **Installed by the builders:** Homebrew `postgis` and `awscli`. `postgresql@17` was already installed.
- **Portability:** a checklist with SHAs is in `local-verification.md`. Weights cannot be regenerated; only the ML team mate has the originals.

### Git state right now
- `HEAD` is `db513dd` on `main` (pushed with 2B).
- **2C is staged but not committed:**
  - `AWS/api.tf`, `lambda/api_handler.py`, `registry/{contract,store}.py`, tests and docs;
  - `App/docs/{HANDOVER,api-contract,integration-status}.md`;
  - `App/docs/prompts/09-public-read.md`.
- **Untracked:** prompts `08`, `10` and this `11`, plus `App/docs/screens/phase-2/*.log` (old Phase 2 logs; leave them alone).
- **Recommended:** ask the user whether to commit and push 2C plus the prompts. The AWS teammate needs `api-contract.md` §2C and prompt 10 from GitHub. Commit only on an explicit request, and check that no identifiers are present first.

## 5. Open items, by owner

**User**
- Submit or track the AWS Support case (CloudFront verification).
- Decide on committing and pushing 2C and the prompts.
- Create a separate IAM user with MFA for the AWS teammate (removed after the hackathon), and share privately with them: the API base URL, `backend.hcl` and `terraform.tfvars`.
- Give the go for Phase 3.
- Share the hackathon deadline. It is unknown to the orchestrator: **ask early**, because it changes how thorough each step should be.

**AWS teammate**
- Build the resident portal per prompt 10 (R0 → R7: map/search/kiln page, inspection-request letter, a separate resident Cognito pool, saved places, an AI assistant with a citation validator and cost caps, Amplify hosting, accessibility/Hindi/demo).
- Finish Part B after verification.
- Later: an API Gateway 5xx alarm. The Lambda `Errors` alarm cannot see registry outages, which come back as 503s.

**ML team mate**
- The saved Kaggle run identity and the weight-to-score linkage.
- An interpretation of the evidence pair.
- Fresh-image type confusion review.
- More AOI or district scans: the next model-side step. No retraining unless separately requested.

**Product decisions still open**
- **Siting rules conflict:** the habitation rule is 1,000 m in UP in one source but 800 m in the concept, and the school rule IDs differ (`UP/HR-SCH-1K` vs `UP-SCH-1K`). Resolve from the official gazette text before implementing rule checks. Nothing displays a legal distance until then.
- **Auth details:** ID tokens are used for now. Multi-district inspectors are deferred. Verified Permissions (Cedar) is not implemented. Managed-login PKCE for iOS is Phase 5.
- **Agents:** AgentCore is disabled. The portal's assistant plan uses a Lambda with Bedrock Converse. The inspector "Ask" planner (Phase 4) is not designed against real data.
- **Unanswered Phase 0 questions:** the flagged colour, whether the mini-map pans, free-text Ask, landscape support, the "Sample data" pill in TestFlight.

## 6. What's next (recommended order)

1. **Phase 3: iOS app on real data, via the public API, with no sign-in.** This is the demo-visible priority. When the user says go, write prompt `12-phase-3-real-registry.md`. Its scope:
   - **API client.** `KilnWatchCore` gets public, token-free methods: `publicKilns(lat:lon:radiusM:)`, `publicKilns(district:cursor:limit:)` and `publicKiln(id:)`.
     - Today `KilnWatchAPI` always sends a bearer token (`send` sets `Authorization`, from `token()`). Add a path without a token, or make the token optional, with the smallest change and tests.
     - Today the app's `AppModel` (`App/KilnWatch/KilnWatchApp.swift:86-93`) builds the API only from `KILNWATCH_API_URL` + `KILNWATCH_API_TOKEN`. Add a public-only configuration: base URL from build configuration or Info.plist, with no secret, because the URL is public. Keep the fixtures/mock path for previews and tests.
   - **Kilns tab.** Real Hapur list with paging. Honest loading, empty, offline, 429 and 503 states.
   - **Kiln detail.** Fetch by ID.
     - Evidence: the real before/after `BeforeAfterComparator` with 256 px pixelated images, dates and Copernicus attribution when URLs exist. Otherwise "Satellite images not yet published". The mock Apple snapshot must never show for real records; Integration 1 already gates this through `usesIllustrativeEvidence`.
     - "Rules not evaluated" and "Population exposure not assessed".
     - Model score labelled honestly, with the type unverified.
   - **Fix the hard-coded 800 m** (finding 13): `KilnView.swift:45` "Within 800 m", `:170` `MapCircle(radius: 800)`, `:212` the caption, and `ExposureBlock.swift:4,29,43`. Real records have no exposure and no resolved rule, so hide or neutralize the buffer ring and the "Within 800 m" heading for them. Keep the fixture demo behaviour only for fixtures.
   - **Today.** There is no real route service. **Do not fabricate a route.** Propose to the user: a "Flagged near you / in Hapur" map of the real 39 with no route, plus an honest "Route planning not available yet" state. Decide this with the user before writing the prompt.
   - **Rules:** DESIGN.md is binding (use Apple's SwiftUI/HIG docs); light/dark, AX sizes and Reduce Motion; root build and core tests with zero warnings; screenshots of key states.
   - **Image tests:** if CloudFront is still pending, build the images path against a local fixture and leave live image verification for after Part B.
2. **Part B (CloudFront)** as soon as AWS verifies the account. Use prompt 09 Part B; no new prompt is needed.
3. **Review the portal milestone reports** if the user pastes them. Review against prompt 10's honesty rules and "what not to do" list.
4. **Later, each separately scoped:**
   - a rules and exposure engine (needs the authoritative rule thresholds, OSM schools/habitation layers in S3, and HRSL population clipped to the AOI);
   - Phase 4: registry-backed Ask/agent and real route planning (Amazon Location + OR-Tools);
   - Phase 5: Cognito iOS sign-in (PKCE, ASWebAuthenticationSession, Keychain), verdict capture and outbox sync, and a test inspector user (`AWS/scripts/id_token.py` exists, unused);
   - Phase 6: Hindi, accessibility and polish;
   - automated scene inference (ECS/Step Functions);
   - the review console;
   - model improvement (ML team mate).

## 7. Review lessons from this chat (keep doing these)

- Verify builder claims cheaply yourself: `git diff`, rerunning the fast Python unit suite, the hashes, `git diff --quiet AWS/.terraform.lock.hcl`, and grepping tracked files for identifiers.
- **Real database runs catch real bugs.** 2A found that `bootstrap_reader.py`'s `%s` needed `::text` (it would have failed on RDS), and that `api.tf` had an HCL syntax error. Don't accept mocked persistence as proof.
- **Runbook steps need to match IAM.** The runner can only `GetObject` on `imports/*`, so recursive downloads fail; download each file by key. Use SSM `send-command`, not interactive sessions. Removing the runner also changes the endpoint policy.
- **New AWS accounts can block CloudFront** (and possibly Amplify) until verified. Plan around it with `-target` rather than workarounds.
- **Lambda reserved concurrency** can fail on new accounts (limit 10). Use API throttling instead.
- Keep reports separated into synthetic tests, real local DB proof, Terraform plan, and live cloud checks. Never call a skipped or mocked check a pass.

## 8. Your first response to the user

1. Confirm you've read this file, `HANDOVER.md` and `integration-status.md`, and checked the live `git status` and `log`.
2. Ask, in one short message:
   - commit and push 2C plus prompts 08–11 now? (the AWS teammate needs them);
   - the hackathon deadline;
   - is the AWS Support case resolved?
   - go for Phase 3, and for Today: real flagged kilns with no route, or another choice?
3. Then write prompt 12 on their go, and stop for review as usual.
