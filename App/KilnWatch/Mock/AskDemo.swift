#if DEBUG
import Foundation
import KilnWatchCore

/// Synthetic local-only states. PublicDemo intercepts every request, including citation detail GETs.
enum AskDemo {
    static let id = "KW-00000000000000000000000000000001"
    static let disclaimer = "Answers cite registry records. Agents never record verdicts. Kilns are flagged by satellite and pending inspection."
    static func response(scenario: String, call: Int) -> (Int, Data) {
        if scenario == "r1Recorded" { return (200, R1Demo.data("R1Ask.recorded")) }
        if scenario == "r1Mixed" { return (200, R1Demo.data("R1AskMixed.synthetic")) }
        switch scenario {
        case "dailyLimit": return error(status: 429, code: "daily_cap_reached", retryable: false)
        case "invalid": return error(status: 400, code: "invalid_request", retryable: false)
        case "unavailable": return error(status: 503, code: "model_unavailable", retryable: false)
        case "retryable": return error(status: 503, code: "upstream_unavailable", retryable: true)
        case "recovery" where call == 1: return error(status: 503, code: "assistant_unavailable", retryable: true)
        case "throttle": return (429, Data(#"{"message":"Too Many Requests"}"#.utf8))
        case "malformed": return (200, Data(#"{"answer":"incomplete"}"#.utf8))
        case "transport": return (-1, Data())
        default: break
        }
        let fallback = scenario == "fallback"
        var steps = [AskStep(tool: "kiln_detail", label: "Reading kiln details", summary: "Record found", ok: true)]
        if scenario == "emptySteps" { steps = [] }
        if scenario == "repeated" { steps.append(.init(tool: "kiln_detail", label: "Reading kiln details", summary: "Invalid tool input", ok: false)) }
        let answer = AskAnswer(
            answer: fallback ? "I couldn't produce a reliable answer to that. Here are the flagged kilns I looked up:"
                : "The registry record \(id) is flagged by satellite and pending inspection.\n\nThis local test record has no published satellite images. Rules and population exposure have not been evaluated.",
            citations: [id, id], steps: steps, fallback: fallback, disclaimer: disclaimer)
        return (200, (try? JSONEncoder().encode(answer)) ?? Data())
    }
    private static func error(status: Int, code: String, retryable: Bool) -> (Int, Data) {
        let body: [String: Any] = ["error": ["code": code, "message": "Local test response", "retryable": retryable]]
        return (status, (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
    }
}
#endif
