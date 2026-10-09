# Prompt 02: KilnWatchCore (data contract, API client, offline outbox)

You are building the non-UI core of the KilnWatch Inspector iOS app as a local Swift package. Another agent is building the design system and the Xcode project at the same time in `KilnWatch/`. Do not touch `KilnWatch/`, `KilnWatch.xcodeproj` or `docs/DESIGN.md`. Your files are `Packages/KilnWatchCore/**` and `docs/api-contract.md`, and nothing else.

## Read first

1. `docs/concept.txt`. Read page 4 (the rules table), pages 9 and 10 (the agents, tools and guardrails), page 11 (architecture) and page 15 (**the kiln record**, which is the contract you are encoding).
2. `docs/build-plan.md`.
3. Load these skills: `axiom:axiom-data` (Codable and storage), `axiom:axiom-networking`, `axiom:axiom-concurrency` and `axiom:axiom-testing`.

Research: use WebSearch, and switch to Firecrawl when a page is gated. Use it only where a decision depends on facts you don't have, for example what date formats a PostGIS/Lambda backend typically emits.

## Build

**Package.** Create `Packages/KilnWatchCore`: one library target `KilnWatchCore` and one test target using Swift Testing. Platforms are iOS 26 and macOS 26, so `swift test` runs on the Mac. Use the Swift 6 language mode. No third-party dependencies.

**Models** (`Codable`, `Hashable`, `Sendable`). Mirror page 15 field by field:
- `Kiln`: kiln_id, footprint (an oriented polygon in latitude/longitude plus a centroid), type, type_confidence, detection_confidence, first_seen, last_seen, violations, exposure, status, evidence (before and after URLs).
- `Violation`: rule_id, measured distance in metres (optional, because C-TECH-10K has no distance), threshold, legal source, evidence link.
- `Exposure`: people within 800 m, under 5, over 60.
- `Rule`: id, check, threshold, source. Include the seven rules from page 4 as fixture data, with the UP overrides noted.
- `Stop` and `InspectionSheet`: route order, kiln_id, ETA, the rules flagged, the people exposed, and what to check on site.
- `Verdict`: a client-generated UUID (the idempotency key), kiln_id, outcome (`confirmed`, `compliant`, `not_a_kiln`, `closed`), photos (each a local file reference with latitude, longitude, horizontal accuracy and timestamp), note, recorded_at.

Enums: `KilnStatus` (`flagged`, `confirmed`, `compliant`, `not_a_kiln`, `closed`) and `KilnType` (`FCBK`, `CFCBK`, `Zigzag`). An unknown value from the server must decode into an `unknown` case and must not throw. A new backend status must never crash the app or drop a record. Wire JSON uses snake_case keys (use the decoder strategy, not CodingKeys everywhere) and ISO 8601 dates.

**Fixtures.** Package resources in `Fixtures/`: `kilns.json`, `route_today.json` and `rules.json`. Use the illustrative figures from concept page 13: KW-0412 is FCBK 0.82, 6,240 people of whom 710 are under 5, C-HAB-800 at 410 m against 800 m, UP-SCH-1K at 620 m against 1,000 m, and C-TECH-10K. KW-0388 has 4,910 people and KW-0451 has 3,120. There are nine stops across Hapur district around 28.73° N, 77.78° E, and Pilkhuwa is at about 28.71° N, 77.65° E. Expose a `Fixtures` accessor so that app previews can load them later.

**API client.** One concrete `struct KilnWatchAPI` holding a `baseURL`, a `URLSession` and an async token-provider closure. It has typed async methods for the REST endpoints in your contract. Errors are typed: transport failure, HTTP status with the body, decoding failure with the key path. Do not create a protocol for it. Tests stub the network with `URLProtocol`.

**Offline.**
- Route cache: the last fetched route and its kilns, saved as a Codable file in Application Support with atomic writes.
- Verdict outbox: an `actor`. `enqueue(_ verdict:, photos:)` copies the photo data into Application Support with file protection `.completeUntilFirstUserAuthentication` and persists the queue atomically before it returns. `flush(using api:)` sends pending verdicts in order, using the client UUID as the idempotency key. On success it removes a verdict and its photos. On failure it keeps them and records the attempt count and the last error. **No code path may delete an unsent verdict.** The app will trigger `flush` when it detects connectivity. That trigger is not your job.
- Use Codable files plus atomic writes. If you find a concrete reason that SwiftData is needed, say so in your report. Do not reach for it by default.

**Contract document.** `docs/api-contract.md` is a **proposal for the backend owner to confirm**. Include:
- The endpoints: list kilns (filtered by district and status), get one kiln, today's route, the rules, and post a verdict (with an idempotency header).
- Their request and response JSON, with fixtures as the examples.
- Auth, which is a Cognito JWT bearer token.
- Error shape.

Mark the agent stream endpoint "TBD, see docs/research/agent-streaming.md", because a parallel research agent owns that. Use Verified Permissions semantics from page 10: residents read public fields, an inspector records verdicts only in their own district, and agents never record verdicts.

## Tests (one file is fine; these are the checks that matter)

- Every fixture decodes, and a Kiln round-trips through encode and decode unchanged.
- An unknown `status` value and an unknown `type` value both decode to `unknown`.
- The client maps a 4xx and a 5xx to typed errors, and a malformed body to a decoding error that names the key.
- Outbox: enqueue, then a flush that fails, leaves the verdict and its photos on disk with `attempts == 1`. Enqueue, then a flush that succeeds, removes both. A crash simulated after enqueue (re-instantiating the actor from disk) recovers the queue.

`swift test` must pass with zero warnings.

## Done means

- The package builds and `swift test` passes on macOS.
- `docs/api-contract.md` is written.
- Report back in at most 30 lines: the files, the test results, any contract assumptions the backend owner must confirm, and anything you deliberately did not build. Do not commit.
