# Prompt 43 lead report — 11 October 2026

**Implementation and deployment complete; see Deploy (43b) below.**

Historical 43 stop:
The existing verdicts invocation permission covers only its original route. Requests need
a separate exact invocation permission, which prompt 43 omitted from its expected changes.
The user declined that scope extension and selected stop before deployment. The prepared
source includes the needed permission for review; it has not been applied.

The lead froze the contract and identical synthetic fixtures before spawning the two client
agents. The lead owned contract/AWS/integration/report; **P** owned portal code and Playwright;
**I** owned iOS/core, Xcode and Simulator. Neither client agent used AWS or the live API/CDN.
No additional agent ran. No files were staged, committed or pushed.

## Lane results

| Lane | Delivered | Verification |
|---|---|---|
| Lead: AWS and contract | Migration 004; request dispatch/validation; atomic insert, dedupe and UTC cap; allowlisted public aggregates; operator reset; Terraform gate/throttle/exact permission; packages; tests and operator documentation | Standard suite: **238 run, 216 passed, 22 skipped**. Disposable PostGIS: **238 run, 238 passed, 0 skipped**. **27 new tests**, six database-only. Terraform format/validate and whitespace pass; zero Terraform warnings. |
| P: portal | English/Hindi request form; browser UUID and sent-date storage; fresh count propagation; duplicate acknowledgment; retained answers on error; sample flow; secondary written draft; neutral copy; docs/tests | Typecheck/build pass; **92 unit/behavior tests**, **15 mocked live Chromium journeys**, **10 sample Chromium journeys** pass. Five light screenshots reviewed. |
| I: inspector app | Optional aggregate decoding and cache spelling; neutral detail section after exposure; positive list counts; honest unavailable/zero states; shared stub; docs/tests | **103 core tests reported: 102 passed, one existing opt-in skip**. Prescribed iPhone 17 build succeeds. Core/build zero warnings. Two light stub screenshots reviewed. |

## Database and deployment record

Both required AWS profiles verified with masked output; the main profile matched the required
user suffix. No sign-in was attempted.

**Local database proof only:** migration replay, exact writer/reader grants and existing-login
membership passed. The request role cannot update candidates or delete requests; the reader
cannot read client hashes, language or row IDs. Real SQL proved 201 insertion, 200 dedupe,
unknown records not counted, concurrent duplicate insertion and a global 300 cap, IST date
rollover, district/nearby/detail reads with both include modes, authoritative zeros, unchanged
candidate checksum, and reset retaining the day counter. The local test server was stopped.
An operator reset in a rolled-back runner test must return to administrative privileges first,
because the request writer deliberately lacks DELETE.

**Runner migration/checks: not run. Targeted plan/apply: not run.** No ignored tfvars were
changed to enable requests. The proposed deployment needs two additions (route and exact
requests invocation permission), plus the two Lambda code updates and stage throttle; this
is a proposal, not a checked plan. It reuses the verdicts integration, login and secret.
A renewed go must expressly include the additional permission, followed by saved-plan review.

**Live checks, hosted portal upload/invalidation, iOS live screenshot and final request reset:
not run.** No real request was inserted, so there was no live request to clean up. Ask and
route planning were neither called nor redeployed. Their source, CDN configuration and provider
lock remain unchanged. The contract remains marked deployment-pending, not live.

Prepared local ZIP SHA-256 (no live CodeSha256 comparison was performed):

- `api_handler`: `328892cbeff8dd97214e280f76c480e1b0f43a3f2be99ce39439fc1610dfda10`
- `verdicts`: `793c9f998ac36fbb79cb3b060f765eb5bf8d7c86427acf1dabfc43f480d95ea9`

## Screenshots

Portal, 390 px phone width plus desktop:

- [phone-form-en.png](../../Web/ResidentPortal/docs/screens/requests/phone-form-en.png)
- [phone-form-send-en.png](../../Web/ResidentPortal/docs/screens/requests/phone-form-send-en.png)
- [phone-confirmation-en.png](../../Web/ResidentPortal/docs/screens/requests/phone-confirmation-en.png)
- [phone-form-hi.png](../../Web/ResidentPortal/docs/screens/requests/phone-form-hi.png)
- [desktop-record-en.png](../../Web/ResidentPortal/docs/screens/requests/desktop-record-en.png)

Inspector app, light iPhone 17 stubs:

- [resident-requests-detail-light.png](../../App/docs/screens/phase-8/resident-requests-detail-light.png)
- [resident-requests-list-light.png](../../App/docs/screens/phase-8/resident-requests-list-light.png)

Phone send-button clearance above the sticky bar is asserted by the browser test. Full portal
panel captures temporarily hide fixed navigation only while capturing; the lower-form viewport
shows actual fixed bars. No dark/accessibility matrix or WebKit run was requested/performed.

## Privacy and open limits

Final scan of every changed/untracked text file against private identifiers from local outputs,
plans and tfvars: **0 private matches**. A public project-name prefix is not a private resource
name. Product-source/public-asset banned-word scans: **0 matches**. Provider-lock diff is clean;
shared app/core/portal request fixture bytes match. Whitespace check passes.

Requests are anonymous and unverified, capped at 300 new requests per UTC day, deduplicated by
browser code per kiln. Clearing storage allows more requests; denied storage preserves browser
identity only within the current document. Requests never change kiln status/review state or
guarantee inspection. No sign-in or route priority is implemented. Public counts can lag about
two minutes. Native Hindi review and production/live verification remain outstanding.

## Changed files by lane

The user's pre-existing untracked prompt 43 is an input and is excluded from this inventory.
The shared fixtures were created by the lead before lane work and are listed with their clients.

### Lead: contract, AWS, docs

- [AWS/api.tf](../../AWS/api.tf)
- [AWS/docs/first-record-runbook.md](../../AWS/docs/first-record-runbook.md)
- [AWS/docs/inspection-requests-report.md](../../AWS/docs/inspection-requests-report.md)
- [AWS/docs/local-verification.md](../../AWS/docs/local-verification.md)
- [AWS/lambda/api_handler.py](../../AWS/lambda/api_handler.py)
- [AWS/migrations/004_requests.sql](../../AWS/migrations/004_requests.sql)
- [AWS/registry/cli.py](../../AWS/registry/cli.py)
- [AWS/registry/contract.py](../../AWS/registry/contract.py)
- [AWS/registry/requests.py](../../AWS/registry/requests.py)
- [AWS/registry/store.py](../../AWS/registry/store.py)
- [AWS/scripts/package_api.py](../../AWS/scripts/package_api.py)
- [AWS/scripts/package_verdicts.py](../../AWS/scripts/package_verdicts.py)
- [AWS/tests/test_requests.py](../../AWS/tests/test_requests.py)
- [AWS/verdicts.tf](../../AWS/verdicts.tf)
- [AWS/verdicts/handler.py](../../AWS/verdicts/handler.py)
- [AWS/verdicts/requests.py](../../AWS/verdicts/requests.py)
- [App/docs/api-contract.md](../../App/docs/api-contract.md)

### P: portal

- [Web/ResidentPortal/README.md](../../Web/ResidentPortal/README.md)
- [Web/ResidentPortal/docs/DESIGN.md](../../Web/ResidentPortal/docs/DESIGN.md)
- [Web/ResidentPortal/docs/HANDOVER.md](../../Web/ResidentPortal/docs/HANDOVER.md)
- [Web/ResidentPortal/docs/screens/requests/README.md](../../Web/ResidentPortal/docs/screens/requests/README.md)
- [Web/ResidentPortal/docs/screens/requests/desktop-record-en.png](../../Web/ResidentPortal/docs/screens/requests/desktop-record-en.png)
- [Web/ResidentPortal/docs/screens/requests/phone-confirmation-en.png](../../Web/ResidentPortal/docs/screens/requests/phone-confirmation-en.png)
- [Web/ResidentPortal/docs/screens/requests/phone-form-en.png](../../Web/ResidentPortal/docs/screens/requests/phone-form-en.png)
- [Web/ResidentPortal/docs/screens/requests/phone-form-hi.png](../../Web/ResidentPortal/docs/screens/requests/phone-form-hi.png)
- [Web/ResidentPortal/docs/screens/requests/phone-form-send-en.png](../../Web/ResidentPortal/docs/screens/requests/phone-form-send-en.png)
- [Web/ResidentPortal/src/components/shared.tsx](../../Web/ResidentPortal/src/components/shared.tsx)
- [Web/ResidentPortal/src/data/client.ts](../../Web/ResidentPortal/src/data/client.ts)
- [Web/ResidentPortal/src/data/fixtures.ts](../../Web/ResidentPortal/src/data/fixtures.ts)
- [Web/ResidentPortal/src/data/live.ts](../../Web/ResidentPortal/src/data/live.ts)
- [Web/ResidentPortal/src/data/model.ts](../../Web/ResidentPortal/src/data/model.ts)
- [Web/ResidentPortal/src/data/requests.ts](../../Web/ResidentPortal/src/data/requests.ts)
- [Web/ResidentPortal/src/features/InfoPage.tsx](../../Web/ResidentPortal/src/features/InfoPage.tsx)
- [Web/ResidentPortal/src/features/area/AreaPage.tsx](../../Web/ResidentPortal/src/features/area/AreaPage.tsx)
- [Web/ResidentPortal/src/features/complaint/draft.ts](../../Web/ResidentPortal/src/features/complaint/draft.ts)
- [Web/ResidentPortal/src/features/evidence/Evidence.tsx](../../Web/ResidentPortal/src/features/evidence/Evidence.tsx)
- [Web/ResidentPortal/src/features/records/RecordPages.tsx](../../Web/ResidentPortal/src/features/records/RecordPages.tsx)
- [Web/ResidentPortal/src/features/requests/InspectionRequest.tsx](../../Web/ResidentPortal/src/features/requests/InspectionRequest.tsx)
- [Web/ResidentPortal/src/styles/global.css](../../Web/ResidentPortal/src/styles/global.css)
- [Web/ResidentPortal/tests/behavior.test.tsx](../../Web/ResidentPortal/tests/behavior.test.tsx)
- [Web/ResidentPortal/tests/browser/live.spec.ts](../../Web/ResidentPortal/tests/browser/live.spec.ts)
- [Web/ResidentPortal/tests/browser/portal.spec.ts](../../Web/ResidentPortal/tests/browser/portal.spec.ts)
- [Web/ResidentPortal/tests/fixtures/requests-recorded.json](../../Web/ResidentPortal/tests/fixtures/requests-recorded.json)
- [Web/ResidentPortal/tests/requests.test.ts](../../Web/ResidentPortal/tests/requests.test.ts)

### I: iOS/core/docs

- [App/KilnWatch/Features/Kiln/KilnView.swift](../../App/KilnWatch/Features/Kiln/KilnView.swift)
- [App/KilnWatch/Features/Kiln/ResidentRequestsBlock.swift](../../App/KilnWatch/Features/Kiln/ResidentRequestsBlock.swift)
- [App/KilnWatch/Features/Kilns/KilnsView.swift](../../App/KilnWatch/Features/Kilns/KilnsView.swift)
- [App/KilnWatch/Mock/PublicDemo.swift](../../App/KilnWatch/Mock/PublicDemo.swift)
- [App/KilnWatch/Mock/RequestsRecorded.json](../../App/KilnWatch/Mock/RequestsRecorded.json)
- [App/Packages/KilnWatchCore/Package.swift](../../App/Packages/KilnWatchCore/Package.swift)
- [App/Packages/KilnWatchCore/Sources/KilnWatchCore/Models.swift](../../App/Packages/KilnWatchCore/Sources/KilnWatchCore/Models.swift)
- [App/Packages/KilnWatchCore/Sources/KilnWatchCore/ResidentRequests.swift](../../App/Packages/KilnWatchCore/Sources/KilnWatchCore/ResidentRequests.swift)
- [App/Packages/KilnWatchCore/Tests/KilnWatchCoreTests/RequestFixtures/requests-recorded.json](../../App/Packages/KilnWatchCore/Tests/KilnWatchCoreTests/RequestFixtures/requests-recorded.json)
- [App/Packages/KilnWatchCore/Tests/KilnWatchCoreTests/ResidentRequestsTests.swift](../../App/Packages/KilnWatchCore/Tests/KilnWatchCoreTests/ResidentRequestsTests.swift)
- [App/docs/DESIGN.md](../../App/docs/DESIGN.md)
- [App/docs/HANDOVER.md](../../App/docs/HANDOVER.md)
- [App/docs/screens/phase-8/resident-requests-detail-light.png](../../App/docs/screens/phase-8/resident-requests-detail-light.png)
- [App/docs/screens/phase-8/resident-requests-list-light.png](../../App/docs/screens/phase-8/resident-requests-list-light.png)
- [App/docs/screens/phase-8/verification.md](../../App/docs/screens/phase-8/verification.md)


## Deploy (43b) — 11 October 2026

Completed by the lead sequentially, with **no sub-agents**. Prompt 43b explicitly added
the requests invocation permission and authorized this deployment. Both AWS sessions
verified with masked identities and the required main-user suffix.

- **Runner:** migration 004 applied and replay checked, exact grants and existing-login
  membership verified. All 39 candidate rows retain the same checksum. The writer-role
  insert, duplicate, aggregate, admin-role reset and rollback passed; request rows and
  daily counter were empty afterwards. Invalid-body/unknown-record live probes were then
  checked read-only on the runner: both request rows and daily counter remained zero.
- **Saved targeted plan and apply:** exactly **2 added, 3 changed in place, 0 destroyed**.
  Additions: requests route and exact POST requests invocation permission. Changes: API
  and verdicts Lambda code, and the requests stage throttle (1/s, burst 2). Existing verdicts
  permission/integration unchanged. No replacement or out-of-scope action. Plan SHA-256:
  `0612b912ed364b7292dae4eb379599648084214df8c5f8404c4a6560ca624145`.
- **Code hashes:** live CodeSha256 values matched both previously reported ZIP hashes;
  current source and ZIP contents matched, so no rebuild was necessary. Ask and route
  Lambda code hashes, update times and revision IDs match their pre-deploy snapshots;
  neither was called or redeployed.
- **Live:** bad body 400; unknown full ID 404 and not counted. One real flagged-record
  request returned 201 with count 1; exact duplicate returned 200, created false, count
  still 1. Detail showed 1; default list retained 38 flagged records and inspected list
  39 records, both with aggregates. Portal-origin preflight returned 204 with POST and
  content-type allowed.
- **Portal:** live production build passed using ignored config/dist. One two-pass upload:
  5 asset uploads/4 obsolete asset deletions,
  4 root-file uploads/0 root deletions;
  9 resulting files, 846327 bytes. Assets immutable for one year;
  root files no-cache. One `/*` invalidation completed. Hosted Chromium at 390 px showed
  the button and count 1; no write requests, page errors or CORS errors.
- **iOS:** installed app configuration matched the live API. Read-only launch disabled
  outbox delivery and opened the same kiln; the neutral requests section showed 1,
  concerns 1/1/0/0, within-1-km count 1 and 11 Oct. Screenshot visually reviewed. AXe's
  UI-tree helper could not load a relocated beta framework; the normal app launch and
  native simulator screenshot succeeded. No product-code change was needed.

Live captures before cleanup:

- [Hosted phone record](../../Web/ResidentPortal/docs/screens/requests/phone-record-live-43b.png)
- [Inspector live detail](../../App/docs/screens/phase-8/resident-requests-live-43b.png)

Cleanup and final leak results are recorded below.
The limits remain anonymous/unverified signals, 300 new requests per UTC day,
browser-code dedupe with storage-clearing limitations, no sign-in and no route priority.
No staging, commit or push.

Final cleanup: operator `reset-requests` completed for the sole live-check kiln.
Request rows are **0**, its public aggregate is the complete authoritative zero shape,
and the daily counter remains **1** as designed. All 39 candidate rows retain the baseline
checksum. The demo starts at zero requests. Final changed-file private-identifier scan:
**0 matches**; product-source banned-word scan **0**; provider lock unchanged; whitespace
check passed; index untouched. The contract is marked live dated 11 October 2026.

## 43c — portal copy fixes, 11 October 2026

- **Diff:** the shared area/record count now says “1 inspection request”; both new-request
  and returning-browser confirmations say “1 resident has asked”. Counts such as 12
  retain their plural forms; Hindi count copy is unchanged. The sticky action now
  subscribes to this browser's sent state and shows “View your request” / “अपना अनुरोध देखें”
  after acknowledgement and on reload, linking to the request card. Before sending,
  its original label and form-opening behavior remain.
- **Checks:** typecheck passed; **96 unit tests passed**, including four count-1/count-12
  component cases covering send and revisit; build passed; **15 mocked Chromium live-mode
  checks passed**, including English/Hindi sticky labels and the scroll destination.
  An initial desktop assertion was corrected to inspect the phone-only bar's markup.
- **Upload:** both AWS sessions verified with identities masked. One production upload
  used the ignored production configuration and ignored build directory: 5 asset uploads,
  3 obsolete asset deletions, 4 root-file uploads and 0 root deletions; 9 files,
  846454 bytes. Assets have one-year immutable caching and root files have no-cache.
  One `/*` invalidation completed. No other AWS change.
- **Hosted check:** Chromium at **390 × 844** loaded the updated bundle containing both
  fixes, showed the unsent request card and sticky action at zero requests, and recorded
  **0 write requests**, page errors or CORS errors. No live API POST was made. Screenshot
  visually reviewed: [390 px record page](../../Web/ResidentPortal/docs/screens/requests/phone-record-live-43c.png).
- **Leak check:** changed/untracked-file private-identifier scan **0 matches**; product
  source banned-word scan **0**; whitespace check passed; provider lock unchanged and
  index untouched. No sub-agents, staging, commit or push.
