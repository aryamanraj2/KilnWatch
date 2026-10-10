# KilnWatch — AWS orchestrator handover #5 (2026-10-10)

You are taking over as the **AWS orchestrator**: backend, infrastructure and agents. You may be running in Claude Code or OpenAI Codex. A separate **iOS orchestrator** (Codex) owns the app.

**Read, in order:**
1. `AGENTS.md`
2. **`App/docs/plan-final-stretch.md`**: the plan you execute. It maps the concept PDF to the steps R1, P1, E1, P2, H1 and M1.
3. This file.
4. `17-orchestrator-handover.md` §3 (live state), §5a (the rules engine) and §5b (the CDN).
5. `11-orchestrator-handover.md` §1, §1a (Codex) and §7 (review lessons).
6. The Phase 4A sections of `AWS/docs/local-verification.md` and `App/docs/api-contract.md`.

These are snapshots: check `git status` and `git log` first.

## 1. Role and rules

- **Your job.** You orchestrate; you don't build. Write **one** builder prompt at a time into `App/docs/prompts/` and give the user a **full copy-paste pre-prompt**, saying "new chat" or "same chat" (the default is new; builders usually run in Codex). Review every report yourself: rerun the tests, `git diff`, a leak scan, and look at any screenshots.
- **Numbering.**
  - **AWS prompts are 30+**, starting with **31 = R1**.
  - The iOS orchestrator uses 18–29.
  - Older AWS prompts are 15, 16 and 16b–16f.
- **No agents.** No sub-agents or parallel agents unless the user explicitly asks.
- **Gates.** Every deploy, DB migration or write, AWS change, commit and push needs the user's explicit go. "Running the prompt = the go for exactly its listed scope" works; put the scope in the prompt.
  - No `terraform destroy`, and no untargeted apply.
  - Never widen IAM, security groups or the bucket policy beyond what a prompt names.
  - Never change the provider lock (`hashicorp/aws 6.68.0`).
- **Files.** AWS builders touch `AWS/`, the AWS docs and `App/docs/api-contract.md` only. iOS builders touch `App/`. Only one builder uses Xcode or the Simulator at a time. **Fetch before every commit,** because teammates push to `main`.
- **The repo is PUBLIC.** Never write or print these:
  - **either** account ID, or any ARN;
  - the API URL or ID, the CloudFront domain or ID, the bucket name, the RDS host;
  - emails, or the second account owner's name (call them "the second account's owner").

  Private values: `.local/` and the ignored `AWS/terraform.tfvars`. Leak-scan the staged diff before every commit, reading the identifiers from `.local/phase-4/cdn/outputs.json`, the tfvars and `.local/phase-4/cdn/distribution-id.txt`, without printing them.
- **Product.** Never use "illegal". "Flagged by satellite · pending inspection". Rule hits are **siting signals**. The type is unverified. The model score isn't accuracy. Missing data is never zero.
- **The user** writes casually, sometimes in Hinglish. Give terse replies, one recommendation, and step-by-step console instructions when they must click something. They sign in only in their own terminal.

## 2. Accounts and tools

- **Main account** (`ap-south-1`): profile `kilnwatch`, IAM user `aryaman`. It holds everything: VPC, RDS/PostGIS, the API Lambda, the public API, the assistant, DynamoDB, S3, Cognito, the runner. **Account-level blocks** pending AWS verification: CloudFront, and Bedrock ("Operation not allowed"). The Support case was unassigned last time it was checked.
- **Second account** (a teammate's, with their consent): profile `kilnwatch-bedrock` (an IAM user, not root).
  - It serves **Bedrock**: role `kilnwatch-assistant-bedrock`, `bedrock:InvokeModel` on Nova 2 Lite only, assumable only by the main `kilnwatch-assistant-lambda` role.
  - It serves the **evidence CDN**: a CloudFront distribution plus OAC, through the Terraform `aws.cdn` provider and the `credential_process` profile `kilnwatch-cdn-tf` in `~/.aws/config`.
  - It has **no budget alarm yet.** The user should ask its owner to add about a $10 one.
- **Terraform:**
  - binary: `.local/tools/terraform/terraform`;
  - main-account credentials go into the environment with `aws configure export-credentials --profile kilnwatch --format env`;
  - the ignored tfvars hold `enable_assistant`, the model ID, `assistant_bedrock_role_arn` and region, `evidence_cdn_account = "second"` and `cdn_profile`.
- **Python tests:** `PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v`. **Last run: 97 tests, 87 pass, 10 skipped** (opt-in PostGIS).

## 3. What's live now

- **Registry:** 39 Hapur candidates (current `best.pt`), all flagged. `rules_assessment: not_evaluated` and `exposure: null` until R1.
- **Public API:** `/public/kilns` (near a point or by district) and `/public/kilns/{id}`, flagged only, through an allowlist.
- **Evidence:** 1 kiln (`KW-6b3b38…`) has published before/after PNGs through the CDN. The other 38 are null.
- **Ask (`POST /ask`):** one Lambda outside the VPC.
  - Nova 2 Lite through the second account, with reasoning off.
  - 3 tools (`list_flagged_kilns`, `kilns_near`, `kiln_detail`).
  - The validator: only kiln IDs from tool results, rule IDs rejected, banned stems `illegal|unlawful|violat`; regenerate once, then a fixed fallback.
  - Plain text only. Per-kiln image facts (`satellite_images`, `images_published_only_for`).
  - Cap **50/day** (DynamoDB); the stage throttle is 1/2 (loose in practice).
  - Logs carry counts and latencies only.
  - 25/50 were used on 2026-10-10.
- **Budgets:** `kilnwatch-monthly-50` (net of credits) and `kilnwatch-monthly-gross-50` (gross).
- **The registry runner is ON on purpose.** R1 needs it to migrate and write. Remove it (`create_registry_runner=false`) after R1 and E1, with a go.

## 4. Lessons from prompts 15–16f (apply them)

- **Contradictory system-prompt lines get followed one way or the other.** 16e said "offer what KilnWatch data can show" and 16f said "no closing offer", and the model kept offering. R1 must **remove** the 16e clause, not add another line.
- **Models misread column/row tables of booleans.** Give per-item facts as explicit words or explicit ID lists, never a bare boolean column.
- **Be precise about matching rules in prompts.** "Words that merely contain them" let "illegalities" through.
- **HTTP API stage throttling is approximate.** Rely on hard counters for cost.
- **`ValidationException: Operation not allowed`** means an account restriction; only Support can lift it.
- **The builders have been honest.** Still rerun the tests and read the live answers yourself.

## 5. Your first task: write prompt 31 (R1, rules + exposure + evidence facts live)

The scope is in `plan-final-stretch.md` §2 **R1**. Before writing it, confirm one product decision with the user (recommendation in brackets):
- [**Yes**] Show all rule results, marking the school, highway and rail thresholds **"unverified threshold"** because they come from an academic compilation. Show "inconclusive" for sparse OSM, never "clear". Show exposure with the HRSL attribution.

Then prompt 31 covers:
1. **Read first:** `AWS/rules/README.md`, `AWS/registry/{cli,store,contract}.py`, `AWS/migrations/002_assessment.sql`, the teammates' `HANDOVER.md` sections.
2. **Locally:** the teammate's assessment inputs and outputs **aren't on this Mac.** `.local/rules/` doesn't exist; they ran it on Windows. Two options:
   - ask the user to get `hapur_assessment.json` from the teammate (plus the OSM and HRSL inputs, for the record);
   - or regenerate it here with `rules.cli fetch` (Overpass OSM plus the pinned public HRSL tiles; network, with approval) and `rules.cli assess` from the live public API kilns.

   Either way, run `registry.cli validate-assessment` before any write, and compare the counts with the teammate's (39 kilns, about 52 flags, median exposure about 4,228).
3. **Public projection:** confirm the allowlist exposes `violations`, `rules_assessment` and `exposure` correctly, including the verification level per rule. If the projection code changes, the API Lambda needs repackaging plus a targeted apply.
4. **On the runner through SSM** (with the go): `registry.cli migrate` (002), then `apply-assessment` (all or nothing). Check counts: 39 kilns, about 52 flags. Check that no human status changed.
5. **Ask:**
   - `trim` and `get_evidence` carry the rule flags (rule ID, measured distance, threshold, status, verification) and exposure (people, under-5s, over-60s, radius) as **explicit fields**;
   - the validator allows rule IDs present in **this request's** tool results;
   - the system prompt is conditional: rules and exposure are stated from the data, unverified thresholds named as unverified, "inconclusive" is not clear, no legal conclusion;
   - **remove the 16e "offer" clause.**

   Then tests, a targeted Lambda apply, and a live set: the earlier 12 plus about 6 rule and exposure questions, within the cap, with the counter read first.
6. **Docs:**
   - `api-contract.md` (the new fields). **Tell the user to pass this to the iOS orchestrator** (prompt 19) **and to the AWS teammate** (the portal).
   - `local-verification.md` and `HANDOVER.md`.

After R1, go on to **P1** (route planning; preflight Amazon Location in the main account, falling back to the second account like 16b), then E1, P2 and H1, per the plan.

## 6. Model (decided by the user)

The ML team mate is training a better model. **Don't wait for it.** Finish everything on the current `best.pt` and the 39 records. The swap is **M1** (`plan-final-stretch.md` §7). Kiln IDs include the model, so a new model means new IDs: get the user's decision before importing, then re-run R1 and E1 on the new data.

## 7. Git state at handover

- `main` = `origin/main` at `8474cba` (Phase 4A plus 16c–16f plus iOS 26.1 compatibility, pushed).
- Untracked: `App/docs/plan-final-stretch.md` and this file. Commit them with the user's go.
- Old untracked `App/docs/screens/phase-2/*.log`: leave them.

## 8. Your first response to the user

1. Confirm what you've read and the live git state.
2. Ask the one product decision in §5, with the recommendation.
3. Then write prompt 31 and its full pre-prompt.
