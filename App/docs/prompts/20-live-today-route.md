# KilnWatch — prompt 20: live Today route

Run in a **new Claude Code builder chat**, in the existing checkout. P1 (`POST /routes/plan`) is live and was reviewed by the orchestrator. Prompts 18 and 19 passed review. This builder may use Xcode and the Simulator; no other builder may use them at the same time.

## 1. Scope and authorization

In live (public API) mode, Today plans an inspection route **on a user tap** through `POST /routes/plan`, shows it with the existing route UI (map, stop pins, road legs, carousel, route list, Apple Maps handoff), caches it, and reopens the saved plan without spending another plan. Keep the labelled Sample data route only where it already exists (DEBUG, no configuration). Preserve the current design and the live registry, imagery, rules/exposure and Ask behavior.

Running this prompt authorizes local iOS edits, tests, builds, Simulator checks, screenshots, a few public registry/image GETs, and **at most 3 live `POST /routes/plan` attempts in total** for the whole phase (scripts, app taps and manual retries all count; fewer is better). The route cap is **15 plans per UTC day, shared** with Ask's `plan_route` and every other caller, and each plan costs money. A cancelled or failed POST may still count. No automatic retries. Keep a local count of every live attempt. If you get `daily_cap_reached`, stop sending and finish with local stubs. **Zero live `POST /ask`** in this phase. No counter, log or AWS reads.

No sub-agents. No AWS CLI, Terraform, consoles, credential files, or `AWS/`/`Model/` reads or edits. No backend changes: the AWS lane owns `App/docs/api-contract.md`, the plan and the orchestrator prompts; read them, don't edit them. No installations, staging, commits, pushes or cloud writes. No sign-in, `GET /routes/today`, verdict sync, P2 inspection-sheet work, Hindi or general polish.

Own `App/` changes only. Leave the root project alone unless a test reference needs it; never add the project to itself. Preserve unrelated changes and the old Phase 2 logs. Do not pull, reset, rebase or switch branches.

## 2. Read and baseline

Read in order:

1. `AGENTS.md`
2. `App/docs/HANDOVER.md` (newest sections at the end), `App/docs/build-plan.md`, `App/docs/DESIGN.md` (binding)
3. `App/docs/api-contract.md`: **"P1: `POST /routes/plan`"**, plus the kiln record and "Phase 4A — Ask" error conventions
4. `App/docs/prompts/19-rules-and-exposure-ui.md` and `App/docs/screens/phase-4c/rules-exposure-report.md` (style, scope and review bar)
5. Current code: `Features/Today/*` (`TodayView`, `RoutePresentation`, `PublicRegistryMap`), `KilnWatchApp.swift` (`AppModel`, `routeState`, `loadRoute`, `planRouteInAsk`, demo states), and in KilnWatchCore `Route`/`Stop`/`RouteLeg`/`RoadAccess`, `RouteCache`, `RouteRefresh`, `RouteNavigation`, `Ask.swift` (POST + nested error + gateway-429 handling) and their tests

Use the Axiom iOS skills where useful (SwiftUI, MapKit, testing); otherwise Apple's documentation. Check git status and recent hashes/subjects (no author metadata). Save a starting changed-file inventory under ignored `.local/phase-4d/`. Keep the iOS **26.1** minimum and current Swift settings.

Recorded bodies to read programmatically (don't print them): `.local/phase-4/live/p1/plan1-people.json` (8 stops, default start), `plan3-start.json` (5 stops, explicit start), `plan5-invalid.json` (400 body). They have no hosts, but sanitize anyway before copying into tracked test resources: remap real kiln IDs to full-format synthetic IDs consistently (stops, legs `to_kiln_id`, kilns), keep numbers, notes and statuses realistic, and label them recorded/sanitized.

## 3. Current architecture to respect

- With a public API configured, `TodayView` shows `PublicRegistryMap` (all flagged kilns, no route). `RouteMap` only runs in fixture/authenticated mode, and `loadRoute` / `planRouteInAsk` return early in public mode. This phase connects the live plan to the existing `RouteMap` UI instead of building a second route screen.
- `RouteRefresh` targets the signed-in `GET /routes/today` and clears the cache on 404. **A plan request must never clear or overwrite a saved plan unless it succeeds.** Leave the `GET /routes/today` path working for fixtures and the future signed-in mode.
- `Route` already decodes the P1 body except `notes`. Add `notes: [String]?` (optional, so old caches and fixtures still decode).

## 4. Request and flow

- Request body, exactly: `{"district": "<district>", "priority": "people", "max_stops": 8}`. No `start` (the server uses the centre of the selected kilns and says so in `notes`; the Simulator's location is not in Hapur), no `depart` (server default: tomorrow 09:00 Asia/Kolkata), no `budget_min`, no `kiln_ids`. The district comes from the app's current registry district (Hapur is the only one today); add no picker.
- Public, no `Authorization` header, existing base URL + `/routes/plan`, JSON, no caching of the request, one request at a time (disable the action while in flight, guard double taps), a timeout like Ask's.
- **Never plan on launch, on tab switch, on foreground, on pull-to-refresh or on retry without a tap.** On launch, show the saved plan from `RouteCache` if there is one (no network), else the registry map with the plan action.
- Entry points: a primary bottom action on the live Today map, "Plan tomorrow in Hapur" (district from data), with one line under it: "Up to 8 stops · most people within 800 m · visited in road order". With a saved plan: "Plan again" (replaces it only on success) and a way back to all kilns that keeps the saved plan. Follow DESIGN.md: primary action in the bottom third, ink button, no new colors, no glass cards.
- Replace the old public-mode dead end: the existing empty state's "Plan a route" must plan directly (or be removed in live mode); don't route it through Ask.
- No "Ask about this plan" prefill: Ask is stateless, and its `plan_route` would spend another plan.

## 5. Showing the plan (honest labels)

- Header: the plan's day, not "Today", when `depart` is not today in Asia/Kolkata, for example "Tomorrow · Hapur" or "Sun 11 Oct · Hapur", then "8 stops · est. 6 h 10 m · leave 09:00". Totals and times are **estimates**: never a bare "ETA 09:13"; use "Estimated arrival 09:13" (compact: "Est. 09:13") everywhere, including the carousel, route list, bottom accessory and VoiceOver.
- Order: "visited in road order". Never "most exposed first" or "priority order". The stops were *chosen* by people within 800 m, then ordered by driving time.
- Access: show the server's `access.note` verbatim ("Kiln centroid, not a verified entrance · confirm on site"). A centroid is not an entrance even though it is a valid coordinate.
- Stop card: full kiln ID, the sheet's flags (rule IDs and the kiln's measured-against-threshold line from 19), "N people within 800 m" (modelled, keep the HRSL attribution reachable as in 19), and the on-site checks. A stop with `rules_flagged: []` (the recorded people plan has one) says "No rule flags measured" with the partial-assessment note; never "clear" or "compliant". Every kiln stays "Flagged by satellite · pending inspection".
- `notes[]`: show them in the route list sheet in a "Plan notes" section, verbatim, in order. Don't paraphrase them into other places.
- No `legs` or invalid geometry: stops and pins still work, no lines, the existing "Road geometry unavailable · stops still usable" banner, and no fabricated total time.
- Saved plan: the existing "Saved plan · <date>" behavior; offline keeps it usable with "Offline · showing saved route".
- Apple Maps: per-stop Navigate and "Open whole route in Maps" keep working, in server order; opening Maps never advances a stop.
- Kiln detail from a stop loads live detail by full ID as today.

## 6. Errors (plan request)

Parse the nested `{"error": {"code", "message", "retryable"}}` body. Never show the server `message` raw or any provider text; keep the existing saved plan in every failure.

| Response | Show | Action |
|---|---|---|
| 400 `invalid_request` | "The plan request was rejected." | none (it's a client bug; log a count, not the body) |
| 404 `no_kilns` | "No flagged kilns with population estimates in <district> to plan." | none |
| 429 `daily_cap_reached` | "Route planning has reached today's limit. It resets at 05:30 IST (00:00 UTC)." | no retry today |
| 429 with no `error.code` (gateway body `{"message":"Too Many Requests"}`) | "Too many requests. Wait a moment." | manual Retry |
| 503 `routing_unavailable` / `upstream_unavailable` | "Route planning is unavailable right now." | manual Retry only if `retryable` |
| Transport / timeout | offline wording; the saved plan stays | manual Retry |
| Undecodable 200 | "The plan could not be read." | none |

Unknown codes fall back by status honestly. No error ever substitutes the sample route in live mode.

## 7. Tests, live checks and screenshots

Local `URLSession` stubs for automated checks. Cover: exact request body and no auth header; decoding of the sanitized recorded plans (8 stops/8 legs with notes; 5 stops); `notes` optional for old caches and `route_today.json`; a plan without `legs`; a stop with empty flags; every error row above including the code-less gateway 429; a failed plan keeps the saved plan; the cache round-trip; no request on model init / launch path; estimated-time strings never produce a bare "ETA". Keep all existing tests green.

Run sequentially: `cd App/Packages/KilnWatchCore && swift test`, then from the root `xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build`. Zero app/core warnings.

Live: one tap of "Plan tomorrow in Hapur" in the app against the configured API should be enough (2 more allowed only if needed, e.g. for one failure). Check: 8 stops, all IDs exist in the registry, notes shown, legs drawn, estimates labelled, Navigate opens Maps for one stop. Then relaunch and confirm the saved plan appears with **no** POST. Error states, AX and dark screenshots use stubs, labelled.

Screenshots in `App/docs/screens/phase-4d/`: live plan map + carousel, route list with plan notes and access note, saved plan after relaunch, the plan action on the registry map, no-legs, cap reached, gateway 429, offline saved, light/dark, AX3/AX5, Reduce Motion. Inspect each yourself; say which are live and which are stubbed.

## 8. Leak scan, report, stop

The repo is public. Never write or print account IDs, ARNs, the API URL/host/ID, the CloudFront domain, the bucket, database hosts, emails or tokens. Scan every changed tracked file, test resource and screenshot (OCR plus exact-value binary checks) against values read internally from the app's ignored configuration; report counts only. Raw bodies stay under `.local/phase-4d/`.

Write `App/docs/screens/phase-4d/live-today-report.md`: behavior, owned files, test/build results and warning counts, the live POST count (`POST /routes/plan` used N of 3; `POST /ask` 0), screenshot provenance, leak counts and remaining limits (Simulator only, no physical device, no turn-by-turn proof). Add a short note at the end of `App/docs/HANDOVER.md`. Stop for orchestrator review: no staging, commit or next phase.
