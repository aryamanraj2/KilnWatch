# KilnWatch — prompt 23: Review tab (change triage, Agent 2)

Run in a **new Claude Code builder chat**, in the existing checkout. This builder may use Xcode and the Simulator; no other builder may use them at the same time.

**Goal:** the inspector app shows what the change-triage agent queued: the differences between the Dec 2023 and Oct 2026 satellite passes, each with the agent's reason and its evidence, **pending review**. This makes the concept's Agent 2 visible in the app. It is **read-only**: no approve or reject (that needs reviewer sign-in, which is not built).

## 1. Scope and authorization

Running this prompt authorizes:
- local iOS edits under `App/` (app and KilnWatchCore), `swift test`, the root build, Simulator checks and screenshots;
- public `GET /public/review` and the public kiln GETs (including `include=inspected`), as often as testing needs.

**Zero** `POST /ask`, `POST /routes/plan` and `POST /verdicts`. No AWS CLI, no backend or contract edits, no sub-agents, no staging or commits. Testing stays **light**: core tests, the root build, the checks listed, and the screenshots in §5.

Read:
- `AGENTS.md`, `App/docs/DESIGN.md` (binding), the newest `App/docs/HANDOVER.md` sections;
- `App/docs/api-contract.md`: **"Review queue read (40b)"** (the exact response shape; it is the contract) and "Change triage (40)" (the four groups and their wording);
- `KilnWatchApp.swift` (`AppTab`, the `TabView`, `DemoOptions`, `AppModel` loading and the `-tab` argument), KilnWatchCore `KilnWatchAPI.swift` (`publicKiln`, `send`), `Offline.swift` (`RouteCache` as the pattern for a saved copy), `Models.swift`, and the Kilns list and Kiln detail views.

## 2. Data (KilnWatchCore)

- `ReviewQueue` / `ReviewItem` models that decode the 40b response exactly: `baseline {run, scene, date}`, `current {label, scene, date}`, `counts` (all four keys), `truncated`, and items with `item_id`, `group`, `state`, `kiln_id?`, `reason`, `centroid {lat, lon}`, `baseline? {type, score}`, `current? {type, score}`, `iou?`, `evidence? {before?, after?}`, `created_at`. An **unknown `group` or `state`** decodes to an `.unknown` case and is shown as "Unrecognised change" (never dropped silently, never crashes).
- `KilnWatchAPI.review()`: `GET /public/review`, no `Authorization`, the same public session and error mapping as the public kiln reads (`503 review_unavailable` is retryable).
- `ReviewCache`: saves the last good response like `RouteCache`; loaded on launch and when offline.
- Evidence URLs: accept them only from the evidence CDN host the app already accepts for kiln evidence.

## 3. The Review tab (DESIGN.md binds; state any deviation in the report)

- **Tab:** a 4th tab, **"Review"**, symbol `checklist`, after Ask: `AppTab.review`, and `-tab review` works. (DESIGN §10 lists three tabs; this adds the concept's review queue. Say so in the report and add the tab to DESIGN §10.)
- **Loading:** on first appearance and on pull-to-refresh only. No polling. Redacted placeholder while loading; offline shows the saved copy with "Offline · showing saved review list"; no saved copy and an error → an honest error with Retry.
- **Header:** title "Review". Under it: "Changes since Dec 2023 · pending review" and, in mono, the two scene dates ("5 Dec 2023 → 5 Oct 2026").
- **Sections** in the contract's order, each with its count, using exactly these labels:
  - `new_candidate`: **"Not detected in Dec 2023"**
  - `no_longer_detected`: **"No longer detected"**
  - `possible_zigzag_conversion`: **"Possible zigzag conversion"** (hide the section when 0, but keep it in the counts line)
  - `low_confidence`: **"Low detector score"**
- **Row:** the kiln ID (mono, never truncated) or "Not in registry"; the type line ("FCBK · score 0.49", with "2023: FCBK · 0.53" when there is a baseline); a small "Pending review" badge (neutral `inkSecondary` on `surface2`, symbol + word; **not** a status color, because it is not a kiln status); the agent's reason, **verbatim**, 3 lines with "More" to expand. One line per item at the top, essentials first (DESIGN §8: Flighty principle).
- **Tap:**
  - with a `kiln_id`: push the **existing kiln detail** for that ID, loaded with `include=inspected` so an inspected kiln (e.g. the demo verdict `KW-00c562…`) still opens with its outcome;
  - without one (`no_longer_detected`): a small detail view with the 2023 type and score, both scene IDs and dates (mono), the centroid (mono, 5 decimals), a small MapKit map with one pin, and **Directions** (Apple Maps handoff, the same pattern as the kiln bottom bar). No invented imagery: if `evidence` is null, say "No published image for this location".
- **Footer** (always visible at the end of the list): "The change-triage agent queues differences for review. Only a reviewer's approval changes the registry; approval needs sign-in and is not available yet."
- **Copy rules (binding):** never "new kiln", "built", "closed", "demolished", "illegal", "violation", "confirmed" in this tab's own text (the stored reason is shown verbatim, and 40's validator already checked it). A score is "detector score", never accuracy. `truncated: true` adds "Showing the first 500".
- **Accessibility:** each row is one VoiceOver element: "KW-…, not detected in December 2023, pending review. Reason: …". At AX sizes the type line stacks under the ID. Reduce Motion as elsewhere.
- **Demo/sample mode:** a recorded, sanitized copy of the live response in `Mock/` (evidence host replaced by the existing placeholder pattern), used by the existing sample mode and by `-demo loading|empty|offline` on this tab.

## 4. Tests (core, stubs)

Decode of the recorded response (45 items, counts 24/17/0/4); null fields per group; unknown `group`/`state`; `review()` sends no `Authorization` and maps 400/503/transport; `ReviewCache` round trip; the evidence host check. Last run: 90 passed. Report the new count. The root build must have **zero warnings**:
`xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build`

## 5. Live check, screenshots, report

- **Live (read-only):** launch with `-tab review` in live mode: 45 items in three sections, counts 24/17/4; open one `new_candidate` with images, the demo-verdict kiln `KW-00c562…` (opens with its outcome), and one `no_longer_detected` (map + Directions; don't complete the Maps handoff).
- **Screenshots** in `App/docs/screens/phase-7/` (6, light unless noted): the Review list (live); a row expanded; a kiln opened from Review (live); a `no_longer_detected` detail; the list in dark mode; offline with the saved copy (stub). Inspect each yourself.
- **Leak scan** of changed files and PNGs, as in 22: the API host and the CDN host must never appear in files, logs or screenshots. Report counts only.
- **Write** `App/docs/screens/phase-7/review-tab-report.md` (what changed, tests and build, the live check, screenshots, leak counts, limits: read-only by design, a demo snapshot until triage is automated, no sign-in) and a 3-line note in `App/docs/HANDOVER.md`. Stop for orchestrator review.
