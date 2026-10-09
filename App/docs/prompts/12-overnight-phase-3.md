# Prompt 12: Overnight autonomous run — Phase 3 (iOS app on real public data)

**For the orchestrator (Codex).** Read `11-orchestrator-handover.md` first, including §1a. This prompt is a **one-time exception** to the no-agents rule, granted by the user on 2026-10-10 for this run only.

The user is asleep. They want Phase 3 built, reviewed and tested by morning, with a clear report waiting. You may **spawn sub-agents** for this run, within the rules below. After this run, the normal rules from handover §1 apply again: no agents unless the user asks.

You cannot ask the user anything tonight. Where a decision is open, use the defaults in §3. If something truly blocks you, stop that part, document it, and finish everything else.

---

## 1. Authorization for tonight

**Allowed**
- Edit iOS app and `KilnWatchCore` source, tests and docs.
- Make small, necessary `KilnWatch.xcodeproj` build-setting changes (xcconfig wiring only). Never add the project to itself.
- Run `xcodebuild`, `swift test`, the iOS Simulator, XCTest UI tests and screenshots.
- Make **read-only** HTTPS `GET` requests to the live public API (`/public/kilns…`, `/health`). It is public and throttled at 10 rps, so keep the total to a few hundred requests at most.
- Spawn sub-agents (see §4).

**Forbidden, with no exceptions tonight**
- Any `aws`, `terraform`, `ssm`, `brew install` or other cloud or infrastructure command. Do not touch AWS. Part B (CloudFront) stays pending.
- `git commit`, `push`, `stash`, `reset`, `checkout` of files, `clean`, branch switching, and any `gh` command. **Leave the git index and every existing file you don't need to edit exactly as they are.** This includes the untracked Phase 2 logs.
- Editing anything under `AWS/`, `Model/`, `.local/` (read-only use of `.local/integration-2b/outputs.json` is allowed, for the API base URL), `best.pt`, `args.yaml` or `scores.json`.
- Sign-in, Cognito users or tokens, inference, training, the portal, or Phases 4–6.
- Writing the API base URL, account ID or any identifier into tracked files (§5). **The repo is public.**

## 2. Before starting: checks the user should do before sleeping

The user does these, not you:
- **Sign out of AWS:** `aws logout --profile kilnwatch`. This makes AWS writes impossible tonight.
- **Codex permissions:** the run needs network access (the public API) and writes outside the workspace (Xcode DerivedData and the Simulator). Without them every build stalls on approval prompts while the user sleeps. Start Codex with a mode that allows this unattended, for example `codex --sandbox danger-full-access --ask-for-approval never`. That is acceptable **only because** AWS is signed out and §1 forbids git, `gh` and cloud commands.

If the network or Simulator is not available, do every offline part (source, unit tests, build) and report the rest as unrun.

## 3. Decisions defaulted for tonight

The user can change any of these tomorrow.
- **Today tab:** there is no real route service, and **you must not fabricate a route.** For real data, Today shows a map of the real flagged kilns, with a calm "Route planning isn't available yet" state where the route and stop carousel would be. Tapping a pin opens the kiln. The fixture route demo stays for fixtures/DEBUG only.
- **District:** the app has no sign-in, so it uses a configured district (`Hapur`) for the public district list.
- **Data source priority:**
  1. If the public API URL is configured, use **live public data**.
  2. Otherwise use the existing fixtures, clearly labelled "Sample data" (the existing mock behaviour).
  3. Never mix the two in one list.
- **Language:** English only. Hindi is Phase 6.
- **No persistence:** don't add an offline cache for kilns (YAGNI). Network failure shows an honest error with a retry button. The existing route cache stays as it is.

## 4. Sub-agent plan (for tonight only)

**Hard rules**
- **Only one agent edits files at any time.** Reviewer agents are read-only. Never run two agents that write to the same files.
- **Only one agent uses the Simulator or `xcodebuild` at a time.** Run builds and tests sequentially.
- **Every agent gets these rules in its prompt:** §1, §5, the "illegal" ban and the honesty rules.
- **Cap:** at most **3 review→fix cycles.** After that, stop and report what remains.

**Roles**
1. **Builder** (one agent at a time; edits allowed): implements §6 milestone by milestone, runs the build and core tests after each milestone, and reports diffs and results to you.
2. **Reviewers** (read-only; they may run in parallel *with each other* only while no builder is editing). Each returns findings as `file:line — problem — fix`.
   - **Design reviewer:** checks against `App/docs/DESIGN.md` (tokens, components, status = symbol + word + colour, Liquid Glass only on navigation, honest states, Reduce Motion).
   - **Accessibility reviewer:** VoiceOver labels, Dynamic Type up to AX5, contrast, touch targets.
   - **Swift concurrency and architecture reviewer:** Swift 6 strict concurrency, `@MainActor`/`Sendable`, no logic in view bodies, cancellation.
   - **Honesty and data reviewer:**
     - no "illegal";
     - flagged items always say "Flagged by satellite · pending inspection";
     - `exposure == nil` never shows 0 and `violations == []` never means rules passed;
     - the type is shown as unverified, and the model score is not called accuracy;
     - no fixture imagery or counts on real records;
     - no 800 m legal claims on real records.
3. **Tester** (one at a time; Simulator): runs §7 and captures screenshots.

You, the orchestrator, merge the findings, decide what is real (reject speculative findings), and hand **one consolidated fix list** to the builder.

## 5. Configuration without leaking the URL

- Add `App/Config/Public.xcconfig.example` (tracked) containing `KILNWATCH_PUBLIC_API_URL = ` (empty) and `KILNWATCH_DISTRICT = Hapur`. Add `App/Config/Public.xcconfig` (**git-ignored**; add it to `.gitignore`) with the real base URL from `.local/integration-2b/outputs.json` → `api_base_url`.
  - xcconfig treats `//` as a comment, so write the URL as `https:/$()/…` or split it the standard way.
  - Wire the xcconfig as the app target's base configuration, falling back gracefully if the file is missing. Use the `#include?` optional include pattern from a tracked base xcconfig.
  - Expose the values through `INFOPLIST_KEY_*` or custom Info.plist keys (`GENERATE_INFOPLIST_FILE = YES` is already on).
- `AppModel` reads them at launch. A missing or empty URL means the fixtures path. Keep the existing `KILNWATCH_API_URL`/`TOKEN` environment path for the protected API untouched; that is Phase 5's business.
- Before finishing, run `git diff` and grep every tracked file for `execute-api`, `amazonaws.com` and the API id, and confirm nothing leaked.

## 6. Phase 3 scope (milestones, in order)

### M1 — `KilnWatchCore` public client (smallest change, with tests)
- `KilnWatchAPI` always sends `Authorization` today: `send` calls `token()`. Add token-free public requests with the smallest clean change. For example, make the token provider optional, or add an `authorized: Bool` parameter to `send`. **Never send an `Authorization` header to public routes.**
- **New methods:**
  - `publicKilns(district:)`: follows `next_cursor` pages using the existing repeated- or empty-cursor protection;
  - `publicKilns(latitude:longitude:radiusM:)`;
  - `publicKiln(id:)`.
  - The paths are `public/kilns` and `public/kilns/{id}`, with no `/v1` prefix.
- **Errors:** map 400/404/429/503 and transport failures to the existing typed `APIError`. A 404 is "not found", and 429 and 503 are transient.
- **Tests** (Swift Testing, `URLProtocol`):
  - no auth header on public calls;
  - paging;
  - query encoding;
  - decoding the real recorded public bodies. Copy small **public** response bodies captured from the live API into test fixtures; they contain no secrets. Note that the near-point records carry an extra `distance_m`.
  - all existing tests still pass.

### M2 — App data flow
- `AppModel` gets a public mode: on launch it loads the configured district list, then the detail on demand.
- **States:** loading, loaded, empty ("No flagged kilns in Hapur in the scanned imagery"), offline, 429 ("Busy, retrying") with one automatic backoff, and 503 ("KilnWatch data is temporarily unavailable"), each with a retry button.
- Never substitute fixtures when live data fails. Show the error instead.
- A "Live data" or "Sample data" indicator, in the existing style, makes the source obvious.

### M3 — Kilns tab and Kiln detail on real records
- **Kilns list:** the real 39 records.
  - Each row has the kiln ID (monospaced, truncated sensibly, full ID available to VoiceOver), the predicted type marked unverified, the flagged status badge, and "Exposure not assessed".
  - Search and filter keep working.
- **Kiln detail:**
  - Header: ID, status "Flagged by satellite · pending inspection", "Predicted FCBK · unverified", and a "Model score 0.82" help line ("How strongly the model matched this shape; not a rule check").
  - Dates: "First seen on satellite imagery" and "Latest satellite image".
  - **Evidence:** if `evidence.before`/`after` URLs exist, a real comparator showing the 256 px images, **pixel-crisp** (`.interpolation(.none)`), integer scaled, with the acquisition date and "Contains modified Copernicus Sentinel data <year>". Use `before_metadata`/`after_metadata` for the dates and the footprint pixel overlay if feasible.
    - If they are null, which is the case for everything today, show "Satellite images not yet published".
    - **Never** show the mock Apple snapshot for real records. Keep the `usesIllustrativeEvidence` gate.
    - Use an `AsyncImage`-style loader with honest loading and failed states, and no placeholder photo.
  - "Rules not evaluated", "Population exposure not assessed".
  - **Finding 13 fix:** for real records, remove the "Within 800 m" heading (`KilnView.swift:45`), the fixed 800 m `MapCircle` (`:170`) and the "Dashed ring: 800 m buffer" caption (`:212`); ExposureBlock's "800 m/metres" copy (`ExposureBlock.swift:4,29,43`) must not appear for real records. The mini-map shows the kiln footprint and location only. Fixture records may keep their demo visuals.
  - Hide the Record verdict and Ask entry points for real records, or show an honest "Sign-in coming soon" note, because there is no auth. Do not let a verdict be "recorded" against live data.

### M4 — Today tab for real data (default from §3)
- A map of the real flagged kiln footprints and pins (status colour + symbol), framed to their bounds.
- In place of the route accessory and carousel: "Route planning isn't available yet. Showing satellite-flagged kilns in Hapur." Tapping a pin opens its detail.
- Keep the Phase 2 fixture route experience intact for fixtures/DEBUG.

### M5 — Polish pass to DESIGN.md
- Light and dark mode, AX sizes, Reduce Motion, no layout truncation.
- Liquid Glass only on navigation.
- Zero build warnings.

## 7. Testing required (the tester agent, sequentially)

1. **Core tests:** `cd App/Packages/KilnWatchCore && swift test`. Everything must pass with zero warnings. Report the counts before and after (it was 26 before tonight).
2. **Build:** `xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build`, with **zero warnings**.
3. **Live app run** in the Simulator with the configured URL. The app loads **39** real kilns. Open `KW-6b3b38da681850e5af46b024f3d3f78e` and check its honest states. Check that Today shows the real map.
4. **State checks.** Add DEBUG-only launch arguments or a stub `URLProtocol` so these can be tested deterministically: loading, empty, offline, 429 and 503. Follow the existing `-demo` launch-argument pattern in `KilnWatchApp.swift`.
5. **UI tests** (XCTest), in the same temporary style as Phase 2 or a small UI test target if one is added cleanly: list loads, detail opens, no "illegal" text anywhere, and no "800 m" text on real records.
6. **Screenshots** into `App/docs/screens/phase-3/`: Kilns list, Kiln detail (top and bottom), Today map, the 503 state and the offline state. Each in light and dark, plus one at AX3. **Look at each screenshot yourself** before calling it done.
7. **Leak scan** (§5) and `git diff --stat`. Confirm that only the intended files changed, and that nothing was staged or committed (record `git status` at the start and compare).

## 8. Morning report

Write `App/docs/screens/phase-3/overnight-report.md` (plain English, short), and also give it as your final chat message:
1. **The verdict, in one line:** done / partly done / blocked.
2. What the app does now, with screenshot links.
3. Files changed, one line each.
4. Tests: exact counts, the build warnings (zero), the live-run result, and the state checks.
5. The sub-agents used, what each found, what was fixed, and what you rejected and why.
6. The defaults applied (§3), which the user should confirm.
7. Anything unrun or blocked, and why.
8. Next steps:
   - commit and push: the user decides;
   - Part B CloudFront after AWS verification; the live image path then needs a recheck;
   - the portal (AWS teammate);
   - later phases.

Update `App/docs/HANDOVER.md` with a short "Phase 3 (overnight run)" paragraph. Do not rewrite the history sections.

## 9. Stop point

Stop after the report. No commits or pushes, no AWS, and no further phases. The user reviews in the morning.
