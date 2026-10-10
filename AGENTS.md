# Agent instructions (KilnWatch iOS)

Start by reading `App/docs/HANDOVER.md`, which has the current state, the open decisions and the next steps. Then read `App/docs/build-plan.md` and `App/docs/DESIGN.md`. `DESIGN.md` is binding for all UI work.

- Work one phase at a time. Do not run parallel agents.
- The Xcode project is `KilnWatch.xcodeproj` at the repo root. Its synced folder points at `App/KilnWatch`. Never add the `.xcodeproj` to itself. Build with:
  `xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Test the core package with `cd App/Packages/KilnWatchCore && swift test`.
- The phase prompts in `App/docs/prompts/` mention "Axiom skills" and "Firecrawl". Those are Claude Code tools. If they aren't available, use Apple's developer documentation and normal web search instead.
- Never use the word "illegal" in the app. Until an inspector records a verdict, a kiln is "Flagged by satellite · pending inspection".
- Commit or push only when the user asks. The working branch is `main`; the app, AWS foundation and model code have been merged there.
