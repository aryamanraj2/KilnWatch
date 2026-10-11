# Prompt 22 — verdict loop

Completed locally on 11 October 2026, on `main`. Stopped for orchestrator review.

## Changes

- Public, unauthenticated verdict submission with the existing idempotency key. No Authorization header on either the POST or photo PUTs. Uploads require HTTPS and an `amazonaws.com` host, without credentials or an alternate port.
- System camera capture on devices; system PhotosPicker fallback on Simulator or hardware without a camera. Up to eight photos, pixel-only JPEG re-encoding at quality 0.7 and a maximum 2,048 px long edge. Photos use the foreground location fix at capture/import, including its real horizontal accuracy; absent or stale fixes prevent attachment. No coordinates are fabricated.
- Optional note limited to 2,000 Unicode scalars. Existing outcome rows, hold gesture and accessible submission action remain. The hold completes only after the verdict and its photo files are durably saved; online/offline feedback follows that save, then flushing starts.
- Outbox flushes after enqueue, on foreground and on restored connectivity. No timers or polling. Rejections (400/404/409) remain saved with plain, allowlisted reasons and confirmed Discard. A daily-cap 429 defers sending until the next UTC day, 05:30 IST; transient failures retain all files. Incomplete, duplicate, mismatched or unsafe photo receipts cannot remove a verdict. Raw network errors, receipts and upload URLs never enter the persisted queue.
- Rows/details distinguish a pending outcome from a recorded registry outcome. Today/Kilns show the waiting count. Successful delivery retains a durable “Recorded · syncing” acknowledgement until a public read agrees, with exactly one detail refresh per completed delivery.
- App list/detail reads opt into `include=inspected`. Optional inspection metadata preserves old caches/fixtures. Recorded dates use Asia/Kolkata. Status filters, public map symbols/colours and saved-plan cards show the outcome; the plan itself is kept. Public verdicts use the outbox; labelled fixture behaviour remains separate. No sign-in was added, by user decision.

## Tests and build

- Final `swift test`: **90 registered tests: 89 passed, one existing opt-in local-detection test skipped**, up from the previous 77-test run. The runner reports the 90-test run as passed. Zero compiler warnings. Added checks cover unauthenticated submission and idempotency, receipt decoding/completeness, upload allowlisting, 201/200 replay, rejection/discard, cap/reset time, 503/transport, legacy inspection decoding, both inspected list shapes/detail, acknowledgements and legacy-error sanitization.
- Prescribed root iPhone 17 build: **BUILD SUCCEEDED, zero warnings**. `git diff --check -- App` passed.
- Scoped Simulator workflows verified queued/rejected presentation and confirmed discard, the one live photo/verdict submission, and the resulting detail/list/map. The temporary UI harness is outside the repository. Harness selectors and asynchronous waits needed correction before submission; several completed runs needed their stuck Xcode result-collection process stopped. iOS 27 beta UI/tool diagnostics occurred separately from the warning-free app/core checks. No second new verdict was attempted.

## The one live verdict

Kiln: **`KW-00c562060b40502fb4a7ed2016ce7576`**, Hapur. It is outside all eight saved-plan stops and is not the reference kiln. Simulator location was set to its centroid, **28.683193, 77.757537**. The attached photo carried the actual Simulator fix, **±5 m**.

Outcome: **confirmed**. Exact note: **“Simulator end-to-end test, not a field inspection”**. One illustrative kiln image was imported into the Simulator photo library and selected through PhotosPicker. Its verdict attachment was uploaded only to the **private bucket** and is **never published by the public API**; it is not field evidence.

| Check | Result |
| --- | --- |
| New live verdict POSTs | **1**; response **201** |
| Live replays | **0** |
| Photo PUTs | **1**; response **200** |
| Outbox after upload | **0 entries** |
| Registry outcome | **confirmed**, inspection outcome **confirmed** |
| `inspection.recorded_at` | `2026-10-10T22:05:31.634000Z` — **11 Oct, 03:35:31.634 IST** |
| POST receipt | **03:35:36.694 IST** |
| POST receipt → successful PUT | **0.511 s** |
| One post-cache inspected-detail verification | **200**, about **72 s** after the receipt, including the read checks; no read polling |
| Default Hapur list | **200**, **39 → 38 flagged kilns** |

**The public flagged count, Ask and route planning now see 38, until an operator reset.** The app's inspected-inclusive list still has 39 records, with one confirmed outcome and 38 flagged records. Ask and planning were not invoked to verify this; their flagged-only input policy is the documented contract.

## Screenshots

One retained PNG per requested item, all visually inspected:

| Capture | Source |
| --- | --- |
| [Sheet, photo, geotag and exact note](verdict-sheet-live.png) | Live form, immediately before its single submission |
| [Queued/offline detail](verdict-offline-stub.png) | Isolated transport-failure stub, labelled Sample data |
| [Rejected detail and Discard](verdict-rejected-stub.png) | Isolated 409 stub, labelled Sample data |
| [Recorded kiln detail](verdict-detail-live.png) | Live inspected read; outcome and “Recorded on site · 11 Oct” |
| [Mixed-status Kilns list](verdict-mixed-list-live.png) | Live inspected-inclusive list |
| [Today map with inspected kiln](verdict-today-live.png) | Live inspected-inclusive map |

## Leak scan

This lane's changed text, PNG bytes/metadata, PNG OCR and the phase's temporary verification logs were scanned without printing matches. Counts only:

| Category | Confirmed leaks |
| --- | --- |
| Presigned URLs/signatures | **0** |
| Bucket hosts | **0** |
| API URL/hosts | **0** |
| Account IDs | **0** |
| Emails | **0** |

Scanned **21 text files, six PNGs and ten temporary logs**. Text and PNG OCR had **0** pattern hits. PNG bytes had **1** numeric-pattern hit inside compressed image data; logs had **3** pattern hits (one accessibility trait integer and two asset filenames). All four were reviewed as false positives; confirmed leaks remain **0**.

Six PNGs were reviewed. The DEBUG delivery proof contains only request method, HTTP status and time; no receipt, URL, host, note or photo coordinates.

## Limits and scope

Simulator uses the photo-library fallback; physical camera capture, physical-device permission cases, spoken VoiceOver and additional appearance/large-text passes were not tested in this light lane. The pending/rejected captures are stubs, not extra live writes. No sign-in/auth by user decision. Public cap: **30 new verdicts per UTC day**; reset requires the runner and a fresh operator go, and was not run.

Live `POST /routes/plan`: **0**. Live `POST /ask`: **0**. No AWS CLI, backend/API-contract edits, sub-agents, staging, commits or pushes by this lane. Existing staged/backend work was left untouched. Only App source/docs and temporary verification artifacts were changed.

Apple references: [PhotosPickerItem](https://developer.apple.com/documentation/photosui/photospickeritem), [ImageIO thumbnail creation](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)), and [orientation transform](https://developer.apple.com/documentation/imageio/kcgimagesourcecreatethumbnailwithtransform).
