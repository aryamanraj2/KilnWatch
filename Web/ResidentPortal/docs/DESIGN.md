# Resident portal design

The [app design system](../../../App/docs/DESIGN.md) is binding. This web translation follows its neutral, soft, precise visual language and the [resident brief](../../../App/docs/prompts/09-resident-portal-master-brief.md).

## Tokens and typography

`src/styles/global.css` defines the exact light/dark canvas, surface, secondary surface, ink, secondary ink, clay, and status colors from the app. Primary buttons use ink; clay identifies a selection or citation. Status is always symbol plus words. Distances, coordinates and IDs use monospace; counts use tabular figures. Spacing follows 4/8/12/16/20/24/32/48 pixels. Content uses solid surfaces, quiet borders, and 20-pixel card corners.

The system font stack includes Kohinoor Devanagari, Nirmala UI, and Noto Sans Devanagari fallbacks. No remote font request is made. Headings and Hindi text reflow without fixed text-container heights; Hindi uses additional line height. Comfortable controls are at least 44 pixels. Map pins use HTML buttons so the touch target does not shrink with SVG coordinates. Inline citations are compact and keyboard accessible.

Theme choices are System, Light, and Dark. Motion is limited to color transitions and a loading indicator; `prefers-reduced-motion` removes these. There are no automatic map flights, gradients, glass cards, AI badges, or decorative dashboards.

## Screens

- **Area:** practical heading, search form, and sample diagram/list workspace. The first action is selecting an area. Desktop keeps map and results adjacent; phones offer Map/List buttons. The list is independently usable. Place results explicitly describe sample lookup.
- **Record:** observation and provisional status first, then evidence and assessed/unassessed rules. The sidebar contains model limitations, population context, deterministic explanations, and drafting actions.
- **Rule:** jurisdiction, reference source/date, threshold availability, and limitations. No conclusion inferred from an ID.
- **Draft:** selected records and optional resident details beside an editable request. Export actions are after the editor. The print document contains only the actual draft, sample notice, source references, and not-submitted statement.
- **About/Privacy:** actual implementation, source attribution and data handling; no generic promises.

Every route has a main landmark, skip link, logical headings, and navigation focus management. Buttons and range controls use native HTML interactions. Focus is visible; source links identify external PDFs. Errors preserve input and provide a next action. Result counts announce completion without repeatedly reading every pin.

## Copy and evidence

The exact English candidate status is **Flagged by satellite · pending inspection**. Its Hindi counterpart is **उपग्रह से चिह्नित · निरीक्षण लंबित**. Human-reviewed fixtures are explicitly fictitious. Unknown status/type is unavailable, not a positive finding. Predictions remain provisional at any score.

Distances from the search centre are labeled centroid distances. Rule distances come exclusively from record assessments; a search radius is never a rule buffer. Missing exposure is not zero, population is not measured health harm, and observation dates are not construction dates.

The two evidence examples are distinct 256×256 SVG scenes composed of coarse cells. They are clearly marked synthetic, not passed off as satellite photography. Only the later side has its supplied outline. This is an intentional R1 web adaptation: the real PNGs remain unpublished and are not copied from private storage. Actual bitmap handling remains an R2 verification requirement.

Source text is rendered as React text, never HTML. Image/source URLs are allowlisted. Complaint exports preserve the edited text, with a mandatory sample notice outside the editable body. Hindi has implementation coverage, but independent human translation review remains a release input.
