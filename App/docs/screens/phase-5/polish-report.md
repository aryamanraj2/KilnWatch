# Prompt 21 — demo polish — 2026-10-10

Local iOS changes are ready for orchestrator review, with the limits below. No staging, commits, backend edits, API-contract edits or AWS access. Existing staged work and Phase 2 logs were left alone. The root project was not edited.

## Cause and change

The main zoom problem was the tiny usable map viewport: four vertically stacked controls, separate saved/sample banners and the unconstrained carousel left roughly 50 pt between the overlays on iPhone 17. Fitting a roughly 9 km route into that height made its pins pile up. The old 16% plus 1,000 MapKit-point margin widened it further; that constant was map points, not metres. The 400 ms refit could not recover space consumed by the layout.

Controls now occupy two rows. Their icons retain normal map-control sizing at accessibility text sizes, preventing the glass controls from expanding into each other. The carousel reserves 42% of the available container height and scrolls vertically, retaining its cards, their content, Navigate and route actions. Start/End remains outside that scroll area. Default-size map space is now roughly 280 pt.

The overview fits the currently drawn stop coordinates and validated drawn legs with bounded 5% geographic padding. Insets are supplied by SwiftUI's actual safe-area layout. Geometry changes trigger a refit while the overview is active; panning, location and stop focus retain their camera behavior. The 400 ms timer is removed. Reduce Motion cuts the camera without animation.

At most two quiet banners appear. Planning failures and offline status take priority. Saved/sample context becomes one line at default size and wraps at larger text sizes.

Passed-day detection compares calendar days in Asia/Kolkata. The banner says the original day and directs the user to Route list → Plan again. The existing action is now the first route-list section; accessibility text opens the native sheet at the large detent. Planning remains an explicit tap.

RuleDistanceBar uses one accessibility representation, including its measurement, threshold, verification, source and any differing supplied check. Its Show rule action remains available. The final accessibility tree has one combined rule label and zero standalone distance children. Initial ignore/hide modifiers did not remove those children from this toolchain's tree; the final representation did.

## Verification

- Core: `swift test` reports **77 tests passed**, **0 warnings**; one existing opt-in real-detection test is skipped. Four new test functions cover Kolkata midnight, departure-day fallbacks, framing of recorded/fixture routes and updated coordinates, bounded padding, singleton and empty bounds.
- Prescribed root iPhone 17 build: **BUILD SUCCEEDED**, **0 warnings**, **0 errors**.
- Recorded plan: eight stop controls present and hittable; preserved Navigate is reachable by scrolling the carousel.
- Final dark map/detail, AX3 map/list, passed-day and Reduce Motion checks passed. AX3 IDs wrap without truncation, controls remain separate and Plan again is immediately reachable. Dark flags, thresholds and exposure are readable.
- Passed-day screenshot shifts dates only in the isolated DEBUG recorded-plan cache to 9 Oct. Unit tests use fixed times around the 11/12 Oct Kolkata boundary. The Simulator clock was not changed.
- Fixture framing unit checks pass. The fixture UI assertion found **8 stop controls instead of 9**, including after selecting the seeded offline demonstration. Its cause remains unresolved; nine-pin fixture UI verification is not claimed.
- Temporary UI harness and logs remain ignored under `.local/phase-5/`. Failed accessibility/AX3 checks were repeated after focused fixes. Several failed UI runs required stopping lingering test cleanup; no broader appearance matrix was run. Test-runner/toolchain diagnostics are separate from the warning-free app/core checks.

## Screenshots

Seven final screenshots, all stubbed, captured on iPhone 17 / iOS 27 and visually inspected:

| File | Item |
| --- | --- |
| `stub-plan-before.png` | Original saved recorded-plan framing |
| `stub-plan-after.png` | Updated framing at default text size |
| `stub-passed-day.png` | Passed-day banner and saved/sample context |
| `stub-plan-dark.png` | Today plan map in dark appearance |
| `stub-plan-ax3.png` | Today plan map at AX3 |
| `stub-kiln-dark-flags-exposure.png` | Dark kiln flags and exposure |
| `stub-route-list-ax3.png` | AX3 sheet, Plan again and wrapped full ID |

## Requests and leak counts

Live `POST /routes/plan`: **0**. Live `POST /ask`: **0**. App registry/detail responses were intercepted locally; no live registry/image GET was needed.

Changed files and screenshots were scanned using the prompt-20 pattern/exact-value checks, including PNG bytes, OCR and metadata. **15 files**, **7 PNGs**, **7 metadata checks**. Raw pattern matches: **1**; exact private matches: **0**; confirmed leaks: **0**. The sole pattern hit is a numeric byte coincidence inside a compressed PNG IDAT chunk; OCR and metadata have zero hits. No matched value is published.

Output-hygiene exception: the initial combined instruction-file read printed existing public documentation reference links before redaction was applied. Subsequent broad reads were redacted; no private infrastructure values were printed.

## Open limits

- Stops 3 and 4 are approximately 123 m apart. Their unchanged pins still overlap when the whole route is shown. The outer stops and road linework fit between overlays, but the requirement that every pin be separately readable is not fully met. Resolving the close pair would require a pin/collision treatment outside the instruction to preserve pins; the route list and carousel retain access to each stop.
- Nine-pin fixture UI verification remains open as described above.
- Lower carousel content, including Navigate, may require vertical scrolling, especially at AX3. Its content and route logic are preserved.
- Simulator only. No physical-device, iOS 26.1 runtime, spoken VoiceOver, turn-by-turn guidance or live service verification was performed.

Stopped for orchestrator review; no later phase work.

21b (11 Oct 2026): Arrival moved directly under the full kiln ID; compact Navigate retains its label and accessibility label with a verified 44 pt target, visible without scrolling at default and AX3; all inspection content and the 42% carousel height retained, with tighter spacing so the default card is fully visible. Core tests: 77 passed; root build: passed, 0 warnings; focused Navigate UI check: passed (an initial offscreen-element query was corrected). Replaced stub-plan-after.png and added stub-plan-ax3-21b.png; leak checks: 0 pattern / 0 exact private matches; live planning/Ask POSTs: 0, AWS: 0; AX3 details still scroll, prior pin/fixture/device limits remain. No staging or commits; stopped for review.
