# Prompt 36: resident portal on the live API, with Ask (Agent 3)

You are the builder for **one web step**. Work sequentially in this one chat. No sub-agents. Don't commit, push or stage. The repo is public.

The resident portal (`Web/ResidentPortal/`, React + Vite, built by the AWS teammate) runs only on fictional sample data. Its "live" mode was written against a *proposed* API shape that doesn't match the real one. This step makes it **show the real 39 Hapur kilns** and adds the **resident assistant** (concept Agent 3). That assistant is the **same live `POST /ask`** the iOS app uses; don't build a second one.

**The user gave the go by running this prompt.** The scope is exactly:
1. edits under `Web/ResidentPortal/` only (code, tests, its docs);
2. public `GET /public/kilns…` calls and image fetches through the evidence CDN, as needed;
3. at most **4** live `POST /ask` questions (the shared cap is 100 a day);
4. local runs only. No hosting, no deploy, no AWS CLI or Terraform, and no change to the API's CORS.

**Out of scope:** AWS code, `App/`, the API contract, `POST /routes/plan` (none from the portal), complaint submission, sign-in and hosting. If something needs one of these, stop and report.

## Read first

- `AGENTS.md`, then `Web/ResidentPortal/README.md`, `docs/HANDOVER.md`, `docs/DESIGN.md` and `docs/public-api-contract.md` (the old proposal).
- `App/docs/api-contract.md`: "Integration 2C: public read API", "R1", "Phase 4A — Ask" and the kiln record table. **This is the real contract. Where it differs from the proposal, the real one wins.**
- `src/data/client.ts`, `src/data/model.ts`, and the record, evidence and area features.

## Facts you need

- **CORS:** the API allows exactly the origin `http://localhost:5173`. `npm run dev` binds `127.0.0.1`, which is a *different* origin, and the browser will block it. Run live mode on `http://localhost:5173` (add a `dev:live` script with `--host localhost --port 5173 --strictPort`). Don't ask for a CORS change.
- **Config:** use an ignored `Web/ResidentPortal/.env.local` (`.env*` is already ignored) with `VITE_DATA_MODE=live`, `VITE_PUBLIC_API_BASE_URL` and `VITE_PUBLIC_IMAGE_HOSTS`. Read the API base URL from `.local/integration-2b/outputs.json` (`api_base_url`) and the CDN host from `.local/phase-4/cdn/outputs.json`, without printing them. **Never write either value to a tracked file, a screenshot, a log you commit or this chat.**
- **The real near query** is `GET /public/kilns?lat=…&lon=…&radius_m=…` (100–5000, at most 50 results, sorted by `distance_m`, `next_cursor: null`). It returns `{"kilns": [...], "next_cursor": …}` with the fields `kiln_id`, `footprint`, `type`, `type_verification`, `detection_confidence`, `status`, `violations`, `rules_assessment`, `rule_checks`, `exposure`, `district`, `evidence` (+ metadata), `first_seen`, `last_seen` and `distance_m`. The detail route is `/public/kilns/{kiln_id}`. There is **no** `/public/rules/{id}`, no localized `name`, no `revision`/`coverage`/`updated_at`/`source_url`.
- A good test point: Hapur kilns lie around 28.70–28.78 N, 77.70–77.83 E (for example 28.7306, 77.7759). Pilkhuwa, the sample-place default, is at the west edge.

## Step 1: live data adapter

- **Adapter:** add one adapter (for example `src/data/live.ts`) that validates the **real** response with zod and maps it into the portal's existing `Kiln` / `Page` model. The UI then stays mostly unchanged. Keep fixture mode exactly as it is, and keep it the default.
- **Honest mapping. Never invent a field:**
  - **Name:** the full kiln ID, in both languages.
  - **Prediction:** "unverified"; the score is a detector score, not accuracy.
  - **Rules:** from `rule_checks`, with the status words used on iOS: a siting flag pending inspection; beyond threshold; **inconclusive · map data incomplete (never clear)**; not evaluated; not applicable. Mark `unverified_compilation` thresholds as unverified.
  - **Exposure:** modelled residents within 800 m of the kiln edge, with the HRSL attribution from the contract. Null stays "not assessed", never 0.
  - **Evidence:** `evidence.before`/`.after` URLs, accepted only from the configured CDN host, with the Copernicus attribution from the metadata.
  - **Page fields the API lacks** (revision, coverage, updated_at, distance basis): fill them with values that state the truth ("unknown" coverage, the footprint distance basis). Don't fabricate a freshness date. Adjust `mergePages` / paging for `next_cursor: null`.
- **Rule pages:** build them from the kiln's own `rule_checks` (check label, threshold, measured distance, source text, verification). No `/public/rules` call and no fake source URL. A rule opened without a kiln context says its details come from a kiln record.
- **Status:** every record says "Flagged by satellite · pending inspection" (Hindi: keep the existing translation pattern). Never "illegal", "violation", "compliant" or "clear". Hindi copy for new strings: add a plain translation, and mark it in the report as needing a native review.
- **Errors:** 400 / 404 / 429 (gateway, no `error.code`) / 503 `registry_unavailable` / network map to the portal's existing error states. Never fall back to fixtures.

## Step 2: Ask panel (Agent 3)

Add one simple page or panel, "Ask about kilns near you", that calls `POST {base}/ask` with `{"question": …}`, plus `kiln_id` when asked from a record page. Follow the contract's "Phase 4A — Ask" section:
- **Request:** the question is trimmed, 1–500 characters. No auth header. One request at a time. **No automatic retry.**
- **Answer:** show the answer as plain text, the server's `steps` labels in order, `citations` as links to the record pages (full IDs; only IDs in `citations` become links), the `fallback` state, and the server `disclaimer` verbatim.
- **Errors:**
  - 400: the question is invalid or too long; keep the draft.
  - 429 `daily_cap_reached`: "Ask has reached today's limit" (it resets at 05:30 IST, 00:00 UTC).
  - 429 with no `error.code`: "Too many questions, wait a moment" (manual retry).
  - 503: honour `retryable`.
- **Language:** answers are English only. In Hindi UI mode, say so in Hindi above the box. Don't machine-translate answers.
- **Product line under the box:** "Answers cite public registry records. The assistant never records verdicts." Never present an answer as a finding about a real site.

## Step 3: tests and live check

- **Automated:** `npm run typecheck`, `npm test`, `npm run build`. Unit tests use recorded real-shape bodies: copy `.local/phase-4/live/e1/hapur-list.json` (it has a `<evidence-cdn>` placeholder host) into a test fixture, **re-sanitized**, with a fake `https://cdn.example.test` host. The tests cover:
  - the adapter (flagged, zero-flag partial, null exposure, every rule-check status, evidence URL accepted only on the configured host);
  - the paging change;
  - the Ask request body, success, fallback, and the 400 / 429 / 429-no-code / 503 errors;
  - no fixture fallback in live mode.
- **Browser:** update the existing `test:e2e:live` interception to the real shapes and run it on **Chromium only**. Keep it light.
- **Live, by hand** on `http://localhost:5173` with `.env.local`:
  - search near 28.7306, 77.7759 at 3000 m: real kilns appear;
  - open the reference kiln `KW-6b3b38da681850e5af46b024f3d3f78e` and check C-HAB-800 at 497 m against 800 m, 4,225 people, and before/after images with the attribution;
  - open one zero-flag kiln: not shown as clear.
- **Ask (at most 4 live):**
  1. "How many kilns are flagged in Hapur?"
  2. From the reference kiln's page: "What should I check at this kiln?"
  3. "Which Hapur kilns have the most people within 800 m?"
  4. Spare.

  For each, report the status, the fallback flag, the latency and the full answer (in this chat only).

## Step 4: leak check, docs, report

- **Leak check:** grep every changed and new tracked file, and every screenshot (exact bytes), for the API host, the API ID and the CDN host, read from the `.local` files without printing them. Expect 0. Confirm `.env.local` is ignored (`git check-ignore`). Screenshots go to `Web/ResidentPortal/docs/screens/live/` and must not show the API or CDN URL; crop or hide the devtools.
- **Docs:**
  - update `Web/ResidentPortal/README.md` ("Live mode": the `localhost` origin, `.env.local` keys with placeholder values only, `npm run dev:live`);
  - update `docs/HANDOVER.md` with a short note;
  - in `docs/hosting-proposal.md`, add one line: "Hosting needs the API's `frontend_origin` set to the exact hosted origin (one targeted apply, needs a go)".
- **Report:** what changed; test and build results; the live checks; the 4 Ask answers and the counter use; screenshots; leak counts; open limits (Hindi review, hosting, the 2 known weak Ask answers).
