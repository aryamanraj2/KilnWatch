# iOS 26.1 compatibility report — 2026-10-10

Configuration changes are complete. Existing core tests, the prescribed Simulator build and the unsigned generic-device build pass with zero compiler warnings. Actual runtime coverage is iOS 27.0 only; iOS 26 and the user's physical phone remain untested.

## Scope and ownership

- `KilnWatch.xcodeproj/project.pbxproj`: the two existing project Debug/Release `IPHONEOS_DEPLOYMENT_TARGET` values changed from 27.0 to 26.1. No target overrides or deployment settings in the included configuration files; no UI-test target exists in this project. No project reformatting or self-reference added.
- `App/Packages/KilnWatchCore/Package.swift`: only `.iOS("27.0")` changed to `.iOS("26.1")`.
- `App/docs/build-plan.md`: current stack sentence distinguishes the retained SDK/toolchain from the runtime minimum.
- `App/docs/HANDOVER.md`: appended one current compatibility note; retained history and the other builder's evidence-publication note.
- This report and nine `ios27-*.png` screenshots in this directory are verification artifacts owned by this pass.

No app or core Swift implementation, UI, tests, fixtures, design tokens, logic, networking, signing, bundle identifiers, entitlements, AWS or model files were changed by this builder. All 73 snapshotted app/core source, test, resource and configuration files still match the starting state. The existing 16c contract-test changes are preserved. DESIGN.md is unchanged. Old Phase 2 logs and other builders' files were not touched. No staging, commit, push, physical-device installation, cloud writes, model calls or POST /ask requests were performed.

Read-only inspection began while 16c was active. Editing and tool verification began after the user reported the Claude builder had moved to 16d and the repository's 16c verification report recorded completed app checks. 16d continued separately; this builder did not edit its AWS files. A private baseline and raw build/test/settings logs are in ignored `.local/ios-26-compatibility/`.

## Availability and effective minimums

Checked actual calls against declarations in the installed Apple iPhoneOS SDK's SwiftUI, SwiftUICore and Symbols Swift interfaces. Liquid Glass, safeAreaBar, scroll edge effects, ConcentricRectangle and its used initializer/corner style, tab-bar minimization/accessory placement, ButtonRole.close and the drawOn symbol effect are available on iOS 26.0. The used `tabViewBottomAccessory(isEnabled:content:)` overload requires **iOS 26.1**, establishing the new minimum. Scroll visibility, geometry callbacks, matched view transitions, navigation zoom and typesetting-language APIs used here predate iOS 26. The iOS 27 long-press overload adds inputKinds; the app uses the older overload without that argument. No used iOS 27-only API blocked either unchanged-source build.

| Check | Effective value |
|---|---|
| App Debug | iOS 26.1 |
| App Release | iOS 26.1 |
| KilnWatchCore package | iOS 26.1 |
| Built Simulator app MinimumOSVersion | 26.1 |
| Built unsigned device app MinimumOSVersion | 26.1 |
| Existing toolchain | Xcode 27.0, build 27A5218g; iOS 27.0 SDK |
| Language/package settings | Swift 6; package tools 6.2 and macOS 26.0 unchanged |

Debug and Release were queried with showBuildSettings; package platforms were independently queried with dump-package. No command-line deployment-target override was used. The device build disables signing only for that command; its app has no signature directory. Release settings were verified; a separate Release build was not requested or run.

## Existing tests and compilation

| Check | Result | Compiler warnings | Skips |
|---|---|---:|---:|
| Existing `swift test` in KilnWatchCore | 35 test functions: 34 passed, 0 failed | 0 | 1 |
| Prescribed root iPhone 17 Simulator build | BUILD SUCCEEDED | 0 | None |
| Generic physical-device build with CODE_SIGNING_ALLOWED=NO and dedicated ignored derived data | BUILD SUCCEEDED | 0 | None |

The skipped test is the existing opt-in local real-detection contract test; KILNWATCH_REAL_CONTRACT_LIST was not supplied. Its opt-in run was not performed and is not represented as a pass. The Swift Testing final summary includes this skipped function in its count of 35. Unsigned device compilation establishes neither installation nor actual phone behavior.

## Runtime actually exercised

Only iOS 27.0 Simulator runtimes are installed. No runtime or dependency was installed or downloaded. The compatibility build was installed on the existing iPhone 17 Simulator and launched repeatedly using the app's existing DEBUG launch hooks. The live public registry and image GET paths were exercised; sample routes and scripted Ask were launched separately with fixtures enabled.

| Runtime check | Observed result and limit |
|---|---|
| Startup / live Today | Map rendered with 39 satellite-flagged candidates, Live data label, pins and the honest route-planning-unavailable notice. |
| Live Kilns / search | List loaded 39 records. Existing query launch hook filtered to one matching live record; keyboard entry and search-to-tab navigation were not established. |
| Live detail | Existing open-record hook fetched the published record and rendered both evidence images in light and dark mode. Tap-to-push, comparator dragging and scrolling were not established. |
| Sample route accessory | Active launch state showed End route and the current-stop accessory; inactive launch state showed Start route with the accessory absent. Actual Start/End taps and cross-tab accessory interaction were not established. |
| Scripted sample Ask | Existing playback hook completed the four-step scripted response with citation chips in dark mode; the completed response was also inspected in light mode. No live Ask request was sent. |

The scripted Ask captures are sample data only, as identified by their filenames and this report; they are not evidence of live assistant integration. The existing sample Ask screen itself lacks a visible Sample data pill. That pre-existing presentation was preserved under this configuration-only scope.

Device Hub is the installed Xcode 27 Simulator UI. Its accessibility tree exposes host controls but not embedded app controls. An attempted manual tab selection returned noWindowsAvailable; a compact-window search click did not activate search. No repeated tab automation or temporary UI-test target was added. Launch hooks therefore provide screen/state coverage only, not a successful manual or automated touch-navigation test. An initial empty detail launch override produced a failed-record state; removing that harness override restored the successful live Today run. There was also a booted iPad: preliminary booted-destination operations may have reached it; all delivered screenshots and reported runtime checks used the explicit iPhone 17 destination. The final Simulator appearance is Light and the app is on live Today.

All nine delivered screenshots were opened and visually inspected:

- `ios27-live-today-light.png`
- `ios27-live-kilns-light.png`
- `ios27-live-search-light.png`
- `ios27-live-detail-light.png`
- `ios27-live-detail-dark.png`
- `ios27-sample-route-active-dark.png`
- `ios27-sample-route-inactive-dark.png`
- `ios27-sample-ask-dark.png`
- `ios27-sample-ask-light.png`

These capture the existing design. In the detail top captures, the lower imagery caption is partially behind the tab bar, as in the prior evidence captures; no UI repair was attempted in this compatibility pass. iOS 26 runtime checks, physical-device checks, touch navigation, VoiceOver, accessibility-size and Reduce Motion checks were not run in this pass.

## Physical phone and remaining review

**Physical iPhone on iOS 26.6: pending.** Connect and trust the phone, enable Developer Mode, open the root Xcode project, select the existing signing team and phone destination, then Run. Verify startup, Today, list/search/detail, separate sample route Start/End accessory behavior and scripted sample Ask on the phone. This builder did not alter signing or install to the phone.

No compilation blocker or behavior-change workaround was needed. The remaining compatibility evidence gap is an actual iOS 26 runtime run; Simulator interaction coverage also remains limited by the host controls described above. Stop here for orchestrator review.

## Privacy review

Private scan values are derived internally from ignored local configuration/output files; matching values and raw lines are never included in the report. The scan covers the four configuration/documentation files owned by this pass, this report and nine screenshots. Screenshots receive literal-file scanning, Apple Vision text recognition and visual review. Baseline/log/derived-data files stay ignored and are not deliverables.

Leak scan: **14 files scanned; 0 literal matches; 0 screenshot-text matches; 0 total matches.** All nine screenshots also passed visual inspection for private account/infrastructure values. Existing signing identifiers in the project were preserved, not introduced by this pass.

Privacy deviation: a preliminary chat-discovery tool response was emitted unfiltered and included unrelated private context. Subsequent outputs were filtered or reduced to counts, and no such values were copied into the deliverables. The file scan does not validate earlier tool responses.
