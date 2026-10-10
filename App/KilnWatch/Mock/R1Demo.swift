#if DEBUG
import Foundation

/// Sanitized recorded R1 responses and explicitly synthetic edge cases. PublicDemo intercepts all requests.
enum R1Demo {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return Data() }
        return data
    }
    static func records(_ scenario: String) -> [[String: Any]] {
        guard let list = try? JSONSerialization.jsonObject(with: data("R1Registry.recorded")) as? [String: Any],
              var records = list["kilns"] as? [[String: Any]], !records.isEmpty else { return [] }
        if scenario == "missing" {
            records[0]["exposure"] = NSNull()
            records[0]["rule_checks"] = []
            records[0]["violations"] = []
            records[0]["rules_assessment"] = "not_evaluated"
        } else if scenario == "zero" {
            records[0]["exposure"] = ["people": 0, "children_under_five": 0, "adults_over_sixty": 0]
        } else if scenario == "states" {
            records[0]["violations"] = []
            records[0]["rule_checks"] = [
                check("C-HAB-800", "Distance to habitation", "within_threshold", 0, 800, "secondary_sources"),
                check("C-KILN-1K", "Distance to another kiln", "beyond_threshold", nil, 1000, "secondary_sources"),
                check("C-ORCH-800", "Distance to orchard", "inconclusive", 1200, 800, "secondary_sources"),
                check("C-TECH-10K", "Technology requirement", "not_evaluated", nil, nil, "unverified_compilation"),
                check("HR-SCH-1K", "School rule outside this state", "not_applicable", nil, nil, nil),
                check("C-FUTURE-2K", "Future check", "future_status", nil, 2000, "future_verification")
            ]
            // Zero is a real supplied measurement, and the flag is kept in its own array.
            records[0]["violations"] = [["rule_id": "C-HAB-800", "measured_distance_m": 0, "threshold_m": 800,
                                          "source": "Synthetic local source", "evidence_url": NSNull()]]
        }
        return records
    }
    private static func check(_ id: String, _ label: String, _ status: String, _ distance: Int?, _ threshold: Int?, _ verification: String?) -> [String: Any] {
        ["rule_id": id, "check": label, "status": status,
         "measured_distance_m": distance as Any? ?? NSNull(), "threshold_m": threshold as Any? ?? NSNull(),
         "verification": verification as Any? ?? NSNull(), "source": "Synthetic local source"]
    }
}
#endif
