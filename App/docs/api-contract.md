# KilnWatch API contract (proposal)

**Status: proposal from the iOS team for the backend owner to confirm.** Everything here is what `Packages/KilnWatchCore` already encodes and decodes. Change requests are welcome; the open questions are listed at the end.

The examples come from the fixtures in `Packages/KilnWatchCore/Sources/KilnWatchCore/Fixtures/` (`kilns.json`, `route_today.json`, `rules.json`), which are full, valid responses. Kiln IDs, distances and counts are illustrative (concept p.13).

## Conventions

- **Base URL:** `https://api.kilnwatch.example` (API Gateway + Lambda). All paths below are relative to it.
- **JSON keys:** `snake_case`.
- **Dates:** RFC 3339 / ISO 8601 date-time **with an offset** (`Z` or `+05:30`), with `T` as the separator. Fractional seconds are optional and may vary inside one payload. PostgreSQL `to_json(timestamptz)` already emits this. Please don't use Python `str(datetime)` (space separator) or `timestamp without time zone` (no offset): the client rejects both.
- **Distances:** metres, as numbers. Keys end in `_m`.
- **Coordinates:** `{"latitude": 28.7158, "longitude": 77.6561}` objects, WGS 84. We avoid GeoJSON `[lon, lat]` arrays because the axis order is easy to swap by mistake.
- **Optional fields** may be `null` or left out.
- **Forward compatibility:** the client ignores unknown keys. An unknown `status` or `type` value decodes to an "unknown" case, keeps the record and is shown as-is. New fields and new enum values are therefore non-breaking. Renaming or removing a field is breaking.
- **Envelopes:** list endpoints return an object (`{"kilns": [...]}`), not a bare array, so that a `next_cursor` can be added later without breaking clients.

## Auth

**User decision: sign-in is deferred for the demo.** The public reads, Ask and route
planner require no login. V1 `POST /verdicts` is live (2026-10-11) as a public demo route,
with no authorizer, no district scope and no required token. An `Authorization`
header is ignored. See the V1 verification entry for deployment checks.

The existing `/kilns` and `/kilns/{id}` inspector reads still require a Cognito ID
token and enforce inspector group/district claims. They are unchanged. Cognito
sign-in and district-scoped verdict authorization remain deferred proposals.
Agents can read through their existing tools; there is no verdict-writing tool,
and there must never be one.

## Errors

Any non-2xx response has this body:

```json
{ "error": { "code": "forbidden_district", "message": "KW-0412 is not in your district." } }
```

`code` is a stable machine string and `message` is human-readable English. The client keeps the raw body together with the status code.

| Status | Meaning | What the offline outbox does |
|---|---|---|
| 400 / 422 | Request fails validation | Keeps the verdict, records the error, moves on to the next one |
| 401 | Token missing or expired | Keeps the verdict and stops the flush (systemic) |
| 403 | Verified Permissions denied, for example another district | Keeps the verdict, records the error, moves on |
| 404 | Unknown kiln_id | Keeps the verdict, records the error, moves on |
| 409 | Same Idempotency-Key with a different body | Keeps the verdict, records the error, moves on |
| 408 / 429 / 5xx | Transient | Keeps the verdict and stops the flush; it retries on the next connectivity trigger |

The outbox never deletes a verdict the server has not accepted.

## Endpoints

### GET /kilns?district={district}&status={status}

Lists the kilns in a district. `district` is required (for example `Hapur`). `status` is optional and takes one of `flagged`, `confirmed`, `compliant`, `not_a_kiln` or `closed`. Integration 1 uses keyset pagination; see the implemented extension below.

`200`: `{"kilns": [Kiln, ...]}`. Full example: `kilns.json`.

### GET /kilns/{kiln_id}

`200`: one `Kiln`. `404` if the ID is unknown.

**Kiln** (concept p.15):

```json
{
  "kiln_id": "KW-0412",
  "footprint": {
    "polygon": [
      { "latitude": 28.715238, "longitude": 77.655655 },
      { "latitude": 28.715905, "longitude": 77.656871 },
      { "latitude": 28.716362, "longitude": 77.656545 },
      { "latitude": 28.715695, "longitude": 77.655329 }
    ],
    "centroid": { "latitude": 28.7158, "longitude": 77.6561 }
  },
  "type": "FCBK",
  "type_confidence": 0.82,
  "detection_confidence": 0.94,
  "first_seen": "2023-11-14T05:21:39Z",
  "last_seen": "2026-10-04T05:31:41Z",
  "violations": [
    { "rule_id": "C-HAB-800", "measured_distance_m": 410, "threshold_m": 800,
      "source": "Central 2022 rules; UP siting rules (2026 amendment)",
      "evidence_url": "https://cdn.kilnwatch.example/evidence/KW-0412/C-HAB-800.png" },
    { "rule_id": "UP-SCH-1K", "measured_distance_m": 620, "threshold_m": 1000,
      "source": "UP siting rules (2012)",
      "evidence_url": "https://cdn.kilnwatch.example/evidence/KW-0412/UP-SCH-1K.png" },
    { "rule_id": "C-TECH-10K", "measured_distance_m": null, "threshold_m": null,
      "source": "Central 2022 rules",
      "evidence_url": "https://cdn.kilnwatch.example/evidence/KW-0412/C-TECH-10K.png" }
  ],
  "exposure": { "people": 6240, "children_under_five": 710, "adults_over_sixty": 540 },
  "status": "flagged",
  "evidence": {
    "before": "https://cdn.kilnwatch.example/evidence/KW-0412/2024-01.png",
    "after": "https://cdn.kilnwatch.example/evidence/KW-0412/2026-10.png"
  }
}
```

| Field | Notes |
|---|---|
| `district` | Optional district name; absent in older records. Display metadata only, never client authorization |
| `violations[].measured_to` | Optional `{ "latitude": Double, "longitude": Double }` feature coordinate; hide feature markers when absent. Fixture values are illustrative |
| `footprint.polygon` | The four corners of the oriented bounding box, in order, with the ring not closed |
| `type` | `FCBK`, `CFCBK` or `Zigzag` (exact case) |
| `first_seen`, `last_seen` | Acquisition times of the first and latest scenes with a detection |
| `violations[].measured_distance_m` | `null` for technology rules (C-TECH-10K) |
| `violations[].evidence_url` | Optional: `null` until an evidence image for that measurement is published. The measurement stands without it |
| `violations[].threshold_m` | The threshold actually applied, after any state override. `null` for technology rules |
| `exposure` | People within 800 m of the footprint (HRSL), with the under-5 and over-60 layers |
| `status` | `flagged`, `confirmed`, `compliant`, `not_a_kiln` or `closed`. Changes only through a verdict or an approved review |
| `evidence` | CloudFront URLs of the before and after Sentinel-2 patches |

### GET /routes/today

Returns the signed-in inspector's route for today, as produced by the planner agent. The response embeds full kiln records so that the app can cache the whole day for offline use. `404` means no route is planned. Full example: `route_today.json` (Hapur, 9 stops).

```json
{
  "district": "Hapur",
  "generated_at": "2026-10-09T16:42:10.513Z",
  "stops": [
    {
      "order": 1,
      "kiln_id": "KW-0412",
      "eta": "2026-10-10T09:40:00+05:30",
      "sheet": {
        "rules_flagged": ["C-HAB-800", "UP-SCH-1K", "C-TECH-10K"],
        "people_exposed": 6240,
        "on_site_checks": ["Distance to the nearest home", "Distance to the school gate",
                           "Chimney type: fixed chimney or zigzag", "Fuel on site", "Is the kiln firing?"]
      }
    }
  ],
  "kilns": [ { "kiln_id": "KW-0412", "...": "full Kiln as above" } ]
}
```

`order` is 1-based. Every `stops[].kiln_id` must have a matching entry in `kilns`. The app follows this server order. Missing records are reported and excluded from browsing/navigation, never substituted.

Phase 2 optional additions (all absent in Phase 1 routes, which still decode):

| Key | Type and meaning |
|---|---|
| `route_id` | Optional string identity for the plan |
| `depart` | Optional RFC 3339 departure time; rendered in Asia/Kolkata for current NCR scope |
| `budget_min` | Optional integer planning limit; never displayed as predicted duration |
| `stops[].service_min` | Optional nonnegative integer on-site duration, minutes |
| `stops[].access` | Optional `{ "lat": Double, "lon": Double, "note": String? }` road access point. This compact form applies only to access, unlike record coordinate objects |
| `legs` | Optional array of legs in server order |
| `legs[].to_kiln_id` | Destination stop ID; one driving leg per stop, including the office-to-first-stop leg |
| `legs[].distance_m` | Optional nonnegative metres |
| `legs[].duration_s` | Optional nonnegative driving seconds; omitted when unknown |
| `legs[].geometry` | Optional GeoJSON `{ "type": "LineString", "coordinates": [[longitude, latitude], ...] }` |

**Geometry-specific axis exception:** GeoJSON pairs are `[longitude, latitude]`, unlike coordinate objects elsewhere. A valid LineString needs at least two pairs, exactly two finite numbers per pair, longitude −180…180 and latitude −90…90. Invalid geometry is never drawn or force-indexed. Missing geometry leaves stops and cards usable, without an invented driving line. The app does not call MKDirections to reconstruct legs.

```json
{ "route_id": "2026-10-10-hapur-ins-17", "depart": "2026-10-10T09:00:00+05:30", "budget_min": 480,
  "stops": [{ "order": 1, "kiln_id": "KW-0412", "eta": "2026-10-10T09:40:00+05:30", "service_min": 35,
              "access": { "lat": 28.7162, "lon": 77.6556, "note": "Confirm entrance on site" }, "sheet": "InspectionSheet as above" }],
  "legs": [{ "to_kiln_id": "KW-0412", "duration_s": 2400, "distance_m": 18240,
             "geometry": { "type": "LineString", "coordinates": [[77.6400, 28.7290], [77.6556, 28.7162]] } }],
  "kilns": ["full embedded kiln records"] }
```

The nine-stop JSON fixture includes **illustrative** access points and schematic linework, not verified rural road routing or server geometry. It is labeled Sample data in the DEBUG app. ETAs and stop order are supplied; driving figures only use `duration_s`. Predicted total is shown only when every stop has valid driving and service durations. Budget is not a prediction.

The app saves successful full route responses atomically. `404` or `200` with zero stops invalidates only the saved route; it never revives an old plan after an authoritative empty response. Transport failures use a readable saved route, with its plan date when different from today. Auth/server/decoding failures show honest errors and preserve a valid cache. No fixtures replace failed live requests. Corrupt route files do not touch the verdict outbox.

Configuration is injected with `KilnWatchAPI` or temporary process environment `KILNWATCH_API_URL` (HTTPS, no `.example` host) and `KILNWATCH_API_TOKEN`; tokens are not hard-coded or persisted by Phase 2. With no configuration, DEBUG shows fixtures and Release shows a configuration/saved-route state. Cognito remains Phase 5.

Primary Maps handoff uses MKMapItem driving directions to `access`, or asks before falling back to the kiln location. The secondary Unified Maps URL preserves remaining server order using repeated `waypoint`, a final `destination` and `mode=driving`, without a source (user location). Opening Maps does not advance or complete a stop. Offline basemap downloads and availability are outside MapKit's APIs.

### GET /rules

`200`: `{"rules": [Rule, ...]}`. Full example: `rules.json`, which holds the 7 rules from concept p.4.

```json
{ "id": "C-HAB-800", "check": "Distance to habitation", "threshold_m": 800, "requirement": null,
  "overrides": [ { "state": "UP", "threshold_m": 1000 } ],
  "source": "Central 2022 rules; UP siting rules" }
{ "id": "C-TECH-10K", "check": "Within 10 km of a non-attainment city", "threshold_m": null,
  "requirement": "Zigzag, vertical shaft or gas", "overrides": [], "source": "Central 2022 rules" }
```

`overrides` lists the state thresholds that replace `threshold_m` in that state. In the fixture, UP sets C-HAB-800 to 1,000 m and C-KILN-1K to 800 m.

### POST /verdicts

**V1 live (2026-10-11). Public for the demo, no auth.**
Records an on-site inspector verdict and changes registry status when the device
`recorded_at` is at least as recent as every previous verdict for that kiln. Older
verdicts remain in history without overwriting the latest status. Equal-time
verdicts apply in transaction order. `confirmed` means the inspector confirmed the
siting concern on site.

Headers:

```
Content-Type: application/json
Idempotency-Key: 6F9619FF-8B86-D011-B42D-00C04FC964FF
```

The `Idempotency-Key` is the client-generated UUID, equal to `id` in the body,
compared case-insensitively. New IDs return **201**; the same ID and canonical body
return **200** with fresh upload URLs; a different body returns **409**
`idempotency_conflict`. UUID casing and JSON object order/whitespace do not change
the canonical hash. Missing and null notes are equivalent.

Request (synthetic full kiln ID):

```json
{
  "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
  "kiln_id": "KW-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "outcome": "confirmed",
  "photos": [
    { "id": "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", "latitude": 28.7158, "longitude": 77.6561,
      "horizontal_accuracy_m": 6, "taken_at": "2026-10-11T04:12:31.204Z" }
  ],
  "note": "Chimney fixed, coal on site",
  "recorded_at": "2026-10-11T04:13:02.881Z"
}
```

Body limit **16 KB** after base64 decoding, unknown/duplicate keys rejected.
`id`, `kiln_id`, `outcome`, `photos` and `recorded_at` are required. `note` is optional
or null and at most **2,000 characters**. The kiln ID must have the full `KW-` plus
32 lowercase hex digits form and exist; unknown IDs return **404** without counting.
Outcomes: `confirmed`, `compliant`, `not_a_kiln`, `closed` (closed or not firing).
`recorded_at` must be an ISO timestamp with timezone, no later than now + 10 minutes;
old offline verdicts are allowed. At most **8 photos**, unique UUIDs, finite latitude
−90..90 and longitude −180..180, finite accuracy ≥ 0 and timezone-bearing ISO
`taken_at`. Validation failures return **400** `invalid_request`.

**30 new verdicts per UTC day**, atomically counted in RDS in the insert transaction.
Replays do not count. The cap returns **429** `daily_cap_reached` (`retryable: true`).
Database failures return **503** `registry_unavailable` (`retryable: true`). Handler
errors have `{"error":{"code":"...","message":"...","retryable":false}}`;
API Gateway throttling may return its own 429 body. Stage rate: 1 request/s, burst 2.

Response:

```json
{
  "id": "6f9619ff-8b86-d011-b42d-00c04fc964ff",
  "photo_uploads": [
    { "photo_id": "1b4e28ba-2fa1-11d2-883f-0016d3cca427",
      "upload_url": "<presigned PUT URL>" }
  ]
}
```

`photo_uploads` returns a fresh presigned **PUT for every photo**, including replays.
The Lambda cannot check arrivals because its VPC has no S3 network path. Re-upload
replaces the same private `verdicts/<verdict_id>/<photo_id>.jpg` key. URLs expire in
**15 minutes** and are signed for `Content-Type: image/jpeg`. Upload JPEG bytes
directly to S3, with no Authorization header on that PUT. The app may remove its
local photo only after POST and every PUT succeed.

Anyone with the deployment URL can record a verdict within the daily cap; no
identity or district authorization is enforced. Agents expose no verdict tool.
Operator rehearsal reset: `registry.cli reset-verdict --kiln <full-id> --confirm`
on the runner, requiring a fresh operator go each time. Resets restore
`flagged` / `pending` and retain history. No live reset was run for V1.

### Agent stream (planner, "Ask")

**v1 is the non-streaming `POST /ask` in "Phase 4A — Ask" below.** Streaming remains a later decision; see `docs/research/agent-streaming.md`. That document is owned by the research spike. Agents can read through their tools but have no tool for `POST /verdicts`.

## Open questions for the backend owner

1. **Footprint shape:** is this coordinate-object form OK, or do you prefer GeoJSON from `ST_AsGeoJSON`? If you prefer GeoJSON, the client would convert it.
2. **C-HAB-800 in UP (resolved 2026-10-10):** the UP First Amendment Rules, 2026 set a uniform 800 m from habitation and raised kiln spacing to 1 km, so UP has no override for either rule (`AWS/rules/rules_v1.json`). `threshold_m` on a violation is the value applied after any override.
3. **School rule ID:** the p.4 table says `UP/HR-SCH-1K`, while p.13 cites `UP-SCH-1K`. We use `UP-SCH-1K` because deployment is UP only, and `HR-SCH-1K` would come with Haryana. Please confirm the IDs the rules engine writes.
4. **District and measured feature coordinates:** the app accepts optional `district` and `violations[].measured_to` for display; absent metadata remains unknown. Please confirm server availability. District metadata never grants authorization.
5. **ID token or access token** (see Auth).
6. **Photo upload flow:** please confirm presigned S3 PUT as described. The alternative is multipart to API Gateway, which needs the payload limits checked.
7. **Pagination** for `GET /kilns`: none in v1. Add `next_cursor` when needed.

8. **Routing additions:** confirm road access points/notes, per-leg GeoJSON shape and `[longitude, latitude]` order, destination linking, departure/ETA time zone and drive/service-duration meanings. The Phase 2 sample is illustrative.
9. **Configuration:** confirm the real API endpoint, route endpoint/error semantics and token provider/type; no live backend was configured for Phase 2 verification.

## Integration 1: model-only candidate (implemented locally, deployment pending)

The initial HTTP API uses root paths: use the `api_base_url` output without `/v1`.
The source proof uses Cognito **ID tokens**, with HTTP API JWT validation and
Lambda permission checks (`token_use=id`, matching `aud`, `sub`, `inspector` group,
`custom:district`). District is immutable and omitted from client write attributes;
only the AWS teammate provisions it. Missing claims deny access. This is a single
district read proof; Verified Permissions and managed-login/PKCE are deferred.
Anonymous `/public/kilns` returned 503 until Integration 2C (below) added the public read. Gateway
JWT failures happen before Lambda and use the gateway's own error body; the client
retains all raw non-2xx bodies. Lambda errors use the nested error form above.

The existing Kiln shape extends as follows. Legacy fixtures still decode; older
clients must adopt these optionals before consuming candidate records.

| Field | Candidate semantics |
|---|---|
| `exposure` | `null` when not assessed; when supplied, all three counts remain required integers. Rules engine: HRSL v1.5.2 cells whose centre lies within 800 m of the footprint edge (`AWS/rules/exposure.py`) |
| `rules_assessment` | `not_evaluated` until the rules engine runs, then `evaluated` or `partially_evaluated` (some rules lacked data; see `AWS/rules/README.md`); legacy absence means assessment state unknown, never passed |
| `violations` | Empty for an unassessed candidate; after assessment, the rules measured inside their threshold. Never a compliance conclusion, and an empty list after `partially_evaluated` is not a clean result |
| `type_verification` | `unverified` for model candidates regardless of class score; no C-TECH-10K finding |
| `evidence.before`, `.after` | Optional URL strings, preserving legacy shape; null until an object is actually published. Since 2026-10-10 they are non-null HTTPS evidence-CDN URLs for published evidence (since E1, 2026-10-10: both sides for all 39 Hapur kilns); a kiln without published evidence stays null |
| `evidence.before_metadata`, `.after_metadata` | Optional scene/grid/image metadata even when URL is unavailable |
| `provenance` | Model hash/version, scene ID, exact acquisition timestamp, input SHA-256 and import timestamp |
| `first_seen`, `last_seen` | Earliest/latest **observed acquisition**, not construction/appearance dates |

Image metadata: `scene_id`, `acquired_at` (RFC 3339), `patch_px=256`, `gsd_m=10`,
`crs`, GDAL-order `geotransform=[x0,10,0,y0,0,-10]`, `footprint_px` (four `[x,y]`
corner pairs, top-left pixel-edge origin), `centroid_px`, `sha256`, `object_key`,
`attribution`, `nodata_fraction`, `rendering`. Historical imagery has no historical
kiln outline without a separate observed detection: `footprint_px=null` on before.
Both dates share the same grid and fixed RGB reflectance rendering. Null before
means unavailable, not proof the kiln appeared after that date. URLs are materialized
only from a verified publication receipt and the configured evidence distribution.

`provenance.confidence_semantics=predicted_class_score_shared` means the current
YOLO score is copied into both confidence fields; these are not independently
calibrated existence/type probabilities. `type_verification` is a verification state,
not a confidence threshold. Unknown raw kiln types/statuses remain preserved.

Imports validate the complete batch before writing. Site keys use canonical corner
order plus scene ID/model SHA, not feature order or file name. Exact/reordered retries
keep IDs; raw input checksum/import identity remain separate. Cross-scene/model
site matching is deferred: IDs are not claimed stable under changed footprints.
Human status/review and assessment fields are never overwritten by an import.
The district argument must be an AWS teammate-approved district for the run's AOI;
it is an administrative assignment, not an inferred boundary result.

GET /kilns requires `district` and optionally `status`; keyset pages contain
`{"kilns":[...],"next_cursor":null|string}`. Default limit 100, max 200; `cursor`
is the last kiln ID and is always combined with the authorized district. The shared
client follows pages, detects repeated cursors, and returns the whole result. Detail
reads use the same serializer and authorized district. Unknown or other-district IDs
return 404 to avoid disclosing their existence. Invalid filters return 400; denied
district/role returns 403; registry/secret failures return 503, never an empty list.

Representative JSON is generated through the importer and API serializer in
`AWS/tests/generate_contract.py`, saved under the core test target's `BridgeFixtures`.
It is explicitly synthetic, includes a high-score unverified type and missing facts,
and is decoded through both `JSONDecoder.kilnWatch` and the existing URLSession client.
Routes, measured rules, jobs, agents, verdicts and live app registry loading are deferred.

## Integration 2C: public read API (live, no login)

Two `GET` routes with **no `Authorization` header**. The resident portal and the iOS
demo use them. The inspector routes (`/kilns`, `/kilns/{id}`) are unchanged and still
require a Cognito ID token. Present flagged records as
"Flagged by satellite · pending inspection"; inspected records use their outcome.

**Default publication policy:** only `status = flagged` is public, enforced in SQL.
V1 adds an opt-in `include=inspected` on both list shapes and detail. With it, all
candidate statuses are eligible and each record adds `inspection: {"outcome",
"recorded_at"}` from the latest verdict, or null while flagged (including an operator
reset). Notes, photos, verdict IDs and review internals remain private. Without
`include`, the existing SQL filtering and serialized response remain unchanged,
with no `inspection` key. Ask, route planning and the portal keep that default.
This opt-in is live as of 2026-10-11.

**Projection (allowlist, `registry/contract.py` `public_view`):** `kiln_id`,
`footprint`, `type`, `type_confidence`, `detection_confidence`, `type_verification`,
`first_seen`, `last_seen`, `status`, `violations`, `rules_assessment`, `exposure`,
`rule_checks` (R1, below), `district`, `evidence` (`before`, `after` and their `*_metadata`: scene, attribution,
grid and checksums are public), plus `distance_m` on near-point results. Everything else
is dropped, including `review_state`, `provenance` (input hash, import time) and the raw
assessment. New internal fields stay private by default. The body decodes into the
existing `KilnList` / `Kiln` (`provenance` is optional; `distance_m` is ignored).

### GET /public/kilns

Exactly one of two query shapes, optionally with `include=inspected`:

| Shape | Keys | Rules | Result |
|---|---|---|---|
| Near a point | `lat`, `lon`, optional `radius_m` | decimals, `lat` −90..90, `lon` −180..180; `radius_m` integer 100..5000, default 2000 | Flagged kilns whose footprint is within the radius, sorted by `distance_m` (integer metres from the point to the footprint, rounded up; 0 if the point is inside), at most 50, `next_cursor: null` |
| District list | `district`, optional `cursor`, optional `limit` | same as the inspector list: limit 1..200, default 100; cursor is the last kiln ID | Flagged kilns of the district, keyset pages `{"kilns":[...],"next_cursor":null|string}` |

Anything else is **400** `invalid_filter`: an empty query, mixed shapes, unknown keys
(including `status`), out-of-range or non-decimal values (`nan`, `1e1`).

### GET /public/kilns/{kiln_id}

The default public detail is flagged-only. **404** `not_found` has an identical body
whether the ID is unknown or the kiln is not flagged. `include=inspected` opts into
all statuses and the public `inspection` field. No other query is accepted.
`include` accepts exactly `inspected`; any other value is **400** `invalid_filter`.
Malformed IDs or other detail query keys return **400** `invalid_id`.

### Errors, caching, throttling

- Database or secret failure: **503** `registry_unavailable`, never an empty list.
- Successful public responses send `cache-control: public, max-age=60`; all errors send
  `no-store`. Outcomes can take up to **60 seconds** to appear through a cached read.
  Inspector responses stay `no-store`.
- API Gateway stage throttling: public routes 10 requests/s with a burst of 20; other
  routes 50/s, burst 100. Throttled requests get the gateway's own 429 body. No Lambda
  reserved concurrency.
- CORS allows `http://localhost:5173` (local development) and the hosted portal origin
  (`https://<portal-distribution>.cloudfront.net`), plus `frontend_origin` when set. Methods
  and headers are unchanged.


## Phase 3 iOS public configuration and presentation (2026-10-10)

The app target's Debug and Release configurations use `App/Config/Base.xcconfig`,
which optionally includes the ignored `Public.xcconfig`. Copy
`Public.xcconfig.example` locally and set the public deployment URL using the
xcconfig `https:/$()/` spelling (a literal double slash starts a comment).
`PublicInfo.plist` supplies custom keys merged into the generated Info.plist:
`KilnWatchPublicAPIURL` and `KilnWatchDistrict`. The default district is Hapur.
Do not publish the local deployment configuration or its expanded build settings.

A configured public URL takes priority over the inspector route/demo flow and
requires no sign-in. The existing protected `KILNWATCH_API_URL` / token environment
path is preserved. An empty or missing public configuration uses the existing
fixtures, labelled Sample data. A live error never substitutes fixtures. The
public list follows district pages with cursor protection; detail loads on demand.
Both public methods omit Authorization and do not call the token provider.

Public reads use a dedicated ephemeral session with URLCache, cookie and
credential storage disabled; public requests bypass local caches. No kiln disk
cache is added. Loading, authoritative empty, transport/offline,
429 and 503 have explicit retry states. A 429 receives one automatic two-second
backoff, then requires manual retry. Detail 404 is not found. Today shows the
public candidate footprints/pins and says route planning is unavailable.

Unverified predictions are labelled as predictions, with model score explained
as shape matching rather than an accuracy or a rule check. Missing rules,
exposure and evidence retain explicit unknown/unpublished copy. Public records
have no mock imagery, inspection actions, route, or assumed siting buffer.
Published before/after PNGs use integer device-pixel magnification and no image
interpolation, with acquisition metadata, attribution and supplied pixel
footprints. Live evidence delivery remains unverified until publication.

## Phase 4A — Ask (`POST /ask`)

Status: built and planned (2026-10-10), **not deployed**. Stateless (one question, one
answer, no history), English only (Hindi is Phase 6), **no streaming in v1**: the HTTP API
returns one JSON body. Public with **no `Authorization` header**, because the app has no
sign-in until Phase 5. The URL is the existing public base URL plus `/ask`.

One shared assistant: the Lambda's core (`AWS/assistant/core.py`, `answer(question,
kiln_id, lat, lon)`) is route-independent. The resident portal will later add its own
**authenticated** route to this same Lambda instead of building a second assistant.

### Request

```json
{"question": "How many kilns are flagged in Hapur?", "kiln_id": "KW-…", "lat": 28.73, "lon": 77.78}
```

- Body: JSON object, at most 2 KB. Unknown keys are rejected.
- `question`: required, non-empty string, at most **500 characters** after trimming.
- `kiln_id`: optional, a full registry ID (`KW-` plus 32 lowercase hex characters, or
  `KW-` plus at least 4 digits). Shortened IDs are rejected.
- `lat` and `lon`: optional, finite JSON numbers (not strings), −90..90 and −180..180,
  given together or not at all.

### Success, 200

```json
{
  "answer": "validated text",
  "citations": ["KW-…"],
  "steps": [{"tool": "list_flagged_kilns", "label": "Searching flagged kilns", "summary": "39 found", "ok": true}],
  "fallback": false,
  "disclaimer": "Answers cite registry records. Agents never record verdicts. Kilns are flagged by satellite and pending inspection."
}
```

- `answer` has passed the server's citation validator: every `KW-…` ID and every rule ID
  (for example `C-HAB-800`) in it came from a tool result in this request, and it uses no
  banned words. Since R1, answers may cite rule IDs.
- `citations`: the full IDs that appear in `answer`, in order of first appearance, de-duplicated.
- `steps`: one per tool call, written by the server (never model text, never raw tool output).
  `tool` is `list_flagged_kilns`, `kilns_near`, `kiln_detail`, `get_evidence` (R1), `plan_route` (P1),
  `inspection_sheet` (P2) or `unknown`; `ok: false`
  means the model sent invalid tool input. A `kiln_detail` that finds nothing has
  `summary: "Not found"` and `ok: true`.
- `fallback: true`: the model failed validation twice. `answer` is fixed server text with no
  model text ("I couldn't produce a reliable answer to that. Here are the flagged kilns I
  looked up:"), and `citations` are the kiln IDs the tools returned (at most 10, possibly empty).
- Headers: `content-type: application/json`, `cache-control: no-store`.

### Errors

Lambda errors use the nested format with a `retryable` flag:
`{"error": {"code", "message", "retryable"}}`.

| Status | Code | Meaning | Retryable |
|---|---|---|---|
| 400 | `invalid_request` | Bad body (see the rules above) | no |
| 429 | `daily_cap_reached` | The global daily cap is used up | no (try tomorrow, UTC) |
| 503 | `assistant_unavailable` | The daily counter is unavailable; the model is never called | yes |
| 503 | `upstream_unavailable` | The public read API returned 429/5xx or timed out | yes |
| 503 | `model_unavailable` | Bedrock failed: throttling or timeout (retryable), or access/configuration (not retryable) | per flag |

**Two kinds of 429.** API Gateway stage throttling on `POST /ask` (**1 request/s, burst 2**)
returns the gateway's own body, `{"message":"Too Many Requests"}`, with **no `error.code`**:
the client should slow down and retry. `daily_cap_reached` has `error.code` and should not
be retried today.

**Daily cap:** **100 questions per UTC day across all callers** (raised for the hackathon demo;
back to 50 afterwards), counted atomically in one
on-demand DynamoDB item before any model call. A question counts once, even if it later fails
or is regenerated. A gateway timeout (504 with the gateway's body) is possible only if the
Lambda exceeds its 28 s budget.

**Cost at the cap (Nova 2 Lite):** typical $0.0027 × 100 × 30 ≈ $8, worst case
$0.0312 × 100 × 30 ≈ $94 per 30 days.

## R1: rules, exposure and rule checks (live, 2026-10-10)

The rules engine (`kilnwatch-rules-v1`) and the HRSL exposure results are now in the
registry for all 39 Hapur kilns. The public routes (`/public/kilns`, `/public/kilns/{kiln_id}`)
and the inspector routes return them. Every flag is a **siting signal pending inspection**,
never a finding. Present the kiln as "Flagged by satellite · pending inspection".

**Now live for Hapur:**
- `violations`: one item per rule with status `within_threshold` (shape unchanged; see
  `Kiln` above). `evidence_url` is `null` for now.
- `rules_assessment`: `partially_evaluated` for all 39 (some rules have no usable data, so
  "no flags" is never a clean result). `not_evaluated` for kilns without an assessment.
- `exposure`: `{"people", "children_under_five", "adults_over_sixty"}` integers, residents
  within 800 m of the footprint edge. `null` means not assessed, never zero.

### `rule_checks` (new)

One object per rule in `rules_v1.json`, in that order. `[]` when the kiln has not been
assessed (then `rules_assessment` is `not_evaluated` and `exposure` is `null`).

```json
{"rule_id": "C-HAB-800", "check": "Distance to habitation", "status": "within_threshold",
 "threshold_m": 800, "measured_distance_m": 497, "verification": "secondary_sources",
 "source": "Central 2022 rules; UP siting rules (2026 amendment)"}
```

| Field | Notes |
|---|---|
| `rule_id` | Stable rule ID, for example `C-HAB-800`, `UP-SCH-1K` |
| `check` | Short human label of what was measured |
| `status` | See the table below |
| `threshold_m` | The threshold applied, in metres. `null` for rules without a distance threshold or not evaluated for lack of a layer (`C-TECH-10K`, `UP-MUN-5K`) |
| `measured_distance_m` | Integer metres from the footprint edge to the nearest mapped feature, or `null` when nothing was found within the search distance or the rule was not evaluated |
| `verification` | How well the threshold itself is sourced; see below |
| `source` | The rules the threshold comes from |

Feature names, feature coordinates and the engine's reasons stay internal.

| `status` | Display |
|---|---|
| `within_threshold` | Siting flag: a mapped feature is inside the threshold; needs inspection. Also listed in `violations` |
| `beyond_threshold` | The nearest mapped feature is beyond the threshold (railways, national highways, other kilns: layers complete enough for absence to mean something) |
| `inconclusive` | No mapped feature inside the threshold, but the map is incomplete here (habitation, schools, orchards). **Not clear.** Never show it as a pass or a green state |
| `not_evaluated` | No usable data (no boundary layer, kiln type unverified, or the threshold ring leaves the searched area) |
| `not_applicable` | A state rule outside its state |

| `verification` | Display |
|---|---|
| `secondary_sources` | Threshold quoted by court records, legal digests or news reports; the gazette text has not been read |
| `unverified_compilation` | **Unverified threshold**, taken from an academic compilation |

**Exposure attribution** (show with any exposure figure): "Modelled estimate of residents
within 800 m of the kiln edge. Population: Meta and CIESIN High Resolution Settlement Layer
(HRSL) v1.5.2, CC BY 4.0. Age groups are modelled shares of the same estimate."

### Ask changes

- Tool results now give the model siting flags, rule checks and exposure as explicit words.
  The new tool `get_evidence(kiln_id)` returns the image dates, scenes and Copernicus
  attribution, every rule check with its source, and the exposure. It never returns URLs,
  polygons or feature coordinates. It appears in `steps` as
  `{"tool": "get_evidence", "label": "Gathering evidence for KW-xxxx…", "summary": "Found", "ok": true}`.
- Answers may cite rule IDs, but only ones a tool returned in the same request.

## P1: `POST /routes/plan` (live, 2026-10-10)

A public inspection route for one district, built from road travel times (Amazon Location,
Car, no live traffic). Public with **no `Authorization` header**, like `/ask`. The URL is the
existing public base URL plus `/routes/plan`. `GET /routes/today` (the signed-in inspector's
route) is still **not built**.

### Request

```json
{"district": "Hapur", "start": {"lat": 28.7306, "lon": 77.7759}, "depart": "2026-10-11T09:00:00+05:30",
 "budget_min": 480, "max_stops": 8, "priority": "people", "kiln_ids": ["KW-…"]}
```

| Key | Rules and default |
|---|---|
| `district` | Required; same validation as the public API |
| `start` | Optional `{lat, lon}` numbers. Default: the centre of the selected kilns (said in `notes`) |
| `depart` | Optional RFC 3339 with `T` and an offset. Default: tomorrow 09:00 Asia/Kolkata |
| `budget_min` | Optional integer 60–720, default 480 |
| `max_stops` | Optional integer 1–8, default 8 |
| `priority` | `"people"` (default: most people within 800 m) or `"flags"` (most siting flags, then people). There is no "schools first" |
| `kiln_ids` | Optional, 1–8 unique full IDs. Plans exactly these (IDs not found in the district are reported in `notes`) |

Body at most 4 KB. Unknown keys or any bad value give 400.

### Success, 200

The same `Route` shape as `GET /routes/today` with the Phase 2 additions, plus `notes`:
`district`, `generated_at`, `route_id` (`plan-<date>-<district>-<hash of the inputs>`), `depart`,
`budget_min`, `stops[]` (`order` from 1, `kiln_id`, `eta` in `+05:30`, `service_min` 35, `access`,
`sheet`), `legs[]` (one per stop including start-to-first, GeoJSON `[longitude, latitude]`, at most
about 200 points each), `kilns[]` (the full public records of the stops) and `notes[]` (plain
strings). It decodes into KilnWatchCore `Route`; `notes` is ignored by the current client.

- **Selection and order:** the top kilns by `priority` (at most 8) are ordered by driving time
  (nearest neighbour + 2-opt). The lowest-priority stop is dropped until driving plus 35 minutes
  per stop fits `budget_min`. Same input, same plan. A kiln without an exposure estimate is left
  out (the sheet needs a number), never ranked as zero.
- **ETAs are estimates** from road travel times without live traffic, plus the on-site time.
  `budget_min` is a limit, not a prediction.
- **`access`** is the kiln centroid, **not a verified entrance**: its note says "Kiln centroid,
  not a verified entrance · confirm on site".
- **`sheet`:** `rules_flagged` (rule IDs from `violations`), `people_exposed`, and `on_site_checks`
  (a short fixed list from the flags plus "Kiln type: fixed chimney or zigzag" and "Is the kiln
  firing?").
- If the road-legs call fails, the plan comes back **without `legs`** and a note says so.
- Every kiln stays "Flagged by satellite · pending inspection".

### Errors

Nested format `{"error": {"code", "message", "retryable"}}`; provider error text is never echoed.

| Status | Code | Meaning | Retryable |
|---|---|---|---|
| 400 | `invalid_request` | Bad body | no |
| 404 | `no_kilns` | Nothing flagged (with an exposure estimate) in the district, or none of `kiln_ids` found | no |
| 429 | `daily_cap_reached` | The global daily cap is used up | no (try tomorrow, UTC) |
| 503 | `routing_unavailable` | Amazon Location or the daily counter failed | yes |
| 503 | `upstream_unavailable` | The public read API failed | yes |

**Cap and throttle:** **15 plans per UTC day across all callers** (Ask's `plan_route` counts too),
counted before any routing call; 400 and 404 are not counted. Stage throttling on this route is
1 request/s with a burst of 2 (the gateway's own 429 body, without `error.code`).

### Ask

New tool `plan_route` (`district`, `priority`, `max_stops`, optional `start_lat`/`start_lon`). Its
step is `{"tool": "plan_route", "label": "Planning a route", "summary": "N stops", "ok": true}`.
Answers state the stops, order and times as returned and call the times estimates.
`get_evidence` now also returns `attribution_text`, quoted exactly.

**P2 (2026-10-10).** New tool `inspection_sheet(kiln_id)`: one kiln's sheet (siting flags with
measured distances, checks to confirm on site, the same on-site checks as a route stop's `sheet`,
people exposed or "not assessed", image dates and attribution). Its step is
`{"tool": "inspection_sheet", "label": "Preparing the inspection sheet for KW-xxxx…", "summary": "Ready", "ok": true}`
(`summary: "Not found"` when the kiln is not found). List results now say "published for all N
kilns listed" (or "not yet published for any kiln listed") instead of listing every ID; the ID
list remains only when some kilns have images. The response shape is unchanged; the app shows
step labels as given.

## Change triage (40): internal review queue (live, 2026-10-11)

**The triage run is internal only.** The queue has one read-only public route, `GET /public/review`
(see "Review queue read (40b)" below). Concept Agent 2. An operator invokes the assistant Lambda
directly with `{"action": "triage", "baseline_run": "m0-before", "current": "registry"}` (optional
`current_run`, default `m0-after`; `start_after`, an item ID cursor; `max_model_calls`, 1–80). The
event is honoured only without an API Gateway `requestContext`; `POST /ask` with that body is a
400 as before and does not touch the Ask daily cap. Gated by `enable_change_triage`.

It compares a baseline detector run with today's registry (all Hapur kilns via
`include=inspected`) and sorts every difference into one of four groups. Matching is one-to-one by
footprint IoU ≥ 0.3, with a centroid-distance fallback of 30 m. An unchanged match is no item.

| Group | When | Fixed wording |
|---|---|---|
| `possible_zigzag_conversion` | matched; baseline FCBK or CFCBK, registry Zigzag | "detected as FCBK in the Dec 2023 scene and as Zigzag in the Oct 2026 scene" |
| `new_candidate` | in the registry, no baseline match | "in the registry; not detected in the Dec 2023 scene" (never "built after") |
| `low_confidence` | matched, current detector score < 0.5 | "current detector score 0.36 is below 0.5" (a score is not accuracy) |
| `no_longer_detected` | in the baseline, no registry match | "detected in the Dec 2023 scene; no longer detected in the Oct 2026 scene" (never "closed" or "demolished") |

Precedence: zigzag, then new, then low confidence. Every item is a **candidate for review**, never
a finding. Groups, matches and numbers come from deterministic code (`AWS/triage/diff.py`); the
model (Ask's Nova 2 Lite path, reasoning off, no tools) only writes a one- or two-sentence reason
from the item's facts. A validator rejects foreign kiln or scene IDs, the banned stems, status
words (confirmed, compliant, closed, approved, "not a kiln"), "finding" and construction or
demolition claims; one regeneration, then a deterministic template (`reason_source: "template"`).

**Queue item** (DynamoDB, written only by `queue_for_review`, a conditional PutItem idempotent on
`item_id`):

```json
{
  "item_id": "<32 hex: sha256 of baseline run + group + footprint>",
  "group": "new_candidate",
  "kiln_id": "KW-… (absent for no_longer_detected)",
  "facts": "<JSON string: group_words, both scenes {id, date}, baseline and current {type, score} or null, iou or \"none\", match basis, centroid, evidence>",
  "reason": "One or two plain sentences.",
  "reason_source": "model | template",
  "state": "pending",
  "created_at": "2026-10-11T08:12:30+00:00",
  "model_id": "<model ID, or none for a template reason>",
  "baseline_run": "m0-before",
  "current": "registry"
}
```

`facts.evidence` holds the registry's `evidence.before/after` URLs when published; otherwise
`{"images": "no published image", "scene_ids": [...], "footprint": [[lat, lon], ...]}`.

**Nothing changes a kiln.** No triage code path writes `status` or `review_state`, RDS or the
public API. The registry changes only when a reviewer approves an item; that review console and
approval path are **not built yet**. Triage is started manually; Step Functions wiring is next.

## Review queue read (40b): `GET /public/review`

Read-only. Approving or rejecting items needs reviewer sign-in and is not built.

The pending change-triage candidates for the iOS Review tab. Public, no sign-in (like
`/public/kilns`), served by the assistant Lambda; gated by `enable_change_triage`. No request
body, no query parameters. Every item is a **candidate pending review**, never a finding; the
response adds no prose of its own beyond the fixed group keys and labels below. `reason` is the
stored reason, verbatim.

**200** (`content-type: application/json`, `cache-control: public, max-age=60`):

```json
{
  "baseline": {"run": "m0-before", "scene": "S2A_T43RGM_20231205T053206_L2A", "date": "2023-12-05"},
  "current": {"label": "registry", "scene": "S2B_T43RGM_20261005T053448_L2A", "date": "2026-10-05"},
  "counts": {"new_candidate": 24, "no_longer_detected": 17, "possible_zigzag_conversion": 0, "low_confidence": 4},
  "truncated": false,
  "items": [
    {
      "item_id": "<32 hex>",
      "group": "new_candidate",
      "state": "pending",
      "kiln_id": "KW-…",
      "reason": "verbatim stored reason",
      "centroid": {"lat": 28.7, "lon": 77.7},
      "baseline": {"type": "FCBK", "score": 0.52},
      "current": {"type": "FCBK", "score": 0.36},
      "iou": 0.76,
      "evidence": {"before": "https://…", "after": "https://…"},
      "created_at": "2026-10-11T08:08:09Z"
    }
  ]
}
```

- **Allowlist:** exactly these keys. Never the model ID, the raw facts, the reason source or
  anything else stored.
- **Nulls:** `kiln_id`, `baseline`, `current`, `iou` and `evidence` are `null` when the item has
  none. `no_longer_detected` has no `kiln_id`, no `current`, no `iou` and no `evidence`;
  `new_candidate` has no `baseline` and no `iou`. Inside `evidence`, either URL may be `null`;
  URLs appear only when they are images on the evidence CDN (anything else is dropped). The
  `type` inside `baseline` and `current` is the unverified predicted type; a score is a detector
  score, not accuracy.
- **Rounding:** scores 3 decimals, coordinates 5.
- **Order:** group (`new_candidate`, `no_longer_detected`, `possible_zigzag_conversion`,
  `low_confidence`), then `kiln_id` (nulls last), then `item_id`.
- `counts` always has all four keys (0 when empty) and counts every item of the shown run, also
  when `items` is cut off at 500 (`truncated: true`). Only the latest baseline run (by
  `created_at`) is shown. `baseline` and `current` are `null` when the queue is empty.

**Errors** (`cache-control: no-store`, the usual
`{"error": {"code", "message", "retryable"}}` body):

| Status | Code | When |
|---|---|---|
| 400 | `invalid_filter` | any query string |
| 503 | `review_unavailable` (`retryable: true`) | the queue could not be read; never an empty list instead |
| 404/405 | (gateway) | any other method, e.g. `POST /public/review` (no route) |

**Caching and throttle:** clients and caches may keep a response for 60 s, and a warm Lambda
reuses its last read for 60 s, so a change shows up within about two minutes. Stage throttle
10/s, burst 20 (the `/public/kilns` group). CORS as for the rest of the API (hosted portal and
`http://localhost:5173`). It never touches the Ask daily counter.

## Inspection requests (43)

Frozen client contract, 11 October 2026. **Live, 11 October 2026 (43b verified).**

`POST /requests` is public, without authentication, with `Content-Type: application/json`.
The UTF-8 body is at most 4 KB; unknown or duplicate keys return 400 `invalid_request`.
All five fields are required:

```json
{"kiln_id":"KW-0123456789abcdef0123456789abcdef","client_id":"a80d2cb8-9e91-4dfd-96fd-a3d6d4c24aa1","concerns":["smoke_or_ash","near_homes"],"distance_band":"under_1km","lang":"en"}
```

- `kiln_id`: full `KW-` plus 32 lowercase hexadecimal characters. Must exist, any status;
  an unknown full ID returns 404 `not_found` and is not counted.
- `client_id`: UUID v4, generated once by the browser and retained in browser storage.
  The server stores only its SHA-256 hash, after canonical lowercase UUID normalization.
- `concerns`: 1–4 unique values from `smoke_or_ash`, `near_homes`,
  `near_school_or_hospital`, `other`.
- `distance_band`: self-reported residential distance, one of `under_1km`, `1_to_5km`,
  `over_5km`, `not_said`.
- `lang`: `en` or `hi`.

One request per browser code per kiln. New pair: 201 with `created: true`.
Repeated pair: 200 with `created: false`, fresh current aggregate, no additional count,
regardless of changed answers. A replay remains available at the daily cap.

```json
{"kiln_id":"KW-0123456789abcdef0123456789abcdef","created":true,"resident_requests":{"count":12,"within_1km":8,"concerns":{"smoke_or_ash":9,"near_homes":7,"near_school_or_hospital":2,"other":1},"last_request_on":"2026-10-11"}}
```

The cap is 300 new requests per UTC day, atomically checked and counted in the insert
transaction. Cap returns 429 `daily_cap_reached`, `retryable: true`. Database failure
returns 503 `registry_unavailable`, `retryable: true`. Validation and not-found errors
are not retryable. All errors use `{"error":{"code":"…","message":"…","retryable":false}}`.
Stage throttle: 1 request/s, burst 2; gateway throttling may use its own error body.

`GET /public/kilns` (district and nearby shapes, with or without `include=inspected`)
and `GET /public/kilns/{id}` include `resident_requests` on every kiln. No requests means:

```json
{"count":0,"within_1km":0,"concerns":{"smoke_or_ash":0,"near_homes":0,"near_school_or_hospital":0,"other":0},"last_request_on":null}
```

Zero is an authoritative count. `last_request_on` is a date in Asia/Kolkata (IST),
never a timestamp. The public allowlist never exposes the client hash, language or row
IDs. Public caching remains `max-age=60`; counts can lag by up to about two minutes,
while the POST response is always fresh and `no-store`.

Requests are anonymous and unverified. Anyone can send more by clearing browser storage,
within the global daily cap. They are a signal for KilnWatch inspectors, never a finding;
they never change `status` or `review_state`, guarantee an inspection, or imply delivery
to an authority. No names, phone numbers, free text or precise residential locations.
The inspector app only displays requests; it does not submit them.

Shared synthetic recorded-shape fixture: `requests-recorded.json` in the portal test
fixtures and core `RequestFixtures` directories. Both contain identical sanitized bytes.
