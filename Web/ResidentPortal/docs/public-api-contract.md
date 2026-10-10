# Public API contract — proposal

**Not agreed with the AWS teammate. Not a description of the deployed public API.** The repository handler still returns `503 publication_unavailable` for `/public/kilns`; no newer live report has been supplied. The read client now has unit and intercepted browser coverage for local R2 preparation. No public backend or publication policy was changed.

## Public boundary

Anonymous access must return a server-side allowlisted projection of explicitly published records. Publication eligibility is distinct from status. A flagged record is not automatically public. A database reader role and frontend filtering are not the privacy boundary.

Exclude inspector identities, notes/private photos, assignments, routes/queues, unpublished candidates, internal object keys/storage paths, private provenance, credentials, and operational metadata. Apply the same projection to list and detail. Unknown and unpublished IDs must have indistinguishable `404` responses. Resident endpoints must not grant mutations. Tests against the actual service must establish this; frontend fixtures cannot.

## Common fields

JSON uses snake_case and metres. Timestamps use ISO 8601 with offsets, including optional fractional seconds. WGS84 coordinate pairs are **[longitude, latitude]**; polygons use a closed ring. Convert the inspector contract's coordinate objects explicitly. Validate finite ranges, nondegenerate/noncrossing footprints, enum unknowns, nulls and image metadata at the browser boundary.

Runtime types/validators are in `src/data/model.ts`. Minimum public record:

| Field | Proposed meaning |
|---|---|
| `id`, `revision` | Stable public identifier and public record revision, never a private operational key. |
| `name` | `{en,hi}` approved public label. Confirm availability; the real UI must fall back to the ID if no label is provided in the agreed contract. |
| `status` | String; known values flagged/confirmed/compliant/not_a_kiln/closed. Unknown values remain unknown. |
| `human_reviewed` | Authoritative server indicator for a published human status. The browser never derives this from confidence. |
| `centroid`, `footprint` | Valid coordinate pair and nullable closed footprint ring. |
| `last_seen` | Latest observed acquisition, never construction date. |
| `prediction` | `{type, score: number|null, verified: boolean}`. Score range 0–1; not independent detection/type probabilities or field accuracy. |
| `evidence.before`, `.after` | Nullable approved image metadata objects. Missing means unavailable. |
| `assessments[]` | `rule_id`, `state` assessed/not_evaluated, nullable `measured_distance_m`, nullable `threshold_m`, nullable approved `source_url`. An assessed comparison needs all relevant facts and verified applicability. |
| `exposure` | Nullable `{people, radius_m, source:{en,hi}, estimated_at}`. A count is not measured emissions or a diagnosis. |

Images propose `url`, nullable `acquired_at`, `source:{en,hi}`, nullable `resolution_m`, `width=256`, `height=256`, and nullable `outline_px` of four pixel-edge `[x,y]` pairs in image bounds. These are reduced public fields; no S3 key, secret URL-fetch capability, or internal import metadata. A historical outline requires actual historical evidence. Each side has its own metadata. URLs must be HTTPS on agreed exact evidence hosts, with correct content type and CORS. The viewer checks decoded dimensions against metadata and sends no referrer with image requests. Current local samples use restricted `/samples/*.svg` paths; that is not the production image contract.

The client currently allows official rule sources only on `mpcb.gov.in`/`www.mpcb.gov.in`. Additional authoritative sources require an explicit reviewed allowlist update; do not solve missing sources with wildcard acceptance.

## GET /public/kilns

Choose one query shape: `longitude`, `latitude`, `radius_m`, `limit`, and optional `cursor`. Do not combine an unbounded map viewport with paged client-side filtering. Proposal: radius choices 800/1000/2000/5000 m; maximum radius 5000 m; server maximum page size 100. R1 requests three records per page to exercise pagination. Confirm production defaults and limits with the AWS teammate.

Response:

```json
{
  "items": [{"kiln": "PublicKiln object", "distance_m": 290}],
  "next_cursor": "opaque cursor or null",
  "complete": false,
  "revision": "public-dataset-revision",
  "coverage": "known",
  "updated_at": "2026-10-01T06:00:00Z",
  "distance_basis": "centroid"
}
```

This is a shape illustration, not a production payload. `coverage` is `known|unknown`; confirmed full coverage and response completeness are separate. A complete response has no next cursor. Empty pages cannot have a next cursor. An incomplete response without a cursor must be explicitly presented as partial, not as a claim of a total. Dataset update time is not browser fetch time.

Sort by canonical distance then ID. Cursors must be stable and bound to the query/filters and dataset revision; document expiry. Reject stale/mismatched cursors explicitly. The client deduplicates IDs, refuses repeated cursors/revision changes, caps loaded records at 100, and reports loaded count rather than an unproven total.

R1 computes centroid distances over the complete fixture collection before filtering/paging. For R2, prefer server-calculated distance to the approved footprint using geography-aware calculations. The current parser deliberately accepts only `distance_basis=centroid`; if the AWS teammate agrees on footprint distances, change that contract and labels explicitly before R2. Never silently relabel either measure as a distance to homes/schools.

## Detail and rules

- `GET /public/kilns/{id}` returns one `PublicKiln`, matching the requested ID. Confirm the production ID format and canonical portal URL/origin. R1 exports use local sample links only.
- `GET /public/rules/{id}` returns ID, `{en,hi}` name/jurisdiction/explanation/limitation, nullable threshold/source URL/effective date, source title, and applicability. The local catalog distinguishes `reference_only` from `sample_assessment`; the actual public assessment semantics require agreement. Do not treat a national reference or rule-ID suffix as a resolved UP threshold.
- `POST /public/assistant` is a future capability, not implemented by this client. Confirm actual request/events, server-side public reads, citation validation before factual output, cancellation, context bounds, rate limits, cost limits, and networking. No fabricated stream protocol or automatic retry of a paid assistant request.

## Errors, requests, caching

Agree on nested error bodies `{ "error": { "code": "...", "message": "..." } }` for 400/422 invalid queries, 404 absent/unpublished, 429 throttled, and 503 unavailable/publication unavailable. Gateway error bodies may differ. The resident UI does not display raw backend bodies.

The local client omits credentials, uses `Accept: application/json`, `cache: no-store`, and `referrerPolicy: no-referrer`. Configuration must be HTTPS without URL credentials/query/hash. No department token is accepted by frontend configuration. Exact CORS origins, allowed methods/headers and deployment security headers need backend agreement.

Reads have a 10-second timeout, cancellation and at most one retry for 408/429/502/503/504. Retry-After over two seconds is left to a user retry instead of extending an automatic wait. Invalid JSON/schema, 404 and invalid configuration do not retry. Responses above the client size cap are rejected. An error never becomes fixture data or a successful empty list.

No persistent response cache or service worker exists in R1. Results and query stay in memory for session navigation. A new search clears the old page and late responses are ignored. A later page failure preserves already loaded records and does not claim completion. An older dataset date is labeled after 30 days; that UI hint is not an agreed production freshness SLA. Define live TTL/revalidation and stale-read behavior before adding persistent caching.

## R2 acceptance evidence required

Anonymous list/detail/rule requests against the deployed service; bounded geospatial search and revision-aware paging; identical private/missing refusal; actual private-field exclusion; no mutation capability; image allowlist/CORS/content proof; real unavailable/malformed/throttled behavior. No mocked test can substitute for this evidence.
