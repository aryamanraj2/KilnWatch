# Phase 3 builder notes

Five milestones were implemented sequentially. Each prescribed core test and
root iPhone 17 build completed with zero compiler warnings. M1/M2 reported 32
Swift Testing functions; M3/M4/M5 report 33, including the original opt-in local
contract test that is skipped without its environment input. The original suite
reported 26. The extra image test loads a synthetic 256 × 256 PNG through the
same local-file loader used by the app and rejects invalid PNG data.

No Simulator launch or screenshot verification was done by the builder; the
sequential tester owns that work. Sanitized milestone logs are beside this note.
No CloudFront work or live image fetch was attempted. Five public GETs captured
small response bodies; these fixtures include public Earth Search source URLs
but no deployment or account identifiers. Actual reference candidate score is
0.324 (displayed rounded to two decimals); both evidence URLs are null.

## Deterministic DEBUG hooks

- Live run: ordinary launch, optionally `-tab kilns` or `-open
  KW-6b3b38da681850e5af46b024f3d3f78e`.
- `-publicDemo loading|loaded|empty|offline|429|429Recovery|503`: isolated
  synthetic HTTP responses. The 11 fixture records are stripped of assessments
  and labelled Sample data. `429` persists after one backoff; `429Recovery`
  succeeds on its second list attempt.
- `-publicDetail offline|503|404|429|slow|recovery` with `-publicDemo loaded`: detail-only
  failures. `recovery` fails its first detail read and succeeds after Retry.
- `-evidenceFixture loaded|loading|failed` with `-publicDemo loaded -open KW-0412`:
  deterministic synthetic local image states. The loaded case reads the bundled
  256 px PNGs through the production evidence loader and comparator. It says
  Synthetic local image fixture · not satellite evidence. The hook is ignored
  for actual live records. Image loading/failed hooks stay in those states;
  retries in the failed hook intentionally remain failed.
- `-fixtures YES -signedIn YES`: preserve the Phase 2 route/list/detail/Ask demo,
  with its existing `-demo` arguments. Public records cannot record a verdict.
- Existing `-scroll rules|exposure|map|checks` still works. Reduced Motion skips
  the camera and DEBUG scrolling animation. Map labels/navigation cap at the
  design's map sizes; list, detail and state content scale freely.

Accessibility identifiers: `kiln-row-<full ID>`, `kiln-pin-<full ID>`,
`public-kiln-map`, `satellite-comparator`. The full ID is available to VoiceOver
when its visible list label is abbreviated.

## Temporary UI project configuration

When a temporary test project lives outside this repository, use the app's
absolute `App/Config/Base.xcconfig` file reference and override `INFOPLIST_FILE`
to the absolute path of `App/Config/PublicInfo.plist`. The built app must contain
nonempty `KilnWatchPublicAPIURL` and `KilnWatchDistrict = Hapur`; check presence
without printing the URL. The public URL exists only in ignored
`App/Config/Public.xcconfig`. The optional include supports a checkout without it.

## Design references

The pixel renderer follows Apple's [no interpolation API](https://developer.apple.com/documentation/swiftui/image/interpolation/none).
Semantic fonts, full accessibility labels and reflow follow Apple's
[accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility).
DESIGN.md tokens, card surfaces and navigation-only regular glass are retained.

## Review fix cycle 1

The detail Retry button now observes the per-record in-flight flag and stays
disabled through loading and the automatic 429 backoff. Repeated taps therefore
cannot cancel and replace a request while its loading guard is held. Core tests
again reported 33 functions (32 passed, one existing opt-in skip), and the root
build passed; both had zero warnings. No other review changes were requested.

View cancellation releases the per-record flag in defer. A rapid pop and reopen
can start the replacement view task before the cancelled request releases its
guard; in that case the new task returns and Retry becomes available after the
old task finishes cancellation. The tester should exercise that timing. No
additional task ownership or cancellation architecture was added for this case.

## Review fix cycle 2

Public registry configuration now uses a dedicated ephemeral URLSession with
URLCache, cookie storage and credential storage disabled. Both the session and
every public request bypass local caches. Protected session construction and
its environment/token path are unchanged. This follows Apple's
[URL cache configuration](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/urlcache)
and [cache behavior guidance](https://developer.apple.com/documentation/foundation/accessing-cached-data).
The regression test checks the stateless session configuration, while all three
public URLProtocol request tests check cache policy; transport remains a typed
error. No seeded-cache custom-protocol behavior is claimed.

Cancelled public loads now end in Loading interrupted with an enabled Retry
after the existing defer releases the in-flight flag. A rapid replacement view
may still meet that guard, but it then sees a recoverable interrupted state
instead of an indefinitely spinning load. The DEBUG-only detail slow hook delays
its response by two seconds; detail 429 exercises the single backoff and disabled
Retry. The delayed protocol's only mutable field is a mutex-protected cancellation
bit; immutable request/client callbacks permit its Sendable conformance.

Core tests report 34 functions (33 passed, one existing opt-in contract skip);
the final prescribed root build and core checks have zero warnings. Tester UI
verification of these new hooks remains pending.

## Final review fix cycle 3

Data-source indicators now contain explicit image and text views, so navigation
toolbars cannot reduce them to an icon-only Label. The words Live data or Sample
data remain visible, with the navigation text cap and an intrinsic chip size.
Today markers now use a compact 32 pt flag disc on a solid surface inside a
transparent 44 pt button target. The detailed status legend remains, and each
marker preserves its full ID, exact status accessibility label and identifier.

The detail ID inserts display-only zero-width wrap opportunities between its
characters, preventing automatic discretionary hyphens from looking like part
of the ID. Its explicit accessibility label retains the original unmodified ID.
Core tests again report 34 functions (33 passed, one existing opt-in contract
skip); the root build passes, both with zero warnings. Visual confirmation of
these final changes belongs to the tester. This is the third and final source
fix cycle; no further builder changes are planned for this overnight run.
