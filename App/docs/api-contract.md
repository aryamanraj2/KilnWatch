# KilnWatch API contract (proposal)

**Status: proposal from the iOS team for the backend owner to confirm.** Everything here is what `Packages/KilnWatchCore` already encodes and decodes. Change requests are welcome; the open questions are listed at the end.

The examples come from the fixtures in `Packages/KilnWatchCore/Sources/KilnWatchCore/Fixtures/` (`kilns.json`, `route_today.json`, `rules.json`), which are full, valid responses. Kiln IDs, distances and counts are illustrative (concept p.13).

## Conventions

- **Base URL:** `https://api.kilnwatch.example/v1` (API Gateway + Lambda). All paths below are relative to it.
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

The JWT comes from the Cognito user pool through the hosted UI (Phase 5). Amazon Verified Permissions authorises each call (concept p.10):

| Principal | Allowed |
|---|---|
| Resident (or anonymous web) | Read public kiln fields only. Not used by this app. |
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

Lists the kilns in a district. `district` is required (for example `Hapur`). `status` is optional and takes one of `flagged`, `confirmed`, `compliant`, `not_a_kiln` or `closed`. No pagination in v1, because a district holds a few hundred kilns.

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
      "source": "Central 2022 rules; UP siting rules",
      "evidence_url": "https://cdn.kilnwatch.example/evidence/KW-0412/C-HAB-800.png" },
    { "rule_id": "UP-SCH-1K", "measured_distance_m": 620, "threshold_m": 1000,
      "source": "UP and Haryana siting rules",
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
| `footprint.polygon` | The four corners of the oriented bounding box, in order, with the ring not closed |
| `type` | `FCBK`, `CFCBK` or `Zigzag` (exact case) |
| `first_seen`, `last_seen` | Acquisition times of the first and latest scenes with a detection |
| `violations[].measured_distance_m` | `null` for technology rules (C-TECH-10K) |
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

`order` is 1-based. Every `stops[].kiln_id` has a matching entry in `kilns`.

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

**TBD, see `docs/research/agent-streaming.md`.** That document is owned by the research spike. Agents can read through their tools but cannot call `POST /verdicts` (see the Cedar `forbid` above).

## Open questions for the backend owner

1. **Footprint shape:** is this coordinate-object form OK, or do you prefer GeoJSON from `ST_AsGeoJSON`? If you prefer GeoJSON, the client would convert it.
2. **C-HAB-800 in UP:** the rules table gives UP a 1,000 m habitation threshold, but concept p.13 shows KW-0412 (in Hapur, UP) at "410 m vs 800 m". The fixture follows p.13. Which threshold does the rules engine apply in UP, and is `threshold_m` on a violation the post-override value?
3. **School rule ID:** the p.4 table says `UP/HR-SCH-1K`, while p.13 cites `UP-SCH-1K`. We use `UP-SCH-1K` because deployment is UP only, and `HR-SCH-1K` would come with Haryana. Please confirm the IDs the rules engine writes.
4. **District on the kiln record:** p.15 has no `district`, but the Cedar policy reads `resource.district`. The client doesn't need it. Should it be exposed anyway?
5. **ID token or access token** (see Auth).
6. **Photo upload flow:** please confirm presigned S3 PUT as described. The alternative is multipart to API Gateway, which needs the payload limits checked.
7. **Pagination** for `GET /kilns`: none in v1. Add `next_cursor` when needed.
