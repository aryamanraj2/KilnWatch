# KilnWatch — final-stretch plan (2026-10-10)

This maps every feature in the concept PDF (`App/docs/concept.txt`) to its current state and the next step, by owner.
- **AWS orchestrator:** the Claude Code session. It writes the backend prompts.
- **iOS orchestrator:** the Codex session. It writes the app prompts.
- **AWS teammate:** builds the resident portal.
- **ML team mate:** owns the model.
- **The user:** gives every go.

Product language everywhere: "Flagged by satellite · pending inspection". Rule hits are **siting signals**, never verdicts. Never say "illegal".

## 0. Status

| Step | Status |
|---|---|
| Phase 4A Ask backend, CDN (second account), answer-style fixes 16d–16f | Live |
| 18: iOS live Ask | **In progress** (iOS orchestrator) |
| R1, P1, E1, P2, H1 | Not started (AWS orchestrator; R1 is prompt 31) |
| 19, 20 | Waiting on R1 and P1 |
| M1: better model | ML team mate training; not blocking |

## 1. Concept vs today

| Concept feature (PDF page) | Today | Next step | Owner |
|---|---|---|---|
| Detector (p.3–8) | 39 Hapur candidates in RDS | Optional: 1–2 more NCR scans for breadth | ML team mate, then an import |
| Rules engine, cited JSON (p.6–7, 11) | Built locally by the teammates; **not in RDS** | **R1** | AWS |
| Population exposure, HRSL (p.7, 12) | Built locally; **not in RDS** | **R1** | AWS |
| Evidence images (p.13) | **1 of 39** kilns live through CloudFront (second account) | **E1:** cut before/after pairs for the rest | AWS (+ the ML team mate's evidence scripts) |
| Agent 1, inspection planner (p.9) | **Ask live** with 3 search tools and the validator | R1 adds rule/exposure facts plus `get_evidence`; **P1** adds `plan_route`; **P2** adds `inspection_sheet` | AWS |
| Agent 2, change triage (p.10) | Not built | Stretch only (needs a second scene and a diff) | — |
| Agent 3, resident assistant (p.10) | Same Lambda as Ask (shared by design) | The portal calls `/ask`; **H1** adds `lang: "hi"` | AWS teammate + AWS |
| Guardrails: read-only tools, citation check (p.10) | Done; rule IDs rejected until R1 | R1 lets the validator allow rule IDs **that come from tool results** | AWS |
| Guardrails: Cognito + Verified Permissions (p.10, 12) | Inspector pool exists, no app sign-in | Phase 5, after the demo | — |
| Routing with Location Service (p.9, 12) | iOS Today route UI built on **sample data**; no backend | **P1** | AWS + iOS |
| Inspector app (p.13–14) | Kilns, kiln detail, live evidence, sample Ask | **18** (live Ask), then **19** (rules/exposure on the kiln screen), then **20** (live Today route) | iOS |
| Record verdict + photos (p.14) | UI built, no backend or sign-in | Stretch: keep it as the labelled demo | — |
| Resident portal (p.13) | The AWS teammate is building it (prompt 10) | Use the public API + `/ask`; show rules and exposure after R1 | AWS teammate |
| Review console (p.13) | Not started | Out of scope for the demo | — |
| Automated pipeline: SNS, Step Functions, Fargate (p.11) | Scaffolding only | Out of scope; mention as roadmap | — |

## 2. Backend steps (AWS orchestrator), in order

**R1 — Rules, exposure and evidence facts live** (one prompt; needs the go for a DB migration and write)
- Run migration `002_assessment.sql` and `registry.cli validate-assessment` / `apply-assessment` with the teammates' Hapur assessment, on the registry runner through SSM.
- The public API then returns `violations`, `rules_assessment` and `exposure`. Check the public allowlist covers them.
- **Ask:**
  - `tools.trim` passes the rule flags (rule ID, measured distance, threshold, status, verification level) and the exposure counts;
  - a new `get_evidence(kiln_id)` tool returns image dates, the scene, attribution, rule text and measured distances;
  - the validator allows rule IDs present in this request's tool results;
  - the system prompt becomes conditional on the real data. Unverified thresholds are said to be unverified, and "inconclusive" is never "clear".
  - It also fixes the two-sentence refusal conflict from 16f.
- The live check is the 12-question set again, plus rule and exposure questions.

**P1 — Route planning v1** (1–2 prompts)
- Preflight: check that Amazon Location (route matrix) works in the main account. If it's blocked like Bedrock, use the second account, the same pattern as 16b.
- A `route` Lambda takes a district or kiln list, a start point, a start time and a time budget, and an optional priority ("people exposed", "schools first").
  - It gets the drive-time matrix from Amazon Location.
  - It orders the stops with a pure-Python nearest-neighbour + 2-opt solver (≤ 15 stops; no OR-Tools).
  - It returns the **existing route contract** the iOS Today tab already reads.
- It needs a daily cap like Ask's, and a cost estimate first.
- `POST /routes/plan` (public for the demo, same throttle and cap pattern), plus a `plan_route` tool in Ask.

**E1 — More evidence images**
- Cut before/after 256 px pairs for the remaining 38 kilns with the existing evidence scripts (same grid and attribution).
- Publish them through the CDN with the receipt, then re-import.
- Check that the cost and time are small first.

**P2 — `inspection_sheet` tool** (small)
- A deterministic one-page brief per stop: the rules flagged, people exposed, imagery, and what to check on site.
- Ask uses it after `plan_route`.

**H1 — Hindi in Ask** (small, optional)
- `lang: "en"|"hi"` on `/ask`, with Hindi banned stems in the validator (for example the Hindi words for illegal or unlawful), a Hindi disclaimer, and a 6-question live check.

## 3. App steps (iOS orchestrator, Codex)

1. **18:** live Ask (`/ask`), already scoped in handover 17. **Status: in progress** (the iOS orchestrator is writing prompt 18).
2. **19:** after R1, the kiln detail shows real rule flags (`RuleDistanceBar`, measured against threshold), "unverified threshold" labels, "inconclusive" states, and exposure (`ExposureBlock`, "Within 800 m", people, under-5s, over-60s, with the HRSL attribution). Kilns list rows show the top rule and the people count.
3. **20:** after P1, Today uses the live route (start, stops, Apple Maps handoff). It's honest when no route is planned, and can open Ask pre-filled with "Plan tomorrow in Hapur".
4. A polish pass with screenshots, light/dark and AX sizes.

## 4. Portal (AWS teammate) — what to tell them

- Read-only data: `GET /public/kilns` (near a point or by district) and `/public/kilns/{id}`. After R1 these carry rules and exposure.
- The assistant: call the **same** `POST /ask`; don't build a second one. Later, add an authenticated route to the same Lambda for per-resident limits.
- Images: the `evidence.before`/`.after` URLs (CDN), with Copernicus attribution.
- Hosting: Amplify may be blocked by the same account verification as CloudFront. Check early; the fallback is hosting from the second account.
- Contract: `App/docs/api-contract.md`.

## 5. How we execute it

**Use the existing model.** The ML team mate is training a better detector, which will take time. We **don't wait for it**: everything below runs on the current `best.pt` and the 39 Hapur candidates already in RDS. The model swap is a separate, later step (**M1**, §7).

**There are four parallel lanes.** Each runs one step at a time, and the user carries reports between them.

| Lane | Who | Works through |
|---|---|---|
| Backend, infra and agents | AWS orchestrator, then builder chats | R1, P1, E1, P2, H1 (AWS prompts numbered 30+) |
| Inspector app | iOS orchestrator (Codex), then builder chats | 18, 19, 20, polish (iOS prompts numbered 18–29) |
| Resident portal | AWS teammate | prompt 10, using the shared API and `/ask` |
| Model | ML team mate | the better model, then M1 |

**Order and dependencies:**
1. **Commit** the staged work, then **R1** (AWS) while **18** (iOS) runs. They're independent.
2. **19** (the iOS rules/exposure UI) starts only after **R1** is live. The portal's rules/exposure view waits for R1 too.
3. **P1** (AWS) after R1, because "schools first" and "most people first" ordering needs the rules and exposure data. **20** (the iOS live Today) starts after P1.
4. **E1, P2, H1** in that order, as time allows.
5. Polish, screenshots, the demo video, and a final commit.

**Rules for running lanes in parallel:**
- Builders in different lanes must not edit the same files. AWS builders touch `AWS/` plus the AWS docs; iOS builders touch `App/` (except the API contract, which the AWS lane owns).
- Only one builder uses Xcode or the Simulator at a time.
- Every deploy, DB write, commit and push still needs the user's explicit go.
- Before any commit, fetch first, because teammates push to `main`.

**Cut first if time runs out:** H1, then P2, then E1. **Never cut:** honest labels and the validator.

**Demo story:** Today route → kiln (evidence, rule flags, people exposed) → Ask "Plan tomorrow in Hapur".

## 6. Out of scope for the demo (say so in the submission)

- Change triage and the automated pipeline.
- Inspector sign-in, Verified Permissions and verdict sync.
- The review console.
- Gazette-verified thresholds for school, highway and rail.

## 7. M1 — swapping in the better model (later, when the ML team mate delivers)

- **Don't block anything on this.** When the new checkpoint arrives:
  - verify its hash and benchmark (never quote AP50 as "accuracy");
  - run the same Hapur scene;
  - compare it with the current 39.
- **Kiln IDs include the model** (scene + model + footprint), so a new model produces **new IDs**. Decide with the user before importing:
  - re-import as new candidates and retire the old ones;
  - or keep the old registry and add the new run as a second observation.

  The importer never overwrites human decisions.
- **After the import:** re-run the rules/exposure assessment (R1 path) and the evidence cut (E1 path), then re-check the app, the portal and Ask. No code changes are expected; this is data only.
