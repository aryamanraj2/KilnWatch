# KilnWatch resident web portal — complete builder handover

Prepared 10 October 2026. This is the full product brief and implementation roadmap for the resident portal. It is intended to be handed to a friend working in Claude Code with the KilnWatch repository.

## 1. Your assignment and working rules

You are the builder for the KilnWatch **resident web portal**. Build a useful, polished, bilingual public website through which residents can check an area, inspect published satellite evidence, understand assessed rules, and prepare a complaint requesting an inspection.

Start by reading, in order:

1. Root `AGENTS.md`.
2. `App/docs/HANDOVER.md`.
3. `App/docs/build-plan.md`.
4. `App/docs/DESIGN.md`.
5. `App/docs/concept.txt`, especially the resident portal, agent, registry, and guardrail sections.
6. `App/docs/integration-status.md` and `App/docs/api-contract.md`.
7. `AWS/docs/first-record-runbook.md` and `AWS/docs/local-verification.md`.
8. The latest Integration 2A verification/decision documents under `AWS/docs/`, and any subsequent deployment report that actually exists.
9. This entire brief.

Inspect the current branch, working tree, existing web folders, backend implementation, and relevant repository instructions before editing. The inspected checkout is on `main`; older references to `PortalAPP` are historical. Respect the actual checkout and do not switch or reset it automatically. Existing changes belong to their owners; preserve them.

Work **one phase at a time, without parallel agents**. Older documents contain parallel work suggestions; the user's sequential instruction takes precedence. Commit, push, deploy, create paid cloud resources, or send messages only when the user explicitly authorizes those actions. This brief authorizes local resident-portal implementation, not an infrastructure deployment.

Call the infrastructure/backend owner **AWS teammate**. Call the training/model owner **ML team mate**.

Do not modify the inspector app, its Xcode project, trained weights, training pipeline, or shared backend behavior merely to make the web prototype work. Put the new web application in `Web/ResidentPortal/`, unless a suitable resident application already exists in the checkout. If it exists, extend it rather than creating a competing application.

Your immediate assignment is **Phase R1: the complete local resident experience using clearly labeled fixtures**. Finish and verify that phase, then report and wait for the user's go before Phase R2. Do not stop at a landing page or a collection of disconnected mockups. The remaining phases below define the full destination and the responsibilities needed to get there.

## 2. What exists, and what you must not assume

As of the inspected repository state:

- The inspector iOS app has completed Phases 0–2. Its design system and core models exist. Real registry fetching and evidence loading remain separate work.
- A kiln-trained rotated-box checkpoint exists locally. Model-to-registry conversion has produced **39 real Hapur candidates** and **one real aligned before/after evidence pair**. Those are candidates, not 39 confirmed violations or 39 evidence pairs.
- Integration 1 is committed. Integration 2A has verified import/replay and the read handler against real local PostgreSQL/PostGIS, including roles and TLS. The later Python verification reported **30 passing tests**, superseding the earlier report of skipped database tests. Core verification reported **26 passing Swift tests**.
- Terraform formatting and validation have passed, and a plan exists. The handover records creation of the remote-state bucket, but **no application-stack apply**. A deployment prompt is not evidence that deployment succeeded. Check any newer deployment report before connecting live services.
- The authenticated inspector registry endpoints exist. **The public list endpoint currently returns `503 publication_unavailable`.** Public detail, resident-assistant, and curated public-rule endpoints are not established by the existing bridge.
- Rules/exposure assessment, live resident-agent tools, public publication policy, and public frontend hosting are not complete just because their intended architecture is described.
- The ML team mate still needs to confirm the saved training-run identity and interpretation of the evidence. The model's metrics do not establish field accuracy or legal status.

Recheck these facts in the friend's checkout, which may have newer changes. Report changes with source evidence. Never carry an old blocker forward after it has actually been resolved, and never call a planned service live.

The local frontend can be built now. Live integration needs an approved public API and actual deployed services. The browser does **not** need `best.pt`, access to the training environment, an AWS secret, or an inspector's Cognito token.

## 3. How the whole system connects

The intended flow is:

`Satellite imagery → ML detections → registry import → geospatial rule/exposure assessment → AWS public data projection → resident website`

The AWS resident assistant reads the same approved public records and curated rules. It explains them and helps draft a request for inspection. The inspector iOS app uses protected data and records human findings. The internal review console handles its own restricted workflow.

The resident portal is a **reader and draft composer**. It does not train the detector, process full satellite scenes, issue verdicts, decide publication, or expose the inspector workflow. Share registry identifiers and source facts across clients, not privileged access.

Do not merge the resident portal with the reviewer console. Residents should not need a department login. Do not add citizen accounts, paid subscriptions, notification systems, or a complaint case-management backend to this assignment without a separate request.

## 4. The resident's complete journey

The principal flow is:

1. Open KilnWatch without signing in.
2. Choose English or Hindi.
3. Enter a place/address, optionally use current location, place a map pin, or enter coordinates.
4. Confirm the area and search radius.
5. See published candidates nearby in a synchronized map and accessible list.
6. Open a kiln record and examine status, actual imagery, assessed distances/rules, and sources.
7. Ask for a plain-language explanation where supported.
8. Select relevant records and create an editable complaint **draft requesting inspection**.
9. Copy, download, or print the draft. Filing remains a separate deliberate action.

The portal must also make sense to a resident who cannot use the map, declines location access, has a slow connection, or encounters a service outage. Every principal action needs a usable fallback or an honest explanation.

## 5. Technology and project boundaries

If no web stack exists, use React, strict TypeScript, Vite, a router, and CSS variables for design tokens. Use a maintained Node LTS version compatible with the selected dependencies, record it, and commit an appropriate package lock when committing is later authorized. Prefer a small dependency set over a framework collection.

Suggested structure, adjusted to actual implementation needs:

```text
Web/ResidentPortal/
  src/
    app/                 routing, providers, configuration
    components/          shared accessible components
    features/            area, kiln, evidence, rules, assistant, complaint
    data/                public types, validation, API client, fixture adapter
    i18n/                English and Hindi dictionaries
    styles/              tokens and global styles
  tests/                 unit/integration and browser tests
  public/                approved static assets only
  docs/
    DESIGN.md
    public-api-contract.md
    aws-integration-request.md
    HANDOVER.md
    verification.md
  .env.example
  README.md
```

These are suggested boundaries, not permission to create empty abstractions. Keep working code understandable. Separate fixture/live data access without duplicating the entire UI. Validate external responses at the boundary. Avoid blanket `any`, unchecked casts, and silently interpreting missing values as zero.

For maps, prefer MapLibre with an AWS teammate-approved Amazon Location map/geocoding configuration when available. Verify provider terms, attribution, coverage, browser-key restrictions, and costs before production use. A locally rendered map diagram without a tile provider is acceptable for Phase R1 if it is labeled illustrative. Do not present a blank or fabricated basemap as live satellite imagery. Coordinate input and the list must remain functional without geocoding or map tiles.

Use Vitest and React Testing Library for meaningful behavior tests and Playwright for browser flows. Run browser checks sequentially. Use semantic locators and condition-based waits rather than arbitrary delays.

## 6. Visual direction and language

Follow `App/docs/DESIGN.md` in spirit and tokens: **soft, exact, trustworthy**, with evidence taking priority over decoration. Translate its principles into normal, accessible web interaction; do not imitate an iOS tab bar or Liquid Glass implementation.

Use these light/dark pairs:

| Token | Light | Dark |
|---|---|---|
| Canvas | `#F4F4F4` | `#111111` |
| Surface | `#FFFFFF` | `#1C1C1C` |
| Secondary surface | `#EBEBEB` | `#262626` |
| Primary text | `#1A1A1A` | `#F2F2F2` |
| Secondary text | `#5C5C5C` | `#A3A3A3` |
| Clay accent | `#A84B25` | `#E07A4F` |
| Pending inspection | `#875A00` | `#E3A93B` |
| Confirmed status | `#B3261E` | `#F2867A` |
| Compliant status | `#2F6B45` | `#7CC495` |
| Not a kiln | `#55606E` | `#A3ADBA` |
| Closed status | `#6B6259` | `#B3A99E` |

Use the 4-pixel spacing scale: 4, 8, 12, 16, 20, 24, 32, 48. Start with 20-pixel page margins, 16-pixel card padding, approximately 20-pixel card radii, and restrained borders. Primary buttons use ink, not clay. Clay highlights selection and citations. A status always includes readable text and a symbol, never color alone.

Use a readable system font stack with tested Devanagari support. Use tabular figures for counts and monospaced identifiers/coordinates where helpful. Wrap long IDs instead of clipping them. Support light and dark themes, system preference, and reduced motion. Keep animations short and functional; avoid automatic map flights when motion is reduced.

Do not build a generic marketing dashboard. Avoid gradients, purple/neon accents, decorative statistics, sparkles, floating AI badges, heavy shadows, glass cards, fabricated charts, and filler content. The opening action is **check an area**, not admire a hero section.

Both English and Hindi must cover navigation, forms, status, errors, empty states, evidence labels, explanations, and complaint templates. Preserve identifiers, source names, and legal citations accurately. Set document language correctly and use locale-aware dates/numbers. Do not place Hindi in fixed-height containers. Maintain the selected language across navigation and refresh; storing the language preference is acceptable.

The binding English status before a human verdict is exactly:

**“Flagged by satellite · pending inspection”**

Never use the word “illegal” in portal copy or generated complaint text. Have Hindi translations reviewed for faithful meaning. Do not treat a high model score as a verified kiln type or a legal finding.

## 7. Pages, navigation, and responsive behavior

Use stable routes such as `/`, `/area`, `/kilns/:id`, `/rules/:id`, `/complaint`, `/about`, and `/privacy`, plus a helpful not-found page. These are frontend routes; they do not prove corresponding API endpoints exist.

Do not put a resident's precise location or draft contents in a URL by default. Public kiln links may be shared by identifier. Preserve search state within the session so Back returns to the previous area and selection. Provide direct-link loading, browser refresh, and understandable failures for missing/unpublished records.

On desktop, use an area workspace with a map and a useful results panel. On phones, provide obvious list/map switching and comfortable details navigation without trapping the user in a bottom sheet. The list is a complete alternative to the map. Verify small Android-size screens as well as desktop browsers.

### A. Check an area

- Clearly explain what satellite candidates mean and that an inspection is required.
- Offer address/place search, coordinates, and optional “Use my location.”
- Ask for browser location only after that explicit action. Use a one-shot location request, not continuous tracking.
- Handle denied, approximate, unavailable, timed-out, and disabled location without blocking manual entry.
- In fixture mode, use explicitly labeled sample places; never pretend a fixture lookup geocoded an arbitrary real address.
- Confirm the selected point and radius before results. Suggested choices are 0.8, 1, 2, and 5 km, subject to backend limits. Start with 1 km.
- An 800 m search circle is a resident search choice, not automatic proof of an 800 m legal threshold.
- Show the active dataset/coverage and last data update when supplied.

### B. Nearby results

- Keep selected map feature and list row synchronized.
- Show identifier, public status, distance with its measurement basis, latest observation date, and evidence availability.
- Show model-predicted type with “confirm on site” wording unless independently verified.
- Sort consistently; distance-first is a useful default. Preserve selection when results refresh.
- Support loading, retry, true empty within known coverage, unknown coverage, service unavailable, partial results, and clearly dated cached data.
- Never interpret “no results” as proof of clean air, no kilns, or compliance. Say no published candidates were returned for the searched area and explain coverage limitations.
- Do not claim a total until pagination/completeness supports it. Say “12 results loaded” when that is all you know.
- Render valid WGS84 GeoJSON with longitude/latitude order. Handle invalid geometry and overlapping pins. Cluster crowded points where useful.
- Provide a keyboard-friendly alternative to dragging a pin, such as coordinate entry or confirming the map center.
- Draw distance circles geodesically. Distinguish the resident's search radius from separately assessed kiln-rule buffers.
- Debounce searches, cancel obsolete requests, and prevent an older response replacing the latest search.

For live results, prefer server-calculated distance to the nearest approved footprint using geography-aware queries. A centroid distance must be labeled as such and must not masquerade as an assessed rule distance. Bounded geospatial filtering and pagination need to agree; filtering one page in the browser is not a complete nearby search.

### C. Public kiln details

Show the identifier, status, last satellite observation, published location/footprint, model prediction with limitations, evidence, and assessed rule/exposure information where actually supplied.

Clearly distinguish:

- A model prediction from a human finding.
- A detected timestamp from construction date or start of operation.
- An assessed rule result from a rule that has not been evaluated.
- An estimated population exposure from measured emissions or a health diagnosis.
- Missing information from a value of zero.

If exposure is absent, say “Exposure estimate not available.” If rules are unassessed, say that. Do not manufacture homes, schools, buffers, populations, or violations to fill a layout. Only show human verdicts from an authoritative published record.

Include actions to inspect sources, ask about this record when supported, add it to a complaint draft, and return to results. Residents do not get “Record verdict,” inspector routes, internal notes, or private photos.

### D. Satellite evidence

- Use only approved evidence URLs and actual associated metadata.
- Support two valid images, one image, missing imagery, expired/unreachable URLs, and loading errors.
- Only enable before/after comparison when a real pair exists. Do not reuse one image as both dates.
- Display acquisition dates, source, and resolution when known. Distinguish those from upload/publication dates.
- Preserve the character of 256-pixel evidence: do not smooth it into apparent detail it does not contain.
- Draw an OBB only from the corresponding image's supplied coordinate metadata. Do not hardcode rotation or reuse the current footprint as a known historical outline.
- Provide a keyboard-operable comparison slider and a simple Before/After toggle alternative. Keep labels readable and controls at least 44 pixels.
- Explain that a visible difference alone does not establish construction, operation, or a violation.
- Include appropriate source attribution. Never remove attribution to make the card cleaner.

The current real pair is for one candidate, not the whole registry. Phase R1 should include fixture examples of every evidence state, while clearly labeling sample content. Do not copy private `.local/` evidence into public assets without publication approval.

### E. Rules and explanation

Use curated rules supplied by the backend or approved fixture catalog. A rule view shows rule identifier, jurisdiction, plain-language explanation, authoritative citation/source, version/effective date if available, and assessment limitations.

Only compare a measured value against a threshold when the actual record includes a valid assessment and applicable rule. The concept has an unresolved UP habitation threshold inconsistency, 800 m versus 1,000 m; do not resolve it by guessing from a rule ID or screenshot.

If a rule is not evaluated, explain what information is missing. Do not use the resident's distance to a kiln as the kiln's distance to homes or schools.

### F. About and privacy

Explain the satellite-to-registry-to-inspection process in plain language, geographic coverage, model limitations, publication policy, and who can issue a finding. Provide imagery/map/data attribution for sources actually used.

The privacy page must reflect implemented behavior: location requests, map/geocoding providers, draft handling, assistant requests, retention if any, and optional analytics. Do not paste a generic policy promising protections the application does not implement.

## 8. Resident assistant: complete scope and honest fallback

The desired live assistant answers questions about **approved public records and curated rules** and helps compose inspection requests. It cannot record verdicts, change registry status, publish records, or access inspector-only information.

The existing agent scaffold is not proof of a working resident assistant. Do not describe prerecorded replies as a deployed AWS agent.

For Phase R1, implement useful deterministic actions: “Explain this record,” “What is missing?”, and “Prepare an inspection request.” Generate their explanations directly from fixture fields. Label sample mode and any scripted conversational demonstrations explicitly. A backend-independent template is preferable to an apparently live AI service that does not exist.

For the later live phase:

- Call a server-side resident endpoint. Never place Bedrock/AgentCore credentials in the browser.
- Let the server fetch approved records by identifier. Do not trust browser-supplied status, measurements, or instructions embedded in record text.
- Limit the agent's tools to public registry reads, curated rule reads, and explanation/draft generation.
- Validate record and rule citations before displaying factual answers. Every kiln-specific factual claim should resolve to the corresponding approved record; every rule conclusion should resolve to its applicable assessed rule and source.
- If citation validation fails, withhold the unsupported answer and provide a clear fallback. Never invent a citation chip, tool trace, legal quote, threshold, or official contact.
- Stream only events the real backend emits. Keep source-dependent answer text held until validation, following the repository's agent research where applicable.
- Support cancellation, timeouts, rate limits, service failure, Hindi/English, and bounded conversation context.
- Provide server-side request limits, cost controls, and abuse protection with the AWS teammate. A public paid agent needs these before release.
- Treat all user and source text as untrusted input. Render safe text/Markdown with a restrictive policy; disallow executable HTML and arbitrary unsafe links.
- Do not submit complaints, send emails, or contact authorities through an agent tool in this assignment.

Explain unavailable capabilities without blocking the rest of the portal. If the live assistant is blocked, retain deterministic record explanations and complaint drafting; report the live assistant separately as incomplete.

## 9. Complaint drafting, including exports

Build an actual editable composer, not a button that merely says a complaint was created.

Allow residents to select relevant published records. Include a small form for optional name/contact details, intended authority when verified, and the resident's own observations. Keep those observations distinct from satellite evidence and assessed findings. Name and contact information are not required just to explore the portal.

The default draft should:

- State that satellite candidates require inspection.
- Identify each selected public kiln record and its authoritative public link.
- Include the latest known observation date and approved evidence references.
- Include measured rule concerns only when they have actually been assessed and cited.
- Describe unknowns honestly and request that the relevant authority check them.
- Keep model classification provisional.
- Avoid claims about measured emissions, health harm, construction dates, or confirmed violations that the data cannot support.
- Omit the resident's exact home/location by default. Include it only after an explicit choice.
- Produce a readable English or Hindi draft and allow editing before export.

Provide Copy, Download text, and a printable layout usable through browser Print/Save as PDF. Test Devanagari rendering and page wrapping. A dedicated PDF library is optional; do not add a heavy export stack unless browser printing is insufficient.

An evidence attachment section must distinguish actual downloaded attachments from links/references. Do not say images are attached when the export only contains URLs. Do not fetch private images or use an arbitrary URL proxy to bypass CORS.

No automatic filing, email, upload, database write, or background submission. Downloading a draft must never display “Complaint filed.” Use “Draft downloaded” or equivalent. Official filing links/contact details require verified current sources and owner review; leave them unavailable rather than inventing them. External filing is not a prerequisite for the local draft flow.

Drafts and personal details remain in memory by default. Warn before discarding meaningful unsaved edits. Persistent draft saving, cloud storage, or analytics of complaint content needs a separate explicit product/privacy decision. In sample mode, put a clear sample-data notice in exports too.

## 10. Public API contract and AWS integration boundary

Write `docs/public-api-contract.md` as a **proposal** until the AWS teammate confirms it. Reuse applicable established field semantics from the repository, but do not equate the private inspector contract with a public contract.

Proposed capabilities:

| Capability | Proposed path | Current integration expectation |
|---|---|---|
| Nearby published records | `GET /public/kilns` | Existing handler currently unavailable; needs real public implementation |
| Published record details | `GET /public/kilns/{id}` | Confirm/implement with AWS teammate |
| Curated public rule | `GET /public/rules/{id}` | Confirm/implement with AWS teammate |
| Resident assistant | `POST /public/assistant` or agreed equivalent | Future server-side service; do not assume streaming shape |

For nearby results, agree on center/radius or bounding-box semantics, maximum area, page size, stable cursor behavior, distance basis, sort order, dataset revision, geographic coverage, completeness, and error bodies. Do not combine incompatible query shapes or accept unlimited map areas.

Use a deliberately allowlisted **server-side public projection**. Publication eligibility is separate from inspection status. A flagged candidate is not automatically public, and a database reader role does not itself enforce publication policy.

Public records may include approved identifiers, location/footprint, public status, observation dates, provisional prediction, approved evidence URLs/metadata, evaluated rule results, estimated exposure with provenance, and a public revision. Confirm the precise list with the AWS teammate.

Public responses must exclude inspector identities, internal notes, private photos, inspection assignments, route/queue information, unpublished candidates, internal storage paths, secrets, database details, and private operational metadata. Frontend filtering is not the privacy boundary: the backend must never send those fields to anonymous clients.

Define nulls, unknown enum handling, ISO timestamps, coordinates, units, empty results, unavailable publication, invalid searches, throttling, missing/unpublished records, and malformed responses. Avoid distinguishing a private record from a nonexistent record in a way that discloses its existence.

Validate image URLs against agreed HTTPS hosts. The browser should not receive a capability to fetch arbitrary private objects. The current bridge's evidence-only delivery model needs explicit confirmation for public records and actual published assets.

A live error must remain a live error. **Never silently replace failed live requests with fixtures.** Do not send an inspector token to public endpoints or place any department credentials in frontend configuration.

## 11. Fixture mode, live mode, caching, and errors

Use explicit fixture/live configuration, for example `VITE_DATA_MODE` and `VITE_PUBLIC_API_BASE_URL`, after choosing the final names. Document that Vite client environment variables are public bundle contents. Supply `.env.example` with placeholders only; ignore local secret/config files appropriately.

Fixture mode needs a persistent “Sample data” indicator and sample notices in assistant output and exports. Build fixtures covering: a candidate with two images, one with one image, missing evidence, unknown type/status, unassessed rules, absent exposure, a published human-reviewed status, no results within known coverage, unknown coverage, pagination, malformed responses, and service failure. Clearly fictitious human-reviewed examples must never be confused with real Hapur results.

Live mode needs bounded timeouts, cancellation, appropriate bounded retries for retryable reads, pagination deduplication, and protection against stale responses. Do not retry a potentially billable assistant request as though it were an idempotent list read.

Cache public data only with a defined freshness policy. Label stale content with its source/update time. Do not persist resident location or drafts as a side effect of caching. Do not describe saved data as current or infer compliance from an unavailable service. A service worker is optional, not required for this first release.

All screens need genuine loading, empty, partial, unavailable, retry, and not-found behavior as applicable. Preserve the resident's current input after failures. Errors should explain the next useful action and avoid dumping raw backend bodies into the interface or logs.

## 12. Privacy, security, accessibility, and performance

### Privacy and security

- Geolocation is opt-in and manual entry works without it. Explain provider disclosure when address searches are sent to a third-party geocoder.
- Do not log precise resident locations, contact information, draft text, or assistant conversations by default.
- Start without behavioral analytics. Add any analytics only with a documented decision and suitable data minimization.
- Do not put secrets, inspector tokens, AWS credentials, or model weights in source, browser storage, exports, or bundles.
- If Amazon Location uses a browser API key, use the provider's supported limited read permissions, origin/referrer restrictions, expiry, and quotas. A deliberately public, restricted map key is different from a secret AWS credential.
- Sanitize any rich text, allowlist external links, validate inputs, and preserve safe text rendering. Do not render user-provided HTML.
- Agree on CORS origins and deployment headers with the AWS teammate. Security headers must match actual API, image, map, font, and worker sources; do not use a wildcard policy just to make everything load.
- Keep unpublished material and personal drafts out of search-engine indexing. Do not expose personal state in share links or page metadata.

### Accessibility

Target WCAG 2.2 AA. Check keyboard operation, visible focus, semantic landmarks, labels, errors linked to fields, screen-reader announcements, sensible focus after navigation/dialogs, and sufficient contrast in both themes.

Use 44-pixel comfortable primary controls as the product target. Test 200% zoom, narrow-screen reflow, Hindi wrapping, reduced motion, and map failure. No information should depend solely on color, hover, a drag gesture, or map position. An evidence slider must work with the keyboard and have understandable values. Announce loaded results without reading every pin or creating repetitive announcements.

### Performance

Design for low-bandwidth mobile use. Lazy-load the map and evidence where practical, constrain response sizes, and avoid shipping full scenes, weights, or enormous GeoJSON files to every browser. Bound displayed results and use clustering appropriately. Avoid needless repeated geocoding, tile requests, and assistant calls.

Measure initial loading, interaction responsiveness, and layout stability on a representative mobile viewport. Record conditions and actual results; do not claim a performance score that was not measured. The list/draft experience should remain usable when the map provider or WebGL fails.

## 13. Hosting and production responsibilities

The intended hosting is AWS Amplify Hosting, subject to the AWS teammate's configuration and deployment approval. Do not create a separate hosting service merely because a scaffold offers one.

Prepare a reviewable build configuration for the actual monorepo path, dependency install from the lockfile, production build, and correct output directory. Pin a supported build runtime. Configure SPA deep-link rewrites while preserving real asset responses; returning HTML for missing JavaScript is a deployment bug.

Prepare HTTPS/domain, environment configuration, exact API/map/image origins, headers, source-map policy, and preview-versus-production settings. Verify direct navigation to a kiln URL and refresh after deployment. Geolocation must work in the production secure context.

Do not repeat the existing infrastructure estimate as the portal's total cost. Maps/geocoding, hosting, public API traffic, and resident-agent calls add their own usage. The AWS teammate must review the incremental cost and limits before enabling paid services.

Publishing a preview with fixtures is a prototype milestone. It is not proof that the public API, live assistant, evidence publication, or real resident workflow has been released.

## 14. What to request from each teammate

Create `docs/aws-integration-request.md` with a concise capability checklist and proposed contracts. Do not message the teammate automatically.

### AWS teammate

Request confirmation of:

1. Actual deployment status, environment, API base URL, and latest live verification report.
2. Which records/fields/images are approved for anonymous public access and who controls publication.
3. A public server-side projection and publication filter, including treatment of unpublished/missing records.
4. Bounded nearby-search queries, canonical distance calculations, pagination, coverage, and freshness/revision semantics.
5. Public detail/rule endpoints and approved evidence delivery with correct metadata and CORS.
6. Curated rule assessments and exposure availability. Missing assessment is allowed; invented data is not.
7. Resident-agent backend, validated citations, actual event protocol, network path to its services, credentials held server-side, rate limits, and cost controls.
8. Map/geocoding provider configuration, restricted browser key if required, attribution, quotas, and budget.
9. Amplify build root, domain/HTTPS, deployment configuration, headers, approved origins, and incremental operating costs.
10. Live acceptance evidence that anonymous requests expose only published fields and cannot use resident endpoints to mutate records.

Do not assume an existing VPC Lambda can call every agent service without further network/IAM work. Let the AWS teammate verify that path.

### ML team mate

Request confirmation of:

1. Saved training-run/version identity and the linkage between weights and reported metrics.
2. Model/version and prediction terminology suitable for public explanation.
3. Known type-confusion and detection limitations. AP is not a general accuracy percentage.
4. What the existing evidence pair actually supports, its acquisition dates/alignment limits, and whether historical footprint metadata exists.
5. Which additional candidate evidence, if any, has been generated and approved for publication.

Do not ask for retraining or another checkpoint just to build the portal. The browser never loads `.pt` weights. Current unknowns must be represented honestly while frontend work proceeds.

## 15. Tests and acceptance checklist

Write meaningful tests around contracts and user behavior, not tests that merely mirror implementation details. At minimum verify:

- Known/unknown types and statuses, null exposure, unassessed rules, missing evidence, and invalid coordinates.
- Correct longitude/latitude handling and clear distinction between search distance and assessed rule distances.
- Pagination/completeness, stale request cancellation, and no false empty/total claims.
- Live `503` and malformed responses never becoming sample results.
- Location denied/unavailable with successful manual entry.
- Synchronized map/list selection, keyboard navigation, map-provider failure, and browser Back.
- Direct public record links and not-found handling.
- Two-image, single-image, and failed-image states; keyboard comparator and reduced motion.
- Complete Hindi/English flow, preserved language choice, and readable Devanagari print output.
- Unknown rule threshold never becoming a made-up rule conclusion.
- Complaint selection, editable content, missing-data wording, copy/download/print, sample watermark, and no automatic submission.
- Private draft/location information not leaking into URLs, storage, analytics, or exports without the chosen explicit action.
- Unsupported assistant citations rejected in the live service when implemented; fallback remains usable.
- Actual public backend projection excluding unpublished/private fields when Phase R2 is enabled. Frontend tests alone cannot prove this boundary.
- Production bundle contains no secret/department credentials and the production build/type checks pass.

Run sequential browser flows on a phone-size viewport and desktop. Check Chromium and at least one other relevant engine; include Safari/WebKit where available. Perform keyboard and screen-reader checks rather than relying only on an automated accessibility score. Capture a small set of useful screenshots showing both languages, mobile/desktop, evidence, a draft, and an error state. Do not create excessive recordings or artifacts.

## 16. Sequential implementation phases and completion gates

### Phase R1 — complete local resident portal

Build the full fixture-backed resident journey: design tokens, responsive navigation, English/Hindi, area selection, map/list with fallback, detail/evidence states, rule explanation, deterministic assistant-style explanations, editable complaint drafting, exports, About/Privacy, errors, and meaningful tests. No live AWS deployment is required for this phase.

Also deliver the proposed public contract and AWS integration request. Clearly label sample content throughout. All visible primary actions should work locally or have an honest dependency-specific disabled state; avoid dead buttons and generic “coming soon” pages.

Gate: production build/type checks pass; key browser flows pass; both languages work; screenshots reviewed; fixture/live separation is tested; no existing app/backend changes were overwritten. Report and wait for the user's go.

### Phase R2 — approved public registry and real evidence

After the public backend is ready and work is authorized, coordinate the agreed contracts with the AWS teammate. Connect actual published records, real geospatial queries, pagination, coverage, and approved imagery. Verify anonymous access and the publication boundary against the deployed service. Test service failures using live-mode behavior.

Do not call this phase complete using mocked responses. Missing rules/exposure can remain explicitly unavailable if that is the approved public contract; list those missing capabilities. Report and wait for the user's go.

### Phase R3 — real resident assistant

Integrate the approved server-side agent, actual tools/events, citation validation, language behavior, rate limits, and failure handling. Test grounded answers and complaint drafts against published records. Keep deterministic fallback. Do not claim this phase complete with scripted agent replies.

If the agent is unavailable, report the blocker and retain the useful portal rather than concealing it. Report and wait for the user's go.

### Phase R4 — release verification and hosting

Finish accessibility, mobile performance, privacy, source attribution, deployment configuration, and cross-browser checks. Obtain the required deployment authorization, deploy through the agreed AWS path, and prove deep links, real API/image loading, geolocation, public projection, and exports on the hosted site.

Publish a clear completion matrix: locally implemented/tested, live verified, and blocked/unimplemented. A mock-hosted portal is not the same as the released public product.

## 17. Required handover and final report

Maintain `Web/ResidentPortal/README.md` with setup/start/build/test instructions, supported runtime, fixture/live configuration, map requirements, and links to project docs. Maintain a resident `HANDOVER.md` with current phase, exact working behavior, changed files, verified checks, and next gate.

At the end of each phase report:

1. What residents can actually do now, in plain language.
2. What was implemented and where.
3. Test/build/browser results actually run, with counts where meaningful.
4. Screenshots/artifacts and any material design deviation.
5. Whether each data source is fixture, local real data, or live published data.
6. Missing inputs assigned to the AWS teammate or ML team mate.
7. The exact next phase and its entry conditions.
8. Whether any commit, push, deployment, or external communication occurred.

Do not give an arbitrary overall completion percentage. Use the phase/capability matrix so a working frontend cannot hide a missing public API or assistant. Do not claim a human inspection, real deployment, valid citation, or successful export that was not verified.

## 18. Primary references for implementation

Use the repository's established contracts first. Consult current official documentation when implementing version-sensitive behavior:

- [Vite guide](https://vite.dev/guide/) and [client environment variables](https://vite.dev/guide/env-and-mode).
- [MapLibre GL JS documentation](https://maplibre.org/maplibre-gl-js/docs/).
- [Amazon Location API keys](https://docs.aws.amazon.com/location/latest/developerguide/using-apikeys.html).
- [Amplify monorepo configuration](https://docs.aws.amazon.com/amplify/latest/userguide/monorepo-configuration.html), [rewrites](https://docs.aws.amazon.com/amplify/latest/userguide/redirects.html), and [custom headers](https://docs.aws.amazon.com/amplify/latest/userguide/custom-headers.html).
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/) and [browser geolocation](https://developer.mozilla.org/en-US/docs/Web/API/Geolocation_API).
- [Vitest](https://vitest.dev/guide/) and [Playwright assertions](https://playwright.dev/docs/test-assertions).

## Start now

Read the required repository documents and inspect the checkout, then execute **Phase R1 only**. Build the complete usable local resident flow and its integration handover. Work sequentially. Preserve existing work. Do not deploy, commit, push, retrain, modify the inspector app, or begin Phase R2. Finish with verified results and concrete missing inputs, then wait for the user's go.
