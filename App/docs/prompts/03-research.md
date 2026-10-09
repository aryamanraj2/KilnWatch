# Prompt 03: Research spikes (no app code)

You are the research agent for the KilnWatch Inspector iOS app. Two other agents are building in parallel: one is building the design system and the Xcode project, and the other is building `Packages/KilnWatchCore` and `docs/api-contract.md`. **Write only to `docs/research/`.** Put any throwaway code you run to verify something in the scratchpad or `/tmp`, never in the repo.

## Read first

Read `docs/concept.txt`, especially pages 9 to 12 (the agents, guardrails and AWS architecture) and page 13 (the inspector app), then `docs/build-plan.md`.

## How to research

- Start with WebSearch. If a page is gated, blocked, paywalled or thin, use Firecrawl: `firecrawl_search`, then `firecrawl_scrape` on the best URL. For SDK and repository questions use `firecrawl_developer_search`, for example on the Strands Agents repos and AWS samples.
- Prefer primary sources: AWS docs, Apple developer docs, the GitHub repos themselves. It is October 2026. Flag anything older than 12 months that may have changed.
- For Apple APIs, also load `axiom:axiom-apple-docs` and `axiom:axiom-networking`, and use them.

## Four questions

Write one file per question. Each file is at most 120 lines and follows the same structure: **recommendation first** (one paragraph), then the evidence with links, then a small example (Swift for the client side, a pseudo-shape for the server side), then open questions for the backend owner.

1. **`agent-streaming.md`**: how does the iOS app receive the planner agent's answer as it is produced? The planner is a Strands Agents SDK agent calling Bedrock (concept page 9), and the app shows each tool call as it happens and then streams the answer text. Compare the hosting and transport options: API Gateway REST response streaming, Lambda function URL response streaming, API Gateway WebSocket, and Bedrock AgentCore Runtime. Check what Strands actually emits when it streams (its event types for tool use start and result, and for text deltas). Recommend one transport and propose a **small app-facing event schema**: step started, step finished with a summary, text delta, citation (kiln_id or rule_id), done, error. Show how the app would parse it with `URLSession.bytes(for:)` or `URLSessionWebSocketTask`. Note how the deterministic citation validator from page 10 fits: if an answer is rejected and regenerated mid-stream, what does the client see?
2. **`auth.md`**: Cognito sign-in without Amplify. Cover the managed login page, the authorization code flow with PKCE through `ASWebAuthenticationSession`, refreshing tokens, storing them in the Keychain, and signing out. Explain how the inspector's role and district reach the app (Cognito groups or a custom attribute in the ID token) so that the UI can hide actions the Verified Permissions policies on page 10 would deny anyway. Name the exact Cognito endpoints and parameters.
3. **`evidence-imagery.md`**: what will the before and after evidence images actually look like? A SentinelKilnDB patch is 128 × 128 px at 10 m, which makes it tiny. Recommend a delivery size and format, and whether the app should upscale with `.interpolation(.none)` or smooth it. Cover how "before" (the 2023–24 dataset season) and "after" (October 2026 scene) patches get paired, whether CloudFront URLs should be public or signed, and how the OBB polygon (lat/lon) maps to pixel coordinates in a patch for the overlay. The backend should ideally send pixel coordinates too: propose the fields.
4. **`routing.md`**: the server orders the stops with the Amazon Location Service route matrix plus OR-Tools (concept page 9). On the device, what is the best way to hand an ordered multi-stop route to navigation? Check whether Apple Maps can take multiple stops from a third-party app in iOS 26 or 27, or whether the app has to hand off one stop at a time. Should the app draw the road geometry itself (`MKDirections`) or receive a polyline from the server? What works offline (MapKit tile caching limits, saved route geometry)?

## Done means

- The four files are in `docs/research/`, each with links you actually opened.
- Report back in at most 25 lines: the four recommendations in one line each, the decisions the user or the backend owner must make, and any concept assumption that turned out to be wrong. Do not commit.
