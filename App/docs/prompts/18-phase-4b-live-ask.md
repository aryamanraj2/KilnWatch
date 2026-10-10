# KilnWatch — prompt 18: Phase 4B, live iOS Ask

Run in a **new Codex builder chat**, in the existing repository checkout. The user has authorized this iOS phase. Xcode and the Simulator are available for this builder now; only one builder may use them at a time.

## 1. Scope and boundaries

Replace the scripted Ask behavior in live mode with the existing public `POST /ask` endpoint. Keep the labelled scripted Sample data experience in fixture or missing-configuration mode. Preserve the current design, public registry, evidence, Today and inspection behavior.

**There is no backend Step 0.** The AWS lane already completed answer-style and image-fact fixes in prompts 16d–16f. Do not inspect or edit `AWS/`, run AWS CLI or Terraform, read a cloud counter, query cloud logs, or access AWS consoles. Do not change backend prompts, infrastructure, assessment data or model settings. The API contract is owned by the AWS lane: read it, but do not edit it.

This prompt authorizes local iOS implementation, tests, builds, screenshots, public registry/image GETs, and **at most eight live `POST /ask` attempts in total** across scripts, app interaction and any manual retries. The global daily cap is 50 questions per UTC day, shared with all callers. Do not test the cap or throttling by flooding requests. Do not retry automatically. Keep a local count of every attempted live POST; fewer than eight is preferred. A cancelled or failed POST may still consume a question. No AWS counter read is needed or permitted.

No sub-agents. No staging, commit, push, deployment, other cloud writes, dependency installation, or next phase. iOS prompts are 18–29; AWS prompts are 30+ and belong to the other orchestrator. Prompt 19 waits for the user's R1-live confirmation; prompt 20 waits for P1. Neither belongs in this phase.

The user explicitly approved independent human/builder lanes in the final-stretch plan. AWS work may run alongside this phase, but never edit its files. Only this builder uses Xcode/Simulator. Preserve other work in the shared checkout; do not reset, pull, rebase, switch branches or overwrite it.

## 2. Read and establish the baseline

Read in order:

1. `AGENTS.md`
2. `App/docs/HANDOVER.md`, `App/docs/build-plan.md`, `App/docs/DESIGN.md`
3. `App/docs/plan-final-stretch.md`
4. `App/docs/prompts/17-orchestrator-handover.md` §5, then handover 14 §3.2 and handover 11 §§1, 1a and 7
5. `App/docs/api-contract.md`, particularly public configuration and Phase 4A Ask
6. Current app/core implementation and tests, especially `AskView.swift`, `KilnWatchApp.swift`, `KilnView.swift`, `ToolCallTrace.swift`, `CitationChip.swift` and `KilnWatchAPI.swift`

The user's scope in this prompt supersedes stale handover instructions about a backend apply, ten calls or reading the daily counter. Some contract prose still says not deployed; the endpoint is live. Do not repair AWS-owned documentation here.

Check git status and a recent log with hashes/subjects only, without author metadata. Record the initial changed-file inventory privately under ignored `.local/phase-4b/`. The app and core package now target **iOS 26.1**; retain that minimum, the current SDK/toolchain, and Swift language settings. Historical iOS 27-only instructions no longer require raising the minimum.

## 3. Backend contract to consume

Use the existing configured `KILNWATCH_PUBLIC_API_URL` base plus `/ask`; add no configuration key. No authentication header and no token-provider call.

Request: JSON `{question, kiln_id?, lat?, lon?}`. One request contains one question, without conversation history. Optional coordinates must be finite, in range and supplied together. Omit absent fields. Questions are non-empty after trimming and at most 500 characters; the body limit is 2 KB. Use the full registry ID for kiln context.

Success:

```json
{
  "answer": "plain validated text",
  "citations": [],
  "steps": [{"tool": "kiln_detail", "label": "Reading kiln details", "summary": "Record found", "ok": true}],
  "fallback": false,
  "disclaimer": "server-provided disclaimer"
}
```

Answers are plain text, with no markdown. Citation entries are full kiln IDs. Steps and their labels/summaries are server-written. `fallback` and `disclaimer` are always present. Steps and citations can be empty; a tool can appear more than once. The endpoint returns one complete JSON body, with no streaming.

Nested errors: `{"error":{"code":"...","message":"...","retryable":false}}`.

| HTTP/code | Presentation and behavior |
|---|---|
| 400 / `invalid_request` | Explain that the question is too long or invalid; retain it for editing. No automatic retry. |
| 429 / `daily_cap_reached` | “Ask has reached today's limit”. If explaining reset, say UTC, not local midnight. No immediate retry action. |
| 429 / no `error.code`, gateway body `{"message":"Too Many Requests"}` | “Too many questions, wait a moment”. A deliberate manual retry is allowed after a short wait. |
| 503 / `model_unavailable`, `retryable:false` | “Ask isn't available right now”. No immediate retry action. |
| 503 / `assistant_unavailable`, `upstream_unavailable`, or retryable `model_unavailable` | Honest temporary-unavailable state with manual Retry. Honor `retryable`. |
| Network offline | Disable the composer/suggestions; explain that Ask needs a connection. Recover when connectivity returns. |
| Timeout, malformed success body, unexpected HTTP error | Honest failure with an appropriate manual recovery path. Never substitute a sample answer. Cancellation is not proof of offline connectivity. |

`fallback:true` is a successful response: show the fixed server answer, all returned citation chips and the disclaimer immediately, without text-reveal animation. Citations can be present even if the fixed answer does not contain those IDs.

Image facts are per kiln. At the start of this phase only the reference kiln beginning `KW-6b3b38` has published images. The backend's `kiln_detail` answer reflects published/unpublished state. Never hard-code all images as unpublished, hard-code publication to that ID, or make new image/rule/exposure claims. R1 may update server facts during this phase; display the returned answer without rewriting it using older missing-data assumptions.

## 4. Core implementation and recorded tests

Add `ask(question:kilnId:lat:lon:) async throws -> AskAnswer` to the existing public client. Add small Codable/Sendable request, answer, step and nested-error types as appropriate. Retain typed error behavior for existing endpoints; avoid unnecessary client abstractions or dependencies.

Use JSON POST with Content-Type/Accept headers, no Authorization, the existing ephemeral public session, no response persistence, and a bounded timeout suitable for the backend's approximately 28-second request budget. Do not reuse the registry's automatic retry loop for this cost-bearing POST. Invalid optional inputs must fail safely, not crash or encode nonfinite numbers.

Recorded bodies are already available in ignored `.local/phase-4/live/fixtures/`:

- `normal_answer.json`
- `fallback.synthetic.json`
- `daily_cap_reached.json`
- `invalid_request.json`
- `model_unavailable.json`
- `gateway_throttled.json`

Copy sanitized versions into a dedicated Swift test resource folder, updating Package.swift resources only as needed. Read files programmatically without printing private contents. Remove host-like values and private infrastructure identifiers. Remap real kiln IDs consistently to full-format synthetic kiln IDs in both answer text and citations; keep lengths, relationships and response shapes realistic. “Identifier-free” does not mean deleting citation coverage. Preserve the synthetic fallback filename and document which fixtures are recorded, sanitized or synthetic. Never put a real API/CDN host in tracked fixtures.

Use local URLSession stubs for all automated tests. Cover:

- Correct POST path, JSON body, optional omission/coordinate pair, headers, no token-provider call and no Authorization.
- Recorded normal/fallback decoding, required fields and honest malformed-response failure.
- Nested error codes/retryability and the gateway 429 distinction.
- Empty steps/citations, repeated tool calls, failed steps and full citation IDs.
- Boundary validation, including trimmed empty input, 500/501 characters, Unicode and the 2 KB request-body bound. Match the server's Unicode-code-point limit rather than Swift grapheme-cluster count alone.
- No automatic POST retry, accidental resubmission or fixture substitution after a live failure.

Test genuine behavior changes and regressions; do not add tests that only mirror private implementation structure. Retain existing registry, evidence, route and outbox tests.

## 5. Wire the app and preserve the design

Own changes under `App/` only, excluding `App/docs/api-contract.md` and shared planning/handover-prompt files owned by the other orchestrator. Small necessary edits to shared app components are allowed, with fixture behavior preserved. No redesign, new dependencies, scaffolding for later phases or modifications to AWS/Model/root project beyond a necessary app-test reference.

### Mode and request lifecycle

- Live public mode uses the endpoint. Fixture/missing-URL mode keeps `AskScript` and an obvious **Sample data** label. Simulated DEBUG scenarios must be labelled sample/test data and never issue live requests.
- A live error must stay a live error. No mixed live/sample turns or synthetic records on a live citation route.
- Keep exchanges in memory only. The backend is stateless: do not imply it remembers earlier questions.
- Permit one in-flight question. Disable duplicate send actions, retain the question on failure, and make manual retry perform exactly one additional request.
- SwiftUI appearance changes, scrolling, tab switching, layout updates and task restarts must not resubmit a completed or failed POST. Handle cancellation and stale responses cleanly; do not clear the composer text the user has typed since submitting another question.
- Enforce the trimmed 500-character limit for typing, paste, suggestion selection and prefilled drafts. Show unobtrusive count/validation feedback; never silently send only a truncated part of the user's question. Also handle the byte limit honestly.
- Do not request location permission just to open Ask. Context coordinates are optional and must be genuine supplied data.

### Waiting, trace and answers

- While waiting, show a generic honest waiting indicator such as “Waiting for an answer…”. Do not show invented tool calls, numeric results or sequential live progress: the server sends steps only with the final response.
- Once received, show the exact server-written labels/summaries and distinguish `ok:false` from successful steps. Use positional/request-local identity so repeated tools render. Handle zero steps without an out-of-range subscript or misleading progress. The existing `ToolCallTrace` assumes numeric sample steps and nonempty arrays; adapt it minimally or add a small live rendering path, preserving its design and fixture demo.
- Render plain answer text with paragraphs/newlines preserved. Defensive removal of stray `**` formatting markers may happen at presentation only; do not invent or rewrite facts.
- A word reveal may animate only the already received, validated text. It must not imply network streaming. Disable it for fallback and Reduce Motion, including the scripted demo's reveal. Preserve accessible full-answer reading without announcements on every word.
- Every answer, including a fallback, displays the response's disclaimer. Preserve the composer guardrail “Answers cite registry records. Agents never record verdicts.”

### Citations and kiln context

- Chips carry full IDs from `citations`, route to the real detail fetch in live mode and provide a VoiceOver action. Do not create a chip from an unreturned ID merely found in answer text.
- Preserve first-appearance order, avoid duplicate chips, and show fallback citations even when not embedded in the prose. Support IDs embedded inline where feasible without losing spaces, punctuation or paragraphs.
- Full IDs must wrap and remain readable at AX3/AX5; do not truncate them, navigate with shortened IDs, or allow the current fixed-width word-flow behavior to overflow the screen. Unknown/unavailable detail uses the existing honest detail state.
- Move/add “Ask about this kiln” so it works on **live** detail as well as sample detail. Prefill a question such as “Explain this kiln's registry record: <full ID>”, retain the full kiln ID as request context, and select Ask without automatically sending. Clear stale kiln context when a draft becomes unrelated. Do not enable verdict or routing actions on live detail as part of this change.
- Live empty-state prompts must match available data, for example “How many kilns are flagged in Hapur?” and “What does the registry know about this kiln?” with genuine selected-kiln context when required. Do not promise planning, sheets, health conclusions or evaluated rules before those tools/data are available.

### Offline and appearance

- Current `AppModel.isOffline` is based on a saved route, so it cannot by itself detect offline live Ask. Use the smallest genuine connectivity observation needed for Ask; keep the existing route semantics intact. A satisfied network path does not prove API availability. Recover disabled controls when connectivity returns, and handle real transport failures separately.
- `DESIGN.md` remains binding: neutral surfaces, clay citations, glass only on navigation/composer, native navigation, Dynamic Type, existing motion tokens and Reduce Motion behavior. Maintain iOS 26.1 availability throughout. Do not raise the target.

## 6. Verify and capture evidence

Run all work sequentially. Commands needing network or extra local permissions include public HTTPS calls, any package resolution, Xcode builds and Simulator operations in environments that restrict them. Use only the permissions actually needed; no permission setting grants cloud-write authorization. The user signs in only in their own terminal or account UI. No installs are needed for this phase.

From the core package:

```sh
swift test
```

From the repository root:

```sh
xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Require zero app/core compiler warnings. Preserve the root project structure. Use existing stable UI tests or a few targeted checks for submission, manual errors/recovery, citation navigation, prefilled context and mode separation. Native beta tab-bar automation can be flaky: accept one manual Simulator check and report the harness failure instead of looping.

Exercise error/fallback/long-answer states using local stubs, not live cap manipulation. Verify light and dark, AX3 and AX5, Reduce Motion, empty answer steps, repeated steps, a long full ID, composer/keyboard visibility and cancellation/re-entry. Test offline recovery and 500/501-character paste. Smoke-check Today, Kilns, published evidence and fixture route behavior for regressions.

Use **no more than eight total live POST attempts**, manually controlled and spaced out. A normal Hapur count answer and a kiln-context answer with real citation navigation are sufficient live smoke checks; use local fixtures for everything else. Keep a private attempt count. If the shared cap is exhausted or service unavailable, stop live requests and report the exact honest state; finish local verification. Never change the limit or backend to unblock tests.

Store raw logs, request details and unsanitized responses only under ignored `.local/phase-4b/`; do not print URLs, headers containing private values, raw transport errors or logs. Save reviewed screenshots to `App/docs/screens/phase-4/` using descriptive filenames. Capture normal, waiting, fallback, daily-limit, gateway-throttle, unavailable, offline, sample and AX states with a sensible small set. Label which use real responses and which use stubs. Inspect screenshots yourself before delivery. Only claim an iOS 26 runtime or physical-device check if actually performed; the current SDK/Simulator may be iOS 27 while the minimum stays 26.1.

## 7. Leak scan and builder report

The repository is public. Never write or print account IDs, ARNs, API URL/host/ID, CloudFront domain/ID, database host, emails, tokens, credentials or private plans. For this lane, scan for those patterns and private exact host values derived internally from the ignored app configuration and already present local fixture/output files. Do not read AWS config or query AWS to obtain scan inputs. Report scan counts only, without matching values or snippets. Scan every file this builder creates/changes, including resources, reports and screenshots; retain ignored files as ignored. Public scene-source URLs are allowed only if actually needed and contain none of the prohibited private identifiers.

Review the diff against the starting inventory, not just the latest commit. Preserve unrelated work and old Phase 2 logs. Add a brief Phase 4B completion/limitations note to `App/docs/HANDOVER.md`; do not update the shared plan or API contract. Do not stage.

Write `App/docs/screens/phase-4/ask-report.md` containing:

- Final behavior and builder-owned file inventory, with any intentional design deviation.
- Core test and root build results, compiler warnings, skipped checks and actual runtime/device versions separately.
- Verified error mappings, full-ID citation navigation, prefill context, request lifecycle, offline recovery, limit enforcement, fallback and Reduce Motion behavior.
- Live POST attempt count, success/failure status and per-kiln image honesty; no private endpoint or question/location logs.
- Fixture provenance/sanitization and screenshot paths, identifying live versus simulated evidence.
- Leak-scan coverage and match count; confirmation of no AWS access/edits, no staging/commit/push, no target increase, and preservation of unrelated changes.
- Remaining limitations and anything the orchestrator needs to review.

Stop after the report. The orchestrator will rerun relevant checks, inspect the diff, scan for leaks and look at screenshots. Do not begin prompt 19, prompt 20 or a polish phase.
