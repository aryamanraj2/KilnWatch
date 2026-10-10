# Prompt 13: Phase 3 polish — detail title, mini-map, Today pins, top edge, one unverified navigation

You are the builder for **one small polish pass** on the Phase 3 iOS app. Phase 3 is built and verified (see `App/docs/screens/phase-3/overnight-report.md`). The orchestrator reviewed the screenshots and found five visible issues. Fix only these. Nothing else changes.

Work sequentially in this chat. **No sub-agents** — the overnight exception is over. Do not commit, push or stage. No AWS, Terraform, `git` writes or `gh`. Do not edit `AWS/`, `Model/` or `.local/`. Never put the API URL in tracked files (it lives only in the ignored `App/Config/Public.xcconfig`). Never use the word "illegal".

## Read first

`AGENTS.md`, `App/docs/DESIGN.md` (binding), `App/docs/screens/phase-3/overnight-report.md`, `tester-notes.md`, then `App/KilnWatch/Features/Kiln/KilnView.swift`, `App/KilnWatch/Features/Today/PublicRegistryMap.swift` and `App/KilnWatch/Design/Components/KilnIDLabel.swift`.

## The five fixes

### 1. Detail title wraps badly
`KilnView.swift:128` joins the ID with zero-width spaces, so the 35-character ID wraps over three lines and leaves a lone "e" (`detail-top-light.png`).
- The large title shows the **same short form the Kilns list uses** (`KW-6b3b38…f3d3f78e`). Reuse the list's formatter, don't write a second one.
- Directly under it, show the full ID once in small monospaced secondary text, with `.textSelection(.enabled)`.
- The accessibility label stays the full ID. Check at AX5 that nothing truncates mid-glyph or overlaps.

### 2. Mini-map hides the footprint
In the live (non-fixture) branch, the camera uses a fixed 2400 m frame and a 32 pt flag annotation at the centroid covers the small polygon (`detail-bottom-light.png`).
- Fit the camera to the footprint's bounding box, padded to a minimum span of about 300 m, so the polygon is clearly visible.
- Draw the footprint with a visible accent stroke plus a light fill, so it reads in both light and dark mode.
- In the live branch, either drop the centroid annotation or replace it with a small dot (about 8 pt) that doesn't cover the polygon. Leave the fixture branch (800 m buffer, home/school points) unchanged.
- Update the map's accessibility label only if the meaning changes.

### 3. Today pins overlap
Thirty-nine 32 pt pins overlap heavily around Hapur (`today-dark.png`).
- Shrink the visible pin to about 20–22 pt and keep a 44 pt tap target (`contentShape`), so taps still work.
- No clustering library and no custom clustering code. If pins still overlap badly after shrinking, report it, and don't build clustering.
- Footprints should become visible when the user zooms in. Check whether they already do, and don't add zoom logic unless it's trivial.

### 4. Content shows through under the floating back button
On the scrolled detail screen, "First seen…" text sits behind the back button and status bar (`detail-bottom-light.png`, top).
- Find out why the system's top scroll-edge treatment is missing. A likely cause is that the toolbar background is hidden or the scroll view ignores the top safe area.
- Prefer restoring the system behaviour (for example `.scrollEdgeEffectStyle(_:for:)` on iOS 26 and later, or not hiding the toolbar background) over a hand-made blur.
- Apply the same fix on Kilns if it shows the same problem.

### 5. Search, then Today (verify only)
In the overnight run, switching to Today right after an active search could not be verified because native tab-bar elements were missing in the harness.
- Try **once** by hand in the Simulator: type a search on Kilns, tap Today, and confirm the map loads with 39 pins and the route-unavailable notice.
- Also try once with a UI test that dismisses the search first (`searchField` cancel) and then taps the tab.
- If it fails for a real app reason, fix it. If it's only the beta harness, record that and stop. **No retry loops.**

## Verification

1. `cd App/Packages/KilnWatchCore && swift test`: still 34 tests (33 passed, 1 skipped), unless you add one.
2. The root iPhone 17 build from `AGENTS.md`, with zero warnings.
3. The existing Phase 3 UI tests still pass. Add assertions only where a fix changes a label.
4. Re-capture only the affected screenshots, overwriting the files in `App/docs/screens/phase-3/`, in light and dark: `detail-top`, `detail-bottom`, `today`, `detail-ax5`, plus Kilns if fix 4 touched it. Inspect each one yourself before reporting.
5. Restore any Simulator settings you change (appearance, Dynamic Type).

## Report

1. Files changed, one line each.
2. What you did for each of the five fixes, or why you skipped it. Reference screenshots by path.
3. Test counts and the build-warning count.
4. The search-then-Today result: pass, fixed, or still unverified and why.
5. Confirm there were no commits, pushes, staging, AWS work, sub-agents or edits to protected folders.

Stop after the report.
