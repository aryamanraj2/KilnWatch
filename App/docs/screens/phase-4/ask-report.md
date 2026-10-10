# Phase 4B — iOS live Ask builder report

2026-10-10. Local implementation and Hapur live smoke check complete; paused for orchestrator review. No work on prompts 19 or 20.

## Behavior

Configured public mode now submits one stateless JSON question to the existing Ask endpoint through the ephemeral public client. It adds no configuration key, authentication header, token-provider invocation, persistence, dependency, or automatic POST retry. The request timeout is 35 seconds, with a 40-second public-session resource bound. Optional fields are omitted; full kiln IDs, paired finite coordinates, trimmed nonempty questions, 500 Unicode scalar values, and the 2,048-byte encoded body are validated before submission.

In-memory exchange ownership prevents duplicate sends and appearance-triggered resubmission. Cancellation discards stale results and explains that an attempted question may still count. Failures retain the draft; a completed response does not erase newer typing. Waiting shows a generic indicator and Cancel. Only a completed response supplies trace steps: exact server labels/summaries, positional identity for repeated calls, and a distinct failed-step indication. Empty steps are supported.

Answers preserve paragraphs and server facts. Each answer and fallback shows its disclaimer. Returned citations alone create inline links and separate clay chips, deduplicated in first-appearance order. Full IDs wrap at accessibility sizes and navigate through the existing detail fetch. Live detail now offers “Ask about this kiln,” prefilling the full ID and request context without sending. Removing the ID from an edited draft clears stale context. Existing live inspection restrictions remain in place.

A dedicated network-path observer disables Ask when the path is unsatisfied and restores controls when it changes. Transport failures remain separate from connectivity and never substitute sample data. A satisfied path does not promise server availability. The labelled scripted Sample data mode remains available when fixtures are selected or public configuration is absent. All DEBUG scenarios use an intercepted local client, including citation detail requests, and carry explicit sample/test labels.

Intentional presentation change: live answers appear immediately after validation, with no optional word reveal. Native attributed text and vertically wrapping chips replace the fixed-width word flow. Scripted playback remains animated, with immediate completion under Reduce Motion. This keeps the live complete-response contract honest and avoids long-ID overflow.

## Verification

| Check | Result |
| --- | --- |
| Core `swift test` | Final 53-test run passed; one existing opt-in real-detection contract check skipped; zero compiler warnings. |
| Prescribed root Xcode build | Passed; zero app/core compiler warnings. Root project restored to its initial contents after Xcode normalized an existing configuration reference; no final project diff. |
| Local UI harness | Submission limits, empty steps, repeated/failed steps, full-ID navigation, prefill, local errors, cancellation, recovery, sample separation, Today/Kilns and fixture-route checks passed in targeted runs. Independent fresh-draft 500/501 paste check passed. |
| Light/dark | Reviewed screenshots; dark normal answer and nonretryable controls passed. |
| AX3/AX5 | Final citation open/back checks passed at both sizes; complete synthetic full IDs wrap without horizontal overflow. Send icon was adjusted to grow with its glyph. |
| Reduce Motion | System setting asserted enabled; scripted answer completed immediately; live/fallback answers do not animate text. Restored Light, Large text and Reduce Motion off afterward. |

Actual tools: Xcode 27.0, build 27A5218g; iPhone 17 Simulator running iOS 27.0. Deployment minimum remains **iOS 26.1**, including the installed root app. No iOS 26 runtime or physical-device test was performed. Spoken VoiceOver was not tested; full citation labels/actions and answer accessibility are implemented, and navigation was exercised through the accessibility-based UI harness.

The temporary harness lives outside the repository; its reviewable source is [ui-checks.swift](ui-checks.swift). It does not add a root-project test reference. Its project emits a manual-build-order deprecation warning, separate from the warning-free root app/core build. An initial waiting test missed a two-second stub response; extending only the waiting stub to 20 seconds resolved it. Extra AX screenshot swipes targeted the composer region; native citation tap followed by Back produced the final passing captures. Same-draft paste replacement assumptions also required harness correction; application typing validation had already passed.

Verified mappings: invalid input/400 retains editing; daily-cap 429 displays the exact limit message, UTC reset, and blocks submissions until reset; gateway 429 offers a deliberate retry after three seconds; nonretryable 503 has no immediate retry; retryable 503, malformed responses, timeout/transport and cancellation have honest manual recovery. Core tests verify one request per action, no auth/provider call, no hidden retries, draft preservation, stale cancellation, and that an earlier failed exchange cannot bypass a later cap response.

Offline recovery was exercised with a DEBUG path-state transition and local responses, without changing host network settings. Typed 500/501 boundaries, Unicode scalar counting, and encoded-byte rejection are covered. No location permission is requested by Ask.

## Live status and scope

After the user explicitly raised the allowance and reauthorized verification, one controlled **live POST /ask succeeded from the installed root app**. The question was “How many kilns are flagged in Hapur?” The completed response reported **39 flagged kilns**, returned one full-ID citation, displayed the server-written “Searching flagged kilns” / “39 found” trace, and included its disclaimer. Waiting was observed before completion; the draft cleared on success. No fallback notice appeared.

The returned full-ID citation opened its live kiln detail, which displayed the complete ID, pending-inspection label, model score and published before/after imagery. This was a detail read and did not send another Ask question. These observations are a smoke check of the returned data, not independent verification of the registry count or model facts.

**Conservative attempt count: 2 of the authorized maximum 8.** This includes the earlier reserved attempt that hit a simulator control error/offline composer without a confirmed POST, plus this one confirmed live submission. No automatic or manual POST retry was made. No daily counter was read. All automated POSTs and error-state captures remain local stubs. The selected-kiln contextual POST remains available for the user's own test; its request construction and prefill were tested locally. No publication state or rule/exposure fact was hard-coded into live answers.

No AWS files, configuration, logs, counters, CLI, infrastructure or console pages were accessed or changed. Scope exception: during simulator reconnection, a broad computer-use inventory unexpectedly returned unrelated existing browser-tab metadata, including AWS tabs. Those pages were not opened or interacted with, and none of that output was copied into public files. No backend or API-contract documentation edits were made by this builder. Independent lane changes to those files were preserved.

No agents, installations, staging, commit, push, deployment or other cloud writes. Initial changed-file inventory and final review notes are private and ignored. Unrelated changes, shared prompts/plans, and old Phase 2 logs were preserved.

## Builder-owned inventory

- Core: new `Sources/KilnWatchCore/Ask.swift` and `Tests/KilnWatchCoreTests/AskTests.swift`; dedicated `AskFixtures/` resources and README; small edits to `KilnWatchAPI.swift` and `Package.swift`.
- App: `Features/Ask/AskView.swift`, new `AskConnectivity.swift`, `KilnWatchApp.swift`, `Features/Kiln/KilnView.swift`, `Design/Components/CitationChip.swift`, `ToolCallTrace.swift`, `Mock/PublicDemo.swift`, and new `Mock/AskDemo.swift`.
- Evidence/docs: this report, local-only harness source, the 18 reviewed screenshots below, and an appended Phase 4B note in `App/docs/HANDOVER.md`.

Fixture provenance: five historical recorded bodies were sanitized; `fallback.synthetic.json` remains explicitly synthetic. Real IDs were consistently remapped to a full-format synthetic ID in answer text, citations and trace text. Host-like values and private infrastructure identifiers were removed. Shapes, required fields and error distinctions were retained. Historical missing-data text is test content, not a claim about the current backend. App UI scenarios are separately synthetic.

The 16 `stub-` and `scripted-` screenshots are **simulated/local**. The two `live-hapur-` screenshots capture the successful live smoke check:

| Paths under this folder | Evidence |
| --- | --- |
| `live-hapur-answer.png`, `live-hapur-citation.png` | Live Hapur answer, expanded server trace/disclaimer and full-ID citation navigation to live detail. |
| `stub-normal.png`, `stub-dark.png` | Normal paragraphs, full citation and disclaimer; light/dark. |
| `stub-waiting.png` | Honest waiting and cancellation action. |
| `stub-fallback.png` | Immediate fallback, citation absent from prose, disclaimer. |
| `stub-dailylimit.png`, `stub-throttle.png`, `stub-unavailable.png` | Cap, gateway and nonretryable unavailable states. |
| `stub-offline.png`, `stub-recovered.png` | Disabled offline controls and deliberate successful recovery. |
| `stub-prefill.png`, `stub-composer-501.png`, `stub-keyboard-501.png` | Full-ID prefill; paste limit; typed draft with software keyboard/validation. |
| `stub-ax3.png`, `stub-ax5.png` | Complete wrapping citation at both accessibility sizes. |
| `scripted-sample.png`, `scripted-reduce-motion.png` | Clearly labelled scripted mode and motion-disabled completion. |

Existing `evidence-live-light.png` and `evidence-live-dark.png` belong to the earlier phase and were not modified.

## Final scan and review

Final leak scan: **40 builder-owned public files, including 18 screenshots; zero prohibited matches.** The final fresh-draft 500/501 paste check passed, and its reviewed focused-composer screenshot is retained alongside the earlier typed software-keyboard capture. The scan covers every builder-owned public file, including fixture resources, this report, the handover, UI harness source, PNG bytes/metadata and local Vision OCR of delivered screenshots. Exact private hosts/first host identifiers were derived internally only from ignored app configuration and existing local recorded fixtures. Generic patterns include infrastructure hosts, account-number shapes, ARNs, emails and access-key shapes. Known synthetic citation digit fragments are excluded from account-ID false positives. Raw build/test/diagnostic files remain ignored under `.local/phase-4b/` and were not copied to public documentation.

Orchestrator review should assess the diff, accessibility footer space at AX5, and the remaining user-run selected-kiln contextual smoke check. The DEBUG test label occupies additional space at large text sizes; the real mode omits that label. Native titles may compact, while citation IDs remain complete and scrollable.
