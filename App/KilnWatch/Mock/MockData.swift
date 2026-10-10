import CoreLocation
import KilnWatchCore

/// Sample values come exclusively from the shared package's JSON fixtures.
enum Mock {
    static let registry = Fixtures.kilns
    static let route = Fixtures.route.kilns
    static let stops = Fixtures.route.usableStops
    static let districts = Array(Set(Fixtures.kilns.compactMap(\.district))).sorted()
}

extension Coordinate {
    var clLocation: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

extension Kiln {
    var coordinate: CLLocationCoordinate2D { footprint.centroid.clLocation }
    var typeIsCertain: Bool { typeMayBePresentedAsCertain }
    var topViolation: Violation? {
        violations.min { lhs, rhs in
            func severity(_ v: Violation) -> Double {
                guard RuleCheck.canDrawBar(measured: v.measuredDistanceM, threshold: v.thresholdM),
                      let m = v.measuredDistanceM, let t = v.thresholdM else { return 2 }
                return m / t
            }
            return severity(lhs) < severity(rhs)
        }
    }
}

extension KilnType {
    var longName: String {
        switch self {
        case .fcbk: "Fixed chimney bull's trench"
        case .cfcbk: "Circular fixed chimney bull's trench"
        case .zigzag: "Zigzag"
        case .unknown(let raw): "Unrecognized type: \(raw)"
        }
    }
}

extension KilnStatus {
    static var knownCases: [KilnStatus] { [.flagged, .confirmed, .compliant, .notAKiln, .closed] }
}

extension Rule {
    static func named(_ id: String) -> Rule {
        Fixtures.rules.first { $0.id == id }
            ?? Rule(id: id, check: "Rule details unavailable", source: "Source unavailable")
    }
    var name: String {
        switch id {
        case "C-HAB-800": "Distance to homes"
        case "C-TECH-10K": "Kiln technology near Delhi"
        default: check
        }
    }
    var feature: String {
        switch id {
        case "C-HAB-800": "homes"
        case "C-KILN-1K": "another kiln"
        case "C-ORCH-800": "an orchard"
        case "UP-SCH-1K": "a school"
        case "UP-NH-300": "a national highway"
        case "UP-RAIL-200": "a railway line"
        case "UP-MUN-5K": "municipal limits"
        default: "the measured feature"
        }
    }
}
