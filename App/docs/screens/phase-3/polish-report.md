# Phase 3 polish report — 10 October 2026

The four presentation fixes are complete. Search → Today passed by hand; the single cancel-search UI-test path remains unverified because the native Cancel button was absent from the beta harness query. No navigation source change was needed.

1. **Detail title:** extracted the existing list formatter into `KilnIDLabel.shortID` and reused it. The actual list format is `KW-6b3b38…d3f78e` (six trailing characters), which is preserved rather than replacing it with the prompt's eight-character example. The large title retains the full accessibility label. The full ID appears directly below in secondary monospaced footnote text with native text selection. Nonlinguistic typesetting prevents system-inserted hyphens while preserving the original selectable string. Both AX5 captures show complete glyphs with no title/ID overlap. See [light](detail-top-light.png), [dark](detail-top-dark.png), [AX5 light](detail-ax5-light.png), [AX5 dark](detail-ax5-dark.png).
2. **Mini-map:** the live branch fits the footprint bounds with 40% padding and a 300 m minimum span. It uses a clay outline, light clay fill and an 8 pt centroid dot. The reference polygon is clearly visible in both [light](detail-bottom-light.png) and [dark](detail-bottom-dark.png). The fixture's 2400 m camera, 800 m buffer and home/school points remain unchanged. The accessibility meaning and label are unchanged.
3. **Today pins:** visible circles are 22 pt, with 44 pt frames/content shapes retained. Dense nearby pairs still overlap slightly, especially south/east of Hapur; there is no heavy region-wide pileup in [light](today-light.png) or [dark](today-dark.png). No clustering or zoom logic was added. Source inspection confirms footprints are already drawn at every zoom level. A supplemental UI check confirmed all 39 pin controls and completed a pan/pinch, but its resulting view did not reach footprint scale; close-zoom footprint visibility remains visually unverified. The Mac locked before that check, so native hand interaction was unavailable.
4. **Top edge:** neither hidden toolbar backgrounds nor ignored top safe areas caused the issue. The detail and list relied on the automatic edge style; it left text readable beneath the controls. Applied the native `.hard` top scroll-edge style to the detail ScrollView and Kilns List. Detail-bottom captures show the clean system boundary with no date text behind the back button/status bar. Kilns [light](kilns-light.png) and [dark](kilns-dark.png) were also recaptured. No handmade blur or design-token changes.
5. **Search → Today:** **pass by hand**, once. Entered `6b3b38`, submitted the active search to dismiss the keyboard, then tapped Today once. The live 39-candidate map and route-unavailable notice loaded. The separate **single UI-test cancel path remains unverified**: its Cancel existence assertion failed before a tab tap. No retry loops and no established app defect. The final separate map check verified 39 pin controls.

Verification: core **34 functions: 33 passed, one existing opt-in skip**, with **zero warnings**. The prescribed root iPhone 17 build passed after the final source change with **zero warnings**. All **eight existing Phase 3 XCTest methods** have passing coverage. Including repeated appearance/AX captures and the supplemental map/settings check: **15 executions, 14 passes, one native-control harness failure**. The initial temporary-harness compile typo was corrected before any tests executed. Temporary harness warnings concern manual build order and missing AppIntents metadata; they do not apply to the root build. The failed suite emitted complete XCTest outcomes and then stalled finalizing its beta result bundle; it was stopped after test completion. Successful selected runs returned `TEST SUCCEEDED`. See [verification extract](polish-verification.txt) and [temporary UI source](polish-ui-checks.swift).

Every delivered capture was opened and inspected. `detail-ax5.png` now matches the explicit dark AX5 top capture. Simulator appearance and text size are restored to **Light / Large**. The Reduce Motion override is absent and a fresh UI runner verified Reduce Motion off; keyboard capture was restored off before the Mac locked.

Kilns light/dark were recaptured and inspected but are byte-identical to the starting screenshots. The sixteen files with content changes follow, one line each (paths relative to the repository):

- `App/KilnWatch/Design/Components/KilnIDLabel.swift` — shares the existing short-ID formatter.
- `App/KilnWatch/Features/Kiln/KilnView.swift` — title/full ID, footprint framing/style/dot and native top edge.
- `App/KilnWatch/Features/Kilns/KilnsView.swift` — native hard top edge.
- `App/KilnWatch/Features/Today/PublicRegistryMap.swift` — smaller visible pins, unchanged 44 pt targets.
- `App/docs/screens/phase-3/detail-top-light.png` — recaptured title/full ID, light.
- `App/docs/screens/phase-3/detail-top-dark.png` — recaptured title/full ID, dark.
- `App/docs/screens/phase-3/detail-bottom-light.png` — recaptured footprint/top edge, light.
- `App/docs/screens/phase-3/detail-bottom-dark.png` — recaptured footprint/top edge, dark.
- `App/docs/screens/phase-3/today-light.png` — recaptured smaller pins, light.
- `App/docs/screens/phase-3/today-dark.png` — recaptured smaller pins, dark.
- `App/docs/screens/phase-3/detail-ax5.png` — refreshed existing AX5 artifact with final dark title capture.
- `App/docs/screens/phase-3/detail-ax5-light.png` — new final AX5 title/full-ID capture, light.
- `App/docs/screens/phase-3/detail-ax5-dark.png` — new explicit final AX5 title/full-ID capture, dark.
- `App/docs/screens/phase-3/polish-ui-checks.swift` — reviewable temporary harness source; no root test target added.
- `App/docs/screens/phase-3/polish-verification.txt` — compact outcomes and harness limitations.
- `App/docs/screens/phase-3/polish-report.md` — this report.

No commits, pushes, staging, AWS work, sub-agents or protected-folder edits. All **419 protected-file/Phase 2/HEAD fingerprints** match the starting values; the staged diff is empty. Read-only Git inspections refreshed index metadata (its byte checksum changed); no Git write commands were issued. The configured deployment hostname is absent from changed app/report/test files. Existing Phase 2 artifacts and the overnight report are preserved. No later-phase work.

Research used: Apple's [ScrollEdgeEffectStyle](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle) describes the more opaque hard boundary; [Text typesettingLanguage](https://developer.apple.com/documentation/swiftui/text/typesettinglanguage(_:isenabled:)-85e9h) documents explicit language control over line breaking. Axiom design, SwiftUI, accessibility, location and testing guidance plus SwiftUI Expert were applied sequentially. No deviation from the binding design system.

Stopped after this report.
