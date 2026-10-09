# KilnWatch iOS — Build Plan

Source of truth for the idea: `docs/concept.txt` (text of KilnWatch.pdf).
iOS scope = the **Inspector app** (concept §05). The resident portal and the review console are web projects and are not part of this repo.

## Ground rules for every agent

- Stack: SwiftUI, MapKit, Swift 6 language mode, Xcode 27, deployment target iOS 26.1. Gate any iOS 27-only API with `#available`.
- Load Axiom skills before you write code: `axiom:axiom-design`, `axiom:axiom-swiftui`, `swiftui-expert-skill`, plus whatever the phase needs.
- Research: start with WebSearch. If a page is blocked, gated or thin, use Firecrawl (`firecrawl_search`, `firecrawl_scrape`). Cite what you used in your report.
- `docs/DESIGN.md` (written in Phase 0) is binding. If you deviate from it, say so in your report.
- Guardrail copy from the concept is binding too. Never call a kiln "illegal". A kiln is "flagged by satellite, pending inspection" until an inspector records a verdict.
- Keep code minimal: no protocols that have only one implementation, no managers, and no scaffolding for later phases.
- A phase is done when it builds with zero warnings, runs on the iPhone 17 simulator, and comes with screenshots.

## Phases

| # | Phase | Builder delivers | Gate (auditor agents, read-only, run in parallel) |
|---|-------|------------------|-------------------------------------|
| 0 | **Design system and clickable mock** | `docs/DESIGN.md`, Xcode project, theme tokens, components, every screen built on mock data, screenshots | orchestrator review of the screenshots · `accessibility-auditor` · `liquid-glass-auditor` · `swiftui-layout-auditor` |
| 1 | Data contract and offline store | `Packages/KilnWatchCore`: Codable kiln record matching concept p.15, JSON fixtures, URLSession API client, file-based route cache and verdict outbox, plus `docs/api-contract.md` | `codable-auditor` · `concurrency-auditor` · `storage-auditor` |
| 2 | Today: map and route | Live route on MapKit, location, Apple Maps handoff, stop carousel wired to data | `swiftui-performance-analyzer` · `energy-auditor` |
| 3 | Kiln card and evidence | CloudFront imagery, before/after comparator, rule bars and exposure from real records | `swiftui-performance-analyzer` · `memory-auditor` |
| 4 | Ask (planner agent) | Streaming agent endpoint, tool-call trace, tappable citation chips | `networking-auditor` · `concurrency-auditor` |
| 5 | Record verdict and auth | Geotagged photo capture, offline outbox sync, Cognito hosted UI via `ASWebAuthenticationSession` (no SDK) | `camera-auditor` · `security-privacy-scanner` |
| 6 | Hindi, accessibility and polish | `hi` localization, VoiceOver pass, Dynamic Type at AX5, app icon (Icon Composer), TestFlight prep | `health-check` · `ux-flow-auditor` · `screenshot-validator` |

## Waves (what runs in parallel)

- **Wave 1:** Phase 0 (`prompts/01-design.md`), Phase 1 (`prompts/02-core.md`) and the research spikes (`prompts/03-research.md`). These own disjoint paths: `KilnWatch/` plus the xcodeproj, `Packages/`, and `docs/research/`.
- **Wave 2 (after Phase 0 is approved):** Phases 2, 3, 4 and 5, each in its own git worktree, each owning one `Features/` folder. `Design/` and the root `TabView` are frozen, so changes to them go through the orchestrator. The first step is to swap the Phase 0 mock models for KilnWatchCore.
- **Wave 3:** Phase 6, then a full health check.
- Give each agent that uses a simulator its own device: iPhone 17, iPhone 17 Pro Max or iPhone Air.

## Loop for each phase

1. The orchestrator writes `docs/prompts/NN-*.md` and dispatches one builder agent.
2. The builder reports back: what it built, screenshots, and open questions.
3. The auditors run in parallel. The orchestrator merges their findings and sends one fix round back to the builder.
4. The orchestrator verifies on the simulator (`simulator-tester`) and reports to the user before the next phase starts.

## Open items (needed before Phase 1, not before Phase 0)

- Who owns the AWS backend, and what the API Gateway endpoint shapes are for the registry, the route and the agent stream.
- Cognito user pool and app client IDs.
