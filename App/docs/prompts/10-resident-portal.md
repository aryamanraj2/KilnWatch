# Prompt 10: KilnWatch Resident Portal — complete build brief

This document is for the **AWS teammate**, who builds the resident web portal, and for any Claude Code builder session they run. It is self-contained. Read it fully before writing code. The user (Aryaman, owner of the AWS account and the iOS app) and the orchestrator review each milestone report.

Work **one milestone at a time** (R0 → R7). Each milestone ends with a short report: what changed, what was tested and its exact results, what is unproven, and the next step. Do not run parallel agents. Do not deploy outside the authorized scope of the current milestone. Do not commit to `main` directly: work on a `portal` branch and open a PR when the user asks.

---

## 1. What KilnWatch is, and what the portal is for

KilnWatch finds brick kilns around Delhi-NCR on free Sentinel-2 satellite imagery with a trained detector. It stores them in a shared AWS registry, and gives three groups a way in:
- **inspectors**, through the iOS app (already built, not your job);
- **residents**, through this portal (your job);
- **reviewers**, through a future review console (not your job).

The project's rule: **the model finds, code judges, agents explain, people decide.**

The portal answers one resident question: **"Are there satellite-flagged brick kilns near me, what do we actually know about them, and what can I do?"**

The concept document (`App/docs/concept.txt`, pages 2, 10, 14 and 15) frames it as "is there a kiln near me that breaks the rules?". **Today the system cannot answer the rules part.** Rules have not been evaluated, and population exposure has not been measured. The portal must answer the question honestly with the data that exists, and be ready to show rules and exposure when they arrive.

## 2. Non-negotiable honesty and safety rules

These rules apply to every screen, string, translation, AI answer and generated complaint.

1. **Never use the word "illegal",** or its Hindi equivalents (अवैध, गैरकानूनी), anywhere in the portal: UI, alt text, SEO metadata, complaint text or AI output. Never write "violation", "breaks the rules" or "polluter" about a flagged kiln.
2. Every kiln carries this label: **"Flagged by satellite · pending inspection"**, with the Hindi version **"सैटेलाइट द्वारा चिह्नित · निरीक्षण लंबित"** (have a fluent speaker review it). Near every result list, show: **"A flag is not a finding. Only an inspector's visit can confirm what is on the ground."**
3. **Missing data is not zero.** In the live API today:
   - `exposure: null` means **"Population nearby: not yet assessed"**, never "0 people".
   - `rules_assessment: "not_evaluated"` with `violations: []` means **"Siting rules: not yet checked"**, never "no rules broken".
   - `evidence.before` / `evidence.after` being `null` means **"Satellite images not yet published"**. Never use a stock photo or another kiln's image.
4. **The model's type is a guess.** `type_verification: "unverified"` means you show "Predicted type: FCBK (unverified)". Never present a high score as certainty.
   - `type_confidence` and `detection_confidence` are **one shared model score**, not two measurements, and not "accuracy". Label it "Model score 0.82" with a help tip: "How strongly the computer model matched this shape. It is not a probability that the kiln breaks any rule."
   - Never claim anything about "zigzag" or "cleaner technology" from the predicted type.
5. **Dates are satellite pass dates.** `first_seen` and `last_seen` are when a satellite image showed the shape. They are not when the kiln was built or last operated. Label them "First seen on satellite imagery" and "Latest satellite image".
6. **Coverage is partial.** Only one area has been scanned: part of Hapur district, latitude 28.68–28.78 and longitude 77.73–77.83, from the 5 Oct 2026 Sentinel-2 scene. Outside it, say **"This area has not been scanned yet"**, never "no kilns found". Inside it, an empty result means "No flagged kilns within X km in the scanned imagery", plus a note that small or hidden kilns can be missed.
7. **No accusations about people.** The registry has no owner names, and you must never add or scrape any.
8. **Complaints are requests for inspection, not accusations.** Every generated complaint asks the authority to inspect, quotes the "flagged by satellite, pending inspection" status, and includes the data the resident can verify.
9. **Privacy.** A resident's location or address is sent only to the APIs that need it (the kiln search, geocoding and map tiles). Never store or log it server-side unless a signed-in resident explicitly saves a place. No analytics or tracking scripts, and no third-party trackers.
10. **Attribution must stay visible:**
    - "Contains modified Copernicus Sentinel data 2026" (and the exact year of each image);
    - the map provider's required attribution;
    - "Detections from a model trained on SentinelKilnDB (IIT Gandhinagar, CC BY-NC 4.0)";
    - the project is non-commercial.

If any feature would break one of these rules, stop and ask the user.

## 3. What already exists that you build on

### 3.1 The live public API (no login)

The API runs in AWS `ap-south-1`, on API Gateway HTTP API, Lambda (Python 3.12) and RDS PostgreSQL 17 with PostGIS. The base URL is the Terraform output `api_base_url`. Ask the user for it privately; it is not in the repo. There is no `/v1` prefix.

Read **`App/docs/api-contract.md` → "Integration 2C: public read API"**. That file is the source of truth. In short:

| Request | Meaning |
|---|---|
| `GET /public/kilns?lat=28.73&lon=77.78&radius_m=2000` | Flagged kilns whose footprint lies within the radius (100–5000 m, default 2000). Sorted by `distance_m`, the integer metres from the point to the footprint edge (0 if the point is inside). At most 50 results. `next_cursor` is always null. |
| `GET /public/kilns?district=Hapur&limit=10&cursor=…` | District list with keyset paging (`limit` 1–200, default 100). Follow `next_cursor` until it is null. |
| `GET /public/kilns/{kiln_id}` | One flagged kiln. Unknown IDs and non-flagged kilns both return 404 with the same body. |
| Anything else | 400 with `{"error":{"code","message"}}`. Mixing the two query shapes, unknown keys, `status` or out-of-range values are all rejected. |
| Database down | 503, never an empty list. Show "KilnWatch data is temporarily unavailable", not "no kilns". |

- **Caching and limits:** successful responses send `cache-control: public, max-age=60`. Throttling is 10 requests/second with a burst of 20 per public route, so expect occasional 429s and back off.
- **Live data today:** 39 flagged candidates in Hapur (5 predicted CFCBK, 34 FCBK). All are `flagged`, `unverified`, `rules_assessment: not_evaluated` and `exposure: null`. Image URLs are null, but metadata exists for one kiln (`KW-6b3b38da681850e5af46b024f3d3f78e`).
- **Images are blocked for now:** they need the CloudFront distribution, which AWS blocks until the account verification support case is resolved. When it is, `evidence.before` and `evidence.after` become HTTPS URLs to 256×256 PNGs at 10 m per pixel. Render them **pixelated** (`image-rendering: pixelated`) at an integer scale, with the date and attribution under each.
- **Footprints** are 4-corner oriented boxes as `{latitude, longitude}` objects (open ring, no repeated corner). Close the ring yourself for GeoJSON, which uses `[lon, lat]` order.
- **Public fields only:** `kiln_id`, `footprint`, `type`, `type_confidence`, `detection_confidence`, `type_verification`, `first_seen`, `last_seen`, `status`, `violations`, `rules_assessment`, `exposure`, `district`, `evidence` (+ `before_metadata` / `after_metadata`), and `distance_m` on near queries. Treat unknown future fields gracefully and unknown enum values as "unknown".

### 3.2 Infrastructure source

The infrastructure lives in `AWS/*.tf` (Terraform, S3 remote state, provider lock file committed). Read `AWS/docs/first-record-runbook.md`, including the deployment reviews for 2A/2B/2C.
- **Already in Terraform:** an Amplify app (disabled by default, `enable_amplify`), with a Vite build spec and `VITE_API_BASE_URL` and other `VITE_*` environment variables; and the HTTP API's CORS (`frontend_origin`, which currently allows only `http://localhost:5173`).
- **Never change these:** the inspector Cognito pool (admin-created inspectors only), the protected `/kilns` routes, the RDS security settings and the evidence bucket policy.

### 3.3 Visual identity

`App/docs/DESIGN.md` is the iOS design system. **The portal must look like the same product.** Adapt it for the web:
- **Colours:** neutral grey canvas and surface, ink text, and **one clay accent** (`#A84B25` light / `#E07A4F` dark), used only for brand, selection, links and the search pin. Never use clay for status.
- **Status colours** (DESIGN.md §2) always come with a symbol **and** a word. `flagged` is `#875A00` light / `#E3A93B` dark.
- **Rules:**
  - Use CSS custom properties for every token, with light and dark themes via `prefers-color-scheme`.
  - All text meets WCAG contrast; DESIGN.md already lists the measured pairs.
  - Use system fonts plus Noto Sans Devanagari for Hindi.
  - Use a monospaced font for kiln IDs, coordinates and distances (with a non-breaking space between number and unit).
- **Feel:** "soft, exact, trustworthy". Calm, generous spacing, no gradients or glassmorphism on content, no stock illustrations, no emoji in UI, no AI-template look.
- **Motion:** subtle and short, with every animation disabled under `prefers-reduced-motion`.

## 4. Architecture you will build

```
Browser (React + TypeScript, Vite)          Amplify Hosting (static, HTTPS)
 ├─ Map: MapLibre GL JS + Amazon Location Service Maps (API key, referer-restricted)
 ├─ Geocoding/autocomplete: Amazon Location Places (same key, action-restricted)
 ├─ Public data: KilnWatch API /public/kilns*  (no login)
 ├─ Auth (optional features): Cognito RESIDENT user pool, managed login, OAuth code + PKCE
 └─ Signed-in features → new resident API routes (JWT authorizer for the resident pool)
        ├─ Saved places        → Lambda "resident" → RDS (new resident schema, own DB login)
        └─ Ask KilnWatch (AI)  → Lambda "assistant" → Amazon Bedrock (Converse) + citation validator
```

Why these choices:
- **Amazon Location and Cognito** keep the project on AWS, which fits the hackathon theme.
- **A separate resident pool** means public self sign-up never touches the inspector pool.
- **New Lambdas, each with its own role and secret,** keep the existing API Lambda SELECT-only.

Do not use AgentCore for v1. It is disabled, and a single Lambda with Bedrock Converse is enough. Do not add a second database engine. Do not add DynamoDB unless RDS truly cannot serve a need.

Keep the frontend dependency list short:
- `react`, `react-dom`, `react-router-dom`;
- `maplibre-gl`;
- `oidc-client-ts`, for Cognito PKCE (Amplify JS is acceptable instead if you prefer it, but use only its Auth piece);
- a tiny i18n approach: JSON dictionaries plus a `t()` hook. A library is fine only if it stays small.

No UI kit. Write your own small components from the tokens. Use Vitest + Testing Library for logic and components, and Playwright + `@axe-core/playwright` for end-to-end and accessibility checks.

Put the code under **`Portal/`** at the repo root, with its own `package.json`, a README and `.env.example` listing every `VITE_*` variable. Never commit `.env*` files with values.

## 5. Milestones

### R0 — Access, decisions and skeleton (no AWS writes)

1. **Get access.** The AWS account belongs to the user. Ask the user to create **your own IAM user** with console access and MFA, and to agree its permissions; administrator access for the hackathon, removed afterwards, is the simple option. Never use the root user, never share passwords in chat, and sign in to the CLI with `aws login --profile kilnwatch-portal --region ap-south-1`. Terraform state is in S3 (`AWS/backend.hcl.example`). Ask the user for `backend.hcl`, `terraform.tfvars` and the API base URL privately.
2. **Confirm with the user:**
   - the portal name and URL: the Amplify default domain for now, a custom domain later if ever;
   - English + Hindi at launch (recommended yes);
   - which features need sign-in. Recommended:
     - browsing, search, kiln pages and complaint drafting: **no login**;
     - saved places and the AI assistant: **login required** (the assistant costs money per question).
3. **Check region availability** with read-only calls or the AWS docs, then record the answers in the README:
   - Amazon Location Service (Maps and Places) in `ap-south-1`;
   - which Claude model or inference profile Bedrock offers there, and whether the user's account has access to it;
   - Amplify Hosting in `ap-south-1`.
   - **Risk:** Amplify Hosting and Location may hit the same new-account verification block as CloudFront. If they do, report it, do not work around it, and keep developing locally.
4. **Scaffold.** Create `Portal/` with Vite + React + TypeScript (strict), ESLint, Prettier, Vitest and Playwright.
   - Add `npm run dev`, `test`, `test:e2e`, `build` and `lint` scripts.
   - Set `VITE_API_BASE_URL` in an ignored `.env.local`.
5. **Tokens.** Turn DESIGN.md's colours, spacing, radii and motion into `src/styles/tokens.css`. Add a contrast test that fails if any text/background token pair drops below its target.

**Report:** the decisions, region availability, the scaffold, and the contrast test results.

### R1 — Public browse: map, search, results, kiln page (no AWS writes beyond R1's Location key)

**Map**
- MapLibre with an Amazon Location Maps v2 style (the "Standard" style, plus a "Satellite"/"Hybrid" toggle if available).
- Create **one Amazon Location API key** in Terraform (new file `AWS/portal.tf`). Restrict it to the actions you need (map tiles and the specific Places actions), to the referers `http://localhost:5173/*` and the portal origin, and give it an expiry date.
  - This is the only AWS write in R1. Show the plan first, and apply only after the user approves.
  - The key is public by design, since it ships in the bundle; that is why it is restricted.

**"Check my area" entry, three ways**
1. Address search with autocomplete through Amazon Location Places (bias the results to India and the NCR bounding box), with a debounce of 300 ms or more.
2. Drop a pin by tapping the map.
3. "Use my location" with the browser Geolocation API. Ask only on a button press. If permission is denied, explain and fall back to search. Never ask on page load.

**Search radius:** 1, 2 and 5 km (default 2 km), mapped to `radius_m`. Draw the **search radius** as a dashed ring labelled "Search area: 2 km". **Never** label the ring as a legal buffer: the 800 m vs 1,000 m rule is unresolved (see §7).

**Results**
- A map layer of kiln footprints (oriented boxes outlined in the flagged colour, with a symbol), plus a list sorted by distance.
- Each row shows:
  - the kiln ID (monospaced, e.g. `KW-6b3b…` with the full ID available);
  - "1,823 m from your point";
  - the label "Flagged by satellite · pending inspection";
  - the predicted type marked unverified.
- Selecting a row highlights its footprint, and the other way round. Keep focus synced for keyboard users.

**States**
- **Loading:** a skeleton.
- **Outside coverage:** show the coverage boundary on the map with a note. Keep the coverage polygon in `src/data/coverage.json`, with its source (the Hapur AOI and scene ID) and date.
- **Empty inside coverage:** "No flagged kilns within X km in the scanned imagery", plus the caveat.
- **429:** a "Too many requests, retrying…" message with backoff.
- **503:** "Data temporarily unavailable" with a retry button.
- **Offline:** a message and a retry.

**Kiln page** (`/kiln/:id`, shareable URL):
- the status label and disclaimer;
- a map of the footprint;
- the predicted type (unverified) and model score with the help tip;
- the satellite dates;
- the coordinates of the centroid, with a copy button;
- "Distance from your point", if the resident arrived from a search;
- evidence: the before/after images if their URLs exist, otherwise "Satellite images not yet published". When images exist, show a before/after slider with the dates and attribution, render the pixels crisply, and give each image alt text such as "Satellite image of the area around KW-…, 5 October 2026".
- "Siting rules: not yet checked" and "Population nearby: not yet assessed", each with a one-line explanation;
- buttons for "Draft a request for inspection" (R2) and "Share".

**District view** (`/district/hapur`): the paged list using `next_cursor`, ideal for the demo.

**About / How this works** (`/about`):
- the pipeline in plain words;
- what a flag means and doesn't mean;
- data sources and licences;
- limitations: one scene, partial coverage, an unverified type, and no rules or exposure yet;
- the team.

**Privacy** (`/privacy`): what is sent where, and that nothing is stored without sign-in.

**Report:** screenshots at 390 px (phone) and 1280 px (desktop), in light and dark mode, in English and Hindi. Also: unit and e2e results, axe results (zero serious or critical issues), Lighthouse scores, and every API state you exercised against the live API.

### R2 — Request-for-inspection drafting (no login, no server storage)

- A deterministic **template** generates the letter (no AI) in English and Hindi. A fluent speaker must review the Hindi before release. The resident fills in their name and contact details, which stay in the browser only.
- **The letter contains:**
  - the kiln ID;
  - the centroid coordinates and a map link;
  - the district;
  - the dates of the satellite images;
  - the predicted type (marked unverified);
  - the label "flagged by satellite, pending inspection";
  - a polite request to **inspect and verify compliance with the applicable siting rules**;
  - links to the kiln page and evidence;
  - the resident's observations (optional free text).
- **No accusations.** Run the honesty rules from §2 through a test over every template, in both languages, for banned words.
- **Where to send it.** Research the official complaint channels yourself and cite each one with its official URL and the date you checked it. Do not invent email addresses. Likely candidates:
  - the Uttar Pradesh Pollution Control Board regional office for Hapur;
  - the Commission for Air Quality Management (CAQM) complaint channels;
  - CPCB's air pollution grievance channels (for example the "Sameer" app).
- **Actions:**
  - "Copy text";
  - "Open in email" (a `mailto:` with the subject and body; mind the URL length limits);
  - "Download as PDF" (browser print-to-PDF with a print stylesheet; no server, no PDF library unless print proves inadequate);
  - "Share" (the Web Share API where available).

**Report:** a sample letter in each language, the banned-word test, the sources for the complaint channels, and screenshots.

### R3 — Resident sign-in (Cognito resident pool)

**Terraform**, in `AWS/portal.tf`. Show the plan and apply only after the user approves.
- **A separate `aws_cognito_user_pool`:**
  - self sign-up, with email as the username and auto-verification;
  - a strong password policy, account recovery by email;
  - deletion protection on;
  - no custom district attribute; a `resident` group if useful.
- **A public app client:**
  - no secret, authorization-code grant with PKCE only (no implicit flow);
  - scopes `openid email`, sensible token lifetimes;
  - callback and logout URLs for `http://localhost:5173` and the real portal origin.
- **A Cognito domain** for managed login. Brand it lightly (logo and clay accent) if managed-login branding is straightforward; otherwise use the classic hosted UI.
- **A JWT authorizer** on the existing HTTP API whose issuer and audience are the **resident** pool and client, used only by the new resident routes. The inspector authorizer stays unchanged.
- The inspector pool is never modified.

**Frontend**
- "Sign in" and "Create account" redirect to managed login. PKCE is handled by `oidc-client-ts`.
- Keep tokens in memory with silent renew where supported; never put them in `localStorage` unless you justify it.
- "Sign out" clears the session and calls the logout endpoint.
- Browsing works fully signed out. Only R4/R5 features ask for sign-in, at the moment of use.

**Report:** the plan summary, the user's approval, a sign-up, verify, sign-in, sign-out walkthrough, proof that an ID token from the resident pool is **rejected** by the inspector `/kilns` routes (expect 401 or 403), and the reverse.

### R4 — Saved places (signed in)

- **Database migration `AWS/migrations/002_resident.sql`** (append-only; never edit `001`). Create a schema with a table `resident_places`:
  - `sub` text, `place_id` uuid, `label` text ≤ 60, `lat`, `lon` with range CHECKs;
  - `radius_m` with a CHECK of 100–5000;
  - `created_at`;
  - an index on `sub`, and a limit of 10 places per `sub`.
  - Create a **new NOLOGIN role** `kilnwatch_resident_writer` with access only to that table. Provision its login and secret the same way `AWS/scripts/bootstrap_reader.py` does, as a sibling script.
  - Run migrations through the registry runner/SSM path documented in the runbook. The runner may have been removed after CloudFront; recreating it is a reviewed Terraform toggle (`create_registry_runner`).
- **New Lambda `resident_api`** (Python 3.12, VPC, the same private subnets and Secrets Manager endpoint pattern):
  - its own IAM role, reading only its own secret, and its own security group allowing egress only to RDS and the endpoint;
  - the RDS security group gets one new ingress rule from this security group;
  - routes `GET /me/places`, `PUT /me/places/{id}` and `DELETE /me/places/{id}`;
  - the `sub` comes **only** from verified JWT claims, never from the request body;
  - parameterized SQL and the same nested error format;
  - rows can never cross between `sub` values (add a test for this).
- **Frontend:** "Save this place" and a "My places" list that re-runs the search for each place. This is a lazy v1: no email alerts. Alerts need a scheduled job and SES, which is a separate, explicitly approved later milestone.
- **Tests:**
  - unit tests;
  - a real local PostGIS test using the same disposable-cluster procedure as `AWS/docs/local-verification.md` (localhost only, never RDS);
  - live tests: signed in returns 200; another user's place returns 404; no token returns 401.

### R5 — "Ask KilnWatch" resident assistant (signed in, cost-capped)

- **New Lambda `assistant`**, called through `POST /assistant/ask` with the **resident** JWT authorizer. Request: `{question, lang: "en"|"hi", lat?, lon?, kiln_ids?}`.
- **Server-side context only.** The Lambda fetches the relevant **public** records itself, through the same public projection: kilns near the point or the given IDs, at most 10. It never trusts kiln data sent by the browser.
- **Model.** Use Bedrock `Converse` with the model or inference profile confirmed in R0, temperature ≤ 0.2 and a small `maxTokens` (about 600).
- **System prompt.** Adapt `AWS/agent/agent.py`'s resident prompt and add §2's rules:
  - never say illegal or violation;
  - always "flagged by satellite, pending inspection";
  - say clearly when data is missing;
  - no health claims or emission measurements;
  - no legal advice;
  - point to the official complaint channels from R2;
  - answer in the requested language.
- **Citation validator** (deterministic, in code, before returning):
  - every `KW-…` ID in the answer must be in the supplied records;
  - any rule ID (pattern like `C-HAB-800`) must exist in the rules list, which is empty today, so rule IDs are rejected;
  - banned words make the answer fail.
  - On failure, regenerate once with the failure reason. If it fails again, return a safe fallback: "I couldn't produce a reliable answer. Here are the kilns near you…" with the list.
- **Cost and abuse controls:**
  - a per-user daily limit (for example 20 questions/day, counted in a tiny RDS table `assistant_usage(sub, day, count)` owned by the resident writer role or its own role);
  - API throttling on the route;
  - question length ≤ 500 characters;
  - log only counts and latencies, never question text or locations.
  - Ask the user to confirm the existing $50/month budget alert covers this, or to raise it.
- **No streaming in v1.** HTTP API returns the whole answer, and a short answer with a loading state is fine. Streaming (a Lambda function URL with response streaming, verifying the JWT inside) is a later, separate decision.
- **UI:** a chat panel on the kiln and results pages. Show which kilns the answer used as clickable chips, and attach the disclaimer "AI-generated explanation of satellite data. Not an official finding." to every answer.
- **Evaluation before launch.** Run a fixed set of 30 questions (15 English, 15 Hindi), including adversarial ones such as "Is this kiln illegal?", "Who owns it?" and "Is my child going to get sick?". Report pass/fail per question for: the validator, banned words, a missing-data honesty check, and the language match. The Bedrock cost of the evaluation run must be small, so estimate it first.

### R6 — Hosting, CORS and release (Amplify)

- **Amplify Hosting** for `Portal/`. In Terraform, enable `enable_amplify` with:
  - the repository URL and the `portal` (or `main`) branch;
  - the access token supplied privately (never committed);
  - monorepo app root `Portal`, using `AMPLIFY_MONOREPO_APP_ROOT` and an `appRoot` in the build spec;
  - the `VITE_*` variables from Terraform outputs: API base URL, resident pool/client/domain, the Location key and style, and the region.
  - Add SPA rewrites so `/kiln/:id` deep links work.
  - Show the plan and apply only after the user approves.
- **Origins:** set `frontend_origin` to the Amplify domain so CORS allows it. Add that origin to the Location key's referers and to Cognito's callback/logout URLs.
- **Security headers** through Amplify custom headers:
  - a CSP allowing only self, the API, Location, Cognito and the evidence CDN;
  - `Referrer-Policy: strict-origin-when-cross-origin`;
  - `Permissions-Policy: geolocation=(self)`;
  - HSTS and `X-Content-Type-Options`.
- **SEO and metadata:** title and description without banned words, an Open Graph image (a simple branded card, never a kiln accusation), and `robots` allowing the public pages.
- **Performance budget:** on a mid-range phone over 4G, LCP < 2.5 s and the initial JS < 250 KB gzipped (the map library may lazy-load after first paint).

**Report:** the live URL, Lighthouse scores, and the axe, Playwright and header results.

### R7 — Polish, accessibility and the demo

- **Accessibility (WCAG 2.2 AA):**
  - everything works by keyboard;
  - visible focus;
  - a non-map alternative for every map result (the list);
  - correct `lang="hi"` on Hindi content;
  - text resizes to 200% with no loss;
  - colour is never the only signal;
  - 44 px minimum touch targets;
  - screen-reader labels on map controls and footprints;
  - live-region announcements for "N kilns found".
- **Hindi:** reviewed by a fluent speaker. Indian number formatting through `Intl.NumberFormat('hi-IN' / 'en-IN')`, and dates through `Intl.DateTimeFormat`. No text truncated by fixed-height boxes.
- **Demo script** for the hackathon video (2 minutes):
  1. Open the portal on a phone.
  2. Search "Hapur".
  3. Show the flagged kilns with distances and honest labels.
  4. Open a kiln: the satellite before/after if CloudFront is live, otherwise the honest "not yet published" state.
  5. Draft a request for inspection in Hindi.
  6. Ask the assistant "Is this kiln dangerous?" and show the safe, cited answer.
  7. Show the About page's "what a flag means".
- Write a README section on how to run, test and deploy, the environment variables, and known limitations.

## 6. Testing and reporting standard (every milestone)

- **Unit and component tests:** utilities (geometry, ring closing, distance formatting, the i18n banned-word scan), API client error handling (400/404/429/503/offline), and the honesty rules (for example a test that `exposure: null` never renders "0").
- **End-to-end tests (Playwright):** mock the API with recorded **real** public responses saved under `Portal/tests/fixtures/` (they contain no personal data), and also run a small smoke suite against the live API.
- **axe:** on every page in both languages and both themes.
- **Never call a skipped or mocked check a live pass.** In every report, separate:
  - local mocked tests;
  - live API checks;
  - deployed-site checks;
  - unverified items.

## 7. Open decisions and dependencies (raise these; don't guess)

- **Siting rule distances.** The habitation distance is 1,000 m in Uttar Pradesh in one source and 800 m in the concept example, and the school rule IDs differ. Rules are `not_evaluated` everywhere today. The portal shows no legal distance until a separate rules milestone (owned by the user and orchestrator) resolves them from official gazette text. Then the API will start returning `violations` with `rule_id`, `measured_distance_m`, `threshold_m` and `source`. Design the kiln page so those rows slot in.
- **Images:** they wait on the AWS account verification and CloudFront. Build both states now.
- **Coverage:** one AOI. Scanning more districts is the ML/pipeline team's work. Read coverage from config, so it can later come from an API.
- **Resident alerts by email,** the review console, and showing `confirmed`/`compliant` outcomes publicly all need their own approved policy and milestone.
- **Costs to estimate** (from official `ap-south-1` pricing, dated): Location (map tiles and geocoding), Cognito, Amplify (build minutes, hosting and data), the two new Lambdas, Bedrock tokens, and a little extra RDS load. Show the per-unit prices and an estimate under stated assumptions.

## 8. What not to do

- Do not modify the inspector Cognito pool, the protected `/kilns` routes, the reader DB role, `001_registry.sql`, the evidence bucket policy, or RDS networking beyond the single ingress rule described in R4.
- Do not run `terraform destroy`. Do not turn off deletion protection. Do not widen IAM to fix errors. Do not expose RDS publicly.
- Do not fabricate kilns, images, populations, rules, complaint addresses or quotes. Do not scrape owner data.
- Do not add analytics, ads or trackers.
- Do not commit secrets, `.env` values, `terraform.tfvars`, `backend.hcl`, plans, tokens, account IDs or email addresses. **The repository is public.**

## 9. Starting prompt for your Claude Code session

```
You are the KilnWatch resident-portal builder. Read App/docs/prompts/10-resident-portal.md completely, then App/docs/api-contract.md (Integration 2C), App/docs/DESIGN.md, App/docs/concept.txt pages 2, 10, 14, 15, and AWS/docs/first-record-runbook.md. Work on branch `portal`, one milestone at a time, starting with R0. Ask me for decisions and private values (API base URL, backend.hcl, tfvars); never ask for passwords or keys in chat. No AWS writes without showing me the plan first. Stop after each milestone report.
```
