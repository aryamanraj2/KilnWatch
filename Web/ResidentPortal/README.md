# KilnWatch resident portal

Phase R1: a local English/Hindi resident experience using explicit sample data. No account, live AWS connection, submission service, or deployment is required. The private inspector app and backend are unchanged.

Live mode (prompt 36, 11 October 2026) reads the real public API locally: flagged Hapur kilns, their rule checks, exposure and evidence, plus the resident assistant (Ask, the same `POST /ask` the iOS app uses). Fixture mode stays the default. Portal hosting is managed separately; prompt 43 has not re-uploaded it.

## Run locally

Use **Node 24.21.0 LTS**, recorded in `.node-version` and `.nvmrc`, and npm. From the repository root:

```sh
cd Web/ResidentPortal
nvm use                 # or use your preferred Node version manager
npm ci
npm run dev
```

Open `http://127.0.0.1:5173/`. The demo opens on a populated **Pilkhuwa** street map. Adjust the search or load more records, open a record, and add it to an inspection draft. Hindi is available from the header. All seven candidates, positions, assessment measurements, verdict examples, population counts, and evidence scenes are fictional.

This workstation also has an isolated, ignored runtime at `.runtime/node_modules/node/bin/node`. It is a convenience, not a checked-in dependency. To use it here, prefix npm commands with `PATH="$PWD/.runtime/node_modules/node/bin:$PATH"`. The system Node 26 runtime is not the pinned build runtime.

## Checks

```sh
npm run typecheck
npm test
npm run build
npx playwright install chromium webkit
npm run test:e2e -- --project=chromium
npm run test:e2e -- --project=webkit
npm run test:e2e:live -- --project=chromium
npm run test:e2e:live -- --project=webkit
```

Functional browser checks mock map tile responses to avoid repeatedly fetching community tiles. Separate visual review checks real provider rendering. Browser checks use one worker, no retries, and a local Vite server. Engines are run sequentially. On this workstation browsers were downloaded to the ignored `.cache/ms-playwright`; set `PLAYWRIGHT_BROWSERS_PATH=.cache/ms-playwright` when running tests. Do not install a second cache unnecessarily. The browser suite creates a small set of review artifacts under `docs/screens/`; failure traces and reports are ignored under `test-results/`.

`test:e2e:live` starts a separate Vite server on port 5174 in live mode and intercepts every API, Ask and image request with recorded real-shape responses (`tests/fixtures/hapur-near.json`, sanitized hosts) and generated 256-pixel PNGs. It does not contact AWS. Run it on Chromium. Set `KW_ARTIFACT_DIR=.cache/sample-review` on sample-suite runs to keep regenerated review files separate from the previously reviewed `docs/screens/` artifacts and Playwright's cleared result directory.

`npm run preview` serves the production `dist/` build locally. No script deploys, commits, or pushes. Tests use fictional personal details only. The production build has no source maps and no development fault controls.

## Live mode

The API's CORS allows exactly the origin `http://localhost:5173`; `127.0.0.1:5173` is a different origin and the browser blocks it. Create an ignored `.env.local` (all `.env*` files are ignored) with placeholder-shaped values:

```sh
VITE_DATA_MODE=live
VITE_PUBLIC_API_BASE_URL=https://<public-api-host>
VITE_PUBLIC_IMAGE_HOSTS=<evidence-cdn-host>
```

Then run `npm run dev:live` and open `http://localhost:5173/`. Never commit the real values or put them in screenshots. Unit and browser tests force their own configuration, so a local `.env.local` does not affect them; `npm run dev` and `npm run build` do read it.

What live mode shows, from the real contract (`App/docs/api-contract.md`, Integration 2C, R1 and Phase 4A):

- Search sends `GET /public/kilns?lat=…&lon=…&radius_m=…` (one page, at most 50, distance to the kiln footprint). Records use the full kiln ID as their name and say "Flagged by satellite · pending inspection". Predictions are unverified; the score is a detector score.
- Rule checks are shown as published, with the iOS status words. Inconclusive is never shown as clear; a record with no siting flag says it did not pass anything. Rule pages are built from a kiln's own `rule_checks` (there is no rule route).
- Exposure is modelled residents within 800 m of the kiln edge, with the HRSL attribution; null is "not assessed". Evidence images load only from the configured CDN host, with the Copernicus attribution.
- The API does not publish a dataset revision, coverage or update time, so the page says "Update time not published" and "Coverage unknown".
- Default reads only: a kiln that is no longer public (for example after an inspector verdict) shows the not-found state.
- **Ask** (`/ask`, and "Ask about this kiln" on a record): one trimmed question of 1–500 characters, one request at a time, no automatic retry. It shows the answer as plain text, the server's step labels, citation links to records, the fallback state and the server disclaimer. Answers are English only. The shared daily cap applies; a 429 with `daily_cap_reached` says the limit resets at 05:30 IST.

## Data configuration

The default is `fixture`. To make it explicit, copy `.env.example` to ignored `.env.local`. **Vite variables are public browser-bundle contents, never a place for secrets.**

| Variable | Meaning |
|---|---|
| `VITE_DATA_MODE` | `fixture` (default) or `live`. An unknown value fails closed. |
| `VITE_PUBLIC_API_BASE_URL` | HTTPS public API prefix (no `/v1`). Only in an ignored `.env.local`. No inspector token. |
| `VITE_PUBLIC_IMAGE_HOSTS` | Comma-separated exact HTTPS evidence hosts, no wildcard. Only in an ignored `.env.local`. |
| `VITE_FIXTURE_SCENARIO` | Optional development-only failure case, listed below. |

Live mode never falls back to fixtures. It was checked by hand against the real API on `localhost` (see [handover](docs/HANDOVER.md)); unit tests and `test:e2e:live` use recorded real-shape bodies with fake hosts.

The public client enforces a 1,000,000-byte streamed JSON limit, rejects invalid UTF-8 and API redirects, and verifies page order, supplied distances within the query radius, and snapshot consistency. The [old proposal](docs/public-api-contract.md) is superseded by the real contract.

For local failure review, start in development mode at one of these URLs, then choose a sample area and search:

| URL | Behavior |
|---|---|
| `/?demo=unavailable` | Service failure; search input survives. |
| `/?demo=malformed` | Malformed-response presentation. |
| `/?demo=empty` | No records in known sample coverage. |
| `/?demo=unknown` | Unknown coverage, no clean-air/compliance inference. |
| `/?demo=partial` | First page succeeds; later page fails while loaded records remain. |
| `/?demo=stale` | Older dataset date explicitly labeled. |
| `/?demo=map-error` | Map unavailable; list and drafting remain usable. |

Use `/kilns/SAMPLE-KW-003?demo=image-error` to review failed evidence and retry behavior.

A scenario is selected at page load and remains for that document session. Return to `/` with a full reload to clear it. The query string contains only a diagnostic scenario, never resident coordinates or drafts. An environment scenario takes precedence. These controls are removed in production builds.

## Behavior and limits

- Bilingual sample-place lookup, Devanagari coordinate digits, opt-in one-shot geolocation, radius confirmation, synchronized map/list, bounded paging, and session Back navigation.
- Interactive Leaflet street maps use OpenStreetMap tiles, with attribution, pan, zoom, reset, search-radius overlays, numbered selections and record location maps. Geography is real; all demo sites are fictional. Tile requests expose the viewed map area and IP address to OpenStreetMap. Near the poles or on map failure, the list remains usable.
- Synthetic before/after evidence, single/missing/broken evidence, per-image outlines, source links, provisional predictions, unknown facts, and deterministic explanations.
- Up to ten selected records in an editable inspection request. Optional personal details and explicit location opt-in. Copy, UTF-8 text download, and browser Print/Save as PDF. Evidence URLs are references, not attachments. Nothing is filed or sent.
- Language/theme preferences, one random browser code, and requested kiln IDs/dates use local storage (with a memory fallback if storage is denied). Sample and live request storage are separate. Written drafts remain memory-only; refresh loses them. Meaningful unsaved draft changes prompt before replacement or unloading. Browser unload warnings depend on browser support/user interaction.
- No external geocoding, analytics, service worker, citizen account, notification system, private image proxy, model weights, or automatic complaint submission.
- Legal sources are references with stated limits. The UP habitation threshold is unresolved. A sample orchard comparison is not a finding about a real site.

## Documentation

- [Plan](docs/PLAN.md) and [web design](docs/DESIGN.md).
- [Public API proposal](docs/public-api-contract.md) and [AWS/ML integration inputs](docs/aws-integration-request.md).
- [Hosting proposal](docs/hosting-proposal.md), [handover](docs/HANDOVER.md), and [verification](docs/verification.md).

Implementation references: [Vite](https://vite.dev/guide/), [Node releases](https://nodejs.org/en/about/previous-releases), [React Router declarative installation](https://reactrouter.com/start/declarative/installation), and [Playwright configuration](https://playwright.dev/docs/test-configuration). Versions actually installed are pinned in `package.json` and `package-lock.json`.

## Inspection requests (prompt 43, 11 October 2026)

Local implementation is complete; backend deployment and portal re-upload are pending. The record page offers a primary **Request an inspection** action with concern checkboxes and a self-reported distance band. The written draft/export flow remains available as **Prepare a written request**.

Live mode sends one `POST /requests` body from the frozen contract in `App/docs/api-contract.md`. No names, phones, free text or precise residential locations are sent. Anonymous, unverified counts appear on records and area results when positive. Successful POST responses update the displayed count immediately; public counts can lag about two minutes. Browser code and requested kiln dates are retained when storage is available; storage denial uses document memory. Duplicate acknowledgements show the already-requested state. Errors preserve answers and writes are never retried automatically.

Fixture mode simulates the flow and keeps its existing sample labels; no request reaches a server. The shared sanitized fixture is `tests/fixtures/requests-recorded.json`. `test:e2e:live` mocks request submissions alongside public reads, Ask and imagery. Request screenshots are under `docs/screens/requests/`.
