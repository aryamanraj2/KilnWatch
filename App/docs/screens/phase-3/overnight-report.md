# Phase 3 overnight report — 10 October 2026

**Partly done.** The live app is built and verified. The detail mini-map footprint remains obscured by its marker after the permitted three review/fix cycles; one navigation sequence remains unverified.

The app now opens without sign-in and loads **39 real Hapur kilns**. Kilns supports search/filter; detail loads on demand with the exact pending-inspection status, unverified predicted type, actual model score and imagery dates. The reference record's score is **0.32**, not the prompt's illustrative 0.82. Missing images, rules and exposure have honest states. Real records have no sample imagery/counts, 800 m claims or verdict actions. Today shows real footprints/pins and “Route planning isn't available yet”; tapping a pin opens detail. The fixture route demo remains available.

| Screens | Light | Dark |
|---|---|---|
| Kilns | [View](kilns-light.png) | [View](kilns-dark.png) |
| Detail top | [View](detail-top-light.png) | [View](detail-top-dark.png) |
| Detail bottom | [View](detail-bottom-light.png) | [View](detail-bottom-dark.png) |
| Today | [View](today-light.png) | [View](today-dark.png) |
| Stubbed 503 | [View](503-light.png) | [View](503-dark.png) |
| Stubbed offline | [View](offline-light.png) | [View](offline-dark.png) |

[AX3](kilns-ax3.png), [AX5](kilns-ax5.png) and [synthetic image comparator](synthetic-evidence-loaded.png). The tester inspected all 23 final captures; the orchestrator inspected the twelve required light/dark captures and AX3.

**Files changed:** [complete inventory, one line per file](changed-files.md), including app/core/configuration, public response fixtures, tests, screenshots and sanitized logs. HANDOVER has an appended Phase 3 paragraph. The actual URL exists only in ignored local configuration.

**Verification:** The documented baseline was 26 core tests; it was not independently rerun before editing. Final Swift Testing reports **34 functions: 33 passed, one existing opt-in local-contract skip**, with **55 executed parameterized cases**. Core tests and the prescribed root iPhone 17 build passed after each milestone/fix and were independently rerun: **zero warnings**. Commands:

```
cd App/Packages/KilnWatchCore && swift test
xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build
```

UI coverage: **8 distinct XCTest methods, 10 relevant passing acceptance executions**. Across the full harness history: **23 executions, 18 passes, 5 harness failures**; details and beta-tool limitations are in [tester notes](tester-notes.md). Temporary harness warnings do not apply to the zero-warning root build.

Live list/search/reference detail and separately launched Today passed. Deterministic checks passed for loading, empty, offline, persistent 429/manual Retry, one-backoff recovery and 503/Retry; detail 404/offline/503/recovery; three rapid reopen loops each during slow detail and 429; synthetic imagery loading/failure/Retry/drag; and the nine-stop fixture route. AX3/light, AX5/dark and Reduce Motion passed. Simulator settings were restored.

**Agents and review:** One builder implemented M1–M5 sequentially. Two read-only reviewers covered design/accessibility and honesty/concurrency; one tester owned Simulator verification. No simultaneous writers or Simulator owners. Cycle 1 fixed in-flight Retry; cycle 2 removed public local caching and made cancellation recoverable; cycle 3 restored visible source words, reduced overlapping Today pins and prevented apparent ID hyphenation. No speculative source finding was accepted. A fixture-badge mismatch was rejected because the test expected the wrong label. Native beta tab-bar hit-point failures were not established as app defects and were not counted as successful navigation.

**Defaults applied for tomorrow's confirmation:** Hapur; English; live when configured, otherwise explicitly Sample data; no mixed lists or kiln persistence; no fabricated live route; fixture routing retained. Failures never substitute fixtures.

**Remaining/unrun:**
- Mini-map footprint: fixed 2400 m framing and the opaque location flag hide the small reference polygon. A later authorized polish pass should fit its bounds or move/reduce the marker. The three-cycle cap prevents another overnight source fix.
- Switching to Today immediately after active search remains unverified: four harness attempts met absent/ghost native tab-bar elements. Separate live Today and cross-tab navigation without search passed.
- Remote imagery is unrun because all live evidence URLs are null and CloudFront is pending. Synthetic 256 px imagery was verified; published imagery/metadata must be checked later.
- Spoken VoiceOver, physical-device testing and an actual missing-config build are unrun. The optional include/fallback was source reviewed; fixture launch was tested.

**Preservation:** HEAD/index unchanged; existing Phase 2 logs and protected AWS/model files unchanged. No actual deployment URL/API identifier leaked in tracked or new files. Final diff: 14 existing tracked files, 655 insertions and 60 deletions, plus 74 intended new files (88 inventoried total). Whitespace checks passed; the banned app term scan found no matches. No staging, commit, push, cloud work, sign-in, training, portal or later-phase work.

**Next:** The user decides whether to commit/push and authorize the mini-map/navigation follow-up. After AWS account verification, the AWS teammate can complete Part B CloudFront and evidence publication; then recheck the live image path. The resident portal belongs to the AWS teammate. Phases 4–6 require separate work. This run is stopped; the normal no-agents rule resumes.
