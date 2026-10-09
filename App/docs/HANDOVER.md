# KilnWatch iOS: Handover (2026-10-09)

Read this first in a new chat. Then read `App/docs/build-plan.md` and `App/docs/DESIGN.md`.

## What this is

KilnWatch is a satellite brick-kiln compliance system for NCR, built for the WeMakeDevs × AWS hack. This repo holds only the **iOS Inspector app**. The resident portal and the review console are web projects that live elsewhere. The concept PDF's text is in `App/docs/concept.txt`.

## How we work (user's rules)

- **One phase at a time. No parallel agents.** Parallel agents cost too many tokens. Do not spawn auditor or builder agents unless the user asks for one in that turn.
- The orchestrator writes a phase prompt in `App/docs/prompts/NN-*.md`. The user runs it in a fresh chat and pastes the report back.
- Top priority: polished, professional, soft UI with good SwiftUI animation and no AI-looking slop. `DESIGN.md` is binding.
- Builder agents load the Axiom iOS skills. For research, use WebSearch first and Firecrawl when a page is gated.
- Commit or push only when the user asks. The current branch is `PortalAPP`.

## Repo layout

```
KilnWatch.xcodeproj           at repo root; synced folder → App/KilnWatch
App/KilnWatch/                SwiftUI app (Design/, Design/Components/, Features/, Mock/, Assets)
App/Packages/KilnWatchCore/   Swift package: models, API client, offline outbox, tests
App/docs/                     DESIGN.md, build-plan.md, api-contract.md, concept.txt,
                              prompts/, research/, screens/ (light, dark, ax3, video)
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

## Known gaps and pending fixes

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

1. Phase 2 completion and verification evidence are recorded; its implementation remains uncommitted on `PortalAPP`. Commit or push only on an explicit user request. Live backend and successful road guidance remain unverified.
2. Await the user's go for the Phase 3 prompt: Kiln card and evidence imagery, using the pixelated comparator and mini-map buffer ring. Do not begin implementation automatically.
3. Phase 4: Ask with the agent stream. Phase 5: verdict capture, outbox sync trigger and Cognito sign-in. Phase 6: Hindi, accessibility and polish.
