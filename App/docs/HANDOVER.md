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

**Phase 0: design and clickable mock.** Builds with zero warnings on iOS 26.1, Swift 6, iPhone, portrait.
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

**Research** (`App/docs/research/`):
- `agent-streaming.md`: AgentCore Runtime with NDJSON events. Hold the answer text until citations validate; tool steps stream live.
- `auth.md`: Cognito managed login with PKCE via ASWebAuthenticationSession, no Amplify. Role from groups, district from `custom:district` in the ID token.
- `evidence-imagery.md`: 256×256 PNGs shown with `.interpolation(.none)`, plus `footprint_px`. Re-cut the "before" images from Earth Search, because the dataset tiles are unusable (non-commercial licence, misaligned grid).
- `routing.md`: the server sends stop order, access points and leg geometry. Hand off to Apple Maps one leg at a time, with a multi-waypoint Maps URL as a secondary option.

## Known gaps and pending fixes

1. The app uses its own models in `Mock/MockData.swift`. It must switch to the KilnWatchCore models; that is step 1 of the next phase. The app added `district` and `Violation.measuredTo`, and the core package must agree on both.
2. The BeforeAfterComparator mock uses a sharp Apple snapshot. Per the research, it should show pixelated 256 px imagery, and the 800 m buffer ring belongs on the mini-map, not on the imagery.
3. `api-contract.md` still needs `footprint_px`, the route leg geometry and road access points.
4. The Axiom audits have not run (accessibility, Liquid Glass, layout, codable, concurrency, storage). Run them one at a time, only if the user asks.

## Open decisions (user or backend owner)

- **Concept conflicts:** C-HAB-800 is 1,000 m in UP, but p.13 shows 800 m. `UP/HR-SCH-1K` vs `UP-SCH-1K`. No `district` field in the record, although the Cedar policy needs one.
- **Auth:** use the ID token everywhere? Make `custom:district` admin-only. Can an inspector cover several districts?
- **Agents:** accept AgentCore Runtime as a second endpoint? Hold the full answer, or release it per sentence?
- **Imagery:** 256 px patches re-cut from Earth Search, with Copernicus attribution.
- **Phase 0 questions:** Is the brown-amber "flagged" color acceptable? Should the mini-map pan? Should Ask answer free text? Landscape support? Show the "Sample data" pill in TestFlight?
- **Still unknown:** the backend owner, the API endpoint shapes, and the Cognito pool, client and domain.

## Next steps (in order, one at a time)

1. The main work is already pushed to `PortalAPP` (commit 2797153). This handover file and `AGENTS.md` are staged; commit and push them.
2. Phase 2 prompt: swap in the KilnWatchCore models and fixtures, then make Today use the real route data, MapKit, location and the Apple Maps handoff.
3. Phase 3: Kiln card and evidence imagery, using the pixelated comparator and the mini-map buffer ring.
4. Phase 4: Ask with the agent stream. Phase 5: verdict capture, the outbox sync trigger and Cognito sign-in. Phase 6: Hindi, accessibility and polish.
