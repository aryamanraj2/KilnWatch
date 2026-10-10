# Agent streaming: how Ask receives the planner's answer

Researched 2026-10-09. Strands checked at `strands-agents` 1.59.0 (PyPI, 2026-10-08).

## Recommendation

Host the planner on **Bedrock AgentCore Runtime** (HTTP protocol, `/invocations`) with **inbound JWT auth** pointed at the KilnWatch Cognito user pool. The app calls it directly with the Cognito **access token** and reads a **Server-Sent Events** response through `URLSession.bytes(for:)`. The container translates raw Strands events into the small, stable schema below. One event is one `data:` line holding one JSON object. Answer text is **released only after the citation validator passes**, so the inspector never sees an uncited claim. Tool steps stream live, and they are where the waiting happens anyway. Do not use WebSocket. Ask is one request and one streamed reply, and AgentCore's own guidance says to use HTTP when you don't need bidirectional streaming.

This departs from concept page 11, which routes the agents through "API Gateway + Lambda". The fallback that keeps API Gateway is a REST API with response streaming in front of a Python Lambda that runs Lambda Web Adapter. The app code stays identical, because it is the same SSE schema on a different URL.

## Why not the others

| Option | Blocking facts |
|---|---|
| Lambda function URL streaming | Natively Node.js only. Python needs a custom runtime or Lambda Web Adapter. Auth is `AWS_IAM` or `NONE`, so there is no Cognito JWT authorizer. Function URLs cannot stream from a VPC-attached function, and the planner's tools need RDS/PostGIS. Billing continues after the client disconnects. |
| API Gateway REST streaming (Nov 2025) | Works: Cognito authorizers, WAF and throttling are all supported, timeout up to 15 min, regional idle timeout 5 min. Costs: still a Python Lambda with Lambda Web Adapter, and the function must write a JSON prelude plus an 8-null-byte delimiter. REST APIs only, not HTTP APIs. A workable fallback. |
| API Gateway WebSocket | No Cognito authorizer, only IAM or a Lambda REQUEST authorizer on `$connect`. Integration timeout is 29 s, so the agent must run asynchronously and post back via `@connections`. 32 KB frames, 10 min idle, 2 h max. Too much plumbing for one request and one reply. |
| **AgentCore Runtime** | Built for Strands (`BedrockAgentCoreApp` turns an async generator into SSE). Validates the Cognito JWT (`discoveryUrl`, `allowedClients`). 15 min request, 60 min stream, 10 MB chunks. Sessions are sticky via a header, so follow-ups keep context. `networkMode: VPC` reaches RDS. |

## What Strands actually emits (Python `stream_async`)

- `{"data": str, "delta": ...}`: a text chunk.
- `{"type": "tool_use_stream", "current_tool_use": {"toolUseId","name","input"}, "delta": ...}`: repeats while the model streams the tool input. The first time a `toolUseId` appears, the tool has started.
- `{"message": {...}}`: the assistant message, then a **user message with `toolResult` blocks** (`toolUseId`, `status`, `content`) once the tool batch finishes. This is the only "tool finished" signal the stream gives you.
- `ToolResultEvent` exists, but its `is_callback_event` is `False`, so **`stream_async` never yields it**. I verified this in `strands/types/_events.py` and `agent.py`. Per-tool completion is also available from the `AfterToolCallEvent` hook.
- `{"result": AgentResult}` is last. `force_stop` and `force_stop_reason` mean an abort. `citation` events are Bedrock document citations, not ours.

## App-facing schema (v1)

`Content-Type: text/event-stream`. Every event is a single `data: <json>\n\n` line, and `: ping` comment lines arrive every 15 s.

```text
step_started   {step, tool, label}                  label is server-written, e.g. "Searching flagged kilns"
step_finished  {step, ok, summary}                  e.g. "214 flagged", "9 stops"; never raw tool output
text           {attempt, delta}
citation       {attempt, kiln_id | rule_id}         only ids the validator confirmed exist in the registry
retry          {attempt, reason}                    a new attempt starts; discard text and citations of older attempts
done           {attempt, session_id}
error          {code, message, retryable}           e.g. citation_check_failed, throttled, unauthorized
```

Server-side mapping (pseudo):

```text
for ev in agent.stream_async(prompt):
  new toolUseId in ev.current_tool_use -> emit step_started(step=toolUseId, tool=name, label=LABELS[name])
  ev.message.role == "user": each toolResult -> emit step_finished(step=toolUseId, ok=status=="success", summary=SUMMARIZE[name](content))
  "data" in ev   -> buffer[attempt] += ev.data          # held, not sent
  "result" in ev -> refs = validator(buffer[attempt])   # deterministic check from concept p.10
     pass -> emit text(attempt, chunk) for each ~40-char chunk of buffer; emit citation per ref; emit done
     fail and attempt < 2 -> emit retry(attempt+1, reason); re-run the agent with the validator's feedback
     fail at max         -> emit error("citation_check_failed", retryable=false)
```

**What the client sees on a regeneration:** the steps from attempt 1, then `retry {attempt:2}`, then possibly more steps, and then the validated text. Because text is held until it passes validation, a reader never watches an answer disappear. The client still honours `retry`: it drops any text and citations with a lower `attempt`. That keeps the schema safe if the backend later releases text sentence by sentence once each sentence's citations check out.

## Client (verified on Swift 6.4, macOS 27, against a recorded stream)

`AsyncBytes.lines` **drops blank lines**, the SSE event separator. I reproduced this locally, and it is also reported in Apple forum thread 725162. The one-line-per-event rule makes that harmless.

```swift
struct AgentEvent: Decodable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case stepStarted = "step_started", stepFinished = "step_finished"
        case text, citation, retry, done, error, unknown
        init(from d: Decoder) throws { self = Kind(rawValue: try d.singleValueContainer().decode(String.self)) ?? .unknown }
    }
    let type: Kind
    var attempt: Int?; var step, tool, label, summary: String?; var ok: Bool?; var delta: String?
    var kilnId, ruleId, reason, code, message, sessionId: String?; var retryable: Bool?
}

func ask(_ prompt: String, session: UUID, token: String) async throws -> AsyncThrowingStream<AgentEvent, Error> {
    let arn = agentRuntimeARN.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    var req = URLRequest(url: URL(string: "https://bedrock-agentcore.us-west-2.amazonaws.com/runtimes/\(arn)/invocations?qualifier=DEFAULT")!)
    req.httpMethod = "POST"; req.timeoutInterval = 120          // idle gap allowed between bytes; the server pings every 15 s
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(session.uuidString, forHTTPHeaderField: "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id") // must be at least 33 chars
    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    req.httpBody = try JSONEncoder().encode(["prompt": prompt])
    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) } // 401 -> refresh, then retry once
    let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
    return AsyncThrowingStream { c in
        let t = Task { do {
            for try await line in bytes.lines where line.hasPrefix("data:") {
                c.yield(try dec.decode(AgentEvent.self, from: Data(line.dropFirst(5).utf8)))
            }; c.finish() } catch { c.finish(throwing: error) } }
        c.onTermination = { _ in t.cancel() }   // leaving Ask cancels the request
    }
}
```

Unknown `type` values decode to `.unknown` and the client ignores them, so new event types never crash the client. Keep one session UUID per Ask thread. A background or network drop ends the stream: show "Connection lost, try again", and resend with the same session ID so the agent keeps its context. Streams cannot be resumed.

## Evidence

- Strands stream event reference: https://strandsagents.com/docs/user-guide/sdk/streaming/events/
- Strands source, `ToolResultEvent.is_callback_event = False`: https://raw.githubusercontent.com/strands-agents/harness-sdk/main/strands-py/src/strands/types/_events.py
- Strands per-tool event order (Before → Stream* → After → Result): https://github.com/strands-agents/harness-sdk/blob/6d60fdb8244795e39aed55592bc98dc0d156ab3e/site/src/content/docs/user-guide/sdk/tools/executors.mdx
- AgentCore streaming with Strands: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/response-streaming.md
- AgentCore HTTP contract (SSE, `/ping`, error headers): https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-http-protocol-contract.html
- AgentCore JWT inbound auth and bearer invoke URL: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-oauth.html
- AgentCore quotas (15 min request, 60 min stream, 8 h session, 15 min idle): https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/bedrock-agentcore-limits.html
- AgentCore WebSocket ("use HTTP when no bidirectional need"): https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-get-started-websocket.html
- AgentCore VPC mode: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-vpc.html
- API Gateway REST streaming (2025-11-19): https://aws.amazon.com/blogs/compute/building-responsive-apis-with-amazon-api-gateway-response-streaming/ and the format at https://docs.aws.amazon.com/apigateway/latest/developerguide/response-transfer-mode-lambda.html
- Lambda streaming runtimes, VPC limit and billing: https://docs.aws.amazon.com/lambda/latest/dg/configuration-response-streaming.html and the regional rollout announcement (2026-04-07) at https://aws.amazon.com/about-aws/whats-new/2026/04/aws-lambda-response-streaming
- WebSocket quotas and auth: https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-execution-service-websocket-limits-table.html and https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-websocket-api-control-access.html
- `lines` drops empty lines: https://developer.apple.com/forums/thread/725162 (2023, re-verified locally on Swift 6.4)

## Open questions for the backend owner

1. Can you accept AgentCore Runtime as a second public endpoint next to API Gateway? If not, the fallback is API Gateway REST streaming with Lambda Web Adapter.
2. Release policy: hold the whole answer until it is validated (recommended), or release it sentence by sentence? The schema supports both.
3. Allowlist the `Authorization` header (`requestHeaderAllowlist`) so the agent can read `custom:district` (see auth.md) and call Verified Permissions for `queue_for_review`.
4. Who writes `LABELS` and `SUMMARIZE` per tool? Summaries must never include free model text.
5. Maximum number of regeneration attempts (2 proposed), and the error copy shown when they are exhausted.
