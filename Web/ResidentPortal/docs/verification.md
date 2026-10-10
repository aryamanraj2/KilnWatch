# R1 local verification

10 October 2026. Data source: **synthetic local fixtures only**. No anonymous production API or real evidence publication was verified. Local implementation is reviewable; the R1 gate is **not fully passed** because spoken screen-reader and native 200% browser-zoom checks remain unverified.

## Executed checks

| Check | Result / evidence |
|---|---|
| Strict TypeScript | `npm run typecheck` passes. |
| Unit and behavior | `npm test`: 32 pass. Includes invalid/unknown data, polygons/coordinates, geodesic distances, page deduplication/revision, no fixture fallback on live failure, retry/abort, out-of-order responses, draft privacy and dirty-edit protection. |
| Production build | `npm run build` passes under Node 24.21.0. Main JS about 432 kB / 129 kB gzip; diagram and fixtures separate chunks. No source maps. |
| Browser journeys | `npm run test:e2e`: 14 pass, one worker, no retries: seven in Chromium and seven in Playwright WebKit. Search, paging, map/list, keyboard, Back/direct refresh, evidence states, rule limits, English/Hindi drafts, denial/manual fallback and failure states. |
| Accessibility automation | Axe checks in light/dark area and record views pass; keyboard navigation, accessible-tree assertions, comparator keys, reduced motion and 320px reflow checked. This is not spoken assistive-technology proof. |
| Exports | Actual UTF-8 downloads in both engines; actual clipboard readback in Chromium; print action intercepted in both engines. Chromium-generated A4 PDFs rendered and visually inspected: English two pages, Hindi one page, no clipping/missing Devanagari glyphs or dark background after the print fix. OS print dialogs and physical printing were not exercised. |
| Privacy | Browser test checks URL/history, storage and outbound-request boundaries with fictional personal details. Only locale/theme persist; no live account/API, private asset, analytics or filing requests. |
| Preservation | Changes confined to the new portal directory. No inspector/backend/model edits or external mutations. |

Browser installation: Playwright 1.64.0; Chromium 156.0.8078.4 (build 1248), WebKit package build 2370. WebKit testing is not a claim of testing an actual iPhone or installed Safari. The runner emits an environment-only NO_COLOR/FORCE_COLOR warning; no unresolved TypeScript or Vite build warnings were observed.

## Reviewed artifacts

Full-page screenshots use a 1440px desktop viewport and a 375×812 mobile viewport (full-page heights vary). They are reproducible from `tests/browser/portal.spec.ts`; regenerated screenshots use the same filenames.

- [English area](screens/desktop-area-en.png), [evidence](screens/evidence-en.png), [editable draft](screens/draft-en.png), [service failure](screens/service-error-en.png).
- [Hindi mobile, dark theme](screens/mobile-area-hi-dark.png).
- [English text](screens/sample-draft-en.txt) and [PDF](screens/sample-draft-en.pdf); [Hindi text](screens/sample-draft-hi.txt) and [PDF](screens/sample-draft-hi.pdf).

Source URLs can wrap across printed lines. Exports contain local record/image references, not embedded image attachments or publicly reachable evidence. Export samples include only fictional resident details. The sample notice and not-submitted statement remain outside the editable body.

## Performance sample

Production preview, Chromium, 390×844, cold browser cache, 4× CPU slowdown, 150ms latency, 1.5Mbps download / 750Kbps upload, one local run: LCP **1,664ms**, CLS **0.0060**, search-to-results **355ms**, maximum observed event duration **64ms**. See [raw measurement](screens/performance.json). These are laboratory observations, not field INP, an accessibility score, or deployed-network performance. The measurement preceded the final print-only background and language-button touch-height CSS adjustments; it is not an exact final-build benchmark.

To repeat after `npm run build`:

```sh
PLAYWRIGHT_BROWSERS_PATH=.cache/ms-playwright KW_PERFORMANCE=1 npm run test:e2e -- --project=chromium
```

The performance check also exercises CSS `zoom: 2` reflow. That approximates layout scaling; native browser 200% zoom is still unverified.

## Open verification and release inputs

1. **R1 manual gate:** spoken VoiceOver/NVDA walkthrough of search, errors, pins/list, evidence, dialogs and draft/export. Computer-use access did not yield a usable screen-reader session; no spoken result is claimed.
2. **R1 manual gate:** actual browser-menu 200% zoom in desktop Chromium/Safari, with focus, content and controls reviewed. Narrow reflow and CSS zoom passed, but are not a substitute for this check.
3. **Release input:** independent Hindi copy review, confirmed official filing contacts and actual mobile-device/OS print behavior.
4. **Later phases:** approved real basemap/geocoder, real evidence alignment, server-side public projection, public-service failure behavior and live assistant grounding require their authorized phases. See the separate [integration request](aws-integration-request.md).

No deployment, commit, push, retraining or R2 connection was performed. The user controls the next phase gate.

## Continuation: local R2 preparation (10 October 2026)

User authorization: continue building; public backend “Not ready — prepare locally.” Current checks pass under Node 24.21.0:

- **35 unit/behavior tests**, including bilingual published-mode draft wording and image-dimension mismatch rejection. jsdom image tests supply decoded dimensions explicitly; browser tests decode actual generated PNGs.
- **14 sample-mode browser journeys**: seven Chromium, then seven WebKit, preserving the original flows, downloads, privacy assertions, automated accessibility checks and print-action coverage.
- **10 live-mode browser journeys**: five Chromium, then five WebKit, with fictional intercepted API responses and generated 256-pixel PNGs. Query/paging/selection/Back, bilingual evidence/explanations/rules/downloads, failures/partial pages, image retry, dimension mismatch and unapproved image-host refusal pass.
- Strict TypeScript and production build pass. Default fixture build: main JS 433.80 kB / 129.86 kB gzip; no source maps or build warnings. Browser runner retains the existing environment-only NO_COLOR/FORCE_COLOR warning.
- `git diff --check` passes; changes remain confined to `Web/ResidentPortal/`. No dependencies added. New test output uses ignored paths; the original reviewed artifacts above are preserved.

The original PDF visual review and performance sample above remain historical evidence; no fresh visual PDF review, native browser zoom or spoken screen-reader proof is claimed for this continuation. Mock browser refusals do not prove the backend publication boundary. Real records, evidence delivery, public CORS and deployed negative-access checks remain pending. See [R2 local preparation](R2-local-preparation.md).
