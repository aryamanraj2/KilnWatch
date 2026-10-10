# Prompt 20: live Today route, builder report

Date: 2026-10-10. Builder lane, iOS only. Paused for orchestrator review. Nothing was staged or committed.

## Behavior

- **Plan on tap only.** In live public mode, the Today map has a bottom action, "Plan tomorrow in Hapur". The district comes from the app's registry district. Under it: "Up to 8 stops · most people within 800 m · visited in road order". Tapping sends one `POST /routes/plan` with exactly `{"district":"Hapur","max_stops":8,"priority":"people"}`. There is no `Authorization` header, no request caching, a 35 s timeout, and one request at a time (the button is disabled while a plan is in flight, and double taps are guarded in `RoutePlanner`). Nothing plans on launch, tab switch, foreground, refresh or retry. Retry is always a manual tap.
- **Launch reads disk only.** The saved plan is shown from its own `RouteCache` folder (`PublicPlan`, separate from the signed-in route cache). With no saved plan, the registry map is shown with the plan action. DEBUG test plans use a separate `DebugPublicPlan` folder and never touch the live saved plan.
- **Saved plan.** The existing route UI (`RouteMap`) is reused: map, stop pins, clay road legs, carousel, route list and Apple Maps handoffs. The header shows the plan's own day ("Tomorrow · Hapur", or for example "Sun 11 Oct · Hapur"), then "8 stops · est. 5 h 52 m · leave 09:00", then "Visited in road order". A saved plan shows "Saved plan · <date>". "All flagged kilns" (header flag button) returns to the registry map and keeps the plan; "Show saved plan" goes back. "Plan again" is in the route list and replaces the plan only on success.
- **Honest labels.** Times are always "Est. 09:13" (compact) or "Estimated arrival 09:13" (route list and VoiceOver), including the bottom accessory. The total appears only when every leg and stop has valid durations. Each stop card shows the full kiln ID, "Predicted FCBK · unverified", "Flagged by satellite · pending inspection", each flagged rule ID with its measured-against-threshold line, "N people within 800 m · modelled", and the on-site checks. A stop with `rules_flagged: []` says "No rule flags measured" with the partial-assessment note. The route list shows `access.note` verbatim and a **Plan notes** section with the server `notes[]` verbatim and in order. The stops footer explains the selection and carries the HRSL attribution.
- **No legs.** Stops and pins still work, the "Road geometry unavailable · stops still usable" banner shows, and no total is shown.
- **Offline.** If the registry read is offline, or a plan fails on transport, a saved plan stays usable with "Offline · showing saved route".
- **Errors.** The nested `{"error":{code,message,retryable}}` body is parsed. The server message is never shown, and every failure keeps the saved plan. Wording: 400 "The plan request was rejected." (logs a count, not the body); 404 `no_kilns` "No flagged kilns with population estimates in Hapur to plan."; 429 `daily_cap_reached` "Route planning has reached today's limit. It resets at 05:30 IST (00:00 UTC)." (no plan until the next UTC midnight); code-less gateway 429 "Too many requests. Wait a moment." (manual Try again); 503 "Route planning is unavailable right now." (Try again only if `retryable`); transport "You're offline. Reconnect to plan a route."; timeout "The plan took too long to arrive. Check your connection and try again."; undecodable or empty 200 "The plan could not be read.". Unknown codes fall back by status. No error substitutes a sample route in live mode.
- **Unchanged.** The signed-in `GET /routes/today` path and its fixtures, and the labelled DEBUG Sample data route with no configuration, are unchanged. So are registry, imagery, rules/exposure and Ask. The old "Route planning isn't available yet" dead end is replaced. The empty-state "Plan a route → Ask" panel is not reachable in live mode (no plan means the registry map is shown). There is no Ask prefill for a plan.

## Owned files

- Core: `Sources/KilnWatchCore/RoutePlan.swift` (new: request, `RoutePlanError`, `planRoute`, `RoutePlanner`, estimate and day text), `Models.swift` (`Route.notes: [String]?`), `Ask.swift` (error envelope made internal for reuse), `Package.swift` (P1Fixtures resource).
- Core tests: `P1Tests.swift` (new), `P1Fixtures/` (sanitized recorded people plan, start plan and 400 body, with a README), `AskTests.swift` (stub helpers made internal for reuse).
- App: `KilnWatchApp.swift` (planner, saved-plan load, `planRoute`, kiln lookup from plan records, accessory text), `Features/Today/TodayView.swift`, `RoutePresentation.swift`, `PublicRegistryMap.swift`, `Mock/PublicDemo.swift`, `Mock/PlanDemo.swift` (new, DEBUG `-planDemo`), `Mock/P1Plan.recorded.json` (sanitized copy).
- Root project unchanged; not added to itself.

## Checks

- `swift test` (KilnWatchCore): **73 tests passed, 0 warnings** (63 before). New coverage: exact body and no auth header, recorded 8-stop/8-leg/4-note and 5-stop plans, optional `notes` for old caches and `route_today.json`, no legs, an empty-flag stop, all 12 error rows including the code-less 429, a failed plan keeps the saved plan, cache round-trip, init and launch path send no request, double tap sends one request, the daily cap blocks until UTC midnight, and estimate strings never contain "ETA".
- Root `xcodebuild … iPhone 17 build`: **BUILD SUCCEEDED, 0 app/core warnings.**
- UI checks: run with a temporary XCTest harness outside the repo (a copy of the 4c harness under ignored `.local/phase-4d/`). AXe/xcui could not tap on this Xcode 27 install because SimulatorKit moved. Passed: stub plan flow, no legs and offline saved, all 8 stub error states plus a failed "Plan again" that keeps the plan, live plan, and live relaunch.

## Live use

**`POST /routes/plan` used 1 of 3. `POST /ask` 0.** One tap of "Plan tomorrow in Hapur" from the installed app. It returned 8 stops with road legs drawn and "est. 5 h 52 m · leave 09:00". All 8 full IDs exist in the live registry (Kilns search on the already-loaded list: 8 of 8). Plan notes and the access note are shown, and times are labelled estimates. After relaunch, the saved plan showed "Saved plan · 11 Oct 2026" with no plan button and no POST. A fresh POST would have shown no "Saved plan" banner. From the saved plan, Navigate opened Apple Maps, which showed its own first-run notification sheet, and the current stop did not advance. Other reads were public registry and detail GETs only. No AWS, counter or log reads.

## Screenshots (`App/docs/screens/phase-4d/`)

- Live: `live-registry-plan-action`, `live-plan-map-carousel` (pins captured mid-entry, legs visible), `live-route-list`, `live-route-list-notes`, `live-saved-relaunch`, `live-navigate-maps` (Maps first-run sheet).
- Stubbed (sanitized recorded plan, labelled "Sample data · recorded test plan"): `stub-registry-plan-action`, `stub-plan-map-carousel`, `stub-route-list`, `stub-route-list-notes`, `stub-all-kilns-keeps-plan`, `stub-saved-relaunch`, `stub-no-legs`, `stub-offline-saved`, `stub-error-cap`, `stub-error-throttle`, `stub-plan-again-failed-keeps-plan`.
- **Not captured:** light/dark pairs, AX3/AX5 and Reduce Motion. The user asked to stop the extra testing for time. The text uses Dynamic Type styles, the carousel is capped at xxxLarge as before, and the registry panel scrolls at accessibility sizes, but none of this was verified this phase.

## Leak scan

35 owned or new files, including the 17 screenshots (OCR plus metadata plus exact bytes), were checked against values read internally from the ignored public configuration and the raw recorded plans: **0 pattern matches, 0 exact matches.** Raw bodies, logs and the harness stay in ignored `.local/phase-4d/`.

## Remaining limits

- Simulator only (iOS 27 runtime, minimum 26.1). No physical device, no turn-by-turn or successful-guidance proof, no spoken VoiceOver pass.
- Dark, AX3/AX5 and Reduce Motion were not captured this phase (see above).
- The map fit was already loose before this phase: the overview fits wider than the stop cluster when the tall carousel inset is present, for fixtures too. A one-time refit after layout was added for a plan that is present at appearance. Tighter framing is polish.
- Server notes are shown verbatim, so the note "ETAs are estimates…" contains "ETAs". The app's own copy never shows a bare ETA.
- Stop cards are tall (full ID, status, flags, people, checks). The carousel uses most of the bottom half.
- Files under `AWS/` and `App/docs/` (`api-contract.md`, the plan and prompts) appeared staged during this session. This lane did not stage them.
