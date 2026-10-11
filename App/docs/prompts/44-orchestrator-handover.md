# KilnWatch — orchestrator handover #9 (2026-10-11, night)

You are taking over as the **single orchestrator** for KilnWatch: backend, infrastructure, agents, the iOS app and the web portal. Builders run in new Claude Code or Codex chats that the user opens.

**Read, in order:**
1. `AGENTS.md`
2. This file (it supersedes 42; 42 §1, §2, §4, §5 and §7 still apply and are summarised here)
3. `App/docs/prompts/30-aws-orchestrator-handover.md` §1–§4 (rules, accounts, lessons)
4. `App/docs/HANDOVER.md` (newest sections at the end), `App/docs/DESIGN.md` (binding for iOS) and `Web/ResidentPortal/docs/DESIGN.md` (binding for the portal)
5. `App/docs/api-contract.md`: "Integration 2C", "Phase 4A — Ask", "R1", "P1", "POST /verdicts", "Change triage (40)", "Review queue read (40b)", "Inspection requests (43)"
6. `AWS/docs/inspection-requests-report.md` (the latest builder report, with the 43b/43c deploy record)

Then `git fetch`, `git status` and `git log`.

## 1. Role and rules

- **You orchestrate; you don't build.** One builder prompt at a time in `App/docs/prompts/`, with a full copy-paste pre-prompt saying "new chat" or "same chat" and which tool (Claude Code or Codex). Review every report yourself: rerun tests and the build, read the diff, leak-scan, look at screenshots, re-check live state read-only.
- **Sub-agents:** none for you. A builder may use them **only when the user asks** for that prompt (43 did, in Codex, with strict lane ownership; it worked well).
- **Every deploy, DB write, AWS change, commit and push needs the user's explicit go.** "Running the prompt = the go for exactly its listed scope." Put the expected Terraform plan counts in the prompt, **including every `aws_lambda_permission` a new route needs** (43 missed one; the builder stopped correctly and 43b added it). Targeted applies only, no `destroy`, never change the provider lock (`hashicorp/aws 6.68.0`). One AWS prompt at a time. Fetch before every commit; stage by explicit paths.
- **The repo is PUBLIC.** Never write or print account IDs, ARNs, the API URL/ID, CloudFront domains/IDs, bucket/table names, ECR hosts, the RDS host, the second account's user name, or emails. Read them from `.local/` (`integration-2b/outputs.json`, `phase-4/cdn/outputs.json`, `portal/outputs.json`, `m0/`, `triage/`, `requests/`) and the ignored `AWS/terraform.tfvars` without printing. Mask CLI identities with `sed -E 's/[0-9]{12}/<acct>/g'`. A leak-scan script pattern that works: collect every string ≥ 8 chars from `.local/**/*outputs*.json`, `distribution-id.txt` and the tfvars values, add any 12-digit and `execute-api|cloudfront|rds` hosts inside them, drop the harmless profile names (`kilnwatch`, `kilnwatch-bedrock`, `kilnwatch-cdn-tf`, `hackathon`), then grep the added lines of every changed/untracked text file; also regex for 12-digit runs (not inside hex), `*.cloudfront.net`, `execute-api.`, `arn:aws:` and emails.
- **Product language:** never "illegal" (also avoid "unlawful", "violation" in user copy). "Flagged by satellite · pending inspection". Rule hits are siting signals; `inconclusive` is never clear; missing data is never zero; a model score is not accuracy; ETAs are estimates. Triage items are candidates pending review. Resident requests are anonymous, **not verified**, and never change a kiln's status.
- **The word "petition"** is the user's own demo-script framing for resident requests. Never put it in the product, prompts or docs.
- **The user** writes casually (sometimes Hinglish). Short, plain replies, one recommendation. Builder testing stays **light** (no dark/AX matrices unless asked). The user usually commits and pushes after you stage; always `git log` before reporting what's uncommitted.

## 2. User decisions (binding)

| Decision | Date |
|---|---|
| No sign-in for now. `POST /verdicts`, `/ask`, `/routes/plan`, `/requests`, `GET /public/review` are public. Cognito login on the portal was discussed and **dropped**: residents don't need it; a meaningful login (verified residents or staff review) is after the demo | 10–11 Oct |
| The second AWS account is permanent for Bedrock, CloudFront and CodeBuild | 10–11 Oct |
| Hindi in Ask cut | 10 Oct |
| Portal hosted on AWS: S3 (main, private) + CloudFront (second account, OAC) | 10 Oct |
| Demo verdict on `KW-00c562…` (confirmed): keep it; **reset once right before recording** (needs `aws login` + a go) | 11 Oct |
| Change triage in scope; queue shown read-only in the iOS Review tab | 11 Oct |
| **Resident inspection requests** (43) built and live: portal button → `POST /requests` → count on portal and in the inspector app | 11 Oct |
| Expanding beyond Hapur: after the demo, one neighbouring UP district | 11 Oct |
| The iOS app is shown from the user's own phone; judges try the hosted portal. No TestFlight for now | 11 Oct |

## 3. Status (all reviewed by the orchestrator, all committed and pushed)

| Step | State |
|---|---|
| R1, P1, E1, P2 (rules/exposure, routes, evidence, inspection sheet) | Live |
| V1 39/39b `POST /verdicts` | Live |
| iOS 18–22 (Ask, rules, live Today, polish, verdicts) | Done |
| 36/36b/36c/37 portal live API + Ask + phone layout + hosting | Live |
| 38/38b detector on AWS (CodeBuild second account → ECR → Fargate → Step Functions; manual start) | Live |
| 40 change triage (Agent 2), 45 pending items; 40b `GET /public/review` | Live |
| iOS 23 Review tab | Done |
| **43/43b/43c** inspection requests: migration 004, `POST /requests` on the verdicts Lambda (own route + exact permission), public aggregate `resident_requests` on every kiln, `registry.cli reset-requests`, portal form (EN/HI, plurals fixed, "View your request" once sent), iOS "Resident requests" section + list counts | **Live, committed `04347ac`** |
| M1 better model | ML teammate; not blocking |

Last verified counts: AWS 238 tests (OK, 22 skipped without PostGIS; 238/238 with PostGIS), core `swift test` 103, portal 96 unit + 15 mocked Chromium, root `xcodebuild` clean.

**All three concept agents are live and visible:** Agent 1 planner (iOS Ask + Today, portal Ask), Agent 2 triage (iOS Review tab; runs only when an operator starts it), Agent 3 resident assistant (portal Ask; same Lambda as Agent 1).

## 4. Live state (main account `ap-south-1` unless stated)

- **Registry (RDS):** 39 Hapur candidates, 38 flagged + 1 confirmed (demo verdict). Public reads flagged-only by default; `include=inspected` adds all. Every kiln carries `resident_requests`; **all counts are 0** (the 43b test request was reset). `request_days` for 11 Oct holds 1 (by design; reset doesn't touch it).
- **Satellite evidence:** 39/39 kilns have before (Sentinel-2, 5 Dec 2023) and after (5 Oct 2026) 256 px tiles at 10 m on the CDN, all verified loading. They are fixed snapshots, not live.
- **Caps per UTC day:** Ask 100 (back to 50 after the hackathon), routes 15, verdicts 30, requests 300.
- **Portal:** hosted URL in `.local/portal/outputs.json` (never print it). Re-upload = `npm run build` with the ignored `.env.production.local`, two-pass `s3 sync`, invalidate `/*` (needs a go).
- **Registry runner (EC2 + SSM):** still on (needed for `reset-verdict` and `reset-requests`). Remove after the demo with a go.
- **Budgets:** main account has two $50 alarms. **The second account still has no budget alarm**; remind the user to ask its owner for about $10.

## 5. Credentials

- **Main:** profile `kilnwatch` (`aws login`, user `aryaman`). The user's browser is signed in to the second account, so for the main account they sign in from a **private window**. `!` commands have no TTY; logins run in the user's own Terminal.
- **Second:** profile `kilnwatch-bedrock` (`aws login`); `kilnwatch-cdn-tf` is a `credential_process` over it. Terraform needs **both** sessions for any plan.
- Sessions expire; every AWS prompt checks both (masked) first and stops if either fails.

## 6. Open items, in order

1. **Demo UI polish (the user's next ask).** iOS and portal, for the video. Write **one** polish prompt at a time; iOS and portal can be separate lanes (different files), or one Codex prompt with two sub-agents if the user asks. Keep it to what the camera sees: the demo flow below. Known nits: a tiny Review-tab badge spacing issue; Today close stops 3/4 overlap (from 21); the portal live screenshots in `Web/ResidentPortal/docs/screens/live/` show an old comparator order. No new features, no backend changes, no AWS deploys except a portal re-upload if the portal lane changes. Ask the user what bothers them on screen before writing it; then capture before/after screenshots.
2. **Physical iPhone run** (the user, in Xcode): signing (Automatic, a team is set; with a personal team the bundle ID may need a local-only change), camera, GPS. In the verdict sheet take one photo to check the geotag, then **Cancel; don't submit**. Camera and location strings are in `App/Config/PublicInfo.plist`; the API URL comes from the ignored `App/Config/Public.xcconfig` (present).
3. **Demo script** (`App/docs/demo-script.md`, about 2 minutes): Today route → kiln (evidence, rule flags, people exposed, resident requests) → Ask → record a verdict → Review tab → portal on a phone: find a kiln, **Request an inspection** → the count appears in the inspector app. Good Ask questions: "Plan a route from 28.7306, 77.7759 with 4 stops", "Which Hapur kilns have the most people within 800 m?", "Give me the inspection sheet for this kiln". Say "Sentinel-2, 10 m, Dec 2023 vs Oct 2026"; don't zoom deep into tiles. Honest lines: requests are anonymous and unverified; triage runs when an operator starts it; the app is installed from Xcode.
4. **Pre-recording reset prompt** (next number free): on the runner via SSM, `registry.cli reset-verdict --kiln <demo id> --confirm` and, if any rehearsal requests exist, `registry.cli reset-requests --kiln <id> --confirm`; confirm public reads (38 flagged → 39 flagged after the verdict reset; request counts 0). Needs both logins and a go each time.
5. **Optional:** wire triage into Step Functions after each detector run; portal `/review` page reusing 40b; route priority by resident requests; native Hindi review of portal strings.
6. **After the demo** (each with a go): remove the runner; Ask cap back to 50; consider `enable_verdicts = false` / `enable_requests = false` or sign-in; second-account budget alarm; next UP district.

## 7. Lessons from today

- **List every resource a new public route needs** (route, integration or reuse, **Lambda permission**, stage throttle) in the expected plan. The builder stopping on an unlisted resource is the system working; answer with a short amendment prompt (43b), not a widened scope.
- **Codex with sub-agents works** when the lead freezes the contract and shared fixtures first, lanes own disjoint paths, only the lead touches AWS, and only one lane uses the Simulator.
- **Check copy at count 1.** The first live request in a demo shows the singular; 43 shipped "1 residents" and needed 43c.
- **Re-check live state yourself after every deploy** (read-only GETs with identifiers read from `.local`, never printed).
- **Staged vs committed:** the user commits right after you stage. Always `git log` first.
