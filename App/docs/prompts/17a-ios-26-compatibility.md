# KilnWatch — iOS 26.1 compatibility, with behavior preserved

Run this in a **new Codex builder chat** in the existing repository checkout.

## Authorization and scope

The user has explicitly authorized lowering the minimum supported iOS version so their iPhone running iOS 26.6 can run KilnWatch, **without changing the app's logic, appearance or functioning**. This overrides the older iOS 27 deployment-target requirement only. The new minimum is **iOS 26.1**, not 26.0.

Running this prompt authorizes only the local compatibility changes, existing tests, builds and local verification listed here. No staging, commit, push, deployment, AWS write, model invocation, registry assessment or Phase 4B Ask implementation. No sub-agents. Preserve the existing Xcode/Swift toolchain and language settings. Do not downgrade the SDK or install dependencies or Simulator runtimes.

**Prompt 16c is running in another chat.** You may read files now, but do not edit files, build, run tests, launch Xcode, or use the Simulator until that builder has finished and released them. Confirm completion from its report or the user; an idle process list alone is not proof. If completion is unknown, finish the read-only inspection and report that you are waiting. Once confirmed, recheck git status and the relevant files before editing. Do not interrupt the other builder.

## Read first

Read, in order:

1. `AGENTS.md`
2. `App/docs/HANDOVER.md`
3. `App/docs/build-plan.md`
4. `App/docs/DESIGN.md` (binding; preserve its UI)
5. `App/docs/prompts/17-orchestrator-handover.md`, especially §§5 and 5b, for current context only
6. This prompt, `KilnWatch.xcodeproj/project.pbxproj`, and `App/Packages/KilnWatchCore/Package.swift`

Check `git status --short --branch` and a git log format that contains only hashes and subjects. Capture a baseline of the existing changes privately under ignored `.local/ios-26-compatibility/`. Other work is present, including 16c's edits to the core contract tests. Never reset, overwrite, stage or incorporate those edits into your own work.

## Step 1 — Check availability before changing anything

Inspect the app's actual framework API usage against Apple's installed SDK declarations or official Apple developer documentation. Use normal commands and official documentation; do not assume tool-specific features exist.

The orchestrator's read-only inspection found:

- Liquid Glass, `safeAreaBar`, scroll edge effects, concentric shapes and the symbol drawing effect used here are available on iOS 26.0.
- The app uses `tabViewBottomAccessory(isEnabled:content:)`; the installed SDK declares this overload available on **iOS 26.1**.
- The core package separately declares `.iOS("27.0")`; changing only the Xcode setting is insufficient.

Verify these facts and check the remaining APIs. If an actual iOS 27-only API blocks an unchanged build, stop and report its location and availability. Do not remove a feature, invent a fallback, add compatibility branches, or raise the new minimum without returning for review.

## Step 2 — Make the smallest configuration change

Expected implementation changes:

1. In `KilnWatch.xcodeproj/project.pbxproj`, change the existing Debug and Release `IPHONEOS_DEPLOYMENT_TARGET` settings from `27.0` to `26.1`. Check for effective target-level or configuration-file overrides; all app and UI-test configurations must agree where relevant. Do not reformat the project or add a self-reference to the `.xcodeproj`.
2. In `App/Packages/KilnWatchCore/Package.swift`, change only `.iOS("27.0")` to `.iOS("26.1")`. Leave its macOS minimum, tools version and Swift language mode unchanged.
3. Update only the current deployment-target sentence in `App/docs/build-plan.md`, distinguishing the existing Xcode/SDK version from the new runtime minimum. Add a short current-state note in `App/docs/HANDOVER.md`. Preserve historical verification statements and `DESIGN.md`.

Do not change Swift source, app logic, tests, fixtures, navigation, data loading, API handling, image handling, animations, design tokens or runtime behavior. No changes to AWS, Model, private configuration, signing team, bundle identifiers, certificates or entitlements. In particular, leave the scripted Ask screen and live registry behavior as they are. If a further implementation change seems necessary, report the blocker and stop.

## Step 3 — Verify sequentially

Do not install or download anything to complete verification. Capture build/test logs only under ignored `.local/ios-26-compatibility/`; never print raw logs that may contain private identifiers.

Run the existing core suite:

```sh
cd App/Packages/KilnWatchCore
swift test
```

From the repository root, run the prescribed build:

```sh
xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Also compile for a generic physical device without signing or installing:

```sh
xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'generic/platform=iOS' -derivedDataPath .local/ios-26-compatibility/device-build CODE_SIGNING_ALLOWED=NO build
```

Check the effective Debug and Release deployment settings and built app minimum: **26.1**, with no command-line deployment-target override. Require zero app/core compiler warnings. An unsigned device build proves compilation, not installation or actual phone behavior.

Check whether an iOS 26 Simulator runtime is already installed. If available, use an existing compatible iPhone Simulator to smoke-check startup, the Today map, kiln list/search/detail, and the unchanged scripted Ask screen. Check light/dark presentation and the fixture route accessory's show/hide behavior. Keep live and sample data clearly separated. Do not make `POST /ask` requests or any other cloud writes. Public registry/image GETs are permitted.

If only the iOS 27 runtime is available, smoke-check it and clearly mark iOS 26 runtime verification as **not run**. Do not equate compilation or an iOS 27 run with an iOS 26 device test. If tab-bar UI automation is unstable, use one manual Simulator check and record the limitation; do not loop.

Save a few useful screenshots of any runtime actually tested to `App/docs/screens/ios-26-compatibility/`, with filenames identifying the runtime and screen. Inspect them yourself. Do not claim screenshots establish behavior on an untested runtime.

The user can install through Xcode after this report: connect and trust the phone, enable Developer Mode, choose their existing signing team and the phone destination, then Run. Do not change signing settings or install to a physical device yourself. Report physical-device verification as pending unless the user actually supplies the result.

Builds and Simulator operations may need local tool permissions; dependency resolution can need network access. Request only the permissions actually required in the current Codex environment. Permission to run local tools is never permission for a cloud write. The user enters sign-in credentials only in their own terminal or Xcode.

## Step 4 — Review the diff and report

Review your diff against the starting state. It should contain configuration/documentation changes only, plus verification artifacts. Preserve all other builders' changes and old Phase 2 logs. Do not stage anything.

The repo is public. Never write or print either account ID, any ARN, API URL/ID/host, CloudFront domain/ID, database host, email, token or credential. Derive private scan values internally from the ignored local output/configuration files. Scan your changed files and report counts only, never matching values or raw matching lines. Check screenshots and reports too. Do not print git author metadata.

Write `App/docs/screens/ios-26-compatibility/report.md` with:

- Exactly what changed and which files you own.
- Confirmation that no Swift logic, UI, AWS, signing or unrelated work changed.
- Availability findings and effective Debug/Release/package minimums.
- Core test results, warnings, and skips separately.
- Simulator and unsigned device build results separately.
- Runtime actually exercised, screenshots inspected, and any harness limitations.
- Physical-phone status: verified only if actually tested; otherwise pending, with concise Xcode run instructions.
- Leak-scan file count and match count.
- Any blocker or deviation. Do not describe unavailable or skipped checks as passes.

Stop after this report for orchestrator review. No next phase, staging, commit, push or deployment.
