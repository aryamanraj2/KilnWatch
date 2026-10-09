import CoreLocation
import Foundation

// MARK: - Kiln record (concept p.15). Phase 1 decodes the registry API into these types.

struct Coordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    var clLocation: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// Oriented polygon in latitude and longitude, plus centroid.
struct Footprint: Codable, Hashable, Sendable {
    let polygon: [Coordinate]
    let centroid: Coordinate
}

enum KilnType: String, Codable, Hashable, Sendable {
    case fcbk = "FCBK", cfcbk = "CFCBK", zigzag = "Zigzag"

    var longName: String {
        switch self {
        case .fcbk: "Fixed chimney bull's trench"
        case .cfcbk: "Circular fixed chimney bull's trench"
        case .zigzag: "Zigzag"
        }
    }
}

enum KilnStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case flagged, confirmed, compliant, notAKiln = "not_a_kiln", closed
}

struct Violation: Codable, Hashable, Sendable {
    let ruleID: String
    /// Metres. Nil for technology rules such as C-TECH-10K.
    let measured: Double?
    /// Metres. Nil for technology rules.
    let threshold: Double?
    let legalSource: String
    let evidenceURL: URL
    /// Where the distance was measured to (nearest home, school …). Not in the p.15 record; see DESIGN.md.
    let measuredTo: Coordinate?

    enum CodingKeys: String, CodingKey {
        case ruleID = "rule_id", measured, threshold, legalSource = "legal_source"
        case evidenceURL = "evidence", measuredTo = "measured_to"
    }
}

struct Exposure: Codable, Hashable, Sendable {
    let peopleWithin800m: Int
    let childrenUnder5: Int
    let adultsOver60: Int

    enum CodingKeys: String, CodingKey {
        case peopleWithin800m = "people_within_800m", childrenUnder5 = "children_under_5"
        case adultsOver60 = "adults_over_60"
    }
}

struct Evidence: Codable, Hashable, Sendable {
    let before: URL
    let after: URL
}

struct Kiln: Codable, Hashable, Sendable, Identifiable {
    let kilnID: String
    let footprint: Footprint
    let type: KilnType
    let typeConfidence: Double
    let detectionConfidence: Double
    let firstSeen: Date
    let lastSeen: Date
    let violations: [Violation]
    let exposure: Exposure
    var status: KilnStatus
    let evidence: Evidence
    /// Not in the p.15 table; the Cedar policy on p.10 reads `resource.district`.
    let district: String

    var id: String { kilnID }
    var coordinate: CLLocationCoordinate2D { footprint.centroid.clLocation }
    /// Below 0.7 the type is a guess and must be confirmed on site.
    var typeIsCertain: Bool { typeConfidence >= 0.7 }
    /// The single most severe rule: technology rules first, then the smallest measured/threshold ratio.
    var topViolation: Violation? {
        violations.min { severity($0) < severity($1) }
    }

    private func severity(_ v: Violation) -> Double {
        guard let m = v.measured, let t = v.threshold else { return 2 }
        return m / t
    }

    enum CodingKeys: String, CodingKey {
        case kilnID = "kiln_id", footprint, type, typeConfidence = "type_confidence"
        case detectionConfidence = "detection_confidence", firstSeen = "first_seen", lastSeen = "last_seen"
        case violations, exposure, status, evidence, district
    }
}

/// A stop on the planner's route.
struct Stop: Hashable, Sendable, Identifiable {
    let number: Int
    let kilnID: String
    /// Drive time from the previous stop.
    let driveMinutes: Int
    var id: String { kilnID }
}

/// Rule catalog (concept p.4): plain-language name and legal source per rule ID.
struct Rule: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    /// What the distance is measured to, for fact lines: "410 m from homes".
    let feature: String
    let check: String
    let source: String

    static let all: [String: Rule] = Dictionary(uniqueKeysWithValues: [
        Rule(id: "C-HAB-800", name: "Distance to homes", feature: "homes", check: "800 m from habitation (UP: 1,000 m)",
             source: "Environment (Protection) Amendment Rules, 2022; UP siting rules"),
        Rule(id: "C-KILN-1K", name: "Distance to another kiln", feature: "another kiln", check: "1 km from another kiln (UP: 800 m)",
             source: "Environment (Protection) Amendment Rules, 2022; UP siting rules"),
        Rule(id: "C-ORCH-800", name: "Distance to an orchard", feature: "an orchard", check: "800 m from an orchard",
             source: "Environment (Protection) Amendment Rules, 2022"),
        Rule(id: "UP-SCH-1K", name: "Distance to a school", feature: "a school", check: "1 km from a school",
             source: "UP and Haryana siting rules"),
        Rule(id: "UP-NH-300", name: "Distance to a national highway", feature: "a national highway", check: "300 m from a national highway",
             source: "UP siting rules"),
        Rule(id: "UP-RAIL-200", name: "Distance to a railway line", feature: "a railway line", check: "200 m from a railway line",
             source: "UP siting rules"),
        Rule(id: "C-TECH-10K", name: "Kiln technology near Delhi", feature: "Delhi",
             check: "Zigzag, vertical shaft or gas within 10 km of a non-attainment city",
             source: "Environment (Protection) Amendment Rules, 2022"),
    ].map { ($0.id, $0) })

    static func named(_ id: String) -> Rule {
        all[id] ?? Rule(id: id, name: id, feature: "", check: "", source: "")
    }
}

// MARK: - Mock registry

enum Mock {
    static let hapur = Coordinate(latitude: 28.7306, longitude: 77.7759)

    private static func date(_ s: String) -> Date {
        (try? Date(s, strategy: .iso8601.year().month().day())) ?? .now
    }

    private static func kiln(
        _ id: String, _ lat: Double, _ lon: Double, _ type: KilnType, _ typeConf: Double,
        people: Int, under5: Int, over60: Int, district: String = "Hapur",
        status: KilnStatus = .flagged, _ violations: [(String, Double?, Double?)]
    ) -> Kiln {
        let c = Coordinate(latitude: lat, longitude: lon)
        // ~150 m × 60 m oriented box around the centroid.
        let dLat = 0.00027, dLon = 0.00075
        let polygon = [(-dLon, -dLat), (dLon, -dLat), (dLon, dLat), (-dLon, dLat)].map {
            Coordinate(latitude: lat + $0.1 + $0.0 * 0.3, longitude: lon + $0.0 - $0.1 * 0.3)
        }
        let evidence = URL(string: "https://evidence.kilnwatch.in/\(id)")!
        return Kiln(
            kilnID: id,
            footprint: Footprint(polygon: polygon, centroid: c),
            type: type, typeConfidence: typeConf, detectionConfidence: 0.94,
            firstSeen: date("2023-11-02"), lastSeen: date("2026-10-14"),
            violations: violations.map { rule, measured, threshold in
                Violation(
                    ruleID: rule, measured: measured, threshold: threshold,
                    legalSource: Rule.named(rule).source,
                    evidenceURL: evidence.appending(path: rule),
                    measuredTo: measured.map { m in
                        // Homes north-east of the kiln, schools south-west, m metres away.
                        let deg = m / 111_000 * 0.707 * (rule == "UP-SCH-1K" ? -1 : 1)
                        return Coordinate(latitude: lat + deg, longitude: lon + deg)
                    }
                )
            },
            exposure: Exposure(peopleWithin800m: people, childrenUnder5: under5, adultsOver60: over60),
            status: status,
            evidence: Evidence(before: evidence.appending(path: "2024.png"), after: evidence.appending(path: "2026-10.png")),
            district: district
        )
    }

    /// Nine stops across Hapur district, ranked by people exposed (concept p.13).
    static let route: [Kiln] = [
        kiln("KW-0412", 28.7124, 77.6541, .fcbk, 0.82, people: 6_240, under5: 710, over60: 890,
             [("C-HAB-800", 410, 800), ("UP-SCH-1K", 620, 1_000), ("C-TECH-10K", nil, nil)]),
        kiln("KW-0388", 28.7231, 77.6802, .fcbk, 0.88, people: 4_910, under5: 560, over60: 702,
             [("C-HAB-800", 520, 800), ("UP-SCH-1K", 840, 1_000)]),
        kiln("KW-0451", 28.7398, 77.7105, .fcbk, 0.79, people: 3_120, under5: 344, over60: 451,
             [("C-HAB-800", 655, 800), ("C-KILN-1K", 610, 800)]),
        kiln("KW-0433", 28.7480, 77.7190, .cfcbk, 0.64, people: 2_870, under5: 318, over60: 402,
             [("UP-SCH-1K", 760, 1_000), ("C-TECH-10K", nil, nil)]),
        kiln("KW-0467", 28.7562, 77.7351, .fcbk, 0.91, people: 2_440, under5: 262, over60: 371,
             [("UP-SCH-1K", 905, 1_000), ("UP-NH-300", 240, 300)]),
        kiln("KW-0502", 28.7689, 77.7642, .zigzag, 0.71, people: 1_980, under5: 205, over60: 288,
             [("C-HAB-800", 730, 800)]),
        kiln("KW-0519", 28.7452, 77.8013, .fcbk, 0.86, people: 1_610, under5: 171, over60: 240,
             [("C-ORCH-800", 540, 800), ("C-KILN-1K", 690, 800)]),
        kiln("KW-0476", 28.7218, 77.8237, .zigzag, 0.69, people: 1_240, under5: 133, over60: 190,
             [("UP-RAIL-200", 150, 200)]),
        kiln("KW-0491", 28.6987, 77.7874, .fcbk, 0.74, people: 980, under5: 104, over60: 151,
             [("C-HAB-800", 780, 800)]),
    ]

    static let stops: [Stop] = zip(route.indices, [14, 18, 22, 25, 19, 31, 24, 20, 17]).map {
        Stop(number: $0 + 1, kilnID: route[$0].kilnID, driveMinutes: $1)
    }

    /// Registry beyond today's route: other districts and recorded verdicts.
    static let registry: [Kiln] = route + [
        kiln("KW-0207", 28.6402, 77.4703, .fcbk, 0.93, people: 7_820, under5: 902, over60: 1_104,
             district: "Ghaziabad", status: .confirmed, [("C-HAB-800", 290, 800), ("C-TECH-10K", nil, nil)]),
        kiln("KW-0231", 28.6619, 77.5012, .zigzag, 0.90, people: 3_340, under5: 371, over60: 466,
             district: "Ghaziabad", status: .compliant, [("C-HAB-800", 760, 800)]),
        kiln("KW-0156", 28.9512, 77.2201, .fcbk, 0.58, people: 1_120, under5: 120, over60: 168,
             district: "Baghpat", status: .notAKiln, [("C-HAB-800", 610, 800)]),
        kiln("KW-0174", 28.9327, 77.2575, .cfcbk, 0.68, people: 2_050, under5: 226, over60: 301,
             district: "Baghpat", [("UP-SCH-1K", 870, 1_000)]),
        kiln("KW-0601", 28.9844, 77.7064, .fcbk, 0.77, people: 4_480, under5: 498, over60: 640,
             district: "Meerut", status: .closed, [("C-HAB-800", 470, 800)]),
        kiln("KW-0618", 29.0102, 77.6619, .zigzag, 0.71, people: 2_610, under5: 280, over60: 377,
             district: "Meerut", [("C-KILN-1K", 720, 800)]),
    ]

    static let districts = ["Hapur", "Ghaziabad", "Baghpat", "Meerut"]
}
