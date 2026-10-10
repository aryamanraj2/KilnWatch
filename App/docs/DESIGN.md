# KilnWatch Inspector — Design System

Binding for every phase after Phase 0. Code lives in `KilnWatch/Design/` (tokens in `Theme.swift`, colors in `Assets.xcassets`, components in `Design/Components/`). Deviate only with a stated reason in your report.

## 1. Direction: "Survey instrument"

A calm, precise measuring tool. Weight comes from evidence (a measured distance against a legal threshold), never decoration. Three words: **soft, exact, trustworthy**. Theming is **neutral**: true-gray paper and ink, one clay accent, status colors only for status.

- **Materials.** Liquid Glass only on the navigation layer: tab bar, toolbars, map controls, the floating Today header, the bottom accessory, the Ask composer. Content sits on solid surfaces. Never glass on a card. Use `.regular` glass only (never `.clear`).
- **Legibility never depends on translucency.** iOS 27 lets users slide glass from clear to tinted. So: the map uses muted emphasis; a dark top scrim appears only over satellite imagery; header text is semibold; labels on imagery sit on a 55% black scrim.

## 2. Color tokens (`Assets.xcassets`, generated symbols `.canvas`, `.ink` …)

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | #F4F4F4 | #111111 | Screen background |
| `surface` | #FFFFFF | #1C1C1C | Cards, rows |
| `surface2` | #EBEBEB | #262626 | Wells, chip fills, bar tracks, secondary button |
| `ink` | #1A1A1A | #F2F2F2 | Primary text; primary button fill; global tint (`AccentColor`) |
| `inkSecondary` | #5C5C5C | #A3A3A3 | Secondary text, eyebrows |
| `hairline` | ink 8% | ink 10% | 0.5 pt card strokes (light mode only) |
| `clay` | #A84B25 | #E07A4F | The single accent: route line, selected pin, citation chips, brand mark. Never a button fill, never status. |
| `flagged` | #875A00 | #E3A93B | Flagged, pending inspection |
| `confirmed` | #B3261E | #F2867A | Confirmed violation |
| `compliant` | #2F6B45 | #7CC495 | Compliant |
| `notKiln` | #55606E | #A3ADBA | Not a kiln |
| `closed` | #6B6259 | #B3A99E | Closed or not firing |
| `obb` | #FFC94D | #FFC94D | Oriented box on imagery: 2 pt stroke + 1 pt dark outer stroke |

Neutral palette replaces the warm-paper values in the Phase 0 brief (user request). `flagged` light darkened from #9A6700 to #875A00 (same hue): the badge failed 4.5:1 on its own 12% tint.

Rules: primary button = ink fill + canvas label. Status is never color alone: symbol + word + color, always.

### Contrast (WCAG, computed from sRGB; badge pairs measured on the 12% tint blended over the surface it sits on)

| Pair | Light | Dark | Target |
|---|---|---|---|
| ink on canvas / surface / surface2 | 15.8 / 17.4 / 14.6 | 16.9 / 15.2 / 13.5 | 4.5 |
| inkSecondary on canvas / surface / surface2 | 6.1 / 6.7 / 5.6 | 7.5 / 6.8 / 6.0 | 4.5 |
| canvas on ink (primary button, pin number) | 15.8 | 16.9 | 4.5 |
| clay on surface2 (citation chip) | 4.8 | 5.1 | 4.5 |
| clay on surface (brand mark) | 5.7 | 5.7 | 4.5 |
| canvas on clay (selected pin) | 5.2 | 6.4 | 3.0 |
| flagged badge (on surface / canvas) | 5.1 / 4.6 | 6.5 / 7.4 | 4.5 |
| confirmed, compliant, notKiln, closed badges | ≥ 4.6 | ≥ 5.7 | 4.5 |
| status fill vs surface2 bar track | ≥ 5.0 | ≥ 6.1 | 3.0 |

All 50 checks (25 pairs × 2 modes) pass in both modes. Regenerate with the token script used in Phase 0 (values above are the source of truth).

## 3. Typography

System fonts and Dynamic Type text styles only; no fixed sizes.
- Kiln IDs (`KW-0412`), rule IDs (`C-HAB-800`), coordinates, measured distances: `.monospaced()`. In sentences only the figure+unit is mono (`410 m`), the words stay proportional.
- Counts and figures: `.monospacedDigit()`, changing with `.contentTransition(.numericText(value:))`.
- Eyebrows: `.footnote` semibold, uppercase, tracking 0.6, `inkSecondary` (`View.eyebrow()`). The only uppercase text.
- Number and unit joined with a no-break space (`410\u{00A0}m`) so units never orphan.
- Hindi (Phase 6): no fixed-height text containers anywhere; layouts reflow.
- Text drawn on imagery/maps (comparator labels, OBB tag, map annotations, stop pins, route accessory) caps at `.xxLarge`/`.xxxLarge`, like system map labels and the tab bar. Everything else scales to AX5.

## 4. Layout

4 pt grid only: `Space.xxs…xxxl` = 4, 8, 12, 16, 20, 24, 32, 48. Screen margin 20, card padding 16, card radius 20 continuous, inner radius 12 (`.inner` = `ConcentricRectangle`, min 12), chips are capsules.
- `View.card(floating:)`: surface fill, hairline in light mode, no shadow. `floating: true` (cards over the map only) adds radius 12, y 4, 8% shadow.
- Primary actions live in the bottom third (`safeAreaBar(edge: .bottom)` or the map's bottom inset).
- Tap targets ≥ 44×44. Exception: inline citation chips inside answer prose (VoiceOver gets them as actions).
- At accessibility sizes rows switch `HStack` → `VStack` (`AnyLayout` or `ViewThatFits`). IDs, rule IDs and distances never truncate.

## 5. Motion (`Motion` in Theme.swift)

| Token | Curve | Use |
|---|---|---|
| `select` | `.snappy(0.28)` | toggles, selection, pins |
| `layout` | `.smooth(0.42)` | camera moves, expanding, content swaps, bar fill |
| `confirm` | `.spring(0.5, bounce 0.18)` | verdict saved only; the only bounce |
| `stagger` | 0.04 s × index, max 6 | pins entering |

Reduce Motion: every token returns `.easeInOut(0.2)` and call sites drop scale/offset (pins don't scale, bars fade in at full length, the camera cuts, the comparator skips its hint nudge).

## 6. Haptics (`.sensoryFeedback`)

`.selection` option changes (verdict rows, imagery toggle) · `.impact(.light)` stop focused · `.success` verdict saved online · `.warning` verdict queued offline.

## 7. Copy rules (binding)

- Never "illegal". Before a verdict the status line is exactly "Flagged by satellite · pending inspection".
- Measurements as fact against the rule: "410 m from homes · rule requires 800 m".
- Type confidence < 0.7: "likely CFCBK" plus "confirm on site".
- Field-manual voice: plain, no exclamation marks, no greetings.

## 8. Anti-slop list

No gradients (except the scrim over imagery) · no purple/indigo/neon, glows, glass cards, heavy shadows · no emoji, sparkle icons, "AI" badges · no icon-in-colored-circle grids, illustrations, Lottie · no fake trends, hero stats without actions, "Welcome back" · one accent per screen, no centering everything, uppercase only in eyebrows · no lorem or placeholder copy · no custom versions of system navigation, sheets, search, menus, pickers.

## 9. Components (`Design/Components/`, each with `#Preview`)

1. **RuleDistanceBar** — rule chip + plain rule name; track = threshold (or measurement if larger), fill = measured in status color, 2 pt ink tick at threshold; "410 m · requires 800 m". Fill grows from 0 and the figure counts up the first time it is ≥ 60% visible (`onScrollVisibilityChange`). Technology rules (C-TECH-10K) show "FCBK found · zigzag required within 10 km of Delhi" (+ "Likely … · confirm on site"). VO: "Distance to homes, 410 metres. Rule C-HAB-800 requires 800 metres." + action "Show rule".
2. **StatusBadge** — symbol + word + 12% tinted capsule; `detailed:` gives the long line. Symbols: flag.fill, exclamationmark.octagon.fill, checkmark.seal.fill, square.slash, pause.circle.fill.
3. **KilnIDLabel** — mono ID + "FCBK · 0.82" / "likely CFCBK · 0.64"; stacks when it doesn't fit.
4. **BeforeAfterComparator** — square, 2024 | Oct 2026 labels on scrim, draggable divider (44 pt strip, handle low so it never covers the box), OBB rotated −28° with "FCBK 0.82" tag, mono caption "Sentinel-2 · 10 m · 14 Oct 2026" + "Illustrative imagery". Phase 0 imagery = one `MKMapSnapshotter` imagery snapshot (1.3 km) on both sides. One 12 pt hint nudge on first load. VO: adjustable (±10%).
5. **ExposureBlock** — "6,240 people within 800 m" large, "710 under 5 · 890 over 60" below; counts up on first view.
6. **ToolCallTrace** — `DisclosureGroup`; rows land one by one (spinner → `checkmark.circle` drawn on via `.transition(.symbolEffect(.drawOn))`, count ticks up); collapses to "4 steps" when the answer finishes.
7. **CitationChip** — clay mono text on surface2 capsule. Opens through `openURL` (`kilnwatch://kiln/KW-0412`, `kilnwatch://rule/C-HAB-800`), handled once in `AppModel.handle(_:)`.
8. **HoldToConfirmButton** — verdict only. 1.2 s hold fills a 3 pt ink ring; early release reverses; completion plays `confirm`, draws a checkmark, fires `.success`/`.warning`. VO/Switch Control: default action submits without the hold.
9. **StopPin** — ink disc, canvas mono number, 2 pt canvas ring; selected = clay, 1.2×; staggered entry; 44 pt hit area.

## 10. Screens and states

Navigation: `TabView` with `Tab` API — Today (map), Kilns (list.bullet), Ask (text.bubble). `.tabBarMinimizeBehavior(.onScrollDown)`. While a route is active, `tabViewBottomAccessory(isEnabled:)` shows "Stop 1 of 9 · KW-0412 · 14 min" (compact "KW-0412 · 14 min" inline or at large text); tap opens the stop. Pushes into a kiln use `matchedTransitionSource` + `.navigationTransition(.zoom)`.

| Screen | Content | States |
|---|---|---|
| Sign in | mark + "KilnWatch", one line, "Sign in with department account" (bottom) | — |
| Today | full-bleed muted map; glass header "Today · Hapur / 9 stops · 5 h 40 m · leave 9:00"; glass list + imagery buttons; clay 4 pt polyline; StopPins; snapping carousel (`.viewAligned`, `scrollPosition`) flies the camera (`layout`); pin tap snaps carousel; card tap pushes Kiln; "Start route"/"End route"; route list sheet (medium/large); DEBUG "Sample data" pill | loading (redacted), empty ("No route planned for today" → "Plan a route" opens Ask prefilled), offline ("Offline · showing saved route") |
| Kiln | mono ID large, type line, detailed badge; comparator; "Flagged rules" bars; "Within 800 m" exposure; buffer map (dashed 800 m ring, home NE / school SW with distances); "Check on site" (chimney, fuel, nearest home); "Ask about this kiln"; bottom bar Directions (Apple Maps) + Record verdict | loading (redacted); rule sheet from any rule chip |
| Record verdict | sheet, large detent, Cancel; "KW-0412 · stop 1 of 9"; four rows with `matchedGeometryEffect` ink ring; geotagged photo tiles + Add photo; note; "This changes KW-0412's status for everyone."; hold button | success online "Verdict recorded", offline "Verdict saved · will sync when online"; swipe-dismiss blocked while a choice is unsaved |
| Kilns | searchable list (search always visible), district menu + status filter menu, rows: ID, type, top rule, badge, people | loading (redacted), empty search "No kilns match 'KW-09'" |
| Ask | "Ask KilnWatch"; user turns right on surface2; agent answers plain, after a trace, with inline chips, streaming word by word; glass composer; "Answers cite registry records. Agents never record verdicts." | empty (3 real requests), offline (composer disabled) |

Launch arguments (for screenshots and later phases): `-signedIn YES`, `-tab kilns|ask`, `-open KW-0412`, `-routeActive YES`, `-demo loading|empty|offline`, `-imagery YES`, `-routeList YES`, `-rule C-HAB-800`, `-query KW-09`, `-askPlay YES`; DEBUG only `-scroll rules|map`, `-verdict YES`, `-verdictChoice confirmed`, `-autoplay carousel|hold`.

## 11. Data

`Mock/MockData.swift` mirrors the p.15 kiln record (`Codable`, snake_case `CodingKeys`). Two additions, flagged for Phase 1: `district` (the Cedar policy reads `resource.district`) and `Violation.measuredTo` (where a distance was measured to, needed for the buffer map). Site photos: Timothy A. Gonsalves, Wikimedia Commons, CC BY-SA 4.0 (Moradabad brick kiln chimney), cropped; mock only.

## 12. References

- iOS 27 Liquid Glass slider (clear ↔ tinted, replaces the 26.1 two-option toggle; midpoint = default): [9to5Mac](https://9to5mac.com/2026/06/15/ios-27-adds-new-liquid-glass-slider-on-iphone-heres-what-it-lets-you-do/), [MacRumors](https://macrumors.com/how-to/ios-27-tone-down-liquid-glass-transparency), [iGeeksBlog](https://www.igeeksblog.com/customize-liquid-glass-in-ios-27-macos-27/). Implication: never rely on glass opacity for legibility over the map.
- HIG [Maps](https://developer.apple.com/design/human-interface-guidelines/maps): muted emphasis for information-rich overlays; clear selection styling; keep the Apple logo/legal visible; thin stroke or light shadow for custom controls over maps.
- HIG [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets): Cancel leading, never a lone Done; medium detent for progressive disclosure (route list), large for compose-like tasks (verdict); confirm before discarding on swipe.
- HIG [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars): navigation not actions; bottom accessory for cross-tab status (Music MiniPlayer), minimizes inline on scroll. Bottom accessory notes: [Create with Swift](https://www.createwithswift.com/enhancing-the-tab-bar-with-a-bottom-accessory/), [Apple forums 806373](https://developer.apple.com/forums/thread/806373).
- Floating sheets over maps (Apple Maps detent behavior): [Expo write-up](https://expo.dev/blog/how-to-create-apple-maps-style-liquid-glass-sheets), [Nil Coalescing](https://nilcoalescing.com/blog/PresentingLiquidGlassSheetsInSwiftUI).
- Flighty (principles, not pixels): one line per item, essentials first, offline-first. [Behind the Design](https://cur.at/VcCahLU?m=web), [Blake Crosley analysis](https://blakecrosley.com/fr/guides/design/flighty), [flighty.com/about](https://flighty.com/about).
- Field use: dark-on-light ≥ 7:1 where possible, avoid thin grays and gradients in glare, larger primary targets for gloves, text + icon offline indicators, queue actions offline. [Glance: apps for construction workers](https://thisisglance.com/learning-centre/how-should-i-design-apps-for-construction-workers), [NN/g touch targets](https://www.nngroup.com/articles/touch-target-size/), [Google offline design](https://design.google/library/offline-design), [web.dev offline UX](https://web.dev/articles/offline-ux-design-guidelines).
