# Demo UI polish — 11 October 2026

Local frontend phase 45. The hierarchy plan and checklist were written before implementation. The user requested a faster wrap-up; remaining verification/capture limits are listed below.

## Before → after hierarchy plan

- iOS Today: several header islands and a dense, internally scrolling inspection card → one grouped navigation surface, map-first viewport, compact selected stop with status/arrival/one fact/Navigate; full inspection sheet remains in kiln detail. Close-stop labels separate visually while geographic anchors remain exact.
- iOS kiln: repeated identity, score and date explanations before evidence → quiet full identity and provisional status, evidence, leading flag, summary exposure and resident requests. Other flags/checks, model/date context and breakdowns expand explicitly.
- iOS Review: paragraphs of counts and reasons in every row → readable four-count summary, identity/group/pending state, explicit Reason and scores expansion and separate detail navigation.
- Portal Area: multiple headings/summaries above map → compact search context with edit and Map/List controls; map and selected record move earlier. Desktop retains adjacent list/map.
- Portal record: long headline and repeated At a glance → quiet full monospaced identity, provisional status, evidence and a single request action; secondary rules, exposure/request/model details reveal on demand. Sticky navigation clears the request form.
- Ask: compact introduction and composer, retained answer/citations/server disclaimer and expandable trace. Native keyboard/sheet behavior and existing safety semantics remain.

## Shared style checklist

System type family; headline for task, body for reading, footnote for qualifications; full monospaced IDs/distances and tabular counts. 4-point rhythm, 20-point screen margins/cards, 12-point inner corners, capsule controls. Solid content; regular native glass only on iOS navigation and restrained web navigation/control translucency with solid fallback. Ink primary actions, clay selection/citations. Status symbol plus exact provisional words. Specific disclosure labels name contents and retain summary/unknown context. Immediate press/selection feedback, scoped settling motion and reduced-motion fallback; maps retain identity and camera changes follow selection/overview only.

## Research/tool availability

Installed Appllama design and usage skills read, including existing-screen improvement playbook; Axiom design/SwiftUI and SwiftUI expert guidance loaded. Connected tool catalog and supported plugin search did not expose libraries.dev or Appllama; no connector installation or credit purchase. Official Apple, React, Leaflet and Playwright documentation used as fallback. Research references and final usage details will follow.


## Local result

Both platforms retain the system type, neutral palette, clay selection, ink primary actions and solid rounded content surfaces. Phone record openings now prioritize the full identity/status and evidence; qualifications remain attached to the prediction, exposure and request count. Named disclosures replace repeated explanations. Desktop keeps its evidence/sidebar layout. Today uses regular native glass for grouped controls; web control translucency uses CSS with a solid fallback, with no native-glass claim.

Today pins 3/4 keep their original geographic anchors and separate labels; both passed independent selection checks. The compact stop card retains full ID, arrival, provisional status and navigation. The inspection sheet moved into kiln detail. Review retains all four counts, verbatim reasons, scores and historical location access. Ask and verdict keep their existing data/submission semantics.

Portal requests retain native concern/distance controls, anonymous/unverified context, privacy copy, server-derived counts, browser dedupe and View your request. The phone has one dominant request action. Opening it clears the action bar; the hash-navigation focus conflict found during rehearsal was corrected by handling the open action without route navigation. Written drafting/export remains in its named expansion.

## Actual tools and packages

Read and applied Appllama design/usage playbooks (existing-screen hierarchy, stable navigation, native controls), Axiom design/SwiftUI layout/motion guidance, SwiftUI expert glass guidance, and Axiom build/testing guidance. libraries.dev and Appllama services were unavailable after supported discovery, so no credit check, screen-media study or connector call is claimed. Official documentation fallback:

- [Apple custom Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) and [Motion](https://developer.apple.com/design/human-interface-guidelines/motion): navigation/control boundaries and reduced motion.
- [React state identity](https://react.dev/learn/preserving-and-resetting-state): stable component identity; record-map props memoized to avoid camera resets during form/disclosure updates.
- [Leaflet 1.9.4](https://leafletjs.com/reference-1.9.4.html): existing package retained for the map and explicit camera controls.
- [Playwright video](https://playwright.dev/docs/videos): existing Playwright 1.64 used for mocked interaction checks, screenshots and recording. Matching Chromium downloaded to its local browser cache. No manifest, lockfile, iOS project, minimum OS, signing or runtime migration.

Native SwiftUI/HTML/CSS were selected over a motion or UI-kit dependency: they preserve existing styling, focus semantics and reduced-motion behavior with no extra bundle dependency. Portal checks used the available compatible Node 24 runtime.

## Verification and warnings

- Prescribed root iPhone 17 Simulator build: passed, zero compiler warnings/errors.
- Core: 103 reported tests passed, zero warnings/errors; one existing opt-in skip.
- iOS focused checks passed: close-stop selection/card synchronization, kiln disclosures and verdict cancellation, mocked Ask keyboard/waiting/answer, Review expansion/detail/historical navigation, and Reduce Motion. Captures came from an ignored temporary XCTest harness. No root-project changes.
- Portal typecheck passed; six unit-test files / 96 tests passed; explicit fixture production build passed. Vite emitted a plugin-timing advisory; Playwright emitted the existing NO_COLOR/FORCE_COLOR environment warning.
- Portal motion check passed, including retained map instance and a focused prefers-reduced-motion expansion smoke check. Matched opening captures completed. Focused phone request journey passed: form focus, action-bar clearance, Send above tabs, mock success, fresh count, reload/revisit with no second write, and Hindi form smoke. Desktop Area/record openings also completed.
- No measured frame-rate/performance claim. No physical iPhone or actual iOS 26.1 runtime coverage; iOS checks used iPhone 17 / iOS 27 Simulator. No broad theme/device/accessibility matrix.

## Captures and data modes

All screenshot pairs use light appearance and initial scroll position zero. iOS pairs use the same recorded eight-stop Plan, recorded R1 detail with synthetic evidence and 12-request fixture, and recorded Review queue. Before UI came from the baseline source in an isolated ignored harness. Portal pairs use the same sanitized recorded four-record public-response shape, 12-request fixture, mocked tiles and generated PNG evidence; no screenshots represent fresh live evidence. Phone is 393 × 852; desktop is 1440 × 1000.

| Screen | Before | After |
|---|---|---|
| iOS Today | [before](today-before.png) | [after](today-after.png) |
| iOS kiln | [before](kiln-before.png) | [after](kiln-after.png) |
| iOS Review | [before](review-before.png) | [after](review-after.png) |
| Portal phone Area | [before](../../../../Web/ResidentPortal/docs/screens/polish-45/phone-area-before.png) | [after](../../../../Web/ResidentPortal/docs/screens/polish-45/phone-area-after.png) |
| Portal phone record | [before](../../../../Web/ResidentPortal/docs/screens/polish-45/phone-record-before.png) | [after](../../../../Web/ResidentPortal/docs/screens/polish-45/phone-record-after.png) |
| Portal desktop record | [before](../../../../Web/ResidentPortal/docs/screens/polish-45/desktop-record-before.png) | [after](../../../../Web/ResidentPortal/docs/screens/polish-45/desktop-record-after.png) |

Additional iOS captures: [close stop 4](close-stop-4-after.png), [checks](kiln-expanded-after.png), [request breakdown](requests-expanded-after.png), [verdict/cancel](verdict-after.png), [Review reason](review-expanded-after.png), [Review detail](review-navigation-after.png), [historical location](review-historical-after.png), [Ask waiting](ask-waiting-after.png), [Ask answer](ask-answer-after.png), [source expansion](motion-detail-expanded.png). Portal [request form](../../../../Web/ResidentPortal/docs/screens/polish-45/phone-request-form-after.png), [confirmation](../../../../Web/ResidentPortal/docs/screens/polish-45/phone-request-confirmation-after.png), [Hindi form](../../../../Web/ResidentPortal/docs/screens/polish-45/phone-request-hindi-after.png), [expanded checks](../../../../Web/ResidentPortal/docs/screens/polish-45/phone-checks-expanded-after.png), [desktop Area](../../../../Web/ResidentPortal/docs/screens/polish-45/desktop-area-after.png) and [interaction recording](../../../../Web/ResidentPortal/docs/screens/polish-45/portal-interaction.webm).

The opening screenshots were visually compared: both use quiet mono identity, exact pending status, an unverified type line, early evidence, solid rounded cards and restrained navigation chrome. Web uses browser-native controls rather than copying the iOS navigation pixels. Secondary material remains readable in expanded states. The full-size before portal identity and duplicated request/glance stack are removed.

## Files and scope

Presentation edits: iOS Today/StopPin, Kiln/RuleDistanceBar/ExposureBlock/ResidentRequestsBlock, Kilns rows, Review, Ask and VerdictSheet. PublicDemo adds an opt-in DEBUG Review-detail fixture only; App/UITests contains the focused rehearsal checks. Portal App banner, Area, Ask, RecordPages, InspectionRequest and global CSS; browser capture configuration and journey assertions adapt to disclosures. Both DESIGN files and handovers record the new defaults. API contract, client, persistence, AWS, model code and dependency locks are unchanged.

Zero live write calls. App launches used readOnly and intercepting mocks; browser write-shaped interactions were intercepted at synthetic hosts. No AWS CLI, sign-in, deployment, staging, commit or push. Hosted portal has not been updated. All work remains local, unstaged and uncommitted for orchestrator review.

## Remaining limits

The Simulator recorder reported a busy host recording and a later recording retry encountered a stalled Xcode build service. Those retries were stopped during the requested faster wrap-up. No usable iOS video is delivered; the successful interaction checks and still captures remain. The focused request journey and Hindi smoke passed. The existing full mocked Chromium journeys and the complete secondary written-draft/export walkthrough have not been rerun after polish. Independent Hindi wording review remains a release input. This is a reviewable local polish, not a completed release verification phase.


## Safety check result

Final changed/untracked-text scan: 28 files. Screenshot scan: 27 files, all 27 recognized with macOS Vision OCR and checked with image metadata. Zero private-value matches, zero account/ARN/private-host/email pattern matches, zero affected files, against ignored configuration values read silently. The recorder's unfinished temporary binary was moved into ignored local storage and is not delivered. The portal recording was visually reviewed through four sampled frames; automated video OCR/metadata scanning was not completed during the faster wrap-up. Safe scan counts and raw diagnostics remain in ignored `.local/polish-45/`. Final whitespace check passed. Capture/test setup mistakes were corrected; the delivered request journey passes. Orchestrator review is the next step.
