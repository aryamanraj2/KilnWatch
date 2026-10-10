# Resident portal handover

Updated 10 October 2026. **R1 is locally implemented with synthetic data. R2 is not started.** The acceptance gate remains open for the manual checks in [verification](verification.md). Work sequentially; no parallel agents.

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

Strict types, production build, 32 unit/behavior tests and 14 browser journeys pass. English and Hindi PDF pages were rendered and visually reviewed. A dark-theme print background defect was corrected. The detailed evidence and limitations are in [verification.md](verification.md).

Next R1 work is a spoken VoiceOver or equivalent walkthrough, native browser 200% zoom review, and any user review feedback. Accessibility-tree assertions and CSS layout zoom are useful evidence but do not close those manual gaps. Independent Hindi review remains a release input. Do not claim full accessibility certification.

## Integration inputs, separately

The [AWS teammate / ML team mate checklist](aws-integration-request.md) is prepared but has not been sent. It distinguishes public publication/search/detail/rule/image inputs from model provenance and interpretation. [Public API](public-api-contract.md) and [hosting](hosting-proposal.md) documents are proposals, not deployed infrastructure. Recheck current teammate reports when integration is authorized; this work did not query the AWS account.

## Preservation and stop

All additions are under `Web/ResidentPortal/` on the existing `webApp` branch. Existing app/backend/model files are unchanged. Dependencies, browser downloads, local runtime, build output and temporary PDF tools are ignored. No commit, push, deployment, retraining, private evidence publication or teammate communication occurred. Wait for the user's go before R2; do not interpret a ready endpoint as authorization.
