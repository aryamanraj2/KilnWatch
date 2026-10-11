# Prompt 36c: phone Area page, map higher up (small)

You are the builder for **one small web step**. Work sequentially in this one chat. No sub-agents. Don't commit, push or stage. The repo is public.

Run after 36b (reviewed). Same scope and rules as 36b: presentational edits under `Web/ResidentPortal/` only, fixture mode, **zero** live calls, no `src/data/*`, no Ask request logic, no AWS. Read `App/docs/prompts/36b-portal-mobile.md` for the context.

## Problem (orchestrator review of `docs/screens/mobile/area-393-light.png`)

On a phone the search card is about 800 px tall (search field, sample-places note, place chip, Use my location, Area settings, legal-buffer note, Confirm button, privacy note), so the map starts about 700 px down; before 36b it was about 500 px. A resident lands on a page with no map in view.

## Changes (phones only, `max-width: 600px`; desktop must stay pixel-identical)

1. **Collapsed search after results.** Once a search has results, the card shows a one-line summary instead of the full form: "Pilkhuwa · 1 km" (or the coordinates in mono when there is no place name) with an "Edit" button (≥ 44 px) that expands the full form in place and moves focus to the search field. A new search, or a validation error, keeps the full form open. Before the first search (live mode starts with an explicit search) the full form shows, as now.
2. **"Use my location"** becomes an icon button inside the search row (the existing target symbol, `aria-label` "Use my location", ≥ 44 × 44), not a full-width row.
3. **Disclosures stay, smaller.** The sample-places note, "This is a search area, not a legal buffer." and the privacy note stay visible in the full form, as `help` text under the button. In the collapsed state, keep one line under the summary: "Search area, not a legal buffer."
4. **Target:** with results loaded in fixture mode at 393 × 852, the top of the map is at or above **360 px** from the top of the page.
5. **Mono units:** in the At-a-glance card and rule figures, the figure and unit are joined with a no-break space and the unit is not spaced like code (`520 m`, not `520  m`), per App DESIGN §3: only the figure+unit is mono, as one token.

## Checks (light)

- `npm run typecheck`, `npm test`, `npm run build`, Chromium e2e (sample + mocked live). Extend the existing phone test: the map top is ≤ 360 px after results; "Edit" expands the form and focuses the search field; no horizontal overflow at 320 px.
- Replace `docs/screens/mobile/area-393-light.png`, `area-393-dark.png` and `area-320-light.png`, and add `area-393-edit.png` (form expanded). Re-shoot `area-1440-light.png` and confirm desktop is unchanged.
- Leak check as in 36b (expect 0). Live calls: 0.
- **Report:** files changed, results, the 5 screenshots, the measured map top, leak count, and new Hindi strings needing review.
