# Prompt 04: Phase 2 — Today, shared models and route navigation

You are the builder for **Phase 2 only** of the KilnWatch Inspector iOS app. Work in this repository on `PortalAPP`. Work sequentially; do not spawn agents, delegate work, run auditors, or start another phase. Do not commit or push. The orchestrator will review your report before the next phase.

## Read first, in order

1. Root `AGENTS.md`, then `App/docs/HANDOVER.md`.
2. `App/docs/build-plan.md`, then `App/docs/DESIGN.md` in full. DESIGN is binding for UI work.
3. `App/docs/research/routing.md`, then `App/docs/api-contract.md`. The API contract and routing additions are proposals, not confirmed backend behavior.
4. The relevant concept sections in `App/docs/concept.txt`: Inspector app, route planner, guardrails, and the kiln record on p.15.
5. Existing code: `App/KilnWatch/KilnWatchApp.swift`, `Mock/MockData.swift`, `Features/Today/TodayView.swift`, the design components, and `App/Packages/KilnWatchCore` models, fixtures, API client, cache and tests.

The parallel waves and auditor instructions in the older build plan and prompts are superseded by AGENTS and HANDOVER. There is one builder in one chat for this phase.

Load the available design and SwiftUI skills (`axiom-design`, `axiom-swiftui`, `swiftui-expert-skill`) and the phase-specific skills (`axiom-location`, `axiom-concurrency`, `axiom-data`, `axiom-networking`, and `axiom-testing` when changing tests). These may appear with different prefixes in your tool catalog. If unavailable, use Apple's developer documentation. Research only decisions that need verification, using normal web search and primary documentation; Firecrawl is optional if available. Check the installed SDK and deployment target before adopting an API. Cite the sources you actually use in your report.

## Outcome and boundaries

Today must consume `KilnWatchCore.Route` and its embedded kiln records, draw the supplied route on MapKit, keep pins and carousel selection in sync, show the inspector's location when authorized, and hand the chosen stop to Apple Maps. A saved route must remain usable without connectivity.

Start with the shared-model migration, then the route data additions, then Today and verification. No work on evidence-image fetching or the comparator (Phase 3), agent streaming (Phase 4), Cognito, photo capture or outbox syncing (Phase 5), or the Hindi/polish phase. Preserve those screens' current mock behavior except for changes necessary to adopt shared models.

Allowed edits: `App/KilnWatch/**`, the root `KilnWatch.xcodeproj/project.pbxproj` for the local package and location usage description, `App/Packages/KilnWatchCore/**` for the model/fixture/cache compatibility work below, `App/docs/api-contract.md`, Phase 2 verification artifacts, and a concise HANDOVER update. Keep design tokens, component appearance and tab structure intact. Mechanical model-adoption changes to other features and components are authorized; explain any actual design deviation. No new dependencies, generic managers, single-implementation protocols, or scaffolding for later phases.

## 1. Make KilnWatchCore the single model source

- Add the local package `App/Packages/KilnWatchCore` to the root Xcode project and link its library to the app. The project syncs `App/KilnWatch`. Never add the `.xcodeproj` as a reference to itself.
- Replace the app's duplicate kiln, coordinate, footprint, type/status, violation, exposure, evidence, stop and rule domain types with imports of KilnWatchCore. Use `Fixtures.kilns`, `Fixtures.route` and `Fixtures.rules` for sample data and previews. Remove the hand-built duplicate registry and route.
- Keep app-specific formatting, rule names, symbols, colors and MapKit conversion in small app extensions or presentation helpers. Keep SwiftUI, MapKit and Core Location types out of the core package. Respect the core's snake_case coder and existing `kilnId`/`ruleId` naming.
- Reconcile `Kiln.district` and `Violation.measuredTo` with the core and proposal. Treat missing metadata in older payloads as unknown/absent; preserve backward decoding. Add the illustrative metadata needed by the fixtures to both registry and embedded route records consistently. Do not fabricate measured feature coordinates for live records or infer authorization from fixture district values. Hide unavailable feature markers.
- Preserve `.unknown(raw)` decoding and round trips. Unknown statuses/types must still render with readable text and neutral styling. Enumerated filter choices should list the known statuses without discarding records with unknown values.
- The core kiln's status is immutable. Preserve the current mock verdict interaction through a small presentation override or an explicit value-copy operation, without weakening the wire model or implementing submission. An unknown kiln ID must show an unavailable state; never silently return KW-0412 or another unrelated record.
- Existing deep links, rule sheets, Kilns, Ask and verdict demos must continue to work after the migration. Rule IDs and numeric thresholds remain as supplied; leave the documented policy conflicts open for the backend owner.

## 2. Extend the route proposal without breaking saved routes

The current core Route contains district, generated time, stops and embedded kilns; it has no access points, road legs, departure or drive-duration metadata. Implement the minimal additions required here and update the contract, fixtures and decoding together.

- Follow `research/routing.md`: server-owned stop order and ETAs, optional road access point/note per stop, and per-leg geometry, distance and duration linked to the destination kiln ID. Add route identity and departure/service/budget metadata only where used. Document the exact keys and optionality.
- The routing research proposes GeoJSON LineString coordinates in `[longitude, latitude]` order, while the existing contract uses coordinate objects. State this geometry-specific exception explicitly. Validate geometry shape, finite coordinates and geographic ranges before converting it for the map; do not force-index malformed arrays.
- Existing Phase 1 JSON and cached routes must still decode when the additions are absent. Preserve the cache's atomic storage and embedded kiln records. Missing geometry means pins and cards still work; do not draw a straight line and present it as a driving route. Missing drive durations mean omit that figure or show the supplied ETA, rather than guessing from gaps between arrival times.
- Extend the nine-stop fixture so this UI can be reviewed. Sample access points and geometry are illustrative and must be labeled as sample data; they are not verified rural road routing. Do not claim to have obtained server road geometry unless you have.
- Make `api-contract.md` consistent with the implemented schema and keep its proposal status. List backend confirmations still needed: access points, geometry/axis order, route timing and endpoint/token configuration. Do not change evidence fields such as `footprint_px` in this phase.

## 3. Load the route and handle its states

- Use a small observable state owned by the app/Today, with explicit loading, loaded, empty, saved/offline and failure states. Consume `KilnWatchAPI.todayRoute()` when real endpoint and token configuration are supplied. Do not call the `.example` endpoint or hard-code credentials. Cognito implementation stays in Phase 5.
- With configuration unavailable, make the fixture path explicit and show the DEBUG sample-data indicator. Report that live backend verification is blocked by configuration. Do not silently replace a failed live request with fixtures or display sample records as live data.
- Save successful route responses through RouteCache and load the saved route on launch and after transport failures. Keep disk work off the main actor. Show "Offline · showing saved route" only when appropriate, plus readable saved-route age/date when it belongs to a different day. Preserve a valid cache on fetch or decoding failure.
- A confirmed `404` or successful response with no stops is the empty state: "No route planned for today" and "Plan a route", which opens Ask with a useful draft. Do not revive an old route as today's plan after an authoritative empty response. Auth/server failures need honest retry/error states; connectivity observation alone does not prove the API is reachable.
- No signal and no cache needs its own recovery state. A corrupt cache must not crash the app or touch verdict files. Use isolated storage for DEBUG simulations so they cannot overwrite the real saved route.
- Replace hard-coded Hapur, nine stops, departure time and total duration with route data. Format times in the route's district time zone (`Asia/Kolkata` for the current NCR scope). Derive totals only from available, well-defined duration fields; a budget is not a predicted duration.
- Keep selected stop separate from active/current route stop. Pin/carousel/list browsing must not silently complete an inspection or change a verdict. Start/End route and the cross-tab accessory must agree on active state and current stop. Guard empty routes, changed routes, missing kiln references and stale selections; no unchecked array indexing. Preserve active stop on returning from Maps; do not infer arrival or completion from opening Maps.

## 4. Wire Today while preserving the design

- Keep the full-bleed muted standard map, imagery toggle, regular glass navigation controls/header, solid floating cards, clay 4 pt route line and existing StopPin styling. Keep MapKit attribution and legal labels visible around overlays.
- Render valid supplied road legs with `MapPolyline`; render pins using kiln coordinates and hand off access points for driving. Do not call `MKDirections` for every leg, optimize/reorder on device, or invent a road line from centroids.
- Fit the initial camera to the actual route/pins with space for the header and carousel. A selected pin snaps the carousel; a swipe or route-list selection focuses that pin and moves the camera. Use stable IDs, avoid selection/camera feedback loops, and do not reset the camera on every location update.
- Reuse `Motion.select` and `Motion.layout`, selected-stop haptics, and Reduce Motion behavior (camera cuts and no scaling). Preserve card-to-Kiln navigation and the zoom transition. Add navigation as a distinct button rather than nesting an interactive button inside the card's NavigationLink.
- Route list, cards and the bottom accessory must use the same loaded stops, counts, ETA/durations and inspection-sheet data. Retain the accessory above the system tabs. Keep all controls reachable at large text sizes and with VoiceOver; retain the documented map-label caps and 44 pt tap targets.
- Keep the existing DEBUG launch arguments useful. Add only the deterministic scenarios needed to verify cache, missing geometry and permission/error states. All demo state and launch-argument overrides must be DEBUG-only.

## 5. Foreground location and Apple Maps

- Request When In Use permission only after an intentional location action, with a plain purpose string. No Always permission, background location capability, continuous navigation tracking or automatic permission prompt on sign-in.
- Show user location when authorized and provide a system-style recenter action. Denied/restricted access, disabled location services, approximate location, and a temporarily unavailable fix must leave route browsing and Maps handoff usable. Offer a Settings action where appropriate. Stop unnecessary updates when Today/app is inactive and handle cancellation/lifecycle using Swift 6 isolation.
- Primary action: "Navigate" for the selected/current stop opens Apple Maps driving directions from the user's location to that stop's road access point using `MKMapItem`. If no access point exists, make the fallback to the kiln location explicit before using it. Do not describe a centroid as a verified entrance.
- Secondary action in the route sheet: "Open whole route in Maps" uses Apple's Unified Maps URL with repeated waypoints and a final destination, preserving the remaining server order. Verify current official documentation/SDK behavior before implementation. Safely handle empty/single-stop routes, coordinate formatting, encoding and failed opening; keep the main one-stop flow usable if the secondary flow cannot be verified.
- Do not claim MapKit can download a basemap or access Apple Maps' offline regions. Cached linework and pins should remain useful without tiles. An offline Maps handoff may depend on the inspector's downloaded region; any copy must not promise navigation availability the app cannot detect.

## Validation and report

Run meaningful checks for the changed behavior, sequentially. Preserve existing core tests. Add focused coverage for the new/legacy route decoding and cache round trips, missing metadata, malformed geometry, unknown enums after migration, the distinction between authoritative empty and failed refresh, and navigation destination/waypoint order where pure logic permits. Use temporary directories and stubbed responses; no live credentials or network in tests. Do not add a large UI-test framework for this phase.

From the repository root:

```sh
xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build
```

From `App/Packages/KilnWatchCore`:

```sh
swift test
```

Both must pass with zero warnings. Launch the app on iPhone 17 and verify: pin ↔ carousel ↔ list sync; kiln pushes and back; Start/End/accessory across tabs; location permission/failure behavior; single-stop Maps handoff and secondary URL behavior; cached relaunch/offline; empty and failure states; missing geometry; and no regressions in the other mock screens. Clearly distinguish simulated coverage from verified system/device behavior.

Save review screenshots under `App/docs/screens/phase-2/`: Today light and dark, selected stop, route list, active accessory, loading, empty, offline saved route and large text (AX3). Include a short carousel/camera recording if tooling permits. Inspect screenshots before reporting. Exercise Reduce Motion and VoiceOver labels/actions. This is builder verification; do not invoke auditor agents.

Update HANDOVER with what changed, exact verification results and remaining backend/device limitations. Report in at most 30 lines: files/behavior, build and tests, clickable screenshot paths, research sources used, design deviations, and unresolved questions. State clearly whether data came from fixtures, cache or a configured backend and which Maps flows were actually opened. Then stop and wait for orchestrator/user review. Do not start Phase 3 or commit/push.
