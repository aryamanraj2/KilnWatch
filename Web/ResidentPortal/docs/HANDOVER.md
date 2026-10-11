# Resident portal handover

Updated 10 October 2026. **The resident demo is polished and includes real interactive street maps with fictional kiln data. R2 frontend preparation remains local; no live connection.** The user asked to continue, then confirmed “Not ready — prepare locally” for the public backend. The R1 acceptance gate remains open for the manual checks in [verification](verification.md). Work sequentially; no parallel agents.

## Run and review

Follow [README](../README.md) using Node 24.21.0. `npm run dev` opens a local server at `http://127.0.0.1:5173/`. The normal demo opens on populated Pilkhuwa geography. Adjust the search, load more records, open a record, inspect its evidence/rules, and add one or more records to an editable inspection request. Switch to Hindi and try copy, text download and Print / Save PDF. Every fixture and export identifies sample data.

The portal has seven fictional candidates; an interactive Leaflet/OpenStreetMap basemap; bilingual sample-place lookup and manual coordinates; one-shot opt-in geolocation; radius search, paging and selection; direct details/rules; two/single/missing/failed evidence states; deterministic explanations; optional resident details and editable multi-record drafts. Preferences alone persist. There is no complaint submission or live assistant.

Street geography is real, with visible OpenStreetMap attribution; all demo kiln positions are fictional. Place lookup is local, without a geocoder. Map tiles require internet access and disclose the viewed area/IP to the provider; Privacy explains this. Images are synthetic SVG scenes, not private satellite assets. Unassessed rules and unknown facts remain missing. The UP habitation threshold is unresolved. The orchard comparisons are sample assessments, not real site findings.

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

Local preparation corrects fixture-specific wording in public-mode search, evidence alt text, rule assessments, explanations, exports, attribution and privacy notices. Address lookup is disabled in public mode until a provider exists; manual coordinates and opt-in location work. Decoded image dimensions must match metadata before an image can be used for comparison. Public mode uses the same street basemap, has no geocoder, and deterministic explanations, no live assistant. The contract is still a proposal; these tests cannot prove the server publication boundary.

The next local continuation tightened streamed JSON byte limits/UTF-8 handling, refused API redirects, validated nearby order/radius, and prevented overlapping or inconsistent pages from changing already displayed records. Invalid later pages preserve the list/selection and can recover with a corrected page. Current unit/behavior count is 52; live-mode journeys are seven per engine. Chrome computer-use access was denied when attempting the native 200% zoom check; the manual gap remains. Details and browser-specific limits are in [R2 local preparation](R2-local-preparation.md).

The [AWS teammate / ML team mate checklist](aws-integration-request.md) is prepared but has not been sent. It distinguishes public publication/search/detail/rule/image inputs from model provenance and interpretation. [Public API](public-api-contract.md) and [hosting](hosting-proposal.md) documents are proposals, not deployed infrastructure. Recheck current teammate reports when integration is authorized; this work did not query the AWS account.

## Preservation and stop

All additions are under `Web/ResidentPortal/` on the existing `webApp` branch. Existing app/backend/model files are unchanged. Dependencies, browser downloads, local runtime, build output and temporary PDF tools are ignored. No commit, push, deployment, retraining, private evidence publication or teammate communication occurred. Next: obtain the approved public contract/base URL and publication proof, then complete deployed R2 verification. The current authorization is local preparation; R3/R4 are not authorized by this continuation.

## Finished demo pass (10 October 2026)

User request: finish the web app with maps and demo data. This locally authorized
map/product polish supersedes the earlier diagram-only restriction. No deployment,
AWS/private evidence connection, submission service, commit, push or agents.

The demo opens populated. Street maps support pan, accessible numbered pins,
zoom/reset, a radius overlay, synchronized selection, and a selected-record card
with evidence/draft actions. Record pages include site maps. Synthetic evidence
now depicts structured agricultural parcels and a kiln-shaped scene; comparison
supports dragging as well as native controls. Additional demo records include
imagery, orchard reference distances and population context. Missing information
remains explicit. Failed imagery moves to `/kilns/SAMPLE-KW-003?demo=image-error`.
Mobile shows the map first, with List/Map views and search settings below it.

Checks and reviewed screenshots: [demo verification](demo-verification.md).
OpenStreetMap is a network dependency; the kiln registry and drafts remain local.
The prepared live client still needs the approved public backend and publication
proof described above. Existing manual accessibility/translation release gaps remain.

## Live mode on the real API (prompt 36, 11 October 2026)

Local only, no hosting, deploy, AWS or CORS change. `npm run dev:live` on `http://localhost:5173` (the only origin the API's CORS allows) with an ignored `.env.local`; see [README](../README.md#live-mode). Fixture mode remains the default and unchanged.

- `src/data/live.ts` validates the real `GET /public/kilns` near query and detail with zod and maps them into the existing `Kiln`/`Page` model: kiln ID as name, unverified prediction with a detector score, `rule_checks` as published (iOS status words, inconclusive never clear), HRSL exposure (null = not assessed), evidence only from the configured CDN host with Copernicus attribution. Page facts the API lacks are stated as unknown. The near query is one page; there is no `/public/rules` call (rule pages come from a kiln's `rule_checks`).
- `src/features/ask/AskPage.tsx` is the resident assistant on the shared `POST /ask`: no auth, one request at a time, no automatic retry, steps/citations/fallback/disclaimer as sent, English answers with a Hindi note, and the 400 / 429 cap / 429 throttle / 503 states.
- Hand checks against the live API passed: near search, the reference kiln (C-HAB-800 497 m vs 800 m, 4,225 people, both images), a zero-flag kiln (not shown as passed), and the inspected kiln by direct link (not found). Three live Ask questions were used. Screens are in `docs/screens/live/`.
- Open: native Hindi review of the new strings; hosting needs the exact `frontend_origin` (see [hosting](hosting-proposal.md)); WebKit was not run for this step.

**Phones (prompt 36b, 11 October 2026):** the iOS-style tab bar, compact top bar, search-first area, kiln "At a glance" card with a sticky action bar, Before | After comparator, flags-only amber rule bars and an Ask composer at the bottom. Desktop is unchanged. See [design](DESIGN.md#phones-prompt-36b-11-october-2026) and `docs/screens/mobile/`.

**Phone Area (prompt 36c, 11 October 2026):** after results the search folds to a one-line summary with Edit, "Use my location" is an icon in the search row, and the map starts at 352 px at 393 × 852 (it was about 700). Desktop is pixel-identical (0 differing pixels at 1440 × 900).
