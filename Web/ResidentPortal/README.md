# KilnWatch resident portal

Phase R1: a local English/Hindi resident experience using explicit sample data. No account, live AWS connection, submission service, or deployment is required. The private inspector app and backend are unchanged.

R2 frontend preparation is now locally implemented. The user confirmed the public backend is not ready; default data remains fictional. See [local R2 preparation](docs/R2-local-preparation.md) for the tested path and service inputs still needed.

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

`test:e2e:live` starts a separate Vite server on port 5174 in live mode and intercepts every test API/image request with fictional contract responses and generated 256-pixel PNGs. It does not contact AWS, change `.env`, or establish public publication approval. Set `KW_ARTIFACT_DIR=.cache/sample-review` on sample-suite runs to keep regenerated review files separate from the previously reviewed `docs/screens/` artifacts and Playwright's cleared result directory.

`npm run preview` serves the production `dist/` build locally. No script deploys, commits, or pushes. Tests use fictional personal details only. The production build has no source maps and no development fault controls.

## Data configuration

The default is `fixture`. To make it explicit, copy `.env.example` to ignored `.env.local`. **Vite variables are public browser-bundle contents, never a place for secrets.**

| Variable | Meaning |
|---|---|
| `VITE_DATA_MODE` | `fixture` (default) or `live`. An unknown value fails closed. |
| `VITE_PUBLIC_API_BASE_URL` | Future approved HTTPS public API prefix. No `/v1` is appended automatically. Blank in R1. No inspector token. |
| `VITE_PUBLIC_IMAGE_HOSTS` | Comma-separated exact HTTPS evidence hosts, no wildcard. Empty in R1. |
| `VITE_FIXTURE_SCENARIO` | Optional development-only failure case, listed below. |

Live configuration is exercised by unit tests and local browser journeys, **not completed R2 integration**. It never falls back to fixtures. The user authorized local preparation; do not configure a real endpoint until the public projection and service are approved/ready.

The public client enforces a 1,000,000-byte streamed JSON limit, rejects invalid UTF-8 and API redirects, and verifies page order, supplied distances within the query radius, and snapshot consistency. Configure the final HTTPS API prefix directly. Backend distance rounding and ID ordering must agree with the [proposed contract](docs/public-api-contract.md) before live connection.

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
- Language/theme preferences are the only local-storage values. Other state is memory-only; refresh loses it. Meaningful unsaved draft changes prompt before replacement or unloading. Browser unload warnings depend on browser support/user interaction.
- No external geocoding, live assistant, analytics, service worker, citizen account, notification system, private image proxy, model weights, or automatic complaint submission.
- Legal sources are references with stated limits. The UP habitation threshold is unresolved. A sample orchard comparison is not a finding about a real site.

## Documentation

- [Plan](docs/PLAN.md) and [web design](docs/DESIGN.md).
- [Public API proposal](docs/public-api-contract.md) and [AWS/ML integration inputs](docs/aws-integration-request.md).
- [Hosting proposal](docs/hosting-proposal.md), [handover](docs/HANDOVER.md), and [verification](docs/verification.md).

Implementation references: [Vite](https://vite.dev/guide/), [Node releases](https://nodejs.org/en/about/previous-releases), [React Router declarative installation](https://reactrouter.com/start/declarative/installation), and [Playwright configuration](https://playwright.dev/docs/test-configuration). Versions actually installed are pinned in `package.json` and `package-lock.json`.
