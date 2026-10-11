# Prompt 45 — calmer demo UI, iOS and resident portal

Use a **new Codex chat** in this repository. One builder, no sub-agents. Work sequentially: iOS first, portal second, then verify and report. This is one presentation phase.

## 1. User direction and authorization

The user likes the existing map, fonts, palette and overall design. Their complaint is that everything is visible at once: the screens feel clustered, scattered and uncomfortable to scan. They want a minimal, professional app and portal with a more finished glass navigation layer and smoother, responsive, snappy interactions for the demo video.

**Highest priority: stay close to the existing KilnWatch UI.** The iOS app and portal must look and behave like products from the same team. Refine the established design; retain its recognizable character in every changed screen. Research references, skills and packages must serve that continuity. Do not import another app's visual identity or a component library's default theme.

Deliver a visibly calmer default view, with secondary facts revealed on demand. Adding space alone or hiding everything behind one giant disclosure does not meet this brief. Preserve the current capabilities, data and honest limitations.

Running this prompt authorizes **local frontend edits, local tests/builds, Simulator/browser checks and captures**. Public API, evidence and hosted-portal **GET/HEAD reads** are allowed, with private configuration read silently. No live POST/PUT/PATCH/DELETE, including Ask, routes, verdicts, inspection requests or photo uploads. Use recorded responses and isolated mocks for interactive flows; prevent outbox delivery before launching the app. Never send a request just to obtain a screenshot.

No deployment, AWS CLI, infrastructure changes, DB writes/resets, migration, commit, push, staging or teammate messages. The hosted portal remains at its existing version until the user gives a separate deployment go. Do not ask for that go during this build; finish the local result for review.

## 2. Read and inspect first

Read `AGENTS.md`, `App/docs/prompts/44-orchestrator-handover.md`, the newest `App/docs/HANDOVER.md` sections, `App/docs/build-plan.md`, `App/docs/DESIGN.md`, and `Web/ResidentPortal/docs/DESIGN.md`. The current handover and this prompt supersede stale phase/auth/parallel-work instructions. Read the relevant API contract sections for public reads, Ask, routes, verdicts, Review and inspection requests; do not edit that contract.

Load available Axiom design/SwiftUI, SwiftUI expert, **appllama-app-design-skill** and **appllama-usage** skills. The Appllama skills are installed under `~/.agents/skills/`; read their `SKILL.md` files and relevant existing-screen improvement guidance. Use other applicable installed development skills for the work actually being done: Apple API documentation, layout/motion/performance, build diagnostics or tests as needed. Actively use their guidance and supporting tools rather than merely naming them in the report. Skills do not authorize extra agents or audit matrices. Reference entry points:

- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Motion](https://developer.apple.com/design/human-interface-guidelines/motion)

Check git status and recent log. Preserve unrelated work. Inspect the current source and **run the current local screens before changing them**. Existing screenshots are evidence, not necessarily the current UI:

- iOS `App/docs/screens/phase-5/stub-plan-after.png` (route, close stops 3/4), `phase-7/review-list-live.png`, `phase-7/review-kiln-live.png`, and `phase-8/resident-requests-live-43b.png`.
- Portal `Web/ResidentPortal/docs/screens/mobile/area-393-light.png`, `docs/screens/requests/phone-record-live-43c.png`, and `phone-form-send-en.png`.
- `docs/screens/live/record-reference.png` predates the Before-left / After-right correction. Do not restore its order or beyond-threshold amber bars. The latest request screenshot is also only a viewport, not the whole record.

Write a short before/after hierarchy plan in the report before implementing it. Proceed without another permission question within this scope.

### Research and development tools

- Discover and use the installed **libraries.dev** tools for the relevant framework/package documentation and examples, checking against this repository's actual versions. Do not assume tool names or capabilities. Use its supported discovery interface if the name is not already exposed in the builder session.
- Use **Appllama** for targeted study of calm map-first screens, compact selected-item cards, progressive disclosure and navigation/interaction continuity. When its MCP is connected, start with the free credit check, then use focused keyword/semantic searches and view the actual screen/flow media. Extract hierarchy and interaction patterns, map them onto KilnWatch's existing design, and record the references and decisions in the report. Keep external reference assets in ignored `.local/polish-45/research/`, not in the product or public docs. Do not reproduce watermarks or copy another brand's styling.
- The repository's stacks override the Appllama skills' Expo/React Native defaults: **SwiftUI/MapKit on iOS, React/TypeScript/Leaflet on the web**. Translate relevant design principles to these stacks. Preserve native SwiftUI navigation and the current motion tokens; do not introduce Expo, React Native, Reanimated, a new state/persistence system, or optimistic inspection/verdict counts. The prompt's light verification scope overrides the skill's broad device/theme/performance matrix. Review motion recordings, but claim measured performance only if actually measured.
- Make active use of appropriate skills, installed packages and development tooling. Select a package for a concrete implementation or verification benefit, with current documentation and compatibility checked through libraries.dev or official package docs. Existing packages and native platform capabilities come first. A small local frontend/development dependency addition is allowed when justified; explain its purpose, alternatives considered and impact in the report. Use headless/unstyled behavior where applicable and apply KilnWatch tokens. Keep package work confined to the portal manifest and its corresponding lockfile; no UI-kit theme adoption, unrelated upgrades, toolchain migration, global installation or iOS package/project changes.
- If either connected service is unavailable, report that specific limit and continue with the installed skill files and official framework/package documentation. Do not claim tool usage, install a connector, purchase credits or pause the authorized local polish merely because a research service is unavailable.

## 3. Shared design direction

Keep the neutral tokens, single clay accent, current type family, monospaced IDs/distances, 4-point spacing scale and soft solid content surfaces. Give each viewport a clear focal point and each task one dominant primary action. Secondary actions remain easy to find; avoid repeating the same full-size action in several adjacent places.

Before implementing, write a short shared style checklist: typography roles, spacing rhythm, corner scale, solid content/glass navigation boundary, ink primary actions/clay selection, status treatment, disclosure labels and interaction feedback. Apply it to both platforms. Translate native controls appropriately; do not force pixel-identical web and iOS chrome. Compare the final phone screens side by side and correct any difference that makes them look like unrelated products.

Use progressive disclosure for provenance, full rule checks, breakdowns and repeated explanations. A collapsed section must identify what it contains and retain an honest summary. Keep the provisional status visible. Keep modelled/unverified labels attached to the numbers or predictions they qualify. Error, offline, sample and saved-state notices remain visible when applicable. Attribution stays with the evidence; maps retain their legal/provider attribution.

The two DESIGN files remain binding. This prompt expressly authorizes these narrow updates: compact summary-first presentation, secondary details collapsed by default, interaction-driven portal motion beyond its previous color/loading-only policy, and restrained translucency on portal map-control chrome with a solid fallback. Document the resulting defaults in a dated addition to each DESIGN file; retain their other rules. No new product capabilities, authentication or data semantics.

## 4. iOS — implement first

### Today and maps

- Make the map the dominant area. Consolidate route context and secondary controls into a compact hierarchy instead of several floating islands and banners. Keep route length/estimated timing, current selection and Start/End clear; route list, map style and location remain reachable through existing native controls/menus.
- The default selected-stop card should show full ID, arrival estimate, a short relevant fact, provisional status and the existing navigation action. Move the repeated on-site checklist, access notes, full exposure explanation and other detail into an explicit expansion or the existing kiln detail. Preserve every field and the distinction between browsing a stop and the active stop. Avoid a second independent scroll area in the compact card where possible.
- Address the stops 3/4 overlap as a presentation problem: both stops must be discoverable and independently selectable. Keep actual geographic anchors, supplied road geometry, numbering and order truthful. Use the smallest appropriate label/disambiguation treatment; do not drop a stop, invent new coordinates or require a new backend feature. Verify selecting either close stop, not only the prettier overview.
- Preserve user panning. Camera changes should follow explicit selection/overview actions; disclosure expansion must not repeatedly reset the map or rebuild it. Existing browsing pins should look quiet until selected.

### Kiln, lists, Review and Ask

- Kiln opening: concise identity/status, evidence, then the facts needed for inspection. Remove repeated identity/date/model explanations from the opening viewport. Preserve a readable full monospaced ID without truncation; a shorter display title may coexist, but must not replace the full ID.
- Show the leading siting flag with its measured distance and threshold, modelled people estimate, and neutral resident-request summary. Put remaining rule checks/sources, exposure age breakdown, request concern/distance breakdown and model/provenance details in clearly labeled disclosures. Do not hide partial assessment, unknown data or anonymous/unverified context. Keep zero and unavailable distinct. The request section stays after exposure.
- Kilns rows: identity, status and one useful supporting line; detail belongs on tap. Positive request counts remain available without turning every row into a stack of badges.
- Review: tighten the title/live-badge spacing and counts hierarchy. Use compact rows with full identity, change group and neutral pending-review state. Reveal the **verbatim** stored reason and supplied scores on an explicit expansion; preserve detail navigation and historical-location access. Keep all four counts available, including zero; this remains a manually produced snapshot pending review, with no approval action.
- Ask: simplify the empty state and composer surroundings; answer, citations and server disclaimer remain intact. Keep trace detail expandable. Polish waiting-to-answer and keyboard transitions using mocks. Do not simulate live streaming or reveal an unvalidated answer.
- Verdict sheet: polish spacing and native presentation only where needed. Preserve all outcomes, photo/location behavior, note, cancellation safeguards, the status-change warning and the existing hold-to-confirm interaction. Verify with a mock, cancel the live sheet, and do not alter outbox/submission behavior.

### Glass and motion

Use native **regular** Liquid Glass on navigation, grouped map controls, appropriate toolbar/accessory surfaces and the composer. Prefer standard navigation/sheets and existing motion tokens. Avoid nested glass, clear glass, glass content cards, added floating ornaments or custom tab bars. Primary content actions keep the established ink styling; clay remains a selection accent.

Make selection, sheet presentation, disclosure expansion and card changes feel immediate and settle smoothly. Scope animations to the changing state; retain stable view identity, existing haptics and Reduce Motion behavior. No arbitrary delays, autoplay, continual bouncing, broad animation modifiers on the entire screen, or map recreation during small UI updates. Do not change the iOS 26.1 minimum or root project/signing configuration.

## 5. Portal — implement after iOS

- Phone Area: reduce the stack of heading, search summary, result summary and map chrome. Keep edit/search and Map/List easy to find; the map and selected record should appear earlier. Preserve explicit public search, sample labels, incomplete result/pagination notices, the search-area limitation, opt-in location and synchronized selection. Do not turn this into automatic location collection or an automatic network search.
- Record opening: stop letting the long ID consume a large headline across three lines. Use a quiet full monospaced identity treatment, exact status and a compact useful summary. Remove duplicate facts from At a glance and the sections immediately below it.
- Keep the resident-request summary and one dominant Request an inspection action accessible. The concern/distance form opens on intent. Keep the existing sent/revisit label **View your request**, anonymous/unverified explanation, privacy line, browser dedupe behavior and fresh count handling. Avoid adjacent duplicate primary buttons; sticky navigation/action bars must not cover the form, Send, keyboard or confirmation. Preserve English/Hindi and count-1/count-many copy.
- Keep evidence prominent: Before left, After right, real supplied dates and attribution. Collapse secondary rule checks, sources, model details and population/request breakdowns. Unknown/inconclusive states remain honest and distinguishable; do not recolor them as successful checks. Written drafting/export remains available as a secondary task.
- Ask: simplify the composer and introduction while retaining citations, trace disclosure, character limits, English-answer note in Hindi, and the server disclaimer. Keep draft/export flows intact. Remove existing public-banner wording that implies candidates have been approved; use concise factual public-registry wording while retaining record-specific pending-inspection status.
- Carry the calmer hierarchy onto desktop without redesigning the desktop workspace. Keep useful adjacent map/list layout and readable content width; do not merely stretch the phone layout.
- Add restrained press/selection feedback and short expansion/composer transitions. Use existing CSS/browser controls or a small justified motion utility under the package rules above. Animate only small affected surfaces, avoid layout jumps and repeated map remounts. Honor `prefers-reduced-motion`; no automatic map flights or decorative entrance sequences.
- Translucency may finish the top/bottom navigation and map-control chrome, with a legible solid fallback. Content remains solid. Do not claim the web has native Liquid Glass or add blur across the evidence, forms and lists.

## 6. Files, safety and verification

Own presentation files under `App/KilnWatch/`, appropriate UI tests/stubs under `App/`, `Web/ResidentPortal/`, and the two DESIGN/handover additions and report/captures. Shared components may change where needed; preserve API/client/persistence behavior. No `AWS/`, `Model/`, API-contract, credentials or root Xcode project changes. Only justified portal package additions may change its manifest/corresponding lockfile; every other dependency lock stays unchanged. Preserve the existing runtimes.

This repository is **public**. Never print or write either account ID, any ARN, API URL/ID, CloudFront domain/ID, bucket/table names, ECR host, RDS host, private user names or emails. Read ignored `.local/` output files and ignored configuration silently, and sanitize any subprocess output before showing it. No raw URL-bearing browser network logs, environment dumps, local config dumps or private identifiers in captures/report. No sign-in attempts.

Light verification only:

1. Run core `swift test` in `App/Packages/KilnWatchCore` and the prescribed root build:
   `xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build`.
2. Portal: `npm run typecheck`, `npm test`, `npm run build` with explicit fixture configuration, and the existing relevant mocked Chromium journeys. Ensure test configuration intercepts writes instead of reaching production. Add or adapt only meaningful checks for changed disclosure/selection/focus/action behavior; do not create a broad new suite.
3. Walk the demo locally: Today route/close-stop selection → kiln/evidence/expanded details → mocked Ask → mocked verdict/cancel → Review expansion/navigation; portal Area → record → request form/mock success/revisit → Ask and secondary written draft. Check compact and expanded states, selection retention, keyboard clearance and disclosure focus. One phone Hindi request-form smoke check and a desktop Area/record smoke check are sufficient. No dark/AX/device/browser matrix or audit agents.
4. Confirm Reduce Motion fallbacks in the changed code and one focused smoke check per platform. Respect existing Dynamic Type/touch/focus behavior without starting a new accessibility audit phase.
5. Capture matched **before and after** light screenshots for iOS Today route, kiln opening and Review; portal phone Area and record opening, plus one desktop record. Use identical data, screen size and initial scroll position. Add after captures of expanded iOS detail and the portal request form/confirmation. Do not hide real sticky bars for viewport screenshots.
6. Save one short local interaction recording per platform showing selection and an expansion, so motion can be reviewed. Use mock responses; recordings need no live write. Inspect all images and clips yourself and fix visible defects. Store captures in `App/docs/screens/phase-9/` and `Web/ResidentPortal/docs/screens/polish-45/`; name the data mode in the report.
7. Review the full diff and whitespace. Leak-scan changed/untracked text and screenshot/video OCR/metadata against values read silently from ignored local outputs/config plus account, ARN, private-host and email patterns. Report counts and safe file locations only, never matched private values. If OCR is unavailable, record the limit and visually inspect every capture; do not claim an OCR pass.

## 7. Deliver and stop

Write `App/docs/screens/phase-9/demo-ui-polish-report.md` covering both platforms: concise before/after hierarchy, shared style checklist and side-by-side consistency findings, actual skills/tools/research/package usage (and availability limits), actual files changed, test/build outcomes and warnings, capture links, motion behavior, zero live write calls, leak counts and remaining limits. Add a short dated note to both handovers and the narrow DESIGN amendments described above.

Report what is still local: **the hosted portal has not been updated**. Do not claim physical-iPhone or actual iOS 26.1 coverage from Simulator checks. Stop for orchestrator review with all work unstaged and uncommitted. No deployment or further phase work.
