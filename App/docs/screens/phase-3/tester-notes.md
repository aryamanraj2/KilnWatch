# Phase 3 tester notes — 10 October 2026

The prescribed final core suite and root iPhone 17 build passed with zero warnings.
The baseline suite reported 26 functions, including its existing opt-in skip.
The final suite reports **34 functions: 33 passed, one existing opt-in skip**.
No app, core, project or infrastructure source was edited by the tester.

The temporary XCTest project is a copy at `/tmp/KilnWatchPhase3Checks`, separate
from the untouched Phase 2 project. It references the current app/package and
absolute base configuration/Info.plist. The generated public URL was confirmed
nonempty and the district Hapur without printing deployment values. The final
UI test source is saved as [ui-checks.swift](ui-checks.swift).

## Acceptance coverage

**Eight distinct XCTest methods have passing coverage, in ten relevant passing
executions across the final transport and presentation revisions.** Four
unaffected network/fixture methods passed after fix cycle 2; six affected
executions passed after the final presentation changes: live, image fixtures,
light screenshots, dark screenshots, AX3 and AX5. Earlier unsuccessful harness
attempts are reported separately below, not counted as app failures or passes.

| Check | Result and actual coverage |
|---|---|
| Live list, reference detail, Today | Pass on the final app. Actual configured public source loads 39; search opens `KW-6b3b38da681850e5af46b024f3d3f78e`; model score displays 0.32, type unverified, evidence unpublished, rules unevaluated and population exposure unassessed. Today is launched separately, shows 39 and the route-unavailable notice; a hittable live pin opens detail. |
| Public list states | Pass: loading, empty, offline, persistent 429 plus manual Retry, 429 automatic recovery, 503 plus Retry. Deterministic isolated HTTP stubs, Sample data. |
| Detail failures and recovery | Pass: 404, offline, 503 and first-failure/manual-Retry recovery. Isolated stubs, Sample data. |
| Cancellation/backoff/Retry guard | Pass: three rapid pop/reopen loops each during the two-second delayed detail and detail-429 backoff; Retry disabled while pending, eventual detail success or bounded busy state, enabled Retry after persistent busy. |
| Fixture route regression | Pass: fixture Start route, second stop, End route and nine-stop route list remain available. Explicit fixture path. |
| Evidence fixtures | Pass: bundled synthetic 256 px loader/comparator, loading and failed states, image Retry; drag changes the accessibility divider value from 50 percent. These are synthetic local images, not published satellite evidence. |
| Required screenshots | Pass in actual system light and dark appearance; twelve final captures. |
| AX3 / AX5 / Reduce Motion | Both final runs pass. System Reduce Motion verified enabled in the runner; full row ID checked against its identifier; live detail scrolling, Today navigation without active search and reachable error Retry checked. Four captures per size. |

The accessibility text checks reject the banned app term and real-record
800 m claims, and confirm live inspection actions are absent. They do not
constitute a spoken VoiceOver or physical-device walkthrough.

## Test harness history and limits

| Run/log | Executed | Passed | Harness failures |
|---|---:|---:|---:|
| tester-ui-initial.log | 6 | 4 | 2 |
| tester-ui-cycle2.log | 7 | 6 | 1 |
| tester-ax3-prepolish.log | 1 | 1 | 0 |
| tester-ax5-prepolish.log | 1 | 1 | 0 |
| tester-ui-final-light.log | 3 | 2 | 1 |
| tester-ui-final-dark.log | 2 | 1 | 1 |
| tester-ax3-final.log | 1 | 1 | 0 |
| tester-ax5-final.log | 1 | 1 | 0 |
| tester-live-final.log | 1 | 1 | 0 |
| Total recorded executions | **23** | **18** | **5** |

One early failure used the wrong fixture badge text. Four attempts hit the
native minimized tab bar after returning to active search: absent or ghost
Today elements, including an invalid computed hit point. The intermediate
`LIVE_AFTER_SEARCH_CROSS_TAB_VERIFIED` log marker was printed before verifying
the resulting screen and **does not establish success**. This specific
cross-tab-after-search case remains unverified. Final live Today is tested by
its independent launch; both AX runs establish native cross-tab navigation
without active search. No further native-beta selector retries were made.

Failed suites emitted their exact XCTest method/suite outcomes, then Xcode
beta stalled finalizing the result bundle. They were stopped after completion;
no complete result bundle is claimed for them. Final successful AX and isolated
live runs returned `TEST SUCCEEDED` normally. Screenshots were saved directly
from XCTest to runner Documents and copied out, avoiding failed bundle export.
Temporary harness logs retain manual-build-order / missing-AppIntents metadata
warnings and beta runtime diagnostics; the prescribed root app build and core
checks have zero warnings. No non-finite/negative-frame warning was found in
final AX/live logs.

Unrun: spoken VoiceOver, physical-device testing, remote evidence images
(all current live evidence URLs are null), and an actual missing-config build.
The optional include/fallback was source reviewed. No auth, cloud command,
verdict recording, inference, training or later-phase work was performed.

## Screenshots and visual inspection

All **23 final PNGs were opened and visually inspected by the tester**.
System light/dark are visibly distinct; Live data / Sample data words are now
visible. The final Today pins are compact and substantially clearer. Large
content reflows and scrolls. At AX sizes, the Today notice is an inner scroll
area; lower content/legend is below the initial fold, not a permanent crop.

| View | Light | Dark |
|---|---|---|
| Live Kilns | [kilns-light.png](kilns-light.png) | [kilns-dark.png](kilns-dark.png) |
| Live detail top | [detail-top-light.png](detail-top-light.png) | [detail-top-dark.png](detail-top-dark.png) |
| Live detail bottom | [detail-bottom-light.png](detail-bottom-light.png) | [detail-bottom-dark.png](detail-bottom-dark.png) |
| Live Today | [today-light.png](today-light.png) | [today-dark.png](today-dark.png) |
| Stubbed 503 | [503-light.png](503-light.png) | [503-dark.png](503-dark.png) |
| Stubbed offline | [offline-light.png](offline-light.png) | [offline-dark.png](offline-dark.png) |

AX3 (light): [Kilns](kilns-ax3.png), [detail](detail-ax3.png),
[Today](today-ax3.png), [stubbed 503](503-ax3.png).
AX5 (dark): [Kilns](kilns-ax5.png), [detail](detail-ax5.png),
[Today](today-ax5.png), [stubbed 503](503-ax5.png).
Synthetic local imagery: [loaded](synthetic-evidence-loaded.png),
[loading](synthetic-evidence-loading.png), [failed](synthetic-evidence-failed.png).

**Remaining minor visual gap:** the live detail mini-map shows the location
flag but the footprint is not discernible in either detail-bottom screenshot.
`KilnView.swift:214` frames a noninteractive 2400 m map, while `:233` draws an
opaque flag marker over the small polygon at `:221`. It appears to obscure the
footprint; adjust framing/marker placement in a later authorized polish pass.
The three-fix-cycle cap was respected; no tester source fix was made.

## Preservation and privacy

Original simulator settings restored and verified: light, large, and absent
ReduceMotionEnabled override. HEAD/index and 67 protected infrastructure/model/
Phase 2 fingerprints match the orchestrator baseline. The public xcconfig is
ignored. The final tracked-plus-new-file scan found no actual deployment URL
or API identifier; expected generic deployment-domain references are confined
to existing infrastructure/docs and the authorization/config documentation.
Only intended app/core/config/docs changes appear in the diff (13 existing
tracked files: 651 insertions, 60 deletions at tester closeout, plus new files).
No staging or commit occurred. Logs and the saved UI test source were sanitized.
