# KilnWatch — prompt 19: live rules and exposure

Run in a **new Codex builder chat**, in the existing checkout. The user confirmed R1 live on 10 October 2026 and authorized this iOS phase. Prompt 18 passed orchestrator review. This builder may use Xcode and the Simulator sequentially; no other iOS builder may use them at the same time.

## 1. Scope and authorization

Show the live siting assessment and population exposure on kiln detail, with an honest compact summary in Kilns rows. Include the small R1 compatibility update for Ask rule citations and `get_evidence` steps. Preserve the current design and existing live registry, imagery, Ask lifecycle and labelled Sample data behavior.

Running this prompt authorizes local iOS edits, tests, builds, Simulator checks, screenshots and a few public registry/image GET checks. **No live POSTs are needed or authorized in this phase**, including Ask and routes. Use recorded/local stub responses for Ask. The shared Ask cap remains 50 questions per UTC day; leave prompt 18's conservative 2/8 count unchanged.

No sub-agents. No AWS CLI, Terraform, consoles, cloud logs, counters, credential files or AWS/Model reads or edits. Public GETs through the app's existing configuration are allowed. No backend changes, installations, staging, commits, pushes, deployment or other cloud writes. No route planning, authentication, verdict sync, new evidence publication, model changes or general polish phase. Prompt 20 waits for the user's P1-live confirmation.

Own `App/` changes only, excluding the AWS-owned `App/docs/api-contract.md`, shared final-stretch plan and other orchestrator prompts. Small necessary shared app/core changes are allowed. Leave the root project alone unless a necessary app-test reference requires an edit; never add the project to itself. Preserve unrelated changes and old Phase 2 logs. Do not pull, reset, rebase, switch branches or make a worktree copy that drops current work.

## 2. Read and baseline

Read in order:

1. `AGENTS.md`
2. `App/docs/HANDOVER.md`, `App/docs/build-plan.md`, `App/docs/DESIGN.md`
3. `App/docs/plan-final-stretch.md`, particularly the app lane and ownership rules
4. `App/docs/api-contract.md`: the kiln record, public read API and **“R1: rules, exposure and rule checks”** section
5. `App/docs/prompts/18-phase-4b-live-ask.md` and `App/docs/screens/phase-4/ask-orchestrator-review.md`
6. Current kiln/list views, `RuleDistanceBar`, `ExposureBlock`, `CitationChip`, `RuleSheet`, `AppModel`, core models/coders/fixtures/tests and Ask response handling

Historical plans saying R1 is not live or 18 is in progress are stale. The user's confirmation and current R1 contract govern this phase. Older parallel-agent/auditor suggestions are overridden by the no-agents rule.

Check git status and recent hashes/subjects without author metadata. Save a starting changed-file inventory under ignored `.local/phase-4c/`. Preserve minimum iOS **26.1**, Swift settings and the installed toolchain; do not raise the target. Use available tools and Apple's documentation when needed, without assuming Claude-specific tooling exists.

Read these existing local samples programmatically without printing private values:

- `.local/phase-4/live/r1/kiln-6b3b38.json`
- `.local/phase-4/live/r1/hapur-list.json`
- `.local/phase-4/live/fixtures/ask-rule-answer.json`

These are recorded bodies, not authority to inspect adjacent raw AWS logs or request files. Even host-replaced files must be sanitized before copying into tracked resources.

## 3. Live facts and model changes

Both `GET /public/kilns` and `/public/kilns/{id}` now carry:

- `violations`: siting flags with existing `rule_id`, `measured_distance_m`, `threshold_m`, `source`, `measured_to` and nullable `evidence_url`. Null evidence must not suppress a real flag or borrow an unrelated image.
- `rules_assessment`: all current Hapur records are `partially_evaluated`. Missing/unassessed data never establishes a clean result.
- `exposure`: required integer counts `{people, children_under_five, adults_over_sixty}` when assessed, otherwise `null`. Null is not zero. A genuine assessed zero remains zero.
- `rule_checks`: one entry per assessed rule, in supplied order; `[]` for unassessed records. Each entry has `rule_id`, `check`, `status`, nullable `threshold_m`, nullable `measured_distance_m`, `verification` and `source`.

Add minimal Codable/Hashable/Sendable support to KilnWatchCore. Retain legacy records and cached fixture routes that omit `rule_checks`; absent/empty checks must not manufacture an assessment. Handle unknown status/verification values safely, using the existing open-enum pattern or equivalent honest fallback. Preserve valid zero distances and null measurements/thresholds separately. Do not require exactly eight checks in the decoder or hard-code Hapur totals into app behavior. Keep wire snake_case/date handling and current pagination intact.

The recorded list has 39 kilns, 52 flags across 36 kilns, population estimates for all 39 and eight checks per kiln. These are verification expectations for this sample, not permanent product constants.

## 4. Detail: flags, checks and sources

Keep the main kiln status exactly **“Flagged by satellite · pending inspection”**. Every rule hit is a **siting signal pending inspection**, never a verdict. Never use “illegal”, “compliant”, “passed” or “clear” to interpret these assessments. Predicted type stays unverified; never derive the technology check from its score.

Show flags prominently using the existing `RuleDistanceBar` design, then make all supplied checks readable in a modest native disclosure or section. Avoid counting a flag twice because it also appears in `rule_checks`. Keep server order for checks and stable row identity. Measurements, applied thresholds, source and verification come from this kiln's response, with `violations` matched by `rule_id`; do not replace them with a catalog default or another kiln's values. Preserve legacy fixture behavior without inventing live checks.

| Status | Required interpretation |
|---|---|
| `within_threshold` | “Siting flag · needs inspection”; show measured distance versus the applied threshold when present. Use flagged styling, never confirmed-verdict styling. |
| `beyond_threshold` | “Beyond threshold”; a mapped-distance result, not kiln compliance. If the measurement is null, say no mapped feature was found within the threshold; do not fabricate the nearest distance. |
| `inconclusive` | “Inconclusive · map data incomplete”; never a pass, green state or checkmark of approval. Keep this status even if an available distance happens to exceed the threshold. |
| `not_evaluated` | “Not evaluated · no usable data”; no zero measurement, fake technology finding or inferred boundary distance. |
| `not_applicable` | “Not applicable”; neutral, no compliance inference. |
| Unknown | Honest unsupported/unavailable check state; retain the ID, no favorable inference. |

Only draw a distance bar when valid finite measurement and positive threshold are present. Avoid divide-by-zero/invalid layout, retain measured zero, and show missing data plainly. Beyond/inconclusive rows use neutral presentation; no green pass signal. Do not fall through to the current `technologyLine` merely because a distance is absent. A real technology requirement is reference text, not a finding that a model-predicted type fails it.

Keep the partially-evaluated note visible. A zero-flag kiln says “No rule flags measured” **and** explains that some rules could not be checked; it never says there are no concerns. With absent/empty checks, show an honest unavailable/not-evaluated state appropriate to `rules_assessment`, and retain any supplied legacy flags. Do not hide conflicting or missing data behind a clean badge.

Verification applies to the **threshold**, separately from check status:

- `secondary_sources`: identify that the threshold comes from secondary sources and has not been checked against the gazette text.
- `unverified_compilation`: show **“Unverified threshold”** beside the relevant rule result and in its source details. Follow this field for every rule, including technology if supplied; do not assume only school/highway/rail can carry it.
- Unknown/missing verification: say verification is unavailable; never promote it to verified.

Rule chips open a native source/reference sheet. For a kiln check, the sheet must show that check's supplied label, applied threshold/measurement when available, status, source and verification. The current global `RuleSheet` only uses a bundled catalog; adapt it minimally so contextual values are not lost. Use “Rule source” or “Threshold source” rather than presenting compilation text as confirmed legal authority. Make the unverified warning visible for school/highway/rail references as well. A rule-only citation without kiln context must not invent a measurement or select an arbitrary kiln's check. Unknown rule IDs use “Rule details unavailable”. No new public rules endpoint or authenticated catalog fetch is needed.

The buffer map remains the existing location/footprint display. Do not draw a centroid circle and call it an 800 m footprint-edge buffer, invent nearest features, or plot missing `measured_to` coordinates. This phase needs no new GIS computation.

## 5. Exposure and list summary

On assessed live detail use **“Within 800 m”**, explaining that this is from the **kiln edge**, with the actual people count and the under-5/over-60 values. Call these modelled residents, not measured health effects or people harmed. Retain “Population exposure not assessed” for null, with no number or age-group zero substitutes.

Show this full attribution with assessed exposure figures:

> Modelled estimate of residents within 800 m of the kiln edge. Population: Meta and CIESIN High Resolution Settlement Layer (HRSL) v1.5.2, CC BY 4.0. Age groups are modelled shares of the same estimate.

The attribution must be readable on detail and on the list screen that displays counts. It may appear once in a clearly associated list section header/footer for all rows; do not repeat the paragraph 39 times or make detail the only place it exists. Keep it accessible and visibly associated with the estimates. Do not falsely attribute arbitrary scripted demo figures to a real HRSL computation; sample mode stays explicitly labelled.

Kilns rows show the existing deterministic top **flag**, its rule ID and measured-versus-applied-threshold summary, and modelled people within 800 m. Carry an “Unverified threshold” warning when that top flag has it. Do not rank inconclusive/beyond/not-evaluated checks as flags or introduce a new risk score. With no flags, preserve the partial-assessment warning; with no population assessment, say so. Preserve search, pagination, loading/recovery and full-ID navigation. The existing list may abbreviate a display title but must retain the full route ID and accessibility identity; do not shorten the actual ID.

Count/bar animations must use existing motion tokens. Under Reduce Motion show actual values immediately, without count-up from zero. Unknown data never appears temporarily as zero. Keep sources, warnings, age groups and units readable at AX3/AX5, with wrapping and no fixed-height text containers. Status always includes words/symbols, not color alone. No glass cards, redesign or new dependencies.

## 6. Small Ask compatibility update

The response shape is unchanged. `get_evidence` is an ordinary server-written step: display its exact label/summary and `ok`, preserving repeated/empty/failed step behavior and honest generic waiting. Do not simulate evidence progress or fetch cloud evidence metadata to render the trace.

The recorded `ask-rule-answer.json` contains `C-HAB-800` in answer prose, but its `citations` array currently contains only the kiln ID. Preserve that recorded fact: display the rule text without inventing an extra returned citation/chip. Only entries in the server `citations` array become citation actions.

Also support well-formed rule IDs when the server explicitly returns them in `citations`. The existing success guard accepts only full kiln IDs; extend response-citation handling narrowly for supported rule-ID forms, with safe unknown-rule presentation. **Do not loosen `AskRequest.kilnId` validation**: context still requires a full kiln ID. Do not accept arbitrary URLs/strings or route rule IDs through `/public/kilns/{id}`. Preserve returned first-appearance order and deduplication; kiln chips still fetch live detail and rule chips open the honest reference sheet.

Keep existing POST lifecycle, timeout, no-auth behavior, no automatic retry, fallback/disclaimer display, offline recovery and limits unchanged. No extra chips inferred from unreturned prose. No route-planning suggestions until P1. Verify the recorded answer with local stubs and add a clearly labelled synthetic mixed kiln/rule-citation case to cover the explicit rule-array path. Do not claim the recorded sample itself returned a rule in its citation array.

## 7. Tests, live GET evidence and screenshots

Copy sanitized versions of the two recorded R1 registry bodies and recorded Ask body into dedicated test resources as needed. Strip every private host/identifier; consistently remap real kiln IDs to full-format synthetic IDs in records, references, answer text and citations. Keep numeric/status relationships realistic. Preserve null URLs rather than substitute mock imagery into a live mode. Clearly label recorded/sanitized versus synthetic cases. Do not print raw body/error/log contents.

Use local URLSession stubs for automated checks. Cover meaningful regressions:

- List/detail R1 decoding, eight supplied checks and the reference flag/exposure relationships; legacy missing checks, empty unassessed checks and unknown enum values.
- All five check statuses, unverified/secondary/unknown verification, null distance/threshold, genuine zero distance and null versus genuinely zero exposure.
- Partially evaluated zero-flag records remain inconclusive/unfinished, with no pass/compliant inference.
- Existing nullable flag evidence, image publication states, route cache legacy decoding and other core behavior remain compatible.
- Recorded Ask prose-rule response succeeds; synthetic explicitly returned rule citations navigate by type, with deduplication, full IDs, safe unknown rules and malformed citation rejection. `get_evidence` labels and repeated/failed steps remain intact; POST attempt/auth/retry tests still pass.

Run sequentially:

```sh
cd App/Packages/KilnWatchCore
swift test
```

From the repository root:

```sh
xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Require zero app/core compiler warnings. Where the environment restricts them, public HTTPS GETs, package resolution, builds and Simulator operations need the specific network/local permission. No environment permission authorizes cloud writes. Do not install tooling or ask for credentials; the existing configuration suffices.

Use a few deliberate app GET checks, without polling or loops: the Hapur list, reference detail and a zero-flag partially-evaluated detail. The reference kiln `KW-6b3b38da681850e5af46b024f3d3f78e` should show C-HAB-800 at **497 m against 800 m**, **4,225** modelled people, **430** under 5 and **294** over 60, with eight checks. These values are a check case, not UI constants. Find the zero-flag case from the recorded list; do not show it as clear. Verify an unverified flagged rule through a suitable real or local recorded record. Live imagery remains per-kiln; do not assume new publication or strip existing published images.

If public GETs are unavailable, finish local checks and report the limitation; never substitute samples into live failure states. **Do not send a live Ask POST for screenshots**. Ask compatibility screenshots must intercept all requests locally and be labelled test/sample data.

Exercise source-sheet opening/closing, list-to-detail, Ask-to-rule and Ask-to-kiln navigation, then detail-to-Ask prefill without submission. Check light/dark, AX3/AX5, Reduce Motion, all statuses, missing/zero exposure and source warnings. Use stable existing UI tests or a small local harness. One manual Simulator check is acceptable for flaky native beta navigation; report harness limits instead of repeated automation loops. Smoke-check existing Today, published imagery and labelled fixture behavior without starting routes or verdict work.

Store reviewed screenshots under `App/docs/screens/phase-4c/`. Include a small set covering live reference flags/exposure, partial zero-flag state, unverified threshold/source, all-check states, missing exposure, list summary/attribution, AX sizes and local Ask rule navigation. Inspect every screenshot yourself. Record which are live GET-backed, recorded/local or synthetic. State actual SDK/runtime/device versions separately; do not claim an iOS 26 runtime, physical iOS 26.6 or spoken VoiceOver check unless performed.

## 8. Leak scan, report and stop

The repo is public. Never write or print account IDs, ARNs, API URL/host/ID, CloudFront domain/ID, database hosts, emails, credentials, tokens or private plans. Keep raw logs and unsanitized material only under ignored `.local/phase-4c/`. Scan every builder-created/changed tracked-path file and screenshots (including OCR and metadata/binary exact-value checks) for prohibited patterns and private host values derived internally from the existing ignored app configuration/local samples. No AWS reads to obtain scan inputs. Report counts only, never matching values/snippets. Preserve private files as ignored.

Write `App/docs/screens/phase-4c/rules-exposure-report.md` with behavior and owned-file inventory, core/build results and warning counts, live GET results, source/verification handling, exposure attribution, zero-flag/null/unknown behavior, Ask citation compatibility, screenshot paths/provenance, leak coverage/counts and remaining limits. State that live POST usage is zero for this phase. Distinguish local UI harness checks from genuine live/runtime/device verification. Add a brief completion/limitations note to `App/docs/HANDOVER.md`; leave shared planning/contract files alone.

Review your final diff against the baseline. Stop for orchestrator review. No staging, commits, push, AWS access, prompt 20 or follow-on polish. The orchestrator will rerun checks, inspect the diff, scan for leaks and review screenshots independently.
