# KilnWatch — prompt 21: demo polish (route map, old plans, appearance check)

Run in a **new Claude Code builder chat**, in the existing checkout. Prompt 20 (live Today) passed orchestrator review and is committed. P2 (`inspection_sheet` in Ask) is live. This builder may use Xcode and the Simulator; no other builder may use them at the same time.

The demo story is: **Today route → kiln (evidence, rule flags, people exposed) → Ask.** This phase makes the first screen look right. It's small. Keep the testing **light**: the user stopped the long capture runs in prompt 20 because they took too long. Run the core tests, the root build, the checks listed here and one screenshot per item. Don't run appearance matrices beyond §4.

## 1. Scope and authorization

Running this prompt authorizes local iOS edits, `swift test`, the root build, Simulator checks, screenshots and a few public registry/image GETs. **Zero live `POST /routes/plan` and zero `POST /ask`**: use the existing DEBUG `-planDemo` recorded plan (and `-resetPlan` where needed) for every route screen. No AWS access, no backend or `App/docs/api-contract.md` edits, no sub-agents, no staging or commits. Own `App/` only; leave the root project alone. Preserve the old Phase 2 logs.

Read: `AGENTS.md`, `App/docs/DESIGN.md` (binding), the newest sections of `App/docs/HANDOVER.md`, `App/docs/screens/phase-4d/live-today-report.md` ("Remaining limits"), then `Features/Today/*`, `RoutePresentation.swift`, the `RoutePlan.swift` route helpers and `RuleDistanceBar`. Use the Axiom SwiftUI/MapKit skills where useful.

## 2. Route map framing (the main fix)

Today the plan map opens far too zoomed out. The 8 pins pile into one blob, and the banners and the floating header cover them (see `phase-4d/live-plan-map-carousel.png` and `stub-plan-again-failed-keeps-plan.png`). The fixture route has the same problem.

- Find the actual cause before changing numbers. Candidates: the `overview` padding (`16% + 1,000 m`), the camera set before the safe-area insets settle (the 400 ms refit from 20 is a workaround), and the tall carousel inset.
- Target: on an iPhone 17 at the default text size, every stop pin and the road lines are visible **between** the header/banners and the carousel, with the pins separated and readable. Same with Reduce Motion (the camera cuts).
- Prefer one honest fix, such as fitting to the stops plus legs with the real insets, over timers. If a short delay really is needed, keep it to one and say why.
- Banners: at most two quiet banners under the header at once. Fold "Saved plan · date" and "Sample data · recorded test plan" into one line when both show. Error and offline banners take priority.
- Don't change the pins, the carousel cards' content or the route logic.

## 3. A saved plan for a day that has passed

`dayLabel` shows "Sun 11 Oct" once the plan's day has passed in Asia/Kolkata, and nothing else changes. Add:
- one quiet banner: "This plan was for Sun 11 Oct · plan again for a new day";
- "Plan again" easy to reach: the existing route-list action is enough if the banner says where it is. Otherwise add one secondary button near the carousel.

**Never plan automatically.** Test this with a fixed `now` in a unit test of the helper, not by changing the Simulator clock.

## 4. Light appearance check (one pass)

Capture each of these once, with stubs, and inspect them yourself:
- the Today plan map in **dark**;
- the Today plan map at **AX3**;
- the kiln detail with flags and exposure in **dark**;
- the route list sheet at **AX3**.

Fix only real breakage you see: clipped IDs, overlaps, unreadable text, or a layout that doesn't wrap. Spot-check the kiln detail's `RuleDistanceBar` with the accessibility inspector or the accessibility tree. If VoiceOver would read the same distance twice (the visible text plus the label), give it one combined label. No spoken VoiceOver pass is needed.

## 5. Tests, build, report

- `cd App/Packages/KilnWatchCore && swift test` (last: 73 passed), plus the root `xcodebuild … build`. Zero warnings.
- Add tests only for new logic: the passed-day detection and, if you add a helper, the framing rect (every stop inside it, padding bounded).
- Screenshots go to `App/docs/screens/phase-5/`: before and after for the plan map, the passed-day banner, and the 4 from §4. Label them all stubbed.
- Leak-scan the changed files and PNGs as in 20; report counts only.
- Write `App/docs/screens/phase-5/polish-report.md`: what changed and why, the cause of the zoom problem, tests and build, screenshots, live POST count (0 and 0), leak counts and open limits. Add a 3-line note to the end of `App/docs/HANDOVER.md`. Stop for orchestrator review.
