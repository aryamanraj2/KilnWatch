# Prompt 23 — Review tab report

2026-10-11. Completed locally on `main`; stopped for orchestrator review.

## What changed

- Added the fourth tab, **Review**, with `checklist`, after Ask. `-tab review` works. DESIGN §10 now records this authorized change from the previous three-tab design; no other design deviations.
- Added exact 40b queue/item decoding, including nullable scene envelopes, every count, nullable predictions/evidence/IoU, five-decimal coordinates, timestamps, and round-tripping unknown group/state values. Unknown values remain visible as **Unrecognised change**.
- Added public `review()` GET with the existing public session/error handling and no Authorization. Loading is limited to first appearance, pull-to-refresh, and explicit Retry; no polling or automatic review retry.
- Added atomic saved review storage with background disk work. Offline uses the last good list; a missing/corrupt saved copy gets honest recovery. Server errors retain the previous list and offer Retry. Successful empty responses replace earlier data.
- Evidence is accepted only on HTTPS, without credentials or a nonstandard port, and on the exact host returned by the existing public kiln evidence read. A bounded public kiln GET establishes this host; review-provided hosts cannot establish trust. If this read fails, the list stays usable without images. Host checks have core tests.
- To honor the no-host-writing constraint, saved queue evidence uses the existing `evidence.example` placeholder while retaining paths and facts. Cached/sample evidence is withheld from image fetching. Registry items obtain their published evidence through the existing kiln detail read.
- Rows retain full monospaced IDs, current/baseline detector scores, neutral pending badges, verbatim reasons limited to three lines, More/Less, and whole-row navigation. Each row exposes one VoiceOver element, full reason and open/expand actions. Accessibility sizes stack score/badge content; expansion uses the existing Reduce Motion-aware token.
- Registry rows push the existing detail with `include=inspected`. Historical rows show the baseline detector score, both scene IDs/dates, centroid, one-pin muted map, missing-image message and Directions. Their optional reason uses native disclosure to keep the map and message visible. Directions uses the shared confirmation/handoff pattern.
- Included a recorded, sanitized live response in Mock and the core test resources. Sample mode and Review's loading/empty/offline demo arguments use this copy, with isolated cache storage. A DEBUG-only `-readOnly YES` rehearsal argument prevents existing outbox delivery during checks.

## Validation

- Core: **99 tests reported; 98 passed, one existing opt-in skip**, up from 90. Zero warnings. Nine new test functions cover recorded 45-item decoding/counts and group nulls, empty/partial evidence, unknown values, public GET/no auth, 400/503/transport mapping, cache round trip and host redaction, exact evidence-host rejection, one-time loading/saved-copy preservation, and no-cache offline recovery.
- Prescribed root iPhone 17 build: **succeeded, zero warnings**. Existing deployment target stays 26.1; Simulator runtime was iOS 27.
- Sequential temporary Simulator harness: live interaction check passed; saved offline stub passed; dark capture passed; compact historical detail recapture passed. The first live check exposed a heading-only tap target; fixed to whole-row navigation and reran successfully. The initial test runner stalled during teardown and was terminated after its failure had already been recorded; subsequent runs completed normally.
- Live public queue: **45 items**, counts **24 / 17 / 0 / 4**, with three populated sections and the zero conversion count retained in the summary. Dates: **5 Dec 2023 → 5 Oct 2026**.
- Opened a queued registry candidate with successfully loaded published before/after images. Opened `KW-00c562060b40502fb4a7ed2016ce7576` from Review and verified its existing outcome and recorded-on-site line. Separate public inspected-inclusive GET also returned its inspection.
- Opened a historical detection, checked map and missing-image copy, tapped Directions and canceled at the detection-location confirmation. **No Maps handoff was completed.**
- All Simulator launches used the DEBUG read-only guard. Live POST counts: **Ask 0, route planning 0, verdicts 0**. No AWS CLI, backend/contract changes, sub-agents, staging, commits or pushes by this lane. Pre-existing AWS/contract/prompt changes remain outside this lane.

## Screenshots

Six PNGs, individually inspected. Light unless noted:

1. [Review list, live](review-list-live.png)
2. [Expanded verbatim reason](review-row-expanded.png)
3. [Existing kiln detail from Review, live images](review-kiln-live.png)
4. [Historical detection: scenes, location, map and Directions](review-historical-location.png)
5. [Review list, dark](review-list-dark.png)
6. [Saved offline sample](review-offline-saved-stub.png)

Inspection confirmed readable full row IDs, neutral review badges, finished reason expansion, public imagery, legible dark content, and visible map attribution/missing-image copy in the compact historical view.

## Leak scan

Scanned this lane's changed text, sanitized verification logs, PNG bytes/metadata, and recognized text from all six PNGs. Confirmed leak counts only:

| Category | Count |
|---|---:|
| API address/host | 0 |
| Evidence CDN host | 0 |
| Account IDs | 0 |
| ARNs | 0 |
| Bucket hosts/names | 0 |
| Emails | 0 |

No matches were printed. The configured bucket prefix matched 72 ordinary project references; it equals the project name and is not a complete bucket identity, so those are excluded from confirmed leaks. A synthetic credential-bearing URL in a test initially matched the generic email pattern; the test now constructs credentials structurally and the final scan is zero.

## Limits and references

The queue is read-only by design. Approval/rejection and reviewer sign-in are unavailable. Live data is a manually queued demo snapshot until triage is automated; refreshing reads the queue and never starts triage. No sign-in was added. Saved Review rows do not provide an offline kiln-detail cache; existing detail recovery remains in use. No physical-device, spoken VoiceOver, AX-size or Reduce Motion Simulator pass was added in this light check; the implementation follows existing accessibility and motion patterns. Loading/empty demonstrations are implemented; the six requested captures focus on live, dark and saved offline states.

Used the local Axiom design, SwiftUI, data/Codable, networking, concurrency, testing and accessibility guidance, plus swiftui-expert-skill. Apple's [named accessibility action documentation](https://developer.apple.com/documentation/swiftui/view/accessibilityaction(named:_:)) supports the row's extra expand action. The 40b response and group wording remain governed by the existing API contract.

Stopped for orchestrator review. No later phase work.
