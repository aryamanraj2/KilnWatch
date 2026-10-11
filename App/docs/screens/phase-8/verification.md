# Prompt 43 iOS local verification — 11 October 2026

The iOS lane is complete locally. Backend deployment and the live-read screenshot remain pending; this verification used a DEBUG URLProtocol stub only. The app has no request submission action.

- Core: prescribed `swift test` reports 103 tests, with one existing opt-in skip and zero warnings. Four new tests cover the shared recorded response, legacy absence/null, authoritative zero through list/route caches, and malformed aggregate rejection. The `within_1km` key retains its exact spelling when cached.
- App: prescribed root `xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeds with zero warnings.
- Screens: iPhone 17, light mode, standard large text. Both PNGs were visually reviewed. Request text and figures are neutral ink; the section follows population exposure. No dark or accessibility-size matrix was run.
- Fixture: app and core copies match the portal's shared synthetic response byte for byte.
- No live API/CDN calls, AWS tools, deployment, staging, commits or push were performed by this lane.

## Screenshots

- `resident-requests-detail-light.png`: 12 inspection requests; self-reported within-1-km count; four concerns with counts; 11 Oct date; anonymous/unverified wording and inspection/status limits.
- `resident-requests-list-light.png`: filtered synthetic kiln row showing 12 requests in secondary ink.

DEBUG setup: `-publicDemo loaded -rulesDemo recorded -requestsDemo recorded -readOnly YES -tab kilns`; detail adds `-open KW-0123456789abcdef0123456789abcdef -scroll requests`, list adds `-query 012345`. `-requestsDemo zero` provides authoritative zero. These hooks intercept the public client and keep the existing Sample data label.

## Live follow-up (43b)

`resident-requests-live-43b.png`: same real kiln as the lead's single request check;
live configuration, read-only launch, count 1, concerns and IST date verified visually.
The test request was subsequently reset to zero. No additional request or verdict sent.
