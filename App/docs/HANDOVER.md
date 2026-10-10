# KilnWatch iOS: Handover (2026-10-09)

Read this first in a new chat. Then read `App/docs/build-plan.md` and `App/docs/DESIGN.md`.

## What this is

KilnWatch is a satellite brick-kiln compliance system for NCR, built for the WeMakeDevs × AWS hack. The iOS Inspector app, AWS foundation and model pipeline have been merged into `main`, under `App/`, `AWS/` and `Model/`. The resident portal and review console are not implemented here. The concept PDF's text is in `App/docs/concept.txt`.

## How we work (user's rules)

- **One phase at a time. No parallel agents.** Parallel agents cost too many tokens. Do not spawn auditor or builder agents unless the user asks for one in that turn.
- The orchestrator writes a phase prompt in `App/docs/prompts/NN-*.md`. The user runs it in a fresh chat and pastes the report back.
- Top priority: polished, professional, soft UI with good SwiftUI animation and no AI-looking slop. `DESIGN.md` is binding.
- Builder agents load the Axiom iOS skills. For research, use WebSearch first and Firecrawl when a page is gated.
- Commit or push only when the user asks. The current working branch is `main`.
- Call the infrastructure/backend owner **AWS teammate**, and the model/training owner **ML team mate**.

## Repo layout

```
KilnWatch.xcodeproj           at repo root; synced folder → App/KilnWatch
App/KilnWatch/                SwiftUI app (Design/, Design/Components/, Features/, Mock/, Assets)
App/Packages/KilnWatchCore/   Swift package: models, API client, offline outbox, tests
App/docs/                     DESIGN.md, build-plan.md, api-contract.md, concept.txt,
                              prompts/, research/, screens/ (light, dark, ax3, video)
AWS/                          Terraform foundation, placeholder Lambda API, agent container
Model/                        preparation, training, scene detection, notebooks and baseline scores
```

**Xcode gotcha:** never drag `KilnWatch.xcodeproj` into Xcode's file navigator. Doing that added a reference from the project to itself and caused the "NSPOSIXErrorDomain 22 Invalid argument" error on open. The fix was to remove the `projectReferences` and self file-ref entries from the pbxproj. Build with:
`xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build`

## Done

**Phase 0: design and clickable mock.** Builds with zero warnings on iOS 27.0, Swift 6, iPhone, portrait.
- Neutral gray theme with a single clay accent (#A84B25 / #E07A4F). Five status colors, each always paired with a symbol and a word. All 50 contrast pairs pass in light and dark mode.
- Monospaced IDs and distances. Liquid Glass on the navigation layer only. Three motion tokens with Reduce Motion fallbacks, plus haptics.
- Nine components: RuleDistanceBar, StatusBadge, KilnIDLabel, BeforeAfterComparator, ExposureBlock, ToolCallTrace, CitationChip, HoldToConfirmButton, StopPin.
- Six screens: Sign in, Today (map, stop carousel, route bar above the tabs), Kiln, Ask (scripted agent trace and streamed answer), Record verdict, Kilns.
- DEBUG-only demo hooks and launch arguments, documented in DESIGN.md §10.
- The site photos are Wikimedia CC BY-SA and only for the mock.

**Phase 1: KilnWatchCore.** `swift test` passes (11 tests).
- Models follow the kiln record on concept p.15. Unknown enum values decode to `.unknown(raw)`.
- `KilnWatchAPI` struct with typed errors.
- `RouteCache` plus a `VerdictOutbox` actor. The outbox never deletes an unsent verdict; photos go to S3 through presigned PUT URLs.
- Fixtures: 11 kilns, a 9-stop Hapur route and 7 rules.
- `App/docs/api-contract.md` is a proposal the backend owner has not yet confirmed.

**Phase 2: Today, shared models and route navigation.** Builder completion reported and verification report/logs checked by the orchestrator on 2026-10-09. Implemented on `PortalAPP`; iOS 27 SDK and deployment target, per the user's correction. No full code audit or independent test rerun in this closeout; no commit/push or Phase 3 work.
- The app links KilnWatchCore and consumes its fixtures and embedded route records. Domain duplicates are removed; optional district/feature metadata and route access/geometry/timing retain legacy decoding. Unknown types/statuses and missing kiln IDs have honest presentation.
- Today renders only validated supplied linework, keeps pin/carousel/list selection synchronized, and separates browsing from the active/current stop. Start/End and the accessory agree across tabs. Native Maps actions use access points and ask before falling back to the kiln location.
- Route loading distinguishes authoritative empty, saved/offline, no cache, corrupt cache and fetch failures. Successful live responses are cached atomically off the UI actor; failures preserve valid saved data and never substitute fixtures. DEBUG simulations use isolated storage.
- No backend endpoint/token is configured: reviewed data is explicitly labeled fixtures or an isolated saved fixture cache. Configuration and optional wire keys are documented in `api-contract.md`; the proposal still needs backend confirmation.


**Phase 2 verification (2026-10-09):** prescribed root build passed with zero warnings; `swift test` passed all 21 tests with zero warnings, retaining the original 11. Six sequential temporary XCTest UI checks passed on iPhone 17 / iOS 27: route interactions, Maps handoffs, denied location, granted one-shot location, recovery states/mock-screen navigation, and AX3 controls with system Reduce Motion confirmed enabled. The temporary UI target is outside the repository. Recovery simulations cover loading, empty → Ask draft, service failure, no cache, corrupt cache, saved relaunch and missing geometry. Stubbed API tests cover authoritative 404/empty, auth/server/decoding failures and cache preservation.
- Both single-stop and whole-route actions actually opened Apple Maps and preserved the active stop. Maps presented its own permission/startup UI; successful road guidance and waypoint rendering were not established. Granted/denied app location were verified; remaining physical-device permission cases are listed below. Accessibility labels/actions were inspected and exercised, but a spoken VoiceOver walkthrough was not performed.
- A transient carousel frame warning was fixed by bounding its initial width; the final missing-geometry/AX3 run emitted no frame warning. iOS 27 beta tool/runtime diagnostics remain in temporary UI logs, separate from the warning-free prescribed app/core checks.
- Reviewed existing images: `screens/phase-2/selected-stop.png`, `route-list.png`, `active-accessory.png`. Additional light/dark/state images and video were skipped at the user's request. Logs and details: `screens/phase-2/verification.md`. Design tokens, component appearance and tabs are preserved; Navigate and honest route/location states are Phase 2 additions.

**Research** (`App/docs/research/`):
- `agent-streaming.md`: AgentCore Runtime with NDJSON events. Hold the answer text until citations validate; tool steps stream live.
- `auth.md`: Cognito managed login with PKCE via ASWebAuthenticationSession, no Amplify. Role from groups, district from `custom:district` in the ID token.
- `evidence-imagery.md`: 256×256 PNGs shown with `.interpolation(.none)`, plus `footprint_px`. Re-cut the "before" images from Earth Search, because the dataset tiles are unusable (non-commercial licence, misaligned grid).
- `routing.md`: the server sends stop order, access points and leg geometry. Hand off to Apple Maps one leg at a time, with a multi-waypoint Maps URL as a secondary option.

## Integration 1 local bridge (2026-10-09)

Prepared on `main`, sequentially, with no agents, deployment, training, commit/push
or Phase 3 work. Verified supplied baseline OBB checkpoint (SHA prefix `3bcbcd0af696`),
matching args/score configuration; saved Kaggle version/weight-to-score linkage still
unverified. One fixed real Hapur run produced 39 candidates (55 raw / 120 patches).
One real 256 px before/after pair is cut on a matched grid and inspected, still local
and unpublished; no precise registration/change/field accuracy claim.

Code now includes strict model/evidence conversion, idempotent transactional registry
import/migrations, authenticated district read API, dependency packaging and minimum
Terraform source for private secret access/credentials and evidence-only delivery.
Core gains honest missing exposure/images, unassessed rules, unverified high-score type,
provenance/image metadata and paginated list reads. Minimal presentation safeguards
retain the binding design and stop real records using mock evidence. Live app registry
fetching/image loading remain deferred.

Verification: **22 Python tests passed; 2 actual PostGIS tests skipped** because local
PostGIS/Docker is unavailable. **26 core tests passed**, including synthetic producer
contract and the real local 39-record body; **root iPhone 17 build passed**; both Swift
checks had **zero warnings**. Lambda ZIP/import/CA and notebook syntax/path checks
passed. Terraform/AWS CLI unavailable, no plan/account or live AWS checks.

Review [`AWS/docs/first-record-runbook.md`](../../AWS/docs/first-record-runbook.md)
and [`AWS/docs/local-verification.md`](../../AWS/docs/local-verification.md). The
**AWS teammate** must confirm account/state/district/publication/private runner and
complete DB/plan/live proof after deployment authorization. The **ML team mate**
still supplies saved-run identity and evidence interpretation. Phase 3 stays on hold.

## Integration 2A preflight (2026-10-09)

Integration 1 is committed at `6092cf8`. Integration 2A (`prompts/07-first-record-preflight.md`
plus its addendum) fixed the evidence-republication bug, hardened the runbook, and
proved the registry on a real local PostgreSQL 17 / PostGIS 3.6.4 cluster (39-record
import and replay, roles, TLS, handler, Swift decode; it also caught and fixed a bootstrap bug). Terraform `fmt`/`validate` pass. Decisions applied: `ap-south-1`,
RDS backups/deletion protection/final snapshot, `PriceClass_200`, S3 remote state. The
only AWS write is the state bucket `kilnwatch-tfstate-<account-id>-ap-south-1`. A
read-only plan shows 75 resources to add; estimated ≈ $38/month always-on before
credits. **No apply.** Integration 2B (deployment) needs explicit authorization.

## Integration 2B live deployment (2026-10-10)

AWS is **deployed** in `ap-south-1`: 73 of 75 planned resources, with the 39 real Hapur
candidates migrated/imported into private RDS (replay 0/0) and served by the live
Lambda. CloudFront (evidence delivery) is blocked until AWS verifies the account; the
user opened a Support case. After that: apply the 2-resource remainder, publish the two
PNGs, re-import with the receipt, run the CloudFront denial probe, then remove the
temporary runner (5 destroy / 1 change). **User decision:** the app is shown in a demo
video with placeholder data and needs no sign-in; no Cognito test user or real-token
checks. Budget alert USD 50/month is on. Always-on cost ≈ $38/month (2A estimate) plus
the runner (~$0.42/day) until removed. Details: `AWS/docs/local-verification.md`.

## Integration 2C public read API (2026-10-10)

The no-login public read API is **live**: `GET /public/kilns?lat=&lon=&radius_m=` (sorted
by `distance_m`, at most 50), `GET /public/kilns?district=&cursor=&limit=` and
`GET /public/kilns/{id}`. Only flagged kilns (SQL), allowlisted fields, cached 60 s,
throttled 10/s. It is ready for the resident portal (AWS teammate) and for Phase 3's demo
data; the iOS app needs no sign-in for it. Inspector routes still require Cognito
(Phase 5). The Lambda log group now has 14-day retention. CloudFront is still pending AWS
verification. Details: `api-contract.md` and `AWS/docs/local-verification.md`.

## Known gaps and pending fixes

Read `App/docs/integration-status.md` for the source inspection and first integration plan. AWS is deployed (Integration 2B) with the public read API live (2C); CloudFront pending. The user supplied and the builder verified the existing baseline `best.pt`, then matching `args.yaml`/`scores.json`; the saved Kaggle version identity remains missing. Weights and raw GeoJSON are intentionally excluded from Git. Phase 3 is on hold while the model-to-AWS record/evidence bridge is prepared.

1. The BeforeAfterComparator mock still uses an Apple snapshot. Pixelated 256 px imagery and the mini-map buffer ring belong to Phase 3.
2. Live route verification needs the real endpoint/token and backend confirmation of access points, geometry/axis order, route timing and error semantics. The sample geometry is schematic, not verified road routing.
3. Simulator Maps launches do not establish successful turn-by-turn guidance or offline navigation. Physical-device, approximate/restricted location and disabled-service behavior remain to verify.
4. The Axiom audits have not run. Run them sequentially only if the user asks. No auditor agents were used in Phase 2.

## Open decisions (user or backend owner)

- **Concept conflicts:** C-HAB-800 is 1,000 m in UP, but p.13 shows 800 m. `UP/HR-SCH-1K` vs `UP-SCH-1K`. No `district` field in the record, although the Cedar policy needs one.
- **Auth:** use the ID token everywhere? Make `custom:district` admin-only. Can an inspector cover several districts?
- **Agents:** accept AgentCore Runtime as a second endpoint? Hold the full answer, or release it per sentence?
- **Imagery:** 256 px patches re-cut from Earth Search, with Copernicus attribution.
- **Phase 0 questions:** Is the brown-amber "flagged" color acceptable? Should the mini-map pan? Should Ask answer free text? Landscape support? Show the "Sample data" pill in TestFlight?
- **Still unknown:** the backend owner, the API endpoint shapes, and the Cognito pool, client and domain.

## Next steps (in order, one at a time)

1. Phase 2 was committed and merged with model/AWS source into `main`. Live backend and successful road guidance remain unverified. Commit or push further work only on an explicit user request.
2. Integrations 1, 2A, 2B and 2C are done, except CloudFront: after AWS account verification, finish evidence publication, the denial probe and runner removal (runbook "Deployed state" and "Integration 2C").
3. Resident portal on the public API (AWS teammate) is next. Phase 3 (real registry and evidence UI) follows on the user's request and can read the public API with no sign-in; inputs are the output names in the runbook's "Deployed state".
4. Phase 4: registry-backed Ask/agent stream and real route planning. Phase 5: verdict capture, outbox sync trigger and Cognito sign-in. Phase 6: Hindi, accessibility and polish.

## Rules engine v1 (local) — 2026-10-10

`AWS/rules/` contains versioned thresholds with citations (`rules_v1.json`), an OSM/Overpass layer fetch, and a pure geodesic footprint-edge distance engine with 12 tests. The full AWS suite has 47 tests (47 OK, 9 skipped). Research found the UP First Amendment Rules, 2026 (3 Feb 2026): habitation 800 m, kiln spacing 1 km, and a new 5 km municipal-limits rule. This resolves the C-HAB/C-KILN concept conflict. The values come from secondary sources, not the gazette text. School, national-highway and railway thresholds come only from an academic compilation and are marked unverified. OSM habitation, school and orchard coverage around Hapur is sparse, so finding nothing there is `inconclusive`, never clear. The local Hapur run flagged 36 of 39 kilns: kiln spacing 28, habitation 14, highway 5, rail 5. A few near-zero distances (for example 4 m to NH9) suggest false-positive detections.

**Follow-up, same day:**
- Migration `002_assessment.sql` adds an assessor role limited to `candidates.assessment`.
- `registry.cli validate-assessment` / `apply-assessment` validate the whole batch and write it all-or-nothing.
- The Hapur assessment now carries real registry IDs. These were rebuilt from the local detections file plus the manifest, and matched all 5 recorded live kilns. It validates: 39 kilns, 52 flags.
- KilnWatchCore `Violation.evidenceUrl` is now optional, with a new decode test. The kiln screen says "No rule flags measured" and adds a note when a kiln is partially evaluated.
- The app fixtures use the v1 thresholds: no UP overrides, school/highway/rail sources marked "UP siting rules (2012)", and UP-MUN-5K added, so the rules count is now 8.
- Python: 51 tests, OK, 10 skipped. The new PostGIS role test is among the skipped ones because this Windows machine has no PostGIS or Docker.
- **Swift build and tests have not run** (no Xcode here). Run the prescribed `xcodebuild` and `swift test` on the Mac.
- Nothing was migrated or written to RDS.

**Population exposure (2026-10-10):**
- `AWS/rules/exposure.py` sums Meta/CIESIN HRSL v1.5.2 (pinned tiles, CC BY 4.0) within 800 m of each footprint edge: all people, children under 5 and adults over 60.
- It is fetched once to `.local/rules/hapur_hrsl.tif`. `apply-assessment` writes `exposure` with its provenance.
- Hapur: all 39 kilns assessed, median 4,228 people (range 60 to 25,701). An independent rasterised-mask cross-check agreed to within 0.14%.
- Python: 55 tests, OK, 10 skipped.
- Optional Swift follow-up: label real records' exposure "Within 800 m". The radius is fixed at 800 m but not yet shown, because `KilnView` passes `bufferRadiusM: nil` for non-fixture kilns.

## Phase 3 (overnight run) — 2026-10-10

**Partly done:** the no-login iOS app now loads 39 real Hapur kilns from the configured public API, with on-demand detail, honest missing evidence/rules/exposure, unverified type/model score, recoverable network states and a real Today map without fabricated routes. Fixture routing remains. Final core checks report 34 functions (33 passed, one existing opt-in skip; 55 executed cases); prescribed root iPhone 17 build and core checks have zero warnings. Light/dark, AX3/AX5 and Reduce Motion were verified. After three fix cycles, the detail marker still obscures its small footprint; navigation immediately after active search remains unverified. Published remote imagery awaits CloudFront; spoken VoiceOver, physical device and actual missing-config build remain unrun. No staging, commit, push, cloud or later-phase work; protected files and existing Phase 2 logs are preserved. See [morning report](screens/phase-3/overnight-report.md) and [file inventory](screens/phase-3/changed-files.md). The one-run agent exception has ended; normal no-agents rules resume.

## Phase 4A preflight — 2026-10-10

**Built and planned, not deployed.** The `POST /ask` backend is in `AWS/assistant/`: one small Lambda outside the VPC that reads only the public API. It has a shared `core.answer()` that the portal can later reach through its own authenticated route on the same Lambda, three thin tools, a deterministic citation validator (regenerate once, then a fixed fallback), a global daily cap of 300 questions on DynamoDB that fails closed, and logs that hold counts only. Terraform `AWS/assistant.tf` is gated by `enable_assistant` (default false). The model is the user's choice, `global.amazon.nova-2-lite-v1:0` with reasoning off; the runner-up is Nova Pro via `apac.`. Python tests: 65 run (56 passed, 9 existing PostGIS skips), all mocked. The read-only targeted plan is 8 add, 1 change (the stage gets `POST /ask` at 1/s, burst 2), 0 destroy.

**Blocker:** the only smoke `Converse` call returned `ValidationException: Operation not allowed`, which looks like an account-level Bedrock block, so real invocation and tool use are unproven. The worst-case cost at the 300/day cap is above the USD 50 budget (see the report). The contract is in `api-contract.md` "Phase 4A — Ask" and the evidence in `AWS/docs/local-verification.md`. Prompt 16 (deploy) needs the user's go after the block is cleared.

## Phase 4A deploy — 2026-10-10

**Deployed; Bedrock still blocked.** `POST /ask` is live: a targeted apply of the saved plan added the 8 assistant resources and changed only the stage (`POST /ask` at 1/s, burst 2; public routes still 10/20, default 50/100). `enable_assistant = true` and the Nova 2 Lite model ID are persisted in the ignored `AWS/terraform.tfvars`. The daily cap is now **50 questions per UTC day** (worst case about $47 per 30 days). Banned words now match any word that starts with one of the stems in `validator.BANNED_WORDS`. A second budget, `kilnwatch-monthly-gross-50` (USD 50, credits excluded, 80% actual and 100% forecast alerts to the existing subscriber), was added outside Terraform. Live checks passed for input validation, the daily cap and log privacy; stage throttling works but is loose (6 parallel requests were never throttled, 20 gave 2 × 429). Every valid question returns 503 `model_unavailable` (`retryable: false`) because Bedrock still answers `ValidationException: Operation not allowed`, also in the console playground. **Real answers are unproven** until AWS lifts the account block; then run prompt 16 Step 5 (smoke calls and the 12 questions). Evidence is in `AWS/docs/local-verification.md`.

Bedrock is served through the user's second account until the main account is unblocked. All 12 live questions (prompt 16b) answered with no fallback; switch-back steps are in `AWS/docs/local-verification.md`.

Evidence images live via CloudFront in the second account; runner kept for the rules-engine apply.

## iOS runtime compatibility — 2026-10-10

The app Debug/Release deployment targets and KilnWatchCore iOS minimum are now 26.1, using the existing Xcode 27 / iOS 27 SDK toolchain. Swift logic, appearance, signing and backend behavior are unchanged. Compatibility verification and actual runtime coverage are recorded in `screens/ios-26-compatibility/report.md`; physical-phone verification remains pending.


## Phase 4B local iOS builder — 2026-10-10

Live Ask is implemented with typed stateless POST handling, honest waiting/server traces, full-ID citations and live-detail prefill, Unicode/byte limits, offline recovery, manual errors and retained labelled Sample data. Final root build and 53-test core run passed with zero app/core warnings (one existing opt-in test skipped). Light/dark, AX3/AX5 and Reduce Motion local checks passed on iOS 27 Simulator; minimum remains 26.1. Live verification is deferred to the user by explicit request: zero POSTs confirmed, one conservatively reserved attempt retained privately, no answer claimed. See `App/docs/screens/phase-4/ask-report.md` for evidence, scan results, harness limitations and the incidental browser-inventory scope exception. No backend/API-contract edits, staging or commits by this lane. Paused for orchestrator review; prompts 19/20 not started.


### Phase 4B live confirmation — 2026-10-10

After explicit user reauthorization, one live Ask submission from the installed app succeeded for the Hapur count question: 39 flagged kilns, one full-ID citation, one server-written trace step and the disclaimer. The citation opened live detail with published imagery. Conservative count is 2 of 8, including the earlier unconfirmed reservation; no retries or counter reads. Updated evidence and scope are in `screens/phase-4/ask-report.md`. The selected-kiln contextual POST remains for the user to test. Implementation remains paused for orchestrator review; no prompts 19/20 started.


## Prompt 19: rules and exposure UI — 2026-10-10

Kiln detail shows live siting flags (measured against threshold, verification label, source), every supplied rule check, and HRSL modelled exposure with attribution; the Kilns list shows the top flag and the modelled residents. Partial assessment is never shown as clear; unknown statuses show as unavailable. The orchestrator reviewed it: 63 core tests passed, the root build succeeded, the leak scan found 0 hits, and the screenshots were reviewed. See `screens/phase-4c/rules-exposure-report.md`. Next for iOS: prompt 20 (live Today on `POST /routes/plan`, live since P1).


## Prompt 20: live Today route — 2026-10-10

In live mode, Today plans a route on a tap ("Plan tomorrow in Hapur") through `POST /routes/plan`, shows it in the existing route UI with estimate-labelled times, verbatim plan and access notes, and the empty-flag stop as "No rule flags measured". It caches the plan and reopens it on launch with no POST. Failures keep the saved plan, with typed wording for each error. Core tests: 73 passed. Root build succeeded with zero warnings. Leak scan: 0. Live `POST /routes/plan` used 1 of 3 (8 stops, all in the registry, legs drawn; Maps opened); `POST /ask` 0. Dark, AX and Reduce Motion captures were skipped at the user's request. See `screens/phase-4d/live-today-report.md`. Paused for orchestrator review.
