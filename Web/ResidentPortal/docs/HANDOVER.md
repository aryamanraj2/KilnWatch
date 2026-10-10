# Resident portal handover

Updated 10 October 2026. **R1 is locally implemented with synthetic data. R2 frontend preparation is locally implemented; no live connection.** The user asked to continue, then confirmed “Not ready — prepare locally” for the public backend. The R1 acceptance gate remains open for the manual checks in [verification](verification.md). Work sequentially; no parallel agents.

## Run and review

Follow [README](../README.md) using Node 24.21.0. `npm run dev` opens a local server at `http://127.0.0.1:5173/`. Select Pilkhuwa, confirm, load more records, open a record, inspect its evidence/rules, and add one or more records to an editable inspection request. Switch to Hindi and try copy, text download and Print / Save PDF. Every fixture and export identifies sample data.

The portal has seven fictional candidates; a coordinate-based interactive diagram; bilingual sample-place lookup and manual coordinates; one-shot opt-in geolocation; radius search, paging and selection; direct details/rules; two/single/missing/failed evidence states; deterministic explanations; optional resident details and editable multi-record drafts. Preferences alone persist. There is no complaint submission or live assistant.

The local map is explicitly an illustration without a basemap or geocoder. Images are synthetic SVG scenes, not private satellite assets. Unassessed rules and unknown facts remain missing. The UP habitation threshold is unresolved. The orchard example is a sample assessment, not a real site finding.

## Code map

- `src/data/`: public validation, geodesic helpers, fixtures and a future read-only live-client boundary. Mock HTTP tests do not establish live integration.
- `src/app/`: routing and memory-only query, selection and draft state; cancellation and draft replacement protection.
- `src/features/`: area search/diagram, evidence, record/rule explanations, drafting and information pages.
- `src/i18n/`, `src/styles/`: bilingual presentation, app-design tokens, responsive layout and print output.
- `tests/`: data/behavior tests and sequential Chromium/WebKit journeys. `docs/screens/` contains reviewed examples and local performance evidence.

## Verified and remaining

The original R1 checks passed with 32 unit/behavior tests and 14 browser journeys; English and Hindi PDF pages were rendered and visually reviewed. The continuation adds live-mode browser preparation and dimension validation; current results and limits are in [R2 local preparation](R2-local-preparation.md) and [verification](verification.md).

Next R1 work is a spoken VoiceOver or equivalent walkthrough, native browser 200% zoom review, and any user review feedback. Accessibility-tree assertions and CSS layout zoom are useful evidence but do not close those manual gaps. Independent Hindi review remains a release input. Do not claim full accessibility certification.

## Integration inputs, separately

Local preparation corrects fixture-specific wording in public-mode search, evidence alt text, rule assessments, explanations, exports, attribution and privacy notices. Address lookup is disabled in public mode until a provider exists; manual coordinates and opt-in location work. Decoded image dimensions must match metadata before an image can be used for comparison. Public mode still has an illustrative geographic diagram, no basemap/geocoder, and deterministic explanations, no live assistant. The contract is still a proposal; these tests cannot prove the server publication boundary.

The next local continuation tightened streamed JSON byte limits/UTF-8 handling, refused API redirects, validated nearby order/radius, and prevented overlapping or inconsistent pages from changing already displayed records. Invalid later pages preserve the list/selection and can recover with a corrected page. Current unit/behavior count is 52; live-mode journeys are seven per engine. Chrome computer-use access was denied when attempting the native 200% zoom check; the manual gap remains. Details and browser-specific limits are in [R2 local preparation](R2-local-preparation.md).

The [AWS teammate / ML team mate checklist](aws-integration-request.md) is prepared but has not been sent. It distinguishes public publication/search/detail/rule/image inputs from model provenance and interpretation. [Public API](public-api-contract.md) and [hosting](hosting-proposal.md) documents are proposals, not deployed infrastructure. Recheck current teammate reports when integration is authorized; this work did not query the AWS account.

## Preservation and stop

All additions are under `Web/ResidentPortal/` on the existing `webApp` branch. Existing app/backend/model files are unchanged. Dependencies, browser downloads, local runtime, build output and temporary PDF tools are ignored. No commit, push, deployment, retraining, private evidence publication or teammate communication occurred. Next: obtain the approved public contract/base URL and publication proof, then complete deployed R2 verification. The current authorization is local preparation; R3/R4 are not authorized by this continuation.
