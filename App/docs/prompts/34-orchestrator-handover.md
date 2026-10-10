# KilnWatch — orchestrator handover #6 (2026-10-10, evening)

You are taking over as the **single orchestrator** for KilnWatch: backend, infrastructure and agents (AWS), **and now the iOS app too**, because the Codex iOS orchestrator ran out of credits. You may be running in Claude Code or Codex.

**Read, in order:**
1. `AGENTS.md`
2. `App/docs/plan-final-stretch.md` (the plan; its §0 status table is updated below)
3. This file
4. `App/docs/prompts/30-aws-orchestrator-handover.md` §1–§4 (the rules, accounts and lessons; still binding)
5. `App/docs/HANDOVER.md` (the iOS state; the newest sections are at the end) and `App/docs/DESIGN.md` (binding for all UI work)
6. `App/docs/api-contract.md`: the sections "Phase 4A — Ask", "R1" and "P1"

Then check `git status` and `git log`.

## 1. Role and rules (short form; full form in handover 30 §1)

- **You orchestrate; you don't build.** Write **one** builder prompt at a time into `App/docs/prompts/`, and give the user a full copy-paste pre-prompt, saying "new chat" or "same chat". Review every report yourself: rerun the tests and the build, read `git diff`, run a leak scan, and **look at screenshots**.
- **No sub-agents** unless the user explicitly asks.
- **Gates.** Every deploy, DB write, AWS change, commit and push needs the user's explicit go. "Running the prompt = the go for exactly its listed scope" is the working pattern, so put the scope in the prompt.
  - Targeted applies only. No `destroy`. No IAM widening beyond what a prompt names.
  - The provider lock (`hashicorp/aws 6.68.0`) never changes.
- **The repo is PUBLIC.** Never write or print account IDs, ARNs, the API URL or ID, the CloudFront domain or ID, the bucket name, the RDS host, the runner ID or emails.
  - The private values live in `.local/` and the ignored `AWS/terraform.tfvars`.
  - **Leak scan** before every commit: read the identifiers from `.local/integration-2b/outputs.json`, `.local/phase-4/cdn/outputs.json`, `.local/phase-4/cdn/distribution-id.txt` and the tfvars into variables without printing them, then grep the staged diff (binary-safe). Coordinate decimals like `77.399999976158` are false 12-digit hits.
- **Product language.** Never "illegal". "Flagged by satellite · pending inspection". A rule hit is a **siting signal**. `inconclusive` is never "clear". Missing data is never zero. The model score is not accuracy. ETAs are **estimates**.
- **The user** writes casually, sometimes in Hinglish. Give terse replies with one recommendation. They sign in only in their own terminal.
- **Builders:** usually new Claude Code chats now (Codex is out of credits). Only one builder uses Xcode and the Simulator at a time.

## 2. Plan status (supersedes the plan's §0 table)

| Step | Status |
|---|---|
| Ask backend, CDN (second account), 16d–16f | Live |
| **R1** (rules + exposure + `rule_checks`), prompt 31 | **Live** |
| **31b** (Ask: rank by exposure, threshold wording) | **Live** |
| **P1** (`POST /routes/plan`, Ask `plan_route`), prompt 32 | **Live** |
| **32b** (route answers say "estimated"; validator rule) | **Live** |
| **E1** (evidence images for all 39), prompt 33 | **Running now.** Review its report first (§5) |
| iOS **18** (live Ask) | Done, reviewed, merged |
| iOS **19** (rules + exposure UI) | Done, reviewed by the AWS orchestrator (`App/docs/screens/phase-4c/rules-exposure-report.md`) |
| iOS **20** (live Today on `POST /routes/plan`) | **Next for iOS:** not written. You write it (§6) |
| P2 (`inspection_sheet`), H1 (Hindi Ask) | Not started. Cut H1 first, then P2, if time runs out |
| Resident web portal | Merged into `main` at `Web/ResidentPortal/` (the AWS teammate's). The user said to ignore it for now |
| M1 (better model) | The ML teammate is training; not blocking |

## 3. Live state (main account `ap-south-1`, unless stated)

- **Registry (RDS PostGIS):** 39 Hapur candidates, all `flagged/pending`.
  - R1 assessment applied: 52 flags on 36 kilns, `partially_evaluated` for all, exposure for all 39 (median about 4,228).
  - Reference kiln `KW-6b3b38da681850e5af46b024f3d3f78e`: C-HAB-800 at 497 m against 800 m; 4,225 people / 430 under 5 / 294 over 60.
- **Public API (API Gateway + `kilnwatch-api` Lambda in the VPC):** `/public/kilns` and `/public/kilns/{id}`, cached for 60 s, through an allowlist that now includes `rule_checks` (7 keys per rule; `rules_results` stays internal).
- **Ask (`kilnwatch-assistant` Lambda, outside the VPC):**
  - Bedrock Nova 2 Lite through the **second account** (STS assume-role).
  - Tools: `list_flagged_kilns` (with `sort_by: people_within_800m`), `kilns_near`, `kiln_detail`, `get_evidence`, `plan_route`.
  - Validator: kiln IDs and rule IDs only from this request's tool results; banned stems; after `plan_route`, any clock time needs "estimat…".
  - **Daily cap is 100** (raised for the mentors and the demo; set it back to 50 after the hackathon, via the tfvars `assistant_daily_cap` and a targeted apply of `aws_lambda_function.assistant[0]`).
- **Routes (`kilnwatch-route` Lambda, outside the VPC):** `POST /routes/plan`.
  - Amazon Location Routes v2 (Core tier), a 9×8 Unbounded matrix plus one `CalculateRoutes` call.
  - Nearest-neighbour + 2-opt, max 8 stops, a cap of **15 plans per UTC day** (Ask's `plan_route` counts against it).
  - About $0.0365 a plan; the worst case is about $16 a month.
  - It returns the existing iOS `Route` contract plus `notes[]`.
- **Evidence CDN:** CloudFront in the second account (OAC to the private main bucket). Before E1: 1 kiln has images.
- **Registry runner (EC2 + SSM):** still running on purpose, for E1. Remove it after E1 and P2 with a go (`create_registry_runner=false`, targeted).
- **Budgets:** `kilnwatch-monthly-50` (net) and `kilnwatch-monthly-gross-50`. The second account still has **no budget alarm**: remind the user to ask its owner to add about $10.
- **Python tests:** `PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v`. Last run: **141 run, 131 pass, 10 skipped** (opt-in PostGIS).
- **iOS:** `cd App/Packages/KilnWatchCore && swift test` gives **63 pass**. The root `xcodebuild … build` succeeded with no warnings.

## 4. Lessons from this stretch (apply them)

- **Fix data shape and validators, not prompt lines.** Nova 2 Lite ignores soft instructions. What worked:
  - explicit strings instead of booleans or status codes;
  - server-side sorting (`sort_by`);
  - putting the word into the value ("estimated arrival 09:13");
  - a deterministic validator rule.

  Stop iterating on wording once answers are honest but incomplete: each round costs a deploy and cap.
- **Known small-model gaps (accepted):** "Plan tomorrow in Hapur" may summarise without listing the stops; "visit first for most exposed" may give the road order. **For the demo, ask:** "Plan a route from 28.7306, 77.7759 with 4 stops", "Which Hapur kilns have the most people within 800 m?", "Show me the evidence for this kiln".
- **Cost-check before building.** P1's first design was about $116 a month worst case. The stop rule ($20 a month) caught it, and the user chose 8 stops and a cap of 15.
- **On macOS, `tar` adds AppleDouble `._*` files.** Use `COPYFILE_DISABLE=1 tar --no-xattrs`. This broke `migrate` once.
- **Regenerated assessments matched the teammate's** (OSM fetched 2026-10-10). The file's SHA is in `local-verification.md` "R1".
- **The builders have been honest and careful.** Still rerun everything and read the live answers yourself.

## 5. First task: review the E1 report (prompt 33)

Check:
- the input hash matched;
- the `KW-6b3b38…` pair is byte-identical to the published one;
- the skipped kilns and their reasons;
- **open `.local/e1/contact-sheet.png` yourself**;
- the receipt verified every object, and the denial probe passed;
- the re-import created 0 new kilns, the status and review counts are unchanged, and **the R1 counts are unchanged (39 / 36 / 39)**;
- the public list shows images for the expected count; spot-check that a few image URLs return 200 and `image/png`;
- the tests, and the leak scan.

Then the docs: `api-contract.md` (the evidence line), `local-verification.md` "E1", and a runbook note. Then ask the user for a commit and push go.

## 6. Next: write the iOS prompt 20 (live Today)

Number it `20-live-today-route.md`. The iOS lane's own numbering is 18–29.

- **Read first:** `App/docs/prompts/18-*.md` and `19-*.md` (the iOS prompt style and scope rules), `HANDOVER.md`, `DESIGN.md`, the Today tab code, `Route`/`Stop`/`RouteLeg` in KilnWatchCore, the api-contract "P1" section, and the samples in `.local/phase-4/live/p1/` (`plan1-people.json`, `plan3-start.json`; hosts already removed).
- **Scope:**
  - Today plans on a **user tap** (for example "Plan tomorrow in Hapur": district Hapur, `priority: people`, max 8 stops). It **never** auto-plans on launch, because each plan costs about $0.04 and the cap is 15 a day.
  - It caches the last plan with the existing atomic route cache, and shows `notes[]`.
  - Labels:
    - ETAs: "Estimated";
    - access points: "Kiln centroid · confirm entrance on site";
    - stop order: road order, never "most exposed first".
  - It handles a plan without `legs` (stops, no lines), and the errors (400, 404 `no_kilns`, 429 `daily_cap_reached` with the gateway 429 that has no `error.code`, 503).
  - The Apple Maps handoff per stop.
  - Labelled Sample data stays only for DEBUG with no config.
  - Optional: an "Ask about this plan" prefill.
- **Gates:**
  - live `POST /routes/plan` calls are **capped** (for example at most 3 in the whole phase); the rest use local stubs;
  - zero Ask POSTs unless named;
  - no backend edits; the AWS lane owns the contract;
  - light/dark, AX3/AX5, Reduce Motion; screenshots in `App/docs/screens/phase-4d/`; the leak scan includes the PNGs.
- **Review it like 19:** `swift test`, the root build with no warnings, the screenshots, and the leak scan of the PNGs and JSON (recorded fixtures must have no URLs or hosts).

## 7. After that

1. **P2 `inspection_sheet`:** deterministic, per stop; Ask uses it after `plan_route`. It can also enrich `sheet.on_site_checks` in the route response.
2. **H1 Hindi Ask** (optional).
3. **Polish:** the "requires 800 m" vs "applied threshold" wording; a VoiceOver double-read check on `RuleDistanceBar`; screenshots; the demo video.
4. **Cleanup after the demo (each with a go):**
   - remove the registry runner;
   - set the Ask cap back to 50;
   - consider lowering the route cap;
   - the second account stays permanent for Bedrock and CloudFront (user decision, 2026-10-10); no switch-back.
5. **M1** whenever the ML teammate delivers: new IDs, so the user decides how to import; then re-run R1 and E1. No code changes.

## 8. Git state at handover

- `main` = `origin/main` at `daeedf3` (the merge of `webApp`, plus R1, 31b, P1, 32b, iOS 18/19 and prompts up to 33).
- Untracked: the old `App/docs/screens/phase-2/*.log` (leave them), and this file once written. Commit it with the next go.
