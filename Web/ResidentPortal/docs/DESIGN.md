# Resident portal design

The [app design system](../../../App/docs/DESIGN.md) is binding. This web translation follows its neutral, soft, precise visual language and the [resident brief](../../../App/docs/prompts/09-resident-portal-master-brief.md).

## Tokens and typography

`src/styles/global.css` defines the exact light/dark canvas, surface, secondary surface, ink, secondary ink, clay, and status colors from the app. Primary buttons use ink; clay identifies a selection or citation. Status is always symbol plus words. Distances, coordinates and IDs use monospace; counts use tabular figures. Spacing follows 4/8/12/16/20/24/32/48 pixels. Content uses solid surfaces, quiet borders, and 20-pixel card corners.

The system font stack includes Kohinoor Devanagari, Nirmala UI, and Noto Sans Devanagari fallbacks. No remote font request is made. Headings and Hindi text reflow without fixed text-container heights; Hindi uses additional line height. Comfortable controls are at least 44 pixels. Map pins use HTML buttons so the touch target does not shrink with SVG coordinates. Inline citations are compact and keyboard accessible.

Theme choices are System, Light, and Dark. Motion is limited to color transitions and a loading indicator; `prefers-reduced-motion` removes these. There are no automatic map flights, gradients, glass cards, AI badges, or decorative dashboards.

## Screens

- **Area:** practical heading, search form, and interactive street-map/list workspace. The demo opens with a populated Pilkhuwa area; public mode starts with an explicit search. Leaflet displays muted OpenStreetMap tiles with visible attribution, a dashed search radius, numbered selectable pins and native HTML zoom/reset controls. A selected record card links to evidence and drafting. Desktop keeps map and results adjacent; phones show the map first, offer Map/List buttons, and place area settings below the workspace. The list is independently usable. Place results explicitly describe sample lookup.
- **Record:** observation and provisional status first, then evidence and assessed/unassessed rules. The sidebar contains model limitations, population context, deterministic explanations, and drafting actions.
- **Rule:** jurisdiction, reference source/date, threshold availability, and limitations. No conclusion inferred from an ID.
- **Draft:** selected records and optional resident details beside an editable request. Export actions are after the editor. The print document contains only the actual draft, sample notice, source references, and not-submitted statement.
- **About/Privacy:** actual implementation, source attribution and data handling; no generic promises.

Every route has a main landmark, skip link, logical headings, and navigation focus management. Buttons and range controls use native HTML interactions. Focus is visible; source links identify external PDFs. Errors preserve input and provide a next action. Result counts announce completion without repeatedly reading every pin.

## Copy and evidence

The exact English candidate status is **Flagged by satellite · pending inspection**. Its Hindi counterpart is **उपग्रह से चिह्नित · निरीक्षण लंबित**. Human-reviewed fixtures are explicitly fictitious. Unknown status/type is unavailable, not a positive finding. Predictions remain provisional at any score.

Distances from the search centre are labeled centroid distances. Rule distances come exclusively from record assessments; a search radius is never a rule buffer. Missing exposure is not zero, population is not measured health harm, and observation dates are not construction dates.

The evidence examples are distinct 256×256 SVG scenes composed of coarse cells, agricultural parcels, an access road, orchard rows and a kiln-shaped structure. They are clearly marked synthetic, not passed off as satellite photography. Only the later side has its supplied outline. This is an intentional R1 web adaptation: the real PNGs remain unpublished and are not copied from private storage. Actual bitmap handling remains an R2 verification requirement. The divider supports pointer dragging as well as the native slider and comparison buttons.

Source text is rendered as React text, never HTML. Image/source URLs are allowlisted. Complaint exports preserve the edited text, with a mandatory sample notice outside the editable body. Hindi has implementation coverage, but independent human translation review remains a release input.

## Demo completion (10 October 2026)

The user authorized a finished local demo with maps and sample data. This supersedes R1’s diagram-only limitation. Record sidebars now include real street geography around fictional demo coordinates. Additional reviewed examples include synthetic evidence, orchard reference measurements and population context. The missing-data record remains intentionally unassessed; failed imagery is a development scenario. No design-token changes or unrelated inspector/AWS work. Map-provider requests are explained in Privacy.

## Phones (prompt 36b, 11 October 2026)

Up to 600 px wide the portal follows the iOS app's structure. Tablet and desktop layouts are unchanged.

- **Tab bar:** fixed at the bottom with Area, Ask and Draft, each a symbol plus a word, with the selected-record count on Draft. Real links with `aria-current="page"`, 56 px targets, `env(safe-area-inset-bottom)` padding and `viewport-fit=cover`. A solid surface bar with a hairline top border. Translucency is a progressive enhancement on this bar and the top bar only, and text stays legible without it. The top text tabs are hidden on phones.
- **Top bar:** one sticky row with the mark and "KilnWatch" on the left and a native `<details>` menu on the right holding the language buttons and theme select. The sample/live banner is one line ("Sample data · fictional records") and is always visible.
- **Area:** a one-line title ("Check an area"), then place search and "Use my location", then a collapsed "Area settings" `<details>` with the coordinates and radius. "This is a search area, not a legal buffer" stays visible. Then the Map/List control, the map at `max(320px, 55svh)`, and the selected record directly below it.
- **Area search after results (36c):** the form folds to one line ("Pilkhuwa · 1 km", or the coordinates in mono) with an "Edit" button and "Search area, not a legal buffer." under it. Edit, a new search or a validation error keeps the full form open. In the full form, "Use my location" is a 44 × 44 icon button in the search row, and the sample-places, legal-buffer and privacy notes sit under the Confirm button. With fixture results the map starts 352 px from the top at 393 × 852.
- **Units:** a figure and its unit are one mono token joined by a no-break space. On phones that space is narrowed so `520 m` doesn't read like code.
- **Kiln:** an "At a glance" card under the ID and status that restates the top rule line, the people line and the latest observation exactly as the page already shows them. Then evidence, rules (siting flags as full cards, the rest under "Other rule checks · N"), exposure and the map. "Model prediction" is collapsible. A sticky action bar above the tab bar has "Ask about this kiln" (`surface2`) and "Add to draft" (ink).
- **Comparator (all widths):** Before on the left, After on the right, as on iOS. The slider value is the divider position: "Show before" moves it to 100 and "Show after" to 0.
- **Rule bars (all widths):** only a siting flag uses the flagged amber fill. Beyond-threshold bars use the secondary ink on the `surface2` track, and the threshold tick stays.
- **Ask:** the answer sits above and the composer at the bottom of the panel, above the tab bar, with the server disclaimer under it.
- **Type:** phone headings are capped at 1.75rem, with a 20 px screen margin and 20 px card radius. No new colours, gradients or shadows.

## Inspection requests (prompt 43, 11 October 2026)

The record places a neutral Resident requests card before evidence, with an ink primary **Request an inspection** action. On phones the sticky action bar links to this card; Ask remains secondary. Native concern checkboxes and distance-band radio controls have 44 px rows. Send is disabled until at least one concern is selected. The privacy line explains the random browser code and excluded personal details. Confirmation, unverified count and already-requested date use neutral ink and tabular figures. Positive counts also appear in area records. The existing written draft/export remains secondary as **Prepare a written request**. English and Hindi copy use `t()` throughout; fixture requests carry a sample/no-send notice. No status or design-token changes.

## Summary-first polish (prompt 45, 11 October 2026)

This addition supersedes the earlier At a glance and request-before-evidence defaults. Record identity is full, small and monospaced; provisional status and unverified type precede evidence. The leading flag stays visible, with remaining checks and rule sources in named native disclosures. Model context, population source/date and anonymous request breakdowns also expand explicitly. Exposure precedes requests. Desktop retains its evidence/sidebar workspace.

Phone search folds after a successful confirmed result; Edit and errors retain the full form. The request action appears once in the phone action bar; opening the form clears that bar, focuses the first concern, and leaves Send above the tabs. Desktop uses the request card action. Confirmation retains View your request, neutral fresh counts and browser dedupe. Written drafting/export and deterministic explanations remain secondary disclosures.

Small press feedback and local disclosure fades are allowed for this phase. Reduced Motion removes them. Navigation and grouped map controls may use restrained translucency with a solid fallback; content and forms remain solid. Existing fonts, palette, corner/spacing tokens, provider attribution, explicit search and no automatic map flights remain binding.
