# KilnWatch — orchestrator handover #7 (2026-10-11)

You are taking over as the **single orchestrator** for KilnWatch: backend, infrastructure, agents, the iOS app and the web portal. Builders run in new Claude Code or Codex chats that the user opens. You may be running in either tool.

**Read, in order:**
1. `AGENTS.md`
2. This file (it supersedes handover 34 where they differ)
3. `App/docs/plan-final-stretch.md` (§0 status, the "Full-AWS order" table and §4–§7)
4. `App/docs/prompts/30-aws-orchestrator-handover.md` §1–§4 (rules, accounts and lessons; still binding, except where §2 below updates them)
5. `App/docs/HANDOVER.md` (the iOS state; newest sections at the end) and `App/docs/DESIGN.md` (binding for all UI work)
6. `App/docs/api-contract.md`: "Integration 2C", "Phase 4A — Ask", "R1", "P1", "POST /verdicts" (live, public) and the `include=inspected` notes

Then check `git status` and `git log`.

## 1. Role and rules

- **You orchestrate; you don't build.**
  - Write **one** builder prompt at a time into `App/docs/prompts/`.
  - Give the user a full copy-paste pre-prompt, saying "new chat" or "same chat".
  - Review every report yourself: rerun the tests and the build, read `git diff`, run a leak scan, look at the screenshots, and re-check live state with read-only calls.
- **No sub-agents** unless the user explicitly asks.
- **Gates.** Every deploy, DB write, AWS change, commit and push needs the user's explicit go. "Running the prompt = the go for exactly its listed scope": put the scope in the prompt.
  - Targeted applies only. No `destroy`.
  - Never change the provider lock (`hashicorp/aws 6.68.0`).
  - Fetch before every commit; teammates push to `main`.
- **The repo is PUBLIC.** Never write or print account IDs, ARNs, the API URL or ID, CloudFront domains or IDs, bucket names, the RDS host, the runner ID, user names of the second account, or emails.
  - Read them from `.local/integration-2b/outputs.json`, `.local/phase-4/cdn/outputs.json`, `.local/phase-4/cdn/distribution-id.txt` and the ignored `AWS/terraform.tfvars` into variables without printing them.
  - **When you check a CLI identity, pipe it through `sed -E 's/[0-9]{12}/<acct>/g'`.** The previous orchestrator printed account IDs into the chat twice by forgetting this (they never reached files).
  - Coordinate decimals and SHA substrings are false 12-digit hits.
- **Product language.**
  - Never "illegal". "Flagged by satellite · pending inspection".
  - A rule hit is a **siting signal**. `inconclusive` is never "clear". Missing data is never zero. The model score is not accuracy. ETAs are **estimates**.
  - A recorded verdict shows its outcome ("Confirmed violation · Recorded on site 11 Oct", per DESIGN).
- **The user** writes casually, sometimes in Hinglish. Keep replies short and plain, with one recommendation. Testing in builder phases stays **light** (the user stopped long screenshot matrices).

## 2. User decisions (binding)

| Decision | Date |
|---|---|
| **No sign-in or auth at all for now.** `POST /verdicts` is public, like `/ask` and `/routes/plan`. Cognito and Verified Permissions are deferred | 2026-10-11 |
| **The second AWS account is permanent** for Bedrock and CloudFront. No switch-back | 2026-10-10 |
| **Hindi in Ask (H1) is cut** | 2026-10-10 |
| **Finish iOS first,** then the web portal, its hosting on AWS (second-account CloudFront), then the model on AWS | 2026-10-10 |
| Portal hosting: **AWS**, S3 (main, private) + CloudFront (second account, OAC), not Vercel or Amplify | 2026-10-10 |
| The user's priority: the **whole loop** works end to end on AWS | 2026-10-11 |

## 3. Status

| Step | State |
|---|---|
| R1 (rules + exposure), 31b, P1 (`POST /routes/plan`), 32b | Live |
| E1 (33): evidence for all 39 Hapur kilns | Live (CDN, second account) |
| P2 (35): Ask `inspection_sheet` + images-list fix | Live |
| **V1 (39/39b): `POST /verdicts`, public, cap 30/UTC day, opt-in `include=inspected`** | **Live** |
| iOS 18 (Ask), 19 (rules/exposure), 20 (live Today), 21/21b (polish) | Done, committed |
| **iOS 22 (verdicts + photos → AWS, outcomes shown)** | **Done, reviewed, staged (not committed)** |
| 36 portal on the live API + resident Ask (Agent 3) | Written, **not run** |
| 37 host the portal on AWS | Written, not run (after 36) |
| 38 detector on AWS (ECR + CodeBuild + Fargate + Step Functions) | Written, not run |
| 40 change triage (Agent 2) | Optional, not written (needs 38's two scenes) |
| M1 better model | The ML teammate is training; not blocking |

**The loop is closed on iOS:** satellite flag → rules/exposure → route plan → kiln detail + Ask → verdict + photo to AWS → outcome shown.
- The first live verdict: `KW-00c562060b40502fb4a7ed2016ce7576` = `confirmed` (Simulator end-to-end test; 1 photo in the private bucket).
- **The public flagged count is now 38** (Ask, routes and the portal see 38) until an operator reset.

## 4. Live state (main account `ap-south-1` unless stated)

- **Registry (RDS PostGIS):** 39 Hapur candidates; 38 `flagged/pending`, 1 `confirmed`. Migrations 001–003.
  - R1 assessment for all 39.
  - The `verdicts` and `verdict_days` tables exist. DB logins: `kilnwatch_api` (reader), the assessor, `kilnwatch_verdicts` (writer).
- **Public API** (`kilnwatch-api` Lambda in the VPC):
  - `/public/kilns`, `/public/kilns/{id}`, flagged only by default;
  - `?include=inspected` adds all statuses plus `inspection {outcome, recorded_at}`;
  - cache 60 s.
- **`POST /verdicts`** (`kilnwatch-verdicts` Lambda in the VPC): no auth; cap **30/UTC day** counted in RDS; idempotent by `id`; presigned S3 PUTs for photos (`verdicts/` prefix, private); stage throttle 1/s, burst 2.
  - Kill switch: `enable_verdicts = false`, then a targeted apply.
  - **Reset for rehearsals:** `registry.cli reset-verdict --kiln <id> --confirm` on the runner via SSM. It needs a go each time and keeps history.
- **Ask** (`kilnwatch-assistant` Lambda, outside the VPC): Bedrock Nova 2 Lite in the **second account** via STS assume-role.
  - Tools: `list_flagged_kilns`, `kilns_near`, `kiln_detail`, `get_evidence`, `plan_route`, `inspection_sheet`.
  - Validator: IDs and rules only from tool results, banned stems, "estimat…" with route times.
  - **Daily cap 100** (set it back to 50 after the hackathon).
  - Two known weak answers, accepted: "which have images" mislabels attribution; a zero-flag kiln's sheet drops the partial-rules note.
- **Routes** (`kilnwatch-route` Lambda): Amazon Location; max 8 stops; **cap 15/UTC day** (Ask's `plan_route` counts against it); about $0.04 a plan.
- **Evidence CDN:** CloudFront in the second account, OAC to the private main bucket; 39 of 39 kilns have before/after.
- **Registry runner (EC2 + SSM):** still running, because it's needed for resets and migrations. Remove it after the demo with a go.
- **Budgets:** `kilnwatch-monthly-50` and `kilnwatch-monthly-gross-50`. The second account has **no budget alarm**; remind the user to ask its owner to add about $10.

## 5. Credentials (lessons from this session)

- **Main account:** profile `kilnwatch` uses `aws login` (IAM user `aryaman`), with the region now set on the profile.
  - **The user's default browser is signed in to the second account.** A plain `aws login` once overwrote `kilnwatch` with the second account's user. The orchestrator repointed it (`aws configure set login_session …` with the main account's user ARN, read from `.local` without printing).
  - **Working method:** run `aws login --profile kilnwatch --remote` in the background with its stdin on a FIFO kept open (`sleep 1200 > fifo &`). Give the user the URL to open in a **private window** and sign in as `aryaman`. They paste the code back; you write it to the FIFO.
  - Then verify: the caller ARN is in the main account and ends `user/aryaman`.
  - `!` commands have no TTY, so an interactive `aws login` fails there with EOF.
- **Second account:** profiles `kilnwatch-bedrock` (an IAM user) and `kilnwatch-cdn-tf` (`credential_process` exporting `kilnwatch-bedrock`). Both work. The runtime Bedrock path needs no CLI login.
- Terraform: `.local/tools/terraform/terraform`; main credentials via `aws configure export-credentials --profile kilnwatch --format env`.

## 6. Open items for the user (ask first)

1. **Resolved (2026-10-11):** the AWS teammate's comment/description edits and the two deleted example files were **restored** after review. They changed no infrastructure, but they dropped useful context and broke references in `AWS/README.md`, `versions.tf` and the runbook. The deployed 39b change in `bridge.tf` is kept. Their patch is saved in the ignored `.local/friend-edits/` if they want any descriptions back.
2. **Commit:** the staged work holds 39/39b (backend, migration, docs), 22 (iOS) and prompts 22/39/39b/41. Fetch first, leak-scan the staged diff, then commit and push with a go.
3. **Keep or reset the demo verdict** on `KW-00c562…` (38 vs 39 flagged). A reset needs a go.

## 7. Next steps (in order)

1. The §6 decisions, then commit.
2. **Optional iOS:** run once on a physical iPhone (camera, GPS, signing); this needs the user's phone. Record the demo video. Demo questions that answer well:
   - "Plan a route from 28.7306, 77.7759 with 4 stops"
   - "Which Hapur kilns have the most people within 800 m?"
   - "Give me the inspection sheet for this kiln"
3. **36** (portal on the live API + resident Ask).
   - It needs `localhost:5173`, the only CORS origin today.
   - The portal is the AWS teammate's code; tell them first.
   - Since 39, the portal could also use `include=inspected` if the user wants outcomes there; not in 36 yet.
4. **37** (host the portal, second-account CloudFront). It runs after 36; one AWS prompt at a time (one Terraform state).
5. **38** (detector on AWS), then optional **40** (change triage).
6. **Cleanup after the demo** (each with a go): remove the runner; Ask cap back to 50; consider lowering the route cap; consider `enable_verdicts = false` or adding auth.

## 8. Lessons (apply them)

- **Fix data shape and validators, not prompt lines.** Stop rewording once answers are honest but incomplete.
- **Check for out-of-scope blockers before deploys.** 39 stopped correctly on an endpoint policy and a runner permission; 39b widened the scope explicitly. That pattern works.
- **Cost-check first.** Read the review's live state yourself (public reads, counts, hashes) instead of trusting the report.
- **Another session can edit the shared checkout.** Always look at `git status` before staging, and stage by explicit paths.
- On macOS, archives use `COPYFILE_DISABLE=1 tar --no-xattrs`.

## 9. Git state at handover

- `main` = `origin/main` at `81732cf`.
- **Staged, not committed:** 39/39b (AWS code, migration 003, verdict Lambda and Terraform, docs, `api-contract.md`), iOS 22 (app and core, phase-6 screenshots and report, `HANDOVER.md`), prompts 22, 39, 39b and 41, plan updates.
- **Unstaged:** nothing (the §6.1 edits were restored).
- **Untracked:** the old `App/docs/screens/phase-2/*.log`; leave them.
- Tests at handover: Python **176 run, 160 pass, 16 skipped**; Swift core **90 passed**; the root build has 0 warnings.
