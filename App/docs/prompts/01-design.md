# Prompt 01: Design system and clickable mock

You are the design engineer for **KilnWatch Inspector**, a native SwiftUI app for pollution-board inspectors in the NCR region of India. Working from satellite evidence, it tells an inspector which brick kilns to visit, why, and in what order, and it records the verdict on site.

This phase sets the look and feel for everything built after it. The work has to look like it came from a careful product team at a company like Apple. It must not look like an AI template.

## 0. Read first (do not skip)

1. `docs/concept.txt`. Read all of it. Pages 4, 5, 9, 10, 13 and 15 matter most: the rules table, the two users, the agents and guardrails, the inspector app screens, and the kiln record.
2. `docs/build-plan.md` for the ground rules.
3. Load these skills and follow them: `axiom:axiom-design` (open `skills/hig.md`, `skills/liquid-glass.md`, `skills/sf-symbols.md` and `skills/typography-ref.md`), `axiom:axiom-swiftui` (open `animation-ref.md`, `26-ref.md`, `nav-ref.md` and `toolbars.md`), `swiftui-expert-skill`, and `axiom:axiom-accessibility`. Use `axiom:axiom-tools` (xcui) and `axiom:axiom-build` for the simulator and the build.

## 1. Research (time-box: about 20 minutes, then build)

Use WebSearch first. If a page is gated, blocked or thin, switch to Firecrawl (`firecrawl_search`, then `firecrawl_scrape` on the best URL). Answer these four questions and put your findings in `docs/DESIGN.md` under a "References" section, with links:

- What changed in the iOS 27 Liquid Glass refinements? Users now get a glass opacity slider that runs from clear to tinted. Confirm this, and work out what it means for legibility over the map.
- How do Apple Maps, Weather and Flighty handle a full-bleed map or dense data together with floating controls? Look at their sheets, carousels and numeral styling.
- Which HIG guidance applies to maps, to sheets with detents, and to the tab bar bottom accessory (`tabViewBottomAccessory`)?
- What do field apps need for outdoor use? Look at sunlight contrast, one-handed reach, gloved taps and offline status.

Do not copy anyone's visuals. Take principles from these apps, not pixels.

## 2. Design direction: "Survey instrument"

The app is a calm, precise measuring tool. Its weight comes from evidence (a measured distance against a legal threshold), not from decoration. The three words to design toward are **soft, exact, trustworthy**.

**Materials.** Use Liquid Glass only on the navigation layer: the tab bar, toolbars, map controls, the floating route header and the composer. Everything in the content layer sits on solid surfaces. Never put glass on a card. Legibility must not depend on glass translucency, because a user can now set glass to fully clear.

**Color tokens.** Define these in `Assets.xcassets` with light and dark variants. Before you lock the values, verify every text/background pair in both modes: at least 4.5:1 for body text and at least 3:1 for large text and UI glyphs. Adjust lightness within the same hue if a pair fails, and record the final contrast table in DESIGN.md.

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | #F5F3EF | #121110 | Screen background (warm paper) |
| `surface` | #FFFFFF | #1C1B19 | Cards, rows |
| `surface2` | #ECE9E3 | #262422 | Inset wells, chip backgrounds, bar tracks |
| `ink` | #1B1A18 | #F2EFEA | Primary text; primary button fill |
| `inkSecondary` | #5F5A53 | #A8A29A | Secondary text |
| `hairline` | ink at 8% | ink at 10% | 0.5 pt separators and card strokes (strokes in light mode only) |
| `clay` | #A84B25 | #E07A4F | The single brand accent: the route line, the selected stop, citation chips, the brand mark. Never use it as a button fill. Never use it for status. |
| `flagged` | #9A6700 | #E3A93B | Status: flagged, pending inspection |
| `confirmed` | #B3261E | #F2867A | Status: confirmed violation |
| `compliant` | #2F6B45 | #7CC495 | Status: compliant |
| `notKiln` | #55606E | #A3ADBA | Status: not a kiln |
| `closed` | #6B6259 | #B3A99E | Status: closed or not firing |
| `obb` | #FFC94D | #FFC94D | Oriented-box overlay on satellite imagery (2 pt stroke plus a 1 pt dark outer stroke) |

The primary button is an `ink` fill with the canvas color as its label. Status is never shown by color alone: every status always pairs its color with an SF Symbol and a word.

**Typography.** Use system fonts and Dynamic Type text styles only. Do not hard-code font sizes.

- Kiln IDs (`KW-0412`), rule IDs (`C-HAB-800`), coordinates and measured distances use `.monospaced()`. This gives the app its instrument feel.
- Counts and figures use `.monospacedDigit()` and change with `.contentTransition(.numericText(value:))`.
- Section eyebrows use `.footnote`, `.semibold`, uppercase, with a small amount of tracking, in `inkSecondary`. Eyebrows are the only uppercase text.
- Hindi is coming in Phase 6. Leave room for about 30% text expansion and taller Devanagari line heights: no fixed-height text containers.

**Layout.** Use a 4 pt grid (4, 8, 12, 16, 20, 24, 32, 48). Screen margins are 20, card padding is 16, card corner radius is 20 (continuous), inner elements have a radius of 12, and chips are capsules. Use `ConcentricRectangle` for anything nested inside a sheet or card. Light-mode cards get a hairline stroke and no shadow. The only shadow in the app belongs to cards that float over the map (radius 12, y 4, opacity 0.08). Keep primary actions in the bottom third of the screen for one-handed use. The minimum tap target is 44 × 44 pt.

**Motion tokens.** Put these in `Theme.swift`, and make every one fall back to a 0.2 s opacity-only ease when `accessibilityReduceMotion` is on.

- `select`: `.snappy(duration: 0.28)` for toggles, selection and pins
- `layout`: `.smooth(duration: 0.42)` for camera moves, expanding sections and content swaps
- `confirm`: `.spring(duration: 0.5, bounce: 0.18)` for the verdict saved state only. This is the only bouncy animation in the app.
- `stagger`: 0.04 s per item, capped at 6 items

**Haptics.** Use `.sensoryFeedback`. `.selection` when an option changes, `.impact(weight: .light)` when a stop is focused, `.success` when a verdict is saved, `.warning` when an action is queued offline.

**Copy rules.** These are binding and come from the concept's guardrails.

- Never use the word "illegal". Before a verdict, the status line is always "Flagged by satellite · pending inspection".
- State measurements as fact against the rule, for example "410 m from homes · rule requires 800 m".
- When type confidence is below 0.7, write the kiln type as "likely FCBK" and add "confirm on site".
- Write plainly, like a field manual. No exclamation marks and no greetings.

## 3. Anti-slop list (a reviewer will reject any of these)

- Gradients on backgrounds, buttons or text. The only exception is a scrim over imagery.
- Purple, indigo or neon colors; glows; glassmorphism cards; heavy drop shadows.
- Emoji. A sparkle or "magic" icon for the agent. "AI" badges.
- Grids of icons inside colored circles. Decorative illustrations. Lottie.
- Fake trend arrows. Hero stat cards with no action behind them. "Welcome back" headers.
- More than one accent color on a screen. Centering everything. Uppercase text outside eyebrows.
- Lorem ipsum or placeholder strings. Every string must be real domain copy based on the concept.
- Custom versions of things the system already provides (navigation, sheets, search, menus, pickers).

## 4. Signature components

Build each component once, in `Design/Components/`, and give each one a `#Preview` that covers its states.

1. **`RuleDistanceBar`**. The hero of the app. The track length is the threshold, the fill is the measured distance (in the status color), and a tick marks the threshold. It shows the rule ID chip (monospaced), the plain-language rule name, and "410 m · requires 800 m". The fill grows from 0 the first time it appears (`layout`) while the number counts up. For a non-distance rule (C-TECH-10K) it shows "FCBK found · zigzag required within 10 km of Delhi" instead of a bar. VoiceOver reads: "Distance to homes, 410 metres. Rule C-HAB-800 requires 800 metres."
2. **`StatusBadge`**. Symbol, word and tinted capsule (status color text on a 12% fill), for all five statuses.
3. **`KilnIDLabel`**. A monospaced ID, with optional type and confidence ("FCBK · 0.82").
4. **`BeforeAfterComparator`**. Square imagery (2024 against Oct 2026) with a draggable divider and a handle. The labels sit in the top corners on a small dark scrim. The OBB overlay is a rotated rectangle with a "FCBK 0.82" tag. The caption line is monospaced: "Sentinel-2 · 10 m · 14 Oct 2026". On first appearance the handle nudges once by about 12 pt as a hint (skip this under Reduce Motion). For mock imagery, use an `MKMapSnapshotter` `.imagery` snapshot spanning about 1.3 km at the stop's coordinate, and label it "Illustrative imagery".
5. **`ExposureBlock`**. "6,240 people within 800 m" as the large figure, with "710 under 5 · 890 over 60" on a secondary line.
6. **`ToolCallTrace`**. A collapsible list of agent steps. Each row shows the tool name in monospace and its result ("search_kilns · 214 flagged"). Rows appear one after another; each check draws on (`.symbolEffect(.drawOn)`) and its count ticks up. Once the answer is complete, the trace collapses to "4 steps".
7. **`CitationChip`**. Clay text on `surface2`, monospaced. Tapping it opens that kiln or rule.
8. **`HoldToConfirmButton`**. Used only for submitting a verdict. A 1.2 s press fills a progress ring around the button. Letting go early reverses the fill. On completion it plays the `confirm` animation, draws a checkmark on, and fires `.success`. It needs an accessibility action that submits without the hold.
9. **`StopPin`**. An ink disc with a white monospaced-digit number. When selected it scales to 1.2× with `select` and turns `clay`. Pins enter staggered.

## 5. Screens

Build every screen with mock data, and wire up navigation so the whole app can be clicked through. Each screen needs its default state, a loading state (`.redacted(reason: .placeholder)`), and the empty, offline and error states listed for it.

**Navigation.** A `TabView` built with the `Tab` API: **Today**, **Kilns** and **Ask**. The Kilns list minimizes the tab bar on scroll. While a route is active, a `tabViewBottomAccessory` shows "Stop 1 of 9 · KW-0412 · 14 min", like the Music now-playing bar, and tapping it opens that kiln. Pushes from a stop or a row into a kiln use the zoom navigation transition (`matchedTransitionSource` with `.navigationTransition(.zoom)`).

1. **Sign in.** A wordmark (KilnWatch set in SF Pro semibold, beside a small mark: a rotated rounded rectangle outline, which echoes the OBB). One line explains what the app does. The button reads "Sign in with department account". Nothing else on the screen.
2. **Today.** A full-bleed `Map`, muted (`.standard` with points of interest excluded), with a map control that toggles `.imagery`. A floating glass header reads "Today · Hapur", with "9 stops · 5 h 40 m · leave 9:00" below it. The route is a `MapPolyline` in clay at 4 pt with round caps, and the stops are `StopPin`s. Along the bottom runs a horizontal, snapping carousel of stop cards (`.scrollTargetBehavior(.viewAligned)`). Each card shows the number, the kiln ID, the type, its single most severe rule as a single line, and the people exposed. Swiping the carousel flies the map camera to that stop (`layout`). Tapping a pin snaps the carousel to that card. Tapping a card pushes to the kiln. A toolbar button opens the full ordered list as a sheet. The primary action is "Start route". States: empty ("No route planned for today", with an action that opens Ask and pre-fills "Plan tomorrow in Hapur. Six hours. Schools first.") and offline (a quiet banner reading "Offline · showing saved route").
3. **Kiln.** The header is the ID set large in monospace, then "FCBK · Fixed chimney bull's trench · Hapur", then `StatusBadge`. Below come `BeforeAfterComparator`; a "Flagged rules" eyebrow with `RuleDistanceBar`s (C-HAB-800 410/800, UP-SCH-1K 620/1,000, C-TECH-10K); `ExposureBlock`; a small map showing the kiln, a dashed 800 m buffer ring (`MapCircle`) and the nearest school and home with distance labels; "Check on site" (chimney type, fuel on site, distance to the nearest home); and an "Ask about this kiln" row. The bottom bar has "Directions" (secondary, hands off to Apple Maps) and "Record verdict" (primary).
4. **Ask.** A conversation with the planner agent. User messages are right-aligned on `surface2`. Agent answers are left-aligned plain text with no bubble, preceded by a `ToolCallTrace` and containing `CitationChip`s inline. Script the canonical exchange from concept p.13 so that it plays with the trace animating and the answer streaming in word by word. The empty state shows three real suggested requests. The composer is a glass capsule. A footnote under it reads "Answers cite registry records. Agents never record verdicts." The screen is titled "Ask KilnWatch" and uses no sparkle icon.
5. **Record verdict.** Presented as a sheet at the large detent from Kiln. The header reads "KW-0412 · stop 1 of 9". There are four large selectable rows: Confirmed violation, Compliant, Not a kiln, and Closed / not firing. Each has a symbol and a one-line meaning, and the selection highlight moves between them with `matchedGeometryEffect` (`select`). Below them: photo tiles with a monospaced geotag line ("28.7124° N, 77.6541° E · ±6 m · 10:42") and an add tile, then a note field. A line of consequence copy reads "This changes KW-0412's status for everyone." Submission uses `HoldToConfirmButton`. The success state reads "Verdict saved · will sync when online" when offline, and "Verdict recorded" when online.
6. **Kilns.** A searchable registry list with a status filter menu and a district picker. Rows show the ID, the type, the status badge, the top rule and the people exposed. States: empty search ("No kilns match 'KW-09'") and loading.

## 6. Project setup (keep it lean)

- Project `KilnWatch`, app target `KilnWatch`, bundle ID `com.kilnwatch.inspector`, iOS 26.1, Swift 6 language mode, iPhone only.
- XcodeGen and Tuist are not installed, and you must not add tools. Hand-write a minimal `KilnWatch.xcodeproj` that uses a `PBXFileSystemSynchronizedRootGroup` (objectVersion 77), so new files under `KilnWatch/` need no pbxproj edits. Verify it with `xcodebuild -list` and a build. If this blocks you for more than 15 minutes, stop and report: the user can create the project in Xcode in 30 seconds.
- Layout:
  ```
  KilnWatch/
    KilnWatchApp.swift
    Design/Theme.swift            spacing, radii, motion, font helpers (colors live in assets)
    Design/Components/*.swift      the 9 components above
    Features/{Today,Kiln,Ask,Verdict,Kilns,SignIn}/*.swift
    Mock/MockData.swift            Kiln, Violation, Exposure, Stop, KilnStatus, KilnType
    Assets.xcassets
  ```
- The model structs mirror the kiln record on concept p.15 field by field (`Codable`, `Hashable`, `Sendable`), because Phase 1 will reuse them. Mock data: KW-0412, KW-0388 and KW-0451 use the figures from p.13. Spread nine stops across Hapur district, around 28.73° N, 77.78° E, with Pilkhuwa at about 28.71° N, 77.65° E. In DEBUG builds, show a small "Sample data" pill on Today.
- Out of scope for this phase: networking, persistence, auth logic and camera capture. Use mock photos from the asset catalog, and keep state in plain `@State` and `@Observable` structures. Add no third-party packages.

## 7. Deliverables

1. `docs/DESIGN.md`. At most about 400 lines. It covers the direction, the tokens with the contrast table, typography, layout, motion, haptics, copy rules, the anti-slop list, each component's spec, each screen's spec with its states, and the references. Every later agent will build from it.
2. The app, building with **zero warnings** and running on the **iPhone 17** simulator.
3. Screenshots in `docs/screens/` of every screen in light mode, dark mode, and at Dynamic Type AX3. Also, short screen recordings (`xcrun simctl io booted recordVideo`) of: the carousel driving the map camera, the rule bars filling, the Ask trace and stream, and the hold-to-confirm flow through to success.
4. Do not commit. The orchestrator reviews the work first.

## 8. Self-check before you report

- [ ] Every text/background pair meets its contrast target in both modes (table in DESIGN.md).
- [ ] At AX3, no kiln ID, rule ID or distance is truncated. Rows reflow to a vertical layout.
- [ ] With Reduce Motion on, every animation becomes a short fade.
- [ ] VoiceOver labels exist on `RuleDistanceBar`, `StopPin`, `BeforeAfterComparator` (adjustable action), `HoldToConfirmButton` (submit action) and `StatusBadge`.
- [ ] No item on the anti-slop list appears anywhere.
- [ ] The word "illegal" does not appear anywhere: `grep -ri illegal KilnWatch/` returns nothing.

## 9. Report back (at most 40 lines)

Report what you built, list the screenshot paths, and include the contrast table summary, any deviations from this prompt with the reason for each, the research links you used, and up to 5 open design questions for the user.
