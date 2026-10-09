# Phase 2 verification — 2026-10-09

Branch: PortalAPP. iOS 27 SDK, deployment target 27.0. No commit, push, parallel agents or Phase 3 work.

- Prescribed root Xcode build: passed, zero warnings/errors. See `build.log`.
- KilnWatchCore `swift test`: 21 tests passed, zero warnings/errors. See `core-tests.log`.
- Six UI checks passed sequentially on iPhone 17 / iOS 27, using a small temporary XCTest target outside the repository.
- Route interactions: pins ↔ carousel ↔ list, kiln push/back, Start/End and cross-tab accessory.
- Maps: both MKMapItem single-stop and Unified Maps URL whole-route actions opened Apple Maps; active stop was preserved. Successful directions/waypoint rendering were not established beyond Maps launch/permission UI.
- Location: no initial app permission prompt; intentional request, denied alert/Settings and granted simulated GPS fix with My Location annotation. Navigation remained reachable.
- Recovery simulations: loading, empty → prefilled Ask, service failure, no cache, corrupt cache, offline cache, cached relaunch, missing geometry. Unknown kiln, rule sheet and verdict mock navigation passed.
- AX3: location/Navigate/Start/End/list selection remained reachable; system Reduce Motion was confirmed enabled. No frame warning after the carousel initial-width correction.
- Accessibility labels/actions were read and exercised; no spoken VoiceOver or physical-device walkthrough.
- UI details: `ui-tests.log`, `recovery-tests.log`, `accessibility-tests.log`. Xcode 27 beta tool/runtime diagnostics in those logs do not affect the zero-warning app/core builds.

All displayed routes came from shared fixtures or an isolated saved fixture cache. Stubbed transport tests verified cache semantics; no configured live backend was exercised.

Reviewed existing screenshots: [selected stop](selected-stop.png), [route list](route-list.png), [active accessory](active-accessory.png). Further screenshot/recording work was skipped at the user's request.

Backend confirmations: real endpoint/token, access points, geometry/axis order, timing and error semantics. Device follow-up: approximate/restricted/off services, no-fix conditions and successful/offline Maps guidance.

Sources used: [Unified Maps URLs](https://developer.apple.com/documentation/mapkit/unified-map-urls), [MKMapItem handoff](https://developer.apple.com/documentation/mapkit/mkmapitem/openinmaps(launchoptions:)), [one-shot location](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation()). See the routing research and API proposal for details.
