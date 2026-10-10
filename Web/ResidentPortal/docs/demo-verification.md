# Resident demo completion · 10 October 2026

Local product polish, on the existing `webApp` branch, sequentially without agents.
The user requested a finished web app with maps and demo data. No iOS, AWS or model
source changes, deployment, private image publication, commit or push.

## Implemented

- Populated Pilkhuwa demo on first entry; explicit search remains required in live mode.
- Leaflet 1.9.4 / OpenStreetMap basemap, pan, native accessible pin buttons, zoom/reset,
  scale, search-radius overlay, footprint overlays and synchronized record selection.
- Selected-record card with evidence and basket actions; site location maps in records.
- Neutral/clay product layout, mobile map-first view, visible result count in both views.
- Synthetic parcel/road/orchard/kiln evidence scenes, pointer comparison, additional
  evidence/measurement/population fixtures, and retained honest missing-data states.
- Map attribution, origin-only tile referrers, provider disclosure in Privacy, and
  continued allowlisting of thumbnail/evidence URLs. Personal details are not sent to maps.

## Validation

Final build and unit checks use the ignored Node 24.21.0 runtime documented in README.

| Check | Result |
| --- | --- |
| TypeScript + Vite production build | Pass, no build warnings |
| Unit/behavior suite | 52 pass |
| Chromium demo journeys | 8 pass |
| WebKit demo journeys | 8 pass |
| Chromium mocked public-client journeys | 7 pass |
| WebKit mocked public-client journeys | 7 pass |
| Git whitespace check | Pass |

Functional browser checks mock tile responses to avoid repeatedly fetching community
map tiles. They cover selection, pagination, Back navigation, location denial, form
validation, missing/failed evidence, drag/keyboard comparison, basket actions, editable
exports, Hindi, theme changes, narrow reflow and automated axe checks. Public-client
checks intercept API/evidence calls; they do not establish live AWS integration.
Playwright emits environment `NO_COLOR`/`FORCE_COLOR` warnings, unrelated to app code.

A separate visual review used real OpenStreetMap responses for the displayed area
and record location. The two review sessions received 8 and 4 successful tile
responses respectively and emitted no browser page errors. No map scans, prefetch,
offline tile archive or geocoder was added.

Reviewed artifacts:

- [Desktop map](screens/demo/desktop-map.png)
- [Mobile map](screens/demo/mobile-map.png)
- [Record and evidence](screens/demo/record-evidence.png)
- [Inspection draft](screens/demo/inspection-draft.png)

Maps require an internet connection. Record selection/list/drafting remain available
when tile requests fail. This is a complete local demo, with fictional records and
synthetic evidence; there is no complaint submission or live assistant. Existing
spoken accessibility/native 200% zoom and independent Hindi review gaps remain
release inputs; automated checks do not certify those manual gates.

Implementation references: [Leaflet reference](https://leafletjs.com/reference.html)
and [OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/).
