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

Every request except the presigned photo upload carries:

```
Authorization: Bearer <Cognito JWT>
```

The JWT comes from the Cognito user pool through the hosted UI (Phase 5). The target architecture proposes Amazon Verified Permissions (concept p.10), which is not provisioned. Integration 1 enforces read permissions in Lambda; the eventual roles are:

| Principal | Allowed |
|---|---|
| Resident (or anonymous web) | No login. Read public fields of flagged kilns only (`/public/kilns`, Integration 2C). |
| Inspector | Read kilns, rules and their own route. `POST /verdicts` **only for kilns in `principal.district`**. |
| Reviewer | Approves registry changes (review console). Not used by this app. |
| Agent | **Forbidden** from `RecordVerdict`, whatever else is true. |

```cedar
permit (principal in Role::"Inspector", action == Action::"RecordVerdict", resource)
when { resource.district == principal.district };
forbid (principal is Agent, action == Action::"RecordVerdict", resource);
```

Proposal: the app sends the **ID token**. The inspector's district is a custom attribute (`custom:district`), and Cognito puts custom attributes in ID tokens, not access tokens, unless a pre-token-generation trigger is added. Please confirm which token the authorizer expects.

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

Records an inspector's verdict. This is the only way a kiln's status changes.

Headers:

```
Authorization: Bearer <JWT>
Content-Type: application/json
Idempotency-Key: 6F9619FF-8B86-D011-B42D-00C04FC964FF
```

The `Idempotency-Key` is the verdict's client-generated UUID, the same value as `id` in the body. The app retries on every reconnect, so the server **must** treat a repeat key with the same body as a replay: return the original result and don't record the verdict twice. A repeat key with a different body returns `409`. Compare UUIDs case-insensitively; iOS sends them in upper case.

Request:

```json
{
  "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
  "kiln_id": "KW-0412",
  "outcome": "confirmed",
  "photos": [
    { "id": "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", "latitude": 28.7158, "longitude": 77.6561,
      "horizontal_accuracy_m": 6, "taken_at": "2026-10-10T04:12:31.204Z" }
  ],
  "note": "Chimney fixed, coal on site",
  "recorded_at": "2026-10-10T04:13:02.881Z"
}
```

`outcome` is one of `confirmed` (violation confirmed), `compliant`, `not_a_kiln` or `closed` (closed or not firing). `recorded_at` is the time on the device. Verdicts can arrive hours late, so order them by `recorded_at`, not by arrival time.

Response: `201` on first receipt, `200` on a replay.

```json
{
  "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
  "photo_uploads": [
    { "photo_id": "1B4E28BA-2FA1-11D2-883F-0016D3CCA427",
      "upload_url": "https://kilnwatch-evidence.s3.us-west-2.amazonaws.com/verdicts/...&X-Amz-Signature=..." }
  ]
}
```

`photo_uploads` holds a presigned S3 PUT URL for every photo the server has **not yet received**. A replay returns fresh URLs for any photos still missing. The app then sends `PUT <upload_url>` with `Content-Type: image/jpeg` and the JPEG bytes. That request carries **no** `Authorization` header, because S3 rejects a request that uses two auth schemes. The URL must be signed for `image/jpeg`. The app deletes its local copy only after the POST and every PUT succeed. Photos go to S3 directly because API Gateway (10 MB) and Lambda (6 MB) payload limits are too small for several full-resolution photos.

### Agent stream (planner, "Ask")

**v1 is the non-streaming `POST /ask` in "Phase 4A — Ask" below.** Streaming remains a later decision; see `docs/research/agent-streaming.md`. That document is owned by the research spike. Agents can read through their tools but cannot call `POST /verdicts` (see the Cedar `forbid` above).

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
| `evidence.before`, `.after` | Optional URL strings, preserving legacy shape; null until an object is actually published. Since 2026-10-10 they are non-null HTTPS evidence-CDN URLs for published evidence (currently both sides of `KW-6b3b38…`); all other kilns stay null |
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
require a Cognito ID token. Present every public record as
"Flagged by satellite · pending inspection".

**Publication policy:** only `status = flagged` is public, enforced in the SQL `WHERE`
clause of every public query (not only in Python). A kiln that a person later marks
`not_a_kiln`, `compliant`, `closed` or `confirmed` disappears from the public API until a
separate publication policy covers those outcomes.

**Projection (allowlist, `registry/contract.py` `public_view`):** `kiln_id`,
`footprint`, `type`, `type_confidence`, `detection_confidence`, `type_verification`,
`first_seen`, `last_seen`, `status`, `violations`, `rules_assessment`, `exposure`,
`rule_checks` (R1, below), `district`, `evidence` (`before`, `after` and their `*_metadata`: scene, attribution,
grid and checksums are public), plus `distance_m` on near-point results. Everything else
is dropped, including `review_state`, `provenance` (input hash, import time) and the raw
assessment. New internal fields stay private by default. The body decodes into the
existing `KilnList` / `Kiln` (`provenance` is optional; `distance_m` is ignored).

### GET /public/kilns

Exactly one of two query shapes:

| Shape | Keys | Rules | Result |
|---|---|---|---|
| Near a point | `lat`, `lon`, optional `radius_m` | decimals, `lat` −90..90, `lon` −180..180; `radius_m` integer 100..5000, default 2000 | Flagged kilns whose footprint is within the radius, sorted by `distance_m` (integer metres from the point to the footprint, rounded up; 0 if the point is inside), at most 50, `next_cursor: null` |
| District list | `district`, optional `cursor`, optional `limit` | same as the inspector list: limit 1..200, default 100; cursor is the last kiln ID | Flagged kilns of the district, keyset pages `{"kilns":[...],"next_cursor":null|string}` |

Anything else is **400** `invalid_filter`: an empty query, mixed shapes, unknown keys
(including `status`), out-of-range or non-decimal values (`nan`, `1e1`).

### GET /public/kilns/{kiln_id}

The public detail of a flagged kiln. **404** `not_found` with an identical body whether
the ID is unknown or the kiln is not flagged. A malformed ID or any query is 400
`invalid_id`.

### Errors, caching, throttling

- Database or secret failure: **503** `registry_unavailable`, never an empty list.
- Successful public responses send `cache-control: public, max-age=60`; all errors send
  `no-store`. Inspector responses stay `no-store`.
- API Gateway stage throttling: public routes 10 requests/s with a burst of 20; other
  routes 50/s, burst 100. Throttled requests get the gateway's own 429 body. No Lambda
  reserved concurrency.
- CORS is still the placeholder origin; the portal step sets the real `frontend_origin`.


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
  `tool` is `list_flagged_kilns`, `kilns_near`, `kiln_detail`, `get_evidence` (R1) or `unknown`; `ok: false`
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

**Daily cap:** **50 questions per UTC day across all callers**, counted atomically in one
on-demand DynamoDB item before any model call. A question counts once, even if it later fails
or is regenerated. A gateway timeout (504 with the gateway's body) is possible only if the
Lambda exceeds its 28 s budget.

**Cost at the cap (Nova 2 Lite):** typical $0.0027 × 50 × 30 ≈ $4, worst case
$0.0312 × 50 × 30 ≈ $47 per 30 days.

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
