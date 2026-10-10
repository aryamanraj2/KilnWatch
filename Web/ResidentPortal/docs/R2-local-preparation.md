# R2 local frontend preparation

10 October 2026. The user authorized continued building, then confirmed the public backend is **not ready** and requested local preparation. No AWS requests, deployment, publication, backend changes, or teammate messages were made.

## Implemented

- Public-mode search explains that confirming sends coordinates/radius to the API. Address lookup is disabled until an approved provider exists; coordinate entry and opt-in location remain usable. Empty results, coverage and centroid distances no longer describe public records as samples.
- Evidence alt text distinguishes published images from synthetic samples. Unknown resolution remains unknown. Images send no referrer. Decoded image dimensions must agree with the supplied 256-pixel grid; mismatched images are rejected and a working comparison side remains usable.
- Published assessments, deterministic explanations, rule references and inspection exports no longer inherit sample wording. Fixture mode retains sample labels and the mandatory export notice. Neither mode submits requests.
- Attribution/privacy copy reflects the configured mode. The diagram still has no basemap, and explanations still use templates.
- `tests/browser/live.spec.ts` exercises the real browser frontend in live mode against intercepted fictional HTTP responses and generated PNGs. Its separate local server uses port 5174, with explicit test API/evidence hosts and no changes to local environment files. Tests are sequential with one worker.
- Public JSON reads now enforce the existing size cap during streaming, in decoded UTF-8 bytes, and reject invalid encodings. Oversized/understated/missing-length responses cannot bypass the cap; abort and timeout remain active during reads. API redirects are refused.
- Nearby reads validate order/radius and deduplicate the first page as well as later pages. Snapshot-time drift, changed overlapping record distances/revisions, and earlier unseen results are refused; valid overlap preserves the displayed record. Invalid later pages leave loaded records and selection intact, and loading a corrected page recovers.

## Verification

Strict TypeScript and production build pass under the pinned Node 24.21.0 runtime. **52 unit/behavior tests pass. Seven live-mode journeys pass in Chromium and seven in WebKit.** These cover query parameters/no auth headers, paging and selection/Back, bilingual evidence/explanations/rules/edited downloads, 503/malformed/429/not-found presentation, loaded-page preservation/recovery, overlapping snapshot consistency, oversized bodies, image retry, rejected dimensions and unapproved image-host refusal. Redirect refusal is exercised in Chromium plus unit request-policy tests; the WebKit interceptor cannot create redirect responses, so no WebKit redirect proof is claimed. Existing sample journeys are rerun separately; see [verification](verification.md) for final results.

All browser service responses and images are test data. The identical missing/unpublished errors test frontend presentation only; it does not establish that the backend applies identical refusals. Bitmap checks prove decoding and dimension handling, not satellite alignment, acquisition accuracy, content-type/CORS of a real CDN, or public eligibility. No new native zoom, spoken screen-reader, human Hindi, or physical-device proof is claimed. Chrome computer-use access was denied during the native-zoom attempt. Existing reviewed R1 PDFs/screenshots remain the original artifacts; current regression output goes to ignored `.cache/sample-review/` so later Playwright runs do not clear it.

## Required before connecting the service

1. Approved public API base URL, environment and current deployed verification report.
2. Publication owner/policy and server allowlisted projection for anonymous list/detail, with private/missing and mutation-refusal proof. Private inspector access cannot substitute.
3. Agreed nearby-query bounds, distance basis, revision/cursor/coverage/freshness semantics; confirm bilingual label availability and rule/assessment semantics against the proposal.
4. Approved evidence hosts/assets, metadata and delivery proof. Confirm which actual pair belongs to which eligible public record; no assumption that all 39 private candidates are public or have imagery.
5. Browser origins/CORS and authoritative rule sources. Missing assessments/exposure may remain unavailable under an agreed contract.

Review [public contract](public-api-contract.md) and [AWS teammate / ML team mate inputs](aws-integration-request.md). No contract field or server capability is inferred from test fixtures.

| Capability | Status |
|---|---|
| R1 sample journey | Locally implemented; manual accessibility gaps remain |
| R2 public-mode frontend | Locally implemented and tested against intercepted HTTP |
| Approved anonymous records, real nearby search and publication refusals | Backend input pending; not live verified |
| Approved real imagery and current rule catalog | Owner input pending; not live verified |
| Basemap/geocoder | Provider input pending; diagram/coordinates available |
| R3 assistant / R4 deployment | Not begun |
