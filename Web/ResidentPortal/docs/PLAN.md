# KilnWatch resident portal — overall plan

Prepared 10 October 2026. **R1 built; verification gate has explicit manual gaps. R2 frontend preparation is locally implemented.** The user authorized continuation, then confirmed the public backend is not ready and requested local preparation. See [verification](verification.md), [handover](HANDOVER.md), and [R2 local preparation](R2-local-preparation.md). R2 has no live connection or deployed acceptance proof.

Further local continuation closes streamed-response byte limits and nearby-page consistency gaps, with bounded UTF-8 decoding, redirect refusal, first-page deduplication and retained results/selection on invalid later pages. Native 200% zoom remains unverified because Chrome computer-use access was denied. The approved public service remains the next R2 integration input; R3/R4 are not begun.

This document translates the [resident portal master brief](../../../App/docs/prompts/09-resident-portal-master-brief.md) into an ordered delivery plan. It began as the planning-only deliverable; local R1 and authorized R2 frontend preparation now exist. Deployed R2 acceptance and R3–R4 remain later gates. Work sequentially, with no parallel agents.

## 1. Outcome and boundaries

A resident can choose English or Hindi, check an area without signing in, explore nearby sample candidates in a map and list, examine evidence and assessed rules, understand missing information, and prepare an editable inspection-request draft. Copy, text download, and browser print/Save as PDF must work. The complete R1 journey remains usable without AWS, a geocoder, map tiles, or a live assistant.

R1 uses clearly labeled sample data throughout. It must not imply that sample candidates, sample human findings, illustrative imagery, or sample coverage are real observations. It must not conceal an unavailable public service behind fixtures.

All new work belongs in `Web/ResidentPortal/`. Preserve existing changes and the current branch. Do not change the inspector app, Xcode project, shared core, backend behavior, infrastructure, training pipeline, or weights. Do not deploy, create paid resources, commit, push, contact teammates, or retrain. The latest authorization extends work to local R2 frontend preparation only; connection needs the approved/ready public service. Accounts, reviewer workflows, verdict entry, notifications, complaint filing, and case management are outside scope.

## 2. Inspected starting point

The planning inspection was read-only before adding this document. The checkout is on **`webApp`**, and `git status --porcelain=v1` was empty. Older instructions describe `main`; the actual checkout takes precedence and will not be switched. No existing `Web/` directory or resident web application was found.

| Finding | Evidence and consequence |
|---|---|
| The iOS design and models exist; no resident frontend exists | Reuse design tokens and applicable data meanings, not the inspector UI or privileged endpoints. |
| AWS deployment is reported complete for 73 of 75 resources in `ap-south-1` | The newer Integration 2B sections supersede older “not deployed” statements. This planning pass did not query AWS or independently repeat deployment checks. |
| 39 real Hapur candidates are stored in the private registry | They are unverified candidates, with unassessed rules and absent exposure. They are not anonymous public records. Do not copy them into fixtures. |
| Public list access is intentionally unavailable | `AWS/lambda/api_handler.py` returns `503 publication_unavailable` for `GET /public/kilns`; the Integration 2B report records the same live result. |
| Public detail, curated-rule, and resident-assistant routes are not implemented by the current API | Propose a public contract separately. The inspector contract is not permission to expose the private serializer. |
| One real evidence pair exists; delivery is pending in the latest report | The two PNGs were approved for eventual publication, but CloudFront is awaiting account verification and registry URLs remain null. That approval does not establish public registry eligibility or authorize this task to publish assets. |
| The agent source summarizes supplied JSON | It does not establish registry-backed resident tools, validated citations, or a released public service. Use deterministic local explanations in R1. |
| Amplify exists only as optional infrastructure configuration | Its existing inspector-oriented environment variables are not the resident contract. Leave `AWS/amplify.tf` unchanged; prepare a portal-specific hosting proposal later in R1. |
| Rule and model interpretation remain unresolved | Do not infer the UP habitation threshold from a rule ID or screenshot. High prediction scores do not verify kiln type; AP is not field accuracy. |

Prior verification is background evidence, not tests run for this document: Integration 2A reports 30 Python tests passing with no skips on local PostGIS; Integration 2B reports 26 Swift tests passing on the saved live response, and separate AWS checks. Real Cognito-token verification was not performed by user decision. That does not block an anonymous sample portal.

Sources reviewed:

- [Repository instructions](../../../AGENTS.md), [app handover](../../../App/docs/HANDOVER.md), [app build plan](../../../App/docs/build-plan.md), and [binding design system](../../../App/docs/DESIGN.md).
- [Concept](../../../App/docs/concept.txt), especially pages 9–15; [integration status](../../../App/docs/integration-status.md); [inspector contract and bridge extensions](../../../App/docs/api-contract.md).
- [First-record runbook](../../../AWS/docs/first-record-runbook.md), including Integration 2A decisions and Integration 2B deployed state; [verification reports](../../../AWS/docs/local-verification.md). No separate newer deployment report was found under `AWS/docs/`.
- [API handler](../../../AWS/lambda/api_handler.py), [API routes](../../../AWS/api.tf), [registry contract](../../../AWS/registry/contract.py), [registry reads](../../../AWS/registry/store.py), [agent scaffold](../../../AWS/agent/agent.py), and [Amplify configuration](../../../AWS/amplify.tf).

The resident master brief and current user constraints supersede the older app plan's parallel-work suggestions and its historical statement that web projects are outside this repository. The app's Phase 3 and the resident portal's R1 are separate workstreams.

## 3. Product and implementation decisions for R1

| Area | Planned decision |
|---|---|
| Stack | React, strict TypeScript, Vite, a router, and plain CSS with shared variables, as specified in the brief. Choose compatible versions using current official documentation at implementation time. Pin a maintained compatible Node LTS runtime and retain a package lock; use npm consistently. |
| Design | Translate the binding neutral light/dark palette, clay selection/citation accent, ink primary buttons, 4-pixel spacing, soft corners, restrained borders, and symbol-plus-text statuses into accessible web controls. No imitation iOS navigation or glass cards. |
| Opening screen | “Check an area,” with language selection and sample-data notice. No marketing dashboard or decorative statistics. |
| Localization | English and Hindi dictionaries for all visible flows, validation, errors, explanations, and exports. Update document language; format dates/numbers by locale; preserve identifiers and citations. Store only language/theme preferences. |
| Map | An interactive, locally rendered geographic diagram for R1, labeled “Illustrative map · sample data.” Plot validated fixture coordinates and a geodesic search circle; never imply a real basemap or satellite view. MapLibre/Amazon Location integration remains dependent on an approved provider configuration. |
| Search | A small bilingual sample-place catalog, validated coordinate entry, optional one-shot browser location, and point selection on the diagram. Sample lookup must never pretend to geocode arbitrary addresses. |
| Search limits | Radius choices 0.8, 1, 2, and 5 km, default 1 km. These are R1 product limits and a public API proposal, not confirmed backend limits or legal buffers. |
| Distances | Compute and label fixture distance to the sample centroid. Draw circles geographically, not as a fixed screen-pixel radius. Keep search distances entirely separate from record rule measurements. |
| Data modes | `VITE_DATA_MODE=fixture|live`; `VITE_PUBLIC_API_BASE_URL` for the proposed public endpoint. Invalid configuration fails clearly. Live mode never imports fixtures as recovery. R1 tests live-client behavior only against a local test server/intercepted HTTP; no deployed service connection. |
| Local assets | Purpose-made, distinct 256-pixel synthetic evidence examples with embedded or adjacent sample labels and explicit provenance. No private `.local/` images, training tiles, model weights, or real Hapur exports enter public assets. |
| Explanations | Field-driven “Explain this record,” “What is missing?”, and “Prepare an inspection request.” No fake tool traces, invented citations, or claim of a live AWS agent. |
| Exports | Copy, UTF-8 `.txt`, and print CSS for browser Print/Save as PDF. Start without a dedicated PDF dependency. Evidence links are references, not claimed attachments. |
| State and privacy | Area, precise location, selected records, personal details, and draft text remain in application memory. No analytics, draft persistence, location logging, service worker, or public-data disk cache in R1. |
| Failure behavior | Maintain form input after failures; distinguish loading, empty, partial, unknown coverage, unavailable, stale, and not found. A diagram failure leaves the full list and draft flow usable. |

Language and theme changes must preserve resident work. Changing the draft language or regenerating it must not overwrite edits silently. If refreshing loses in-memory state, say so; do not persist private state just to retain it. Browser Back must restore the current session's search/selection without encoding precise location in the URL or browser history state.

Proposed project boundaries, created only when they contain working code:

```text
Web/ResidentPortal/
  src/app/                  routes, app state, configuration
  src/components/           shared accessible controls
  src/features/             area, records, evidence, rules, explanations, complaint
  src/data/                 public types, validators, read client, fixture adapter
  src/i18n/                 English/Hindi dictionaries and formatting
  src/styles/               tokens, responsive layout, print styles
  public/                   approved local sample assets and attribution
  tests/                    contract, behavior, and sequential browser checks
  docs/                     plan, design, contracts, integration request, verification, handover
  README.md                 setup, supported runtime, commands, configuration
  .env.example              public placeholders only
```

Keep one UI over a small fixture/live data-access boundary. Reuse established snake_case meanings for identifiers, acquisition dates, missing facts, and confidence semantics where applicable. Explicitly convert coordinate objects to valid WGS84 GeoJSON `[longitude, latitude]`; do not copy private payloads wholesale. Avoid generic managers, plugin systems, or abstractions for hypothetical providers.

## 4. Sequential R1 work plan

These are checkpoints inside one phase, not permission to stop after a partial mockup or begin R2. Finish each checkpoint and its focused proof before proceeding. Add meaningful tests with the behavior they protect; run the full R1 gate at the end.

### R1.1 — foundation, design, and public data proposal

Create the runnable project and local scripts. Record exact runtime/dependency versions, lock dependencies, and add a portal-local ignore file for dependencies, builds, test output, and local environment files. `.env.example` contains no real credentials; document that Vite variables are public bundle contents.

Write `docs/DESIGN.md` with web tokens, responsive layouts, focus behavior, bilingual wrapping, theme behavior, and motion limits. Build accessible navigation and real routes: `/`, `/area`, `/kilns/:id`, `/rules/:id`, `/complaint`, `/about`, `/privacy`, plus a not-found page. Public record IDs may appear in URLs; resident location and draft content may not.

Write `docs/public-api-contract.md` prominently marked **proposal awaiting AWS teammate confirmation**. Cover the public projection and capabilities in section 6. Add validators and fixtures for the minimum public fields, unknown enums, nulls, dates, geometry, assessment states, and image metadata. Keep unknown values honest, never mapped to a known positive status.

**Proof:** the app starts locally, production build and type checks pass, EN/HI and theme survive navigation/refresh, routes handle direct entry, and malformed inputs/unknown facts have meaningful behavior. Record the initial bundle size as a baseline, not a performance score.

### R1.2 — bilingual area search and synchronized map/list

Implement sample-place matching using English/Hindi names and sensible aliases. Unmatched addresses explain the sample catalog's limit and offer coordinates. Accept clearly labeled latitude/longitude fields with range validation and a deliberate confirmation step. Normalize supported Hindi digits rather than accepting ambiguous coordinate ordering.

“Use my location” requests one position only after a click. Show accuracy when supplied and allow correction. Denied, unavailable, disabled, timed-out, and approximate location all retain a manual path. Do not force a real position into the sample coverage area; offer an explicit sample-place choice.

After center/radius confirmation, show distance-sorted results, coverage/update metadata, and loaded count. Desktop uses a map/list workspace; phones offer obvious list/map switching. Selection, detail navigation, return, and browser Back stay synchronized. Coordinate input is the keyboard alternative to pin placement. Handle overlapping pins with accessible selection; group crowded markers if necessary without hiding list results.

The fixture adapter filters the full fixture dataset before paginating. The future live client must not filter one server page and claim a complete nearby search. Define deterministic order, duplicate handling, cursor exhaustion/repetition, query revision, and stale-response protection. Debounce place lookup; cancel replaced searches and ignore late responses.

**Proof:** both languages complete place and coordinate searches; invalid coordinates cannot produce a misleading map; location denial still reaches results; a slow old search cannot overwrite the latest; pagination never creates false totals; diagram failure leaves every result/action accessible.

### R1.3 — record details, evidence, rules, and sources

Render identifier, exact status, observation date, public location/footprint, provisional model type, evidence, rule assessments, and exposure provenance when present. All pre-verdict English statuses use exactly **“Flagged by satellite · pending inspection”**. Hindi must faithfully convey the same meaning. Do not use “illegal” in generated portal copy or complaint templates.

Build two-image, single-image, missing-image, loading, and failed-image states. Only compare two distinct, associated images. Label synthetic images as illustrative in the viewer and exports; use their fixture metadata, not invented satellite acquisition details. Preserve 256-pixel character when enlarged. Show OBBs only from the corresponding side's supplied pixel coordinates; a historical image without a historical outline stays without one. Provide keyboard slider operation and Before/After buttons, including reduced-motion behavior.

Rule views show ID, jurisdiction, plain-language meaning, authoritative source when verified, version/effective date when supplied, and limitations. Before presenting a real rule threshold in a sample assessment, verify the authoritative current source or obtain an approved fixture catalog. A missing source/threshold remains unavailable; do not treat concept mock values as established law. Explicitly retain the unresolved UP habitation case. Purely synthetic rule examples, if needed to exercise layout, must be identified as demonstrations and cannot masquerade as authoritative legal citations.

Compare measurements only when the record includes a valid applicable assessment and threshold. Missing exposure is unavailable, not zero. Population estimates do not establish emissions or health harm. First/last observation dates do not establish construction or operation. Human-reviewed fixture records must be obviously fictitious; a high model score is always provisional unless separate verification is supplied.

**Proof:** test all evidence combinations and invalid metadata, keyboard controls, missing assessment/source, null exposure, unknown status/type, long IDs, broken deep links, and the distinction between search radius and rule distance. Review mobile/desktop evidence and Hindi wrapping visually.

### R1.4 — deterministic resident explanations

Generate bilingual explanations directly from the selected fixture's validated fields. Explain known facts, missing facts, model limitations, applicable assessed rules, and inspection questions. Link record claims to the actual displayed record; link rule conclusions only to a supplied valid assessment and source. Do not invent a citation to decorate an answer.

“Prepare an inspection request” carries the selected record into the real composer. Display sample-data and template-based explanation labels. Do not add an apparently live free-text chat or simulated AWS activity. Record explanations remain useful if a later assistant is unavailable.

**Proof:** changing fixture facts changes the explanation; unsupported rule/model/health conclusions are absent; sources resolve; both languages reach the composer with the intended selection. A failed source lookup preserves the useful fallback and does not invent a result.

### R1.5 — complaint composer and exports

Allow multi-record selection, removal, and a clear empty-selection state. Offer optional name/contact details and resident observations, distinguished from satellite evidence. Authority/contact choices appear only if current official sources have been verified and reviewed; otherwise explain their unavailability without blocking the draft.

Generate an editable English/Hindi request for inspection containing selected record IDs, observation dates, local sample record links, approved evidence references, assessed concerns only when cited, and explicit missing-data wording. In R1, local links are identified as sample links, never authoritative production URLs. Real canonical public links are an R2 input. Keep model classification provisional and the tone factual.

Exact resident location is excluded by default. Include it only via a specific opt-in, previewing the included value. Optional personal details enter an export only as deliberately provided in the composer. Do not infer or inject browser location, contact data, or other private state. Draft regeneration, selection changes, language changes, resets, and refresh must warn when they would discard meaningful edits; routine navigation can preserve the draft in memory.

Implement Copy with an honest failure/manual-copy path, UTF-8 text download, and print CSS with readable Devanagari, wrapped links, sensible page breaks, and a persistent sample notice. Export the edited content, not a regenerated template. Label evidence as links/references unless actual attachments are implemented and verified. No automatic filing, mail, upload, or backend mutation; success copy says “Draft copied” or “Draft downloaded,” never “Complaint filed.” A print dialog alone is not proof that a PDF was saved.

**Proof:** select two records, edit text, switch language safely, exercise dirty-state protection, copy/download/print in both languages, and inspect the resulting text and saved PDF. Confirm sample notices remain, references are accurate, personal location is absent by default, and no submission request occurs.

### R1.6 — complete states, About/Privacy, and integration handover

Complete real About and Privacy pages reflecting actual local behavior and attribution. Explain sample coverage, satellite limitations, publication/inspection roles, opt-in location, memory-only drafts, and any provider request actually made. R1 should make no external geocoding or tile request.

Exercise the local read client against unavailable, malformed, rate-limited, delayed, and paginated test responses. Use bounded timeouts/cancellation and limited retries for retryable reads; propose a 10-second timeout and at most one automatic retry, respecting bounded `Retry-After`, for review in the contract. Never retry invalid input, not-found, malformed data, or a future billable assistant request automatically. Test that live configuration errors never activate sample mode.

If retaining a previous successful read in memory after failure, keep it tied to its original query, source, revision, and fetched time and label it stale. Never present it as the latest search result. Fixture scenarios must cover stale content even though persistent caching is excluded from R1.

Write `docs/aws-integration-request.md`, with the AWS teammate checklist and a separately assigned ML team mate section; do not send it. Maintain `README.md`, `docs/HANDOVER.md`, and `docs/verification.md`. Prepare a reviewable Amplify monorepo build configuration under the portal docs: runtime, lockfile install, `Web/ResidentPortal` app root, build command, and `dist` output. Document route rewrites, missing-asset handling, headers, origins, source-map policy, and preview/production differences; do not activate hosting or fabricate unknown origins.

**Proof:** every primary action works or explains its exact dependency; the Privacy page matches observed requests/storage; errors preserve inputs; the contract and teammate checklist clearly distinguish proposed capabilities from implemented services.

### R1.7 — acceptance verification and stop

Run the final checks in section 7 sequentially, fix failures within R1, review a small set of screenshots and exported artifacts, and record exact commands/results/environment. Check the working-tree diff to confirm app/backend/model work is untouched. Do not run unrelated Swift/Xcode/backend suites for portal-only changes.

Report what residents can do, changed files, test counts and actual browser checks, screenshots/design deviations, fixture/local-real/live data status, missing inputs, and next gate. Do not assign an overall completion percentage. **Stop after R1 and wait for the user's go; no R2 connection or deployment.**

## 5. Fixture and state coverage

Use unmistakably sample IDs such as `SAMPLE-KW-001`, with independent synthetic coordinates and metadata. A sample human verdict must never use a real Hapur candidate ID. The fixture collection should be only large enough to cover required states and pagination; avoid a large fabricated registry.

| Fixture/scenario | Expected resident behavior |
|---|---|
| Flagged candidate with two distinct synthetic images | Usable comparator, per-image metadata/outline, sample labels, and observation limitations. |
| One image; neither image; broken image URL | Only valid evidence is shown, with a useful unavailable/error state for the rest. |
| Unknown type/status; high-score unverified type | Honest unknown/provisional wording; never a confident finding inferred from a score. |
| Valid sample assessment; unresolved threshold/source; unassessed record | Assessed facts and unassessed questions stay separate in UI, explanations, and drafts. |
| Exposure supplied with sample provenance; exposure null | Labeled estimate or unavailable, never inferred zero or health claim. |
| Explicitly fictitious human-reviewed record | Demonstrates published verdict presentation without suggesting a real inspection occurred. |
| Known sample coverage with zero results; unknown/outside coverage | Distinct messages; neither implies no kilns, clean air, or compliance. |
| Multiple pages, duplicate IDs, repeated cursor, revision change, partial failure | Loaded count, honest completeness, stable selection, and recoverable paging errors. |
| Malformed coordinates/geometry/response; missing record | Clear validation/not-found behavior, no misleading marker or fixture fallback. |
| Slow or stale search, unavailable service, throttling, diagram failure | Preserved input, bounded recovery, correct latest search, and usable list/draft. |

Keep fault controls local/test-only and documented so failure states are reproducible without cluttering normal resident navigation. No private operational payloads belong in fixtures.

## 6. Public integration proposal and missing inputs

These are future integration inputs. None blocks the complete fixture experience. They must be reported separately from local implementation defects.

### Proposed public capabilities

| Capability | Proposed endpoint | Required contract decisions |
|---|---|---|
| Nearby records | `GET /public/kilns` | One bounded center/radius query shape, units, max area/page size, stable sort/cursor tied to query and dataset revision, canonical distance basis, coverage, freshness, partial/completeness semantics. Do not mix bounding-box and center/radius semantics. |
| Public detail | `GET /public/kilns/{id}` | Explicit publication eligibility, public revision/canonical link, identical missing/unpublished behavior, validated public fields and evidence metadata. |
| Curated rule | `GET /public/rules/{id}` | Jurisdiction, authoritative source, effective/version dates, applicable threshold and assessment status; no rule-ID guessing. |
| Future assistant | `POST /public/assistant` or agreed path | Server-side public reads, actual request/events, validated citations before factual text, cancellation, limits, failure policy, no automatic billable retries. R3 implementation only. |

The public response must be a **server-side allowlisted projection**. Publication eligibility is separate from status. A database SELECT role or frontend field filtering is not the publication/privacy boundary. Exclude inspector identities, internal notes/photos, assignments, routes/queues, unpublished candidates, object keys, internal provenance/storage details, secrets, and operational metadata. Public evidence URLs must use approved HTTPS hosts and actual approved assets; never provide an arbitrary URL proxy.

Specify snake_case fields, ISO timestamps with offsets, WGS84 coordinate order/conversion, metres, unknown enums, optional/null data, empty pages, invalid queries, throttling, unavailable publication, malformed responses, and non-disclosing not-found errors. CORS and browser origins must be explicit. Never send a department token to a resident endpoint.

### AWS teammate inputs

| Input needed | R1 treatment | Gate it enables |
|---|---|---|
| Latest deployment status, environment, public base URL, and verification report | Record the reported Integration 2B state; make no new AWS requests. | R2 |
| Publication owner/policy, approved records/fields, backend projection, and anonymous negative-access proof | Use synthetic fixtures; no assumption that all 39 candidates are public. | R2 |
| Nearby query bounds, footprint distance, sort/paging/revision, coverage and freshness | Propose semantics; test local adapter and HTTP boundary. | R2 |
| Public detail/rule services, approved sources/assessments, exposure provenance | Missing real facts stay missing; source-verified samples only. | R2; specific absent facts may remain explicitly unavailable by agreement |
| Evidence publication completion, approved HTTPS hosts, acquisition metadata, image/CORS verification | Synthetic local assets; do not move `.local/` evidence. | R2 evidence |
| Map/geocoder configuration, attribution/terms, coverage, restricted browser key, expiry/quotas and cost limits | Bilingual sample catalog, coordinates, illustrative diagram. | Provider integration before release |
| Server-side resident tools, validated citations/event protocol, network/IAM path, throttling and cost controls | Deterministic explanations and composer. | R3 |
| Amplify root/runtime/domain/HTTPS, exact origins/headers, environment alignment and incremental costs | Reviewable configuration proposal only; existing `VITE_API_BASE_URL` settings need reconciliation. | R4 |
| Anonymous read-only acceptance evidence, including unpublished/private-field exclusions | Document required server tests; frontend mocks are insufficient proof. | R2/R4 |

The existing infrastructure estimate is not the portal's operating cost. Hosting, maps/geocoding, public reads, and paid assistant traffic need a separate estimate and limits. The current VPC Lambda's ability to reach agent services must be verified by the AWS teammate; IAM permissions alone do not establish connectivity.

### ML team mate inputs

| Input needed | R1 treatment | Later use |
|---|---|---|
| Saved training run/version and weights-to-metrics linkage | No real model accuracy or saved-run claims in the portal. | Public model provenance |
| Approved model/version wording and known class confusion/detection limits | Model predictions remain provisional at any score; explain limitations. | R2 public explanations |
| Interpretation of the current real pair, acquisition/alignment limits, and any historical outline | Synthetic per-side metadata; no inferred change or historical footprint. | R2 evidence interpretation |
| Any additional generated evidence and publication readiness | No assumption that 39 candidates have 39 pairs. Publication still needs AWS teammate approval. | R2 evidence coverage |

Do not request retraining or a new checkpoint for this frontend. Arrange faithful Hindi copy review before release; record whether language has had human review rather than claiming it from automated checks. Current official filing contacts also require verified sources and owner review before becoming active links.

## 7. Verification and acceptance

Use Vitest/React Testing Library for meaningful contracts and behaviors, and Playwright browser flows with one worker and no fully parallel execution. Run engines sequentially. Final commands will be documented in the README, with scripts for `typecheck`, `build`, `test`, and `test:e2e`; clean installs use the lockfile.

| Check | Passing evidence required for R1 |
|---|---|
| Types/build | Strict TypeScript and production build pass; runtime and commands recorded; no unresolved build warnings. |
| Data boundaries | Unknown/null/unassessed states; finite coordinate ranges and axis order; valid image metadata; no live failure/configuration error silently loading fixtures. |
| Search/pagination | Correct radius/distance labels, bounded queries, stable selection, cancellation/out-of-order protection, deduplication, honest partial/coverage/completeness states. |
| Navigation/map | Direct record/rule links and refresh, browser Back, synchronized selection, keyboard access, narrow mobile view, map unavailable fallback. |
| Location | Explicit permission trigger; denied/unavailable/timed-out/approximate cases; successful manual search afterwards; no background tracking. |
| Evidence/rules | Two/one/no/failed images, keyboard comparator, reduced motion, source links, no made-up thresholds or historical outline. |
| Languages | Complete English and Hindi journey, preference across refresh, correct document language, wrapped IDs/text, locale formatting, faithful provisional wording. |
| Draft/export | Multi-record selection, edited content survives export, missing-data wording, explicit location inclusion only, copy fallback, actual UTF-8 download and inspected Devanagari print/PDF output, persistent sample notice. |
| Privacy/security | Inspect URL/history, browser storage, network requests, console, and bundle for private state/credentials. No HTML injection, unsafe links, analytics, filing, uploads, or private asset fetches. |
| Accessibility | Keyboard walkthrough, focus after navigation/dialogs, semantic labels/errors, screen-reader walkthrough, contrast in both themes, 200% zoom, narrow-screen reflow, 44-pixel controls and reduced motion. Automated scores alone do not satisfy this. |
| Browsers | Chromium and a second engine, using WebKit/Safari where available; record exact engines and unverified cases. A missing required check remains an explicit gate gap. |
| Performance | Measure initial load, response to interaction, and layout stability on a representative mobile viewport with recorded network/device conditions. Record actual values, avoid unmeasured score claims, and fix regressions that obstruct the journey. |
| Repository preservation | Diff confirms changes only under the resident portal; no existing source overwritten and no external action taken. |

Capture a small reviewed artifact set: desktop English area results, mobile Hindi results/detail, evidence comparison, editable draft, a useful error/fallback state, and English/Hindi printed exports. Include dark theme in at least one view. State actual dimensions/browser and avoid excessive recordings. If screen-reader or export inspection cannot be completed, say exactly what is unverified; do not mark the R1 gate fully passed.

## 8. Overall phase roadmap and stop conditions

| Phase | Deliverable | Entry and completion gate | Current status |
|---|---|---|---|
| R1 — local resident experience | Full bilingual sample journey, states, exports, meaningful tests, public contract proposal and integration handover | Complete section 7, reviewed artifacts, no existing work overwritten; report and wait. | Locally implemented; automated checks pass; spoken screen-reader and native 200% zoom checks remain unverified |
| R2 — public registry and real evidence | Approved anonymous records, bounded real search, public details/rules, pagination/coverage, published evidence | User's go plus ready/approved backend; prove deployed anonymous projection and refusals, real imagery and service failures. Mock HTTP cannot complete R2. | Frontend locally prepared/tested; approved backend pending, no live proof |
| R3 — resident assistant | Real server-side public tools, grounded bilingual explanations/drafts, validated citations/events, limits and fallback | User's go plus ready service; prove real responses, rejected unsupported citations, cancellation/errors, and cost controls. Scripted replies cannot complete R3. | Not started |
| R4 — release verification and hosting | Approved AWS Amplify release with operational, privacy, accessibility, attribution and performance proof | User's go and explicit deployment authorization; verify hosted deep links/refresh/assets, HTTPS geolocation, API/images, projection, exports and configuration. | Not started |

After each phase, report capabilities as **locally implemented/tested**, **live verified**, or **blocked/unimplemented**, identifying the actual data source. A fixture preview does not establish a released public registry or assistant.

## 9. Handover for the next work session

Read [HANDOVER.md](HANDOVER.md), [verification.md](verification.md), [R2 local preparation](R2-local-preparation.md), this plan and the master brief; recheck the branch/working tree and any updated teammate reports. Local preparation is implemented/tested. Next obtain the approved public contract/base URL, publication proof and evidence inputs before connecting and verifying deployed R2. R1 manual verification gaps remain open. Do not carry historical deployment blockers forward without checking newer supplied evidence.

Historical planning baseline: the first step added only this plan. The subsequent authorized work added the local portal, dependencies, tests, review artifacts and handover under `Web/ResidentPortal/`. No live API integration, deployment, commit, push, retraining, inspector-app change or teammate communication occurred.
