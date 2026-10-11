# KilnWatch — orchestrator handover #8 (2026-10-11, evening)

You are taking over as the **single orchestrator** for KilnWatch: backend, infrastructure, agents, the iOS app and the web portal. Builders run in new Claude Code or Codex chats that the user opens.

**Read, in order:**
1. `AGENTS.md`
2. This file (it supersedes handover 41 where they differ; 41 §1, §5 and §8 still apply and are summarised below)
3. `App/docs/plan-final-stretch.md` (older status table; this file is newer)
4. `App/docs/prompts/30-aws-orchestrator-handover.md` §1–§4 (rules, accounts, lessons)
5. `App/docs/HANDOVER.md` (newest sections at the end) and `App/docs/DESIGN.md` (binding for UI)
6. `App/docs/api-contract.md`: "Integration 2C", "Phase 4A — Ask", "R1", "P1", "POST /verdicts", "Change triage (40)", "Review queue read (40b)"

Then `git fetch`, `git status` and `git log`.

## 1. Role and rules (unchanged)

- **You orchestrate; you don't build.** One builder prompt at a time in `App/docs/prompts/`, with a full copy-paste pre-prompt saying "new chat" or "same chat". Review every report yourself: rerun tests and the build, read the diff, leak-scan, look at screenshots, re-check live state read-only.
- **No sub-agents** unless the user asks. **Every deploy, DB write, AWS change, commit and push needs the user's explicit go**; "running the prompt = the go for exactly its listed scope". Targeted applies only, no `destroy`, never change the provider lock (`hashicorp/aws 6.68.0`). One AWS prompt at a time (one Terraform state). Fetch before every commit; stage by explicit paths.
- **The repo is PUBLIC.** Never write or print account IDs, ARNs, the API URL/ID, CloudFront domains/IDs, bucket/table names, ECR hosts, the RDS host, the second account's user name, or emails. Read them from `.local/` (`integration-2b/outputs.json`, `phase-4/cdn/outputs.json`, `portal/outputs.json`, `m0/`, `triage/`) and the ignored `AWS/terraform.tfvars` without printing. Mask CLI identities with `sed -E 's/[0-9]{12}/<acct>/g'`.
- **Product language:** never "illegal". "Flagged by satellite · pending inspection". Rule hits are siting signals; `inconclusive` is never clear; missing data is never zero; the model score is not accuracy; ETAs are estimates. Triage items are **candidates pending review** ("not detected in Dec 2023", never "new kiln"/"built"; "no longer detected", never "closed").
- **The user** writes casually (sometimes Hinglish). Short, plain replies, one recommendation. Builder testing stays **light**. The user often commits and pushes themselves after you stage; check `git log` before offering to commit.

## 2. User decisions (binding)

| Decision | Date |
|---|---|
| No sign-in or auth for now. `POST /verdicts`, `/ask`, `/routes/plan`, `GET /public/review` are public | 10–11 Oct |
| The second AWS account is permanent for Bedrock, CloudFront **and CodeBuild** (main account's CodeBuild quota is 0) | 10–11 Oct |
| Hindi in Ask cut | 10 Oct |
| Portal hosted on AWS: S3 (main, private) + CloudFront (second account, OAC) | 10 Oct |
| Demo verdict on `KW-00c562…` (confirmed): **keep it; reset once right before recording the demo video** (needs `aws login` + a go) | 11 Oct |
| Change triage (Agent 2) is in scope; its queue is shown **read-only** in the **iOS Review tab**; no approve/reject without sign-in | 11 Oct |
| Expanding beyond Hapur: **after the demo**, one neighbouring **UP** NCR district (rules are UP rules; Delhi/Haryana need their own) | 11 Oct |

## 3. Status (all reviewed by the orchestrator)

| Step | State |
|---|---|
| R1, P1, E1, P2 (rules/exposure, routes, evidence, inspection sheet) | Live |
| V1 39/39b `POST /verdicts` | Live, committed |
| iOS 18–22 (Ask, rules, live Today, polish, verdicts) | Done, committed |
| **36/36b/36c** portal on the live API + resident Ask + phone-first layout | Done, committed `7d3fbdf` |
| **37** portal hosted (second-account CloudFront, OAC, SPA rewrite; CORS = localhost:5173 + portal origin) | Live, committed `aba69ad` |
| **38/38b** detector in Docker on AWS: image built by **second-account CodeBuild**, pushed to main ECR (repo policy for that one role); Fargate ARM64 4 vCPU/16 GB; Step Functions `{scene, run_id}`; runs `m0-after` (39, byte-identical to local) and `m0-before` (2023: 32) | Live, committed `677592e` |
| **40** change triage (Agent 2) inside the assistant Lambda, internal invoke only; DynamoDB `review-queue`; 45 items pending (24 not detected in Dec 2023 / 17 no longer detected / 0 zigzag / 4 low score); all reasons model-written and validated | Live, committed `6432f97` |
| **40b** `GET /public/review` (read-only, allowlisted fields, 60 s cache + memo, public throttle) | **Live, reviewed, NOT committed** |
| **iOS 23** Review tab (4th tab, read-only, offline copy, registry rows open kiln detail with `include=inspected`, historical rows show map + Directions) | **Done, reviewed, NOT committed** |
| M1 better model | ML teammate; not blocking |

**All three concept agents are visible in the apps:** Agent 1 planner (iOS Ask + Today, portal Ask), Agent 2 triage (iOS Review tab), Agent 3 resident assistant (portal Ask; same Lambda as Agent 1).

## 4. Live state (main account `ap-south-1` unless stated)

- **Registry (RDS):** 39 Hapur candidates, 38 flagged + 1 confirmed (demo verdict). Public reads flagged-only by default; `include=inspected` adds all.
- **Ask** (`kilnwatch-assistant`, outside the VPC, Bedrock Nova 2 Lite via second account): cap **100/UTC day** (back to 50 after the hackathon). The same Lambda serves triage (internal) and `GET /public/review`.
- **Routes:** cap 15/day. **Verdicts:** cap 30/day, idempotent, presigned photo PUTs.
- **Portal:** hosted URL in `.local/portal/outputs.json` (never print it). Re-upload = `npm run build` with the ignored `.env.production.local`, two-pass `s3 sync`, then invalidate `/*` (needs a go).
- **Detector:** manual Step Functions start only. Ultralytics settings-dir warning is harmless.
- **Registry runner (EC2 + SSM):** still on (needed for the verdict reset). Remove after the demo with a go.
- **Budgets:** main account has two $50 alarms. **The second account has no budget alarm** and now bills Bedrock, CloudFront and CodeBuild; remind the user to ask its owner for about $10.

## 5. Credentials

- **Main:** profile `kilnwatch` (`aws login`, user `aryaman`). The user's browser is signed in to the second account: for the main account, the user signs in from a **private window**, and the command must keep `--profile kilnwatch`. `!` commands have no TTY; interactive logins run in the user's own Terminal.
- **Second:** profile `kilnwatch-bedrock` is also an `aws login` session (it expired once today and blocked 37's CloudFront read). `kilnwatch-cdn-tf` is a `credential_process` over it. Re-login: `aws login --profile kilnwatch-bedrock` in the user's Terminal, then verify `kilnwatch-cdn-tf` resolves to the second account (masked) and `kilnwatch` still ends `user/aryaman`.
- Terraform needs **both** sessions for any plan (the `aws.cdn` provider), even for main-only changes.

## 6. Open items

1. **Commit 40b + 23** (stage by path; the user may commit themselves):
   - 40b: `AWS/api.tf`, `AWS/assistant.tf`, `AWS/assistant/handler.py`, `AWS/triage/diff.py`, `AWS/triage/review.py`, `AWS/tests/test_triage.py`, `AWS/docs/local-verification.md`, `App/docs/api-contract.md`, `App/docs/prompts/40b-review-read-route.md`;
   - 23: `App/KilnWatch/` (Review feature, `KilnWatchApp.swift`, `RoutePresentation.swift`, `Mock/ReviewDemo.swift`, `Mock/ReviewRecorded.json`), `App/Packages/KilnWatchCore/` (`Package.swift`, `KilnWatchAPI.swift`, `Review.swift`, `ReviewTests.swift`, `ReviewFixtures/`), `App/docs/DESIGN.md`, `App/docs/HANDOVER.md`, `App/docs/screens/phase-7/`, `App/docs/prompts/23-review-tab.md`, and this file.
2. **Demo prep:** one run on the user's physical iPhone (signing, camera, GPS); reset the demo verdict right before recording (`registry.cli reset-verdict --kiln <id> --confirm` on the runner via SSM; go each time); record: Today route → kiln → Ask → record a verdict → Review tab → the portal on a phone. Good Ask questions: "Plan a route from 28.7306, 77.7759 with 4 stops", "Which Hapur kilns have the most people within 800 m?", "Give me the inspection sheet for this kiln".
3. **Optional:** wire triage into Step Functions after each detector run; portal `/review` page reusing 40b; re-shoot `Web/ResidentPortal/docs/screens/live/` (old comparator order); native Hindi review of the portal strings; tiny Review-tab badge spacing nit.
4. **After the demo** (each with a go): remove the runner; Ask cap back to 50; consider `enable_verdicts = false` or auth; second-account budget alarm; next UP district (detector entrypoint needs `--bbox`/`--district` + rebuild, then import, R1 assessment, E1 evidence, iOS district picker).

## 7. Lessons from today

- **Check quotas and account blocks in preflight.** 38 stopped correctly on a CodeBuild quota of 0; the fix was an amendment prompt (38b), not widening scope silently.
- **Scope the number of applies the steps actually need** (38 needed two; 40 needed a second for a bug fix). Builders stopping for a go is the pattern working.
- **Fix data shape, not prompt lines:** triage groups and numbers are deterministic; the model only writes the reason, behind a validator.
- **Staged vs committed:** the user often commits right after you stage. Always `git log` before reporting what's uncommitted.
- **Parallel builders on the same files clash:** UI polish waited for the data-layer prompt (36 → 36b → 36c).
