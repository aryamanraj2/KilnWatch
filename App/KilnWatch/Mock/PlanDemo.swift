#if DEBUG
import Foundation

/// The sanitized recorded P1 plan and local error bodies, labelled Sample data. PublicDemo intercepts every request.
enum PlanDemo {
    private static var recorded: [String: Any] {
        (try? JSONSerialization.jsonObject(with: R1Demo.data("P1Plan.recorded")) as? [String: Any]) ?? [:]
    }
    /// The plan's own embedded records double as the test registry, so stop details resolve.
    static var kilns: [[String: Any]] { recorded["kilns"] as? [[String: Any]] ?? [] }

    static func response(scenario: String) -> (Int, Data) {
        switch scenario {
        case "recorded", "slow": return (200, R1Demo.data("P1Plan.recorded"))
        case "noLegs":
            var plan = recorded; plan["legs"] = nil
            return (200, (try? JSONSerialization.data(withJSONObject: plan)) ?? Data())
        case "cap": return error(429, "daily_cap_reached", retryable: false)
        case "throttle": return (429, Data(#"{"message":"Too Many Requests"}"#.utf8))
        case "unavailableFinal": return error(503, "routing_unavailable", retryable: false)
        case "noKilns": return error(404, "no_kilns", retryable: false)
        case "invalid": return error(400, "invalid_request", retryable: false)
        case "malformed": return (200, Data(#"{"stops":"no"}"#.utf8))
        case "offline": return (-1, Data())
        default: return error(503, "routing_unavailable", retryable: true)
        }
    }
    private static func error(_ status: Int, _ code: String, retryable: Bool) -> (Int, Data) {
        let body: [String: Any] = ["error": ["code": code, "message": "Local test response", "retryable": retryable]]
        return (status, (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
    }
}
#endif
