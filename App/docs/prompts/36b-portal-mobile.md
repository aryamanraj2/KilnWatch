# Prompt 36b: resident portal, phone-first polish (closer to the iOS app)

You are the builder for **one web step**. Work sequentially in this one chat. No sub-agents. Don't commit, push or stage. The repo is public.

**Run this only after prompt 36 has finished and been reviewed.** 36 added the live adapter and the Ask panel; this step changes how the portal looks and flows on a phone. It does not change what data it shows.

**The user gave the go by running this prompt.** The scope is exactly:
1. edits under `Web/ResidentPortal/` only: layout, CSS, presentational components, `index.html`, tests and its docs;
2. local runs in **fixture mode** (the default). **Zero** live `POST /ask` and no live API reads are needed; if you open live mode at all, read-only `GET`s only.
3. No hosting, no deploy, no AWS CLI or Terraform, no CORS change.

**Out of scope:** `src/data/*` (the live adapter, client, model and fixtures from 36), the Ask request/response/error logic, any copy that states a status or a measurement, `App/`, `AWS/` and the API contract. If a change needs one of these, stop and report.

## Read first

- `AGENTS.md`, `App/docs/DESIGN.md` (binding: tokens, copy rules, anti-slop list, §10 screens), then `Web/ResidentPortal/docs/DESIGN.md` and `README.md`.
- `src/app/App.tsx`, `src/styles/global.css`, `src/features/area/AreaPage.tsx`, `src/features/records/RecordPages.tsx`, `src/features/evidence/Evidence.tsx`, and the Ask panel 36 added.

## What the orchestrator saw at 393 × 852 (iPhone 15, fixture mode)

- **Too much chrome before content.** Brand row + language switch + theme menu, then a second row of text tabs, then the sample banner, then an eyebrow, a two-line hero and a subtitle. The map starts about 500 px down; the search controls ("Choose your area") sit **below** the map and the selected record.
- **The kiln page is about 3,800 px long.** The facts a resident wants (rule flag measured against the threshold, people within 800 m) come after a tall evidence block; actions ("Add to inspection draft") are at the very bottom.
- **The comparator is the reverse of iOS:** After is on the left, Before on the right. iOS shows before | after (earlier left).
- Desktop at 1440 px looks right; keep it.
- No horizontal overflow at 393 px. Good; keep it that way down to 320 px.

## Changes (phones: `max-width: 600px`; keep tablet and desktop as they are unless a fix is shared)

1. **Bottom tab bar on phones**, like the iOS `TabView`: Area, Ask, Draft (Draft shows the selected-record count). Fixed to the bottom with `padding-bottom: env(safe-area-inset-bottom)`; add `viewport-fit=cover` to the viewport meta. Use real links with `aria-current="page"`, symbol + word, targets ≥ 44 px. A solid `surface` bar with a hairline top border; a translucent `backdrop-filter` is allowed **only** on this bar and the top bar (DESIGN §1: glass on navigation only), and text must stay legible without it. Hide the top text tabs on phones. Pages get bottom padding so nothing hides behind the bar.
2. **Compact top bar on phones:** mark + "KilnWatch" on the left; language and theme move into one native control (a `<details>` menu or two `<select>`s) on the right. One row, sticky. The sample/live banner becomes one line ("Sample data · fictional records"), still always visible and still never removable in sample mode.
3. **Area page on phones:**
   - One-line page title; drop the eyebrow and subtitle on phones (keep them on desktop).
   - The place search field and "Use my location" come **first**, above the map. Coordinates and radius go into a collapsed native `<details>` ("Area settings"). The radius stays a 4-option segmented control. Keep "This is a search area, not a legal buffer."
   - Then the Map/List segmented control, then the map at about `55svh` (min 320 px).
   - The selected record card stays directly below the map.
4. **Kiln page on phones:**
   - Right under the ID and status badge, an **"At a glance"** card built only from fields the page already renders: the top rule line as it already reads (e.g. "520 m · rule 800 m" with its verification label, or the existing "Not assessed" / "inconclusive" wording, never "clear"), the people line as it already reads (or "Not assessed" when null, never 0), and the latest observation date. No new claims, no new numbers.
   - Evidence follows, then the rule cards, exposure and map as now. Collapse "Model prediction" into a native `<details>` on phones.
   - A **sticky action bar** above the tab bar: "Ask about this kiln" (opens the Ask panel with this kiln, as 36 wired it) and "Add to draft" (existing action). Primary = ink fill; the other = `surface2`.
5. **Comparator:** Before on the left, After on the right, matching iOS (both the image layers and the labels; keep the drag, the slider and the buttons working, and keep "Show before" / "Show after" in that order).
6. **Ask panel on phones:** the composer sits at the bottom of the panel (above the tab bar), the answer list scrolls above it, citation chips use the clay-on-`surface2` style, the server disclaimer stays verbatim under the composer.
7. **Type and spacing:** cap the phone hero at about `1.75rem`; keep the 4 px grid, 20 px screen margin, 20 px card radius; no new colors, no gradients, no shadows except the existing floating map cards.

8. **Two fixes from the 36 review (all widths):**
   - **Rule bar colour.** In `RecordPages.tsx` every rule bar uses the flagged amber fill, so "Beyond threshold" (e.g. C-KILN-1K, 1,273 m against 1,000 m) looks like a flag. Amber is for a siting flag only (`within_threshold`). A `beyond_threshold` bar uses a neutral fill (`inkSecondary` on the `surface2` track), matching iOS, where only flags get the status colour. Keep the threshold tick. No wording change.
   - **Phone rule list.** On phones, show the flagged checks first as full cards; the rest (beyond threshold, inconclusive, not evaluated) go in one native `<details>` ("Other rule checks · N"), still listing every check with its status words. Inconclusive is still never clear.

Keep everything else: the copy rules ("Flagged by satellite · pending inspection", never "illegal"), Hindi strings (new strings get a plain translation, marked for native review), focus management, skip link, reduced motion, dark mode, print styles.

## Checks (keep them light)

- `npm run typecheck`, `npm test`, `npm run build`, and the existing Playwright e2e on **Chromium only** (update selectors that moved). Add one small e2e: at 393 × 852 the tab bar is visible, navigates to Area / Ask / Draft, and the page has no horizontal overflow at 320 px.
- Screenshots in fixture mode to `Web/ResidentPortal/docs/screens/mobile/`: Area, Kiln (top + action bar), Ask (empty state), Draft at 393 × 852 light; Area and Kiln dark; Area at 320 px; Area at 1440 × 900 to show desktop is unchanged. Nine images, no more.
- Leak check: grep changed files and screenshots for the API host, API ID and CDN host (read from the `.local` outputs without printing them). Expect 0.

## Docs and report

- Add a short "Phones" section to `Web/ResidentPortal/docs/DESIGN.md` (tab bar, top bar, area order, at-a-glance, action bar, comparator order) and a one-line note in `docs/HANDOVER.md`.
- **Report:** what changed (files), test/build/e2e results, the nine screenshots, leak count, live calls used (expected 0), and anything you left as it was and why.
