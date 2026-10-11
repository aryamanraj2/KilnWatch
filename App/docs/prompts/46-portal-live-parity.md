# Prompt 46: resident portal works end to end on live data, map-first like iOS

Use a **new Codex chat**. One builder, **no sub-agents** (one lane). Don't stage, commit or push. The repo is public.

## 1. Why this prompt exists

The hosted portal is wired to the live API, but in practice **it doesn't work for a visitor**. The orchestrator opened the hosted site at 390 px (11 Oct, after 43c):

- The place field is **disabled** ("Address search needs an approved provider. Enter coordinates below."). A visitor must open Area settings and type latitude/longitude to see anything.
- Nothing is on the map until a search succeeds.
- The local prompt-45 polish (uncommitted, not uploaded) accepts only the exact word "Hapur", rejects anything else with a validation error, and its 5 km circle around one point returns **22 of the 38** flagged kilns.

**User direction (binding):** the portal must work like the iOS app. Whatever a visitor types, they get the **Hapur map with every kiln highlighted**, and everything that's built (records, evidence, Ask, inspection requests, the draft) works on live data. Hapur is the only district for now; the user will add a coverage note **after** recording the video, so **don't add a new coverage warning now** (keep the existing "Hapur, Uttar Pradesh" context line).

**Do not touch the iOS app**: no files under `App/` except reading docs, no Swift, no Xcode, no Simulator. Build on top of the current working tree, which includes prompt 45's uncommitted portal polish; keep its design.

## 2. Authorization

Running this prompt authorizes:
- local edits in `Web/ResidentPortal/` only, plus `Web/ResidentPortal/docs/`;
- GET/HEAD reads of the public API, the evidence CDN and the hosted portal (private config read silently from `.local/` and the ignored `Web/ResidentPortal/.env.production.local`, never printed);
- **at most 2 live `POST /ask`** calls for the final check (Ask cap is 100/day, shared with iOS); **no** live `POST /requests`, `/verdicts` or `/routes/plan`;
- after all checks pass, **one** hosted re-upload by 37's procedure: `npm run build` with the ignored `.env.production.local`, two-pass `s3 sync` to the portal bucket, invalidate `/*`. First check both `aws login` sessions (`kilnwatch`, `kilnwatch-bedrock`) with masked output; if either fails, stop and ask the user to sign in. No other AWS action.

Not allowed: API or contract changes, backend code, Terraform, DB writes, iOS files, new map/geocoding providers that need keys or accounts, analytics.

## 3. What to build

Read first: `AGENTS.md`, `App/docs/prompts/44-orchestrator-handover.md` §1, `Web/ResidentPortal/README.md`, `Web/ResidentPortal/docs/DESIGN.md` (binding), `App/docs/api-contract.md` "Integration 2C", "R1", "Phase 4A — Ask", "Inspection requests (43)". Then open the current local portal in live mode and the hosted portal and use them like a resident before changing anything.

**3.1 Map-first area page (live mode).**
- On load, without any search, fetch **all Hapur kilns** with `GET /public/kilns?district=Hapur` (follow `next_cursor` until null; the default flagged-only read) and show them on the Leaflet map, fitted to their bounds, plus the list. Today that's 38 kilns. Loading, error-with-retry and empty states stay honest.
- Each kiln is drawn **like iOS**: its footprint polygon plus a pin, in the existing status colour, with a clear selected state. Tapping a kiln (map or list) selects it and shows the compact card (ID, status line "Flagged by satellite · pending inspection", top rule, people within 800 m, resident request count when > 0, after-image thumbnail) with a link to the record. The list and map stay in sync.
- **Search never dead-ends.** Whatever is typed (a place, an address, "Delhi", anything) and submitted shows the full Hapur map with every kiln highlighted. Special cases:
  - a kiln ID or a prefix of one (e.g. `KW-04e7`) selects and zooms to that kiln if it matches; otherwise show all kilns;
  - coordinates (`28.73, 77.77`) or **Use my location**: still show every Hapur kiln, add a "You" marker at that point, and sort the list by distance from it (computed client-side from the footprint edge or centroid; say which in the list label);
  - an empty submit shows all kilns.
  - Remove the disabled state, the "approved provider" message and the "Only the Hapur pilot area…" validation error. The radius control is no longer needed for filtering; remove it or keep it only as the "near you" sort distance cap. Don't call it a legal buffer.
- Keep the map basemap as OpenStreetMap with its attribution. A satellite toggle is optional: only add it if a no-key imagery source's terms allow this use, with its required attribution; otherwise skip it and say so in the report.
- Fixture mode keeps working with the sample data and its labels (tests depend on it).

**3.2 Everything else on live data**, checked by hand on the local live build, then the hosted site:
- record page: rule checks, exposure, before/after evidence images from the CDN, resident requests block and the request form (submit **mocked** in tests; no live POST), "View your request" after sending;
- Ask page: answers with citations that open the record page; the "Ask about this kiln" button pre-fills; errors (cap, busy, network) read correctly;
- the draft/export flow still works from a selected kiln.
Fix anything that is broken or still sample-only in live mode. If something can't work without a backend change, don't change the backend; list it in the report.

**3.3 Copy rules.** Never "illegal", "unlawful" or "violation". A kiln is "Flagged by satellite · pending inspection". Counts are real (0 is a real resident-request count; missing data is never 0). English and Hindi through `t()`; mark new Hindi "needs native review" as existing code does. Never the word "petition".

## 4. Checks

- `npm run typecheck`, `npm test`, `npm run build`, mocked `test:e2e:live` and the sample suite on Chromium. Update tests for the new search behaviour (any text → all kilns; kiln ID → that kiln; coordinates → sorted by distance; no disabled field).
- Light only, phone width 390 and one desktop. Screenshots in `Web/ResidentPortal/docs/screens/parity-46/`: landing with all kilns, "Delhi" typed and submitted (all kilns), a kiln ID search, a selected kiln card, a record page with evidence, an Ask answer (from the mocked suite).
- After the upload: open the **hosted** site at 390 px, read-only: landing shows all 38 kilns without any input; submit "Delhi" → all 38; open one record; images load; no page or CORS errors. Use at most 2 live Ask calls total across the whole prompt.

## 5. Report

Diff summary; what was broken and what you fixed; test counts; screenshots; the hosted check; the upload and invalidation summary (no identifiers); live POST count (Ask ≤ 2, everything else 0); leak check of changed files against every identifier in `.local/` and the tfvars (expect 0); banned-word grep of `Web/ResidentPortal/src` (expect 0); anything that still needs a backend change. Add a short entry to `Web/ResidentPortal/docs/HANDOVER.md`.
