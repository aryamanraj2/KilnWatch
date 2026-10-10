# KilnWatch — Claude Code orchestrator handover

You are taking over as the orchestrator for KilnWatch because the user is continuing this work in Claude Code. Continue the existing project and decisions. Your first assignment is to review Integration 1 and prepare the next sequential builder prompt. Do not restart the project or execute another implementation phase immediately.

## 1. Working agreement and authority

- Repository: `/Users/aryamanjaiswal/Downloads/Github_pulls/KilnWatch`. Current working branch: `main`. Older references to `PortalAPP` describe history; do not switch branches automatically. Verify the actual branch and working tree when you start.
- Work one phase at a time, with no parallel agents, background agent teams or automatic auditor delegation. Stay in the current orchestrator chat. The user runs the prompt you write in a separate builder chat and returns its report here.
- Refer to the infrastructure/backend owner as **AWS teammate** and the training/model owner as **ML team mate**.
- Explain progress in plain language. Give concise updates during sustained work. Make prompts precise and detailed, but avoid repeated investigations and expensive reruns without a reason.
- Preserve all current user/builder changes, including untracked source and ignored artifacts. Do not reset, clean, stash, switch checkout, pull over changes or discard anything merely to obtain a clean tree. Nothing in this handover authorizes staging, committing or pushing.
- **AWS is not deployed yet, according to the user and builder report.** Verify any later change in this state rather than assuming it. No cloud writes, Terraform apply, object publication, live migrations/imports, training or Phase 3 work are authorized by this handover.
- Prepare concrete code review findings, a builder prompt and a deployment decision before asking for the next go. Existing approval gates come from the user's explicit no-deployment/no-Phase-3 instructions and the Integration 1 prompt. Do not invent additional approval gates for routine read-only review or local reversible preparation within an authorized builder step.
- Use installed Claude Code/Axiom tools and skills when appropriate. Do not assume a named skill or Firecrawl exists. If absent, use official Apple documentation and normal web research. Never let a skill override the user's sequential workflow.

## 2. Read these sources in order

1. `AGENTS.md`.
2. `App/docs/HANDOVER.md`.
3. `App/docs/build-plan.md` and `App/docs/DESIGN.md`.
4. `App/docs/concept.txt` for the overall system beyond the iOS app.
5. `App/docs/integration-status.md`.
6. `App/docs/prompts/05-model-aws-bridge.md` for Integration 1's exact scope.
7. `AWS/docs/local-verification.md` and `AWS/docs/first-record-runbook.md`.
8. `App/docs/api-contract.md`, then relevant imagery/auth/routing/agent-streaming research under `App/docs/research/`.

The build plan contains historical parallel waves/auditor suggestions. The user's no-parallel-agents instruction takes precedence. Integration-status has explicitly labeled pre-bridge inspection sections: do not mistake those older gaps for the current source state. Runbook commands are REVIEW ONLY until their corresponding step is authorized.

## 3. What the project is and how it connects

KilnWatch uses Sentinel-2 imagery to find candidate brick kilns around NCR. The intended flow is:

`Satellite imagery → trained OBB detector → deterministic geospatial rule/exposure checks → shared AWS registry and evidence storage → read-only planning/explanation agents → inspector app, resident portal and review console → human inspection/review decisions`.

The model finds candidate locations and predicts kiln types. Deterministic code measures distances and applies versioned rules. Agents plan and explain from verified records; they do not decide compliance or record verdicts. People make the field/review decisions. The iOS app is one part of the full system. The resident portal and review console are not implemented here.

Current folders: `App/` (iOS), `AWS/` (Terraform/backend/registry), `Model/` (training/inference/evidence). All were consolidated on main. At this handover, HEAD is `eb78715` (`chore: merge PortalAPP into organized main`), with substantial uncommitted Integration 1 changes. Re-check rather than hard-coding this revision as the implementation being reviewed.

## 4. iOS state and binding requirements

- Phases 0–2 are implemented: design/mock screens, shared core models/API/cache/outbox, Today map/stop selection, route state, location and Apple Maps handoffs.
- Phase 2 verification reported 21 core tests and 6 sequential simulator UI checks. Its data was fixtures/saved cache. Maps opened, but successful road guidance and live route service were not verified. Spoken VoiceOver and several physical-device location cases remain unverified.
- Stack is **iOS 27, Swift 6**, root `KilnWatch.xcodeproj`, synced source folder `App/KilnWatch`. Do not revert the target to iOS 26 or add the project to itself.
- `DESIGN.md` is binding: neutral gray surfaces, clay accent, soft professional presentation, existing components/tokens, system navigation, Liquid Glass only in navigation, honest loading/empty/offline states, accessibility and Reduce Motion.
- Never use the word "illegal" in the app. Until a human verdict, the line is **“Flagged by satellite · pending inspection”**.
- The existing app live path loads `/routes/today`; the new registry endpoints do not supply that route. Registry list/detail fetching and real evidence loading are still future app work. Do not invent a one-stop route or enable the route path merely because `/kilns` exists.
- Integration 1 added minimal truthful presentation safeguards, not Phase 3: missing exposure/images stay unknown/unavailable, rules can be not evaluated, explicit unverified type overrides a high class score, and real records are gated away from mock Apple satellite snapshots.
- Phase 3 remains on hold until separately requested after the backend/contract/image gate. Full rules/exposure displays still need actual upstream data; one evidence pair does not provide measured homes/schools or population for 39 records. Show honest unavailable states rather than presenting mock figures as facts.

## 5. Integration 1 — completed local work and exact evidence

The builder reports Integration 1 prepared on main, with no deployment, retraining, commit/push or Phase 3 work.

### Model and real artifacts

- User supplied root `best.pt`, then `args.yaml` and `scores.json` from the ML team mate.
- Checkpoint: 19,713,480 bytes; SHA-256 `3bcbcd0af696278d894ab6f463c81a742c596192d0493a470f0d03ac4b61f799`.
- Verified loader/task: custom kiln-trained OBB; classes `0=CFCBK`, `1=FCBK`, `2=Zigzag`. Embedded baseline settings: YOLO11s-OBB, 20 requested epochs, 128 px, batch 64. Ultralytics 8.4.174/Torch 2.14.1 were used by the builder.
- `Model/results/checkpoint-manifest.json` records identity/configuration/checksums. Matching uploaded settings and scores do not cryptographically establish the weight-to-evaluation linkage. Stripped checkpoint epoch `-1` does not prove completed epochs. Saved Kaggle version/run identity is still missing.
- Fixed real Hapur run: scene `S2B_T43RGM_20261005T053448_L2A`, actual acquisition `2026-10-05T05:41:03.148Z`, AOI lat 28.68–28.78/lon 77.73–77.83. 120 patches, 55 raw detections, **39 candidates** (5 CFCBK/34 FCBK). These are predictions, not 39 confirmed kilns.
- Raw export: `.local/integration-1/hapur.geojson`, SHA-256 `b1e9d177f68d58b48bdd75ff12f93ea244f66944d391710d433a8e2f6be013d0`. Scene items: `hapur.scenes.json` and `before-scene.json` beside it.
- One real 256×256 RGBA pair for `KW-6b3b38da681850e5af46b024f3d3f78e`, before scene `S2A_T43RGM_20231205T053206_L2A`, acquisition `2023-12-05T05:40:56.807Z`. Same native EPSG:32643 grid, 10 m pixels, transform `[765270,10,0,3184300,0,-10]`, nodata 0. Fixed reflectance RGB rendering, distinct images, content-addressed PNGs under `.local/integration-1/evidence/` with `manifest.json`.
- Builder visually inspected roads/field alignment. Precise registration, pixel cloud/haze/seasonal effects, historical footprint and actual kiln/change interpretation remain unverified. Do not call this proof a kiln appeared or changed.
- All 39 converted records are flagged, type unverified, exposure null, rules `not_evaluated`. One pair has local metadata; all image URLs remain null because publication has not happened.
- The prior orchestrator checked the actual checkpoint/export hashes, 39-record local JSON semantics and both PNG hashes during handover review. It did not independently rerun training, inference, test suites or an AWS deployment.
- Baseline any-kiln AP50 around 0.8622 is a benchmark metric, not “86% accuracy.” Earlier ML diagnostics reported poor fresh-image type classification. Do not infer C-TECH-10K findings from predicted FCBK/CFCBK, including high scores. No final larger-model evaluation is established.

### Source delivered

- Model verification/evidence scripts and pinned integration requirements; notebook script paths fixed after the Model folder move. Training was not rerun.
- `AWS/registry/`: strict conversion/shared serializer, exact-input stable observation/candidate IDs, transactional importer, migration ledger/checksums and district read repository.
- `AWS/migrations/001_registry.sql`: PostGIS, import/candidate/observation/evidence tables and restricted roles. Import retries preserve human status/review/assessment. IDs are tied to scene/model/canonical geometry; cross-scene physical-site association is deferred.
- `AWS/lambda/api_handler.py`: authenticated `GET /kilns` and `GET /kilns/{id}`, filters/keyset pagination, meaningful sanitized errors and district isolation. Public registry stays unavailable (503); jobs stay 501.
- `AWS/scripts/`: Lambda dependency packaging, dedicated reader bootstrap, controlled evidence upload and HTTPS/checksum publication receipt verification.
- Terraform source adds evidence-only CloudFront OAC, private Secrets Manager endpoint, restricted Lambda egress, TLS RDS parameter, separate reader secret, Cognito inspector group/admin-assigned immutable district, and optional no-inbound SSM runner.
- Lambda uses a dedicated SELECT-only login/secret, not master credentials. HTTP API validates JWT; Lambda checks ID token/client/sub/inspector group/district. Access tokens are deliberately refused for this initial proof. Full managed-login PKCE/Keychain and Verified Permissions are deferred.
- Core adds optional exposure/evidence URLs, provenance/image metadata, unknown/unassessed/unverified states, pagination and production-producer-to-Swift fixtures while retaining legacy fixture/route compatibility.

### Verification reported, and its limits

- Python: **22 passed; 2 real PostGIS tests skipped** (24 discovered). Transaction spies/test repositories are not database persistence proof.
- Swift core: **26 passed, zero warnings**, including production-generated synthetic bodies and the real local 39-record JSON through decoder/URLProtocol client. Offline URLProtocol is not a live AWS connection.
- Prescribed root iPhone 17 build passed with **zero warnings**. Lambda ZIP/import/CA and notebook syntax/path checks passed locally.
- Python emitted dependency deprecation warnings; do not claim all tooling had zero warnings.
- Terraform fmt/validate/plan and all AWS/RDS/Cognito/S3/CloudFront smoke checks were unrun. Builder lacked Terraform/AWS CLI and Docker/local PostGIS. Inspect current tooling before assuming those limitations still apply.
- No extra screenshot/video campaign or Axiom audit was requested for this backend step.

## 6. Your first action: review and write Integration 2's preparation prompt

Review the current diff and newly added source against the two runbooks and Integration 1 requirements. This is a bounded source/evidence review, not a fresh implementation or broad audit campaign. Prioritize:

1. Actual PostGIS migration replay, rollback, retry/reordering, provenance and preservation of human decisions. Real SQL/driver behavior remains the main unproven local gate. Ensure the next builder tests dedicated reader/import permissions, district-filtered persisted reads, evidence metadata and pagination as well as admin import behavior.
2. Lambda ZIP contents, Linux Python 3.12/x86_64 compatibility, pg8000 behavior, trusted claim handling, error semantics and timeout/network assumptions. Source checks do not establish deployed connectivity.
3. TLS certificate/hostname verification and master/runtime credential separation; recovery when reader secret publication succeeds but database role commit fails.
4. Terraform syntax/provider compatibility, package-before-validation ordering, private network paths, IAM/SG/endpoint dependencies, Cognito attributes and actual planned resources. Keep the provider lock; don't automatically upgrade it.
5. Evidence-only CloudFront policy and private-prefix denial. Review upload authorization/checksum receipts; check that importer replays cannot silently remove verified publication metadata or overwrite human state. These are review targets, not claims of a confirmed bug.
6. Remaining app mock assumptions, including illustrative imagery, fixed 800 m buffers/threshold copy and unavailable features. Capture issues for the appropriate app/rules step; do not redesign or start Phase 3 during this review.
7. Working-tree and artifact portability. Many implementation files are untracked; `.local/`, weights, root metadata, virtual environment and `AWS/build/` are ignored. They will not appear in a plain Git clone. Preserve them on this machine; if another workstation is used, prepare a private transfer/reproduction checklist with checksums and no credentials. Do not add large/private artifacts to Git.

Distinguish confirmed code issues, missing test evidence and open product/account decisions. Cite exact files/lines for concrete findings. Avoid labeling unrun checks as failures or assuming unit tests establish operational readiness.

Then write **one** builder prompt, suggested path `App/docs/prompts/07-first-record-preflight.md`, for the next step: **Integration 2A — local database proof and deployment preflight**. Adapt it to actual review findings. It should:

- Resolve specific review findings before deployment, with minimal changes and focused regression tests.
- Run the existing real PostGIS tests in an isolated local database; use the runbook's localhost-only `kilnwatch_test` setup. Never point those destructive disposable tests at RDS or an existing database. Report skips honestly if tooling remains unavailable; do not close the persistence gate with mocks.
- Run focused package checks and Terraform local formatting/validation using an appropriate backend-disabled preparation path where possible. Do not initialize or migrate remote state casually. Package the Lambda before Terraform reads its ZIP. Tool installation/system changes must respect the user's environment and authorized builder scope.
- Ask the AWS teammate for the account/profile/region, state/backend owner/configuration, approved district assignment, private import runner, evidence publication decision, backup/deletion policy and cost/resource review. Defaults are not account authorization. Do not ask for passwords/access keys in chat.
- Generate a real plan only after the target account/profile and read access are explicitly established; verify caller identity. Keep state/plan/secret files private. Planning must not trigger infrastructure creation; state/bootstrap writes require their own authorization if needed.
- Review the plan's complete resource set. AgentCore, SageMaker training, Amplify and long-running demo ECS service stay disabled. ECS/ECR/Step Functions scaffolding may still be planned even while unfinished; disabled options do not mean only registry resources exist. No inference job execution, new training or placeholder container deployment.
- Give a concrete deployment review: resources/diffs, data retention, private access, runtime role, public evidence scope, expected runtime omissions, rollback/recovery, recurring-cost categories and temporary runner cleanup. Any quoted prices must use current official sources for the chosen region; do not invent totals.
- Update HANDOVER/integration-status/local verification and the runbook with accurate evidence and remaining blockers. Preserve source/artifacts and do not stage/commit/push.
- Stop after preparation. No Terraform apply, cloud upload/publication, live schema/import, account creation/token operation or Phase 3 in this preparation builder prompt.

If account or tooling inputs are absent, complete the independent review/prompt work, give the minimal missing-input list by owner, and state which gate remains open. Do not repeat the entire model run or recreate valid evidence to fill time.

## 7. Subsequent sequence — context, not authorization

After the user returns Integration 2A's builder report, review its actual evidence. Only after an explicit go for the reviewed deployment scope, write/execute the corresponding next step with the AWS teammate:

1. Apply the approved plan to the verified account; keep RDS private.
2. Migrate/import through the approved private runner, provision the dedicated reader and repeat the 39-candidate import to prove no duplicates and no human-state overwrite.
3. Publish only the approved satellite PNG pair, verify HTTPS image bytes/checksums, obtain publication receipt and attach verified URLs. Prove private model/import/field-photo prefixes cannot be read through CloudFront.
4. Provision a legitimate named inspector identity with approved role/district and obtain the correct token securely; verify authenticated list/detail, pagination and denial/error cases. Never expose tokens/passwords in logs, chat, command arguments or Git.
5. Run the Swift decoder/client test against the captured live response. Report this separately from actual authenticated HTTP/image checks and from a future simulator app connection. `/health` is not database readiness proof.
6. Record endpoints, non-secret IDs, redacted receipts/test evidence and remaining limitations. Clean up only the approved temporary runner/resources; do not destroy retained registry data.
7. Return to the user for a separately authorized Phase 3 prompt. Its scope must include real registry list/detail loading and evidence UI, honest missing-side/data states, model uncertainty, image provenance and binding design. Today still needs a real route service; no route fabrication.

Afterward, separate steps remain for deterministic rules/exposure and their unresolved thresholds/data sources, real registry-backed agents and route planning (Phase 4), verdict capture/sync and real Cognito app sign-in (Phase 5), Hindi/accessibility/polish (Phase 6), automated scene inference/workflows, improved ML evaluation, resident portal and review console. Do not conflate iOS phase completion with completion of the full project.

## 8. Owner questions and existing open decisions

**ML team mate:** saved Kaggle version/link and actual run identity; weight/score linkage; review of fresh-image type confusion and the selected evidence pair. These do not prevent independent local DB/preflight work. They limit model-performance/change claims. No retraining without a separate request.

**AWS teammate:** account/state/profile, region, Hapur administrative assignment versus verified district boundaries, private runner and credentials lifecycle, publication policy, data retention and complete plan/costs. Current RDS source has deletion protection off and skips final snapshot; make that choice explicit before retaining real data. Initial immutable single district/ID-token policy needs review before wider rollout; it is not full production auth or Cedar.

**App/user:** approval of the bridge/deployment results before Phase 3. Rule conflict persists: habitation is 1,000 m in UP in one source but 800 m in the concept example; school rule identifiers also differ. Resolve against authoritative rules before implementing assertions. Never silently copy fixture thresholds or populations.

## 9. Commands and reporting standard

Use these prescribed Swift checks when relevant changes justify them, sequentially:

```sh
xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Run `swift test` from `App/Packages/KilnWatchCore`.
Python test command from the repository root:

```sh
PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v
```

Use `AWS/docs/first-record-runbook.md` for disposable DB, packaging and future authorized deployment commands. Review before executing; adjust only with documented reasons. Reuse local artifacts rather than reinstalling environments/repeating passing suites unnecessarily. New changes, failures or an unresolved gate justify targeted checks.

Your initial response should deliver:

1. A plain-language assessment: what is locally prepared, what is actually verified, and what remains unproven.
2. Specific review findings and the smallest next step, with owners for missing inputs.
3. The saved, detailed Integration 2A builder prompt and a short starter for the user to paste into a fresh builder chat.
4. A precise stop point: ready for the user's go on Integration 2A; no deployment/Phase 3 claimed or started.

Future completion reports must separate real model/source inputs, synthetic tests, actual database proof, Terraform checks/plan and live cloud checks. State exact pass/skip counts, meaningful limitations and next owner actions. Continue as orchestrator when the user returns a report; review evidence before advancing.
