# Prompt 19: rules and exposure UI, review report

The builder ran out of session before writing its report. The AWS orchestrator reviewed the work independently on 2026-10-10. This file records that review.

## What changed

- **KilnWatchCore:** `RuleCheck` (`rule_checks` entries), with open enums for status and verification so unknown values show as "unavailable", never as a pass. Optional on `Kiln`, so legacy records still decode. Shared exposure attribution text. Ask can navigate rule citations. Tests: `R1Tests.swift`, plus additions to `AskTests.swift`, with sanitized recorded and synthetic fixtures in `R1Fixtures/` (provenance in its README).
- **Kiln detail:**
  - Flagged rules use `RuleDistanceBar`: a measured-against-threshold bar, "Siting flag · needs inspection", the verification label and the source.
  - An "All supplied checks" sheet lists every rule check (`RuleCheckRow`).
  - `ExposureBlock` shows modelled residents within 800 m, the age groups and the HRSL attribution.
  - The partial-assessment note ("Some rules could not be checked from map data. Check on site.") also appears when there are no flags.
- **Kilns list:** each row shows the top flag (rule, distance against threshold, verification) and the modelled residents, with the attribution once in the section header.
- **The project file:** a comment-only rename of the `Base.xcconfig` reference. No new targets, and the project is not added to itself.

## Verification by the orchestrator

- `swift test` (KilnWatchCore): **63 tests passed**.
- The root `xcodebuild … build` (iPhone 17 simulator): **BUILD SUCCEEDED**, with no warnings or errors in the filtered output.
- **Leak scan:** all 66 changed or untracked files, including the PNGs and the JSON fixtures, checked against the account IDs, API host and ID, CloudFront domain and ID, and RDS host: **0 hits**. No URLs in the recorded fixtures. `App/Config/Public.xcconfig` (the live URL) stays git-ignored.
- **Screenshots reviewed:**
  - `live-reference-flags.png`: C-HAB-800 at 497 m against 800 m, secondary sources, 4,225 / 430 / 294, attribution shown.
  - `live-zero-flags-partial.png`: "No rule flags measured" plus the partial note; not shown as clear.
  - `recorded-unverified-source.png`: an UP-RAIL-200 "Unverified threshold" source sheet, labelled Sample data.
  - `live-list-attribution.png`: list rows and the header attribution.
  - `recorded-ax5-reduce-motion.png`: AX5 text wraps without truncation.
- **Provenance:** file names say `live-` (public GET), `recorded-` (sanitized recorded bodies, labelled Sample data in the app) or `synthetic-`.
- **Live POSTs in this phase:** none expected by the prompt. Not independently confirmed beyond the builder's partial log.

## Remaining limits

- No spoken VoiceOver pass. `RuleDistanceBar` sets a container label with `children: .contain`, so VoiceOver may read the summary and then the children. Check this on a device during polish.
- Rows say "requires 800 m" while the source sheet says "applied threshold". Consider "threshold 800 m" everywhere for consistency (polish).
- Simulator only (iOS 27 SDK), with a minimum deployment of 26.1. No physical-device check.
