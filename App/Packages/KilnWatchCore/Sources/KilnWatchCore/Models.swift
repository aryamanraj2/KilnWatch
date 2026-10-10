import Foundation

// Wire JSON is snake_case and the coders in JSON.swift convert keys. That is why properties
// are spelled `kilnId` and `evidenceUrl`, not `kilnID`: `kiln_id` converts back to `kilnId` only.

// MARK: - Kiln record (concept p.15)

public struct Kiln: Codable, Hashable, Sendable, Identifiable {
    /// Stable identifier, for example "KW-0412".
    public let kilnId: String
    public let footprint: Footprint
    public let type: KilnType
    /// Predicted class score, 0...1; see provenance for calibration semantics.
    public let typeConfidence: Double
    /// May share the class score; not an independently calibrated existence probability.
    public let detectionConfidence: Double
    /// Scene time of the first and latest detections.
    public let firstSeen: Date
    public let lastSeen: Date
    public let violations: [Violation]
    public let exposure: Exposure?
    /// Changed only by an inspector's verdict or an approved review.
    public let status: KilnStatus
    public let evidence: Evidence
    /// Optional in older records; never an authorization claim.
    public let district: String?
    public let rulesAssessment: String?
    public let typeVerification: String?
    public let provenance: DetectionProvenance?

    /// Legacy records retain their former presentation; explicit model state overrides score.
    public var typeMayBePresentedAsCertain: Bool {
        if let typeVerification { return typeVerification == "verified" }
        if provenance != nil { return false }
        return typeConfidence >= 0.7
    }

    public var id: String { kilnId }
}

public struct Coordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// The oriented bounding box from the detector: four corners in order, ring not closed.
public struct Footprint: Codable, Hashable, Sendable {
    public let polygon: [Coordinate]
    public let centroid: Coordinate
}

public struct Violation: Codable, Hashable, Sendable {
    public let ruleId: String
    /// Metres from the footprint to the nearest feature. Nil for technology rules such as C-TECH-10K.
    public let measuredDistanceM: Double?
    /// The threshold the rules engine applied, after any state override. Nil for technology rules.
    public let thresholdM: Double?
    /// Legal source, for example "Central 2022 rules".
    public let source: String
    /// Nil until an evidence image for this measurement is published; the measurement still stands.
    public let evidenceUrl: URL?
    /// Supplied feature coordinate; absent when unknown.
    public let measuredTo: Coordinate?
}

/// People living within 800 m of the kiln footprint (HRSL population layers).
public struct Exposure: Codable, Hashable, Sendable {
    public let people: Int
    public let childrenUnderFive: Int
    public let adultsOverSixty: Int
}

/// Before and after image patches on CloudFront.
public struct Evidence: Codable, Hashable, Sendable {
    public let before: URL?
    public let after: URL?
    public let beforeMetadata: EvidenceMetadata?
    public let afterMetadata: EvidenceMetadata?
}

public struct DetectionProvenance: Codable, Hashable, Sendable {
    public let sceneId: String
    public let acquiredAt: Date
    public let modelSha256: String
    public let modelVersion: String
    public let inputSha256: String
    public let importedAt: Date
    public let confidenceSemantics: String
}

public struct EvidenceMetadata: Codable, Hashable, Sendable {
    public let sceneId: String
    public let acquiredAt: Date
    public let patchPx: Int
    public let gsdM: Double
    public let crs: String
    public let geotransform: [Double]
    public let footprintPx: [[Double]]?
    public let centroidPx: [Double]
    public let sha256: String
    public let objectKey: String
    public let attribution: String
    public let nodataFraction: Double
    public let rendering: String
}

// MARK: - Open enums: an unknown server value decodes to `.unknown(raw)` and re-encodes unchanged.

public enum KilnStatus: Hashable, Sendable, Codable, RawRepresentable {
    case flagged, confirmed, compliant, notAKiln, closed
    case unknown(String)

    public init(rawValue: String) {
        self = switch rawValue {
        case "flagged": .flagged
        case "confirmed": .confirmed
        case "compliant": .compliant
        case "not_a_kiln": .notAKiln
        case "closed": .closed
        default: .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .flagged: "flagged"
        case .confirmed: "confirmed"
        case .compliant: "compliant"
        case .notAKiln: "not_a_kiln"
        case .closed: "closed"
        case .unknown(let raw): raw
        }
    }
}

public enum KilnType: Hashable, Sendable, Codable, RawRepresentable {
    case fcbk, cfcbk, zigzag
    case unknown(String)

    public init(rawValue: String) {
        self = switch rawValue {
        case "FCBK": .fcbk
        case "CFCBK": .cfcbk
        case "Zigzag": .zigzag
        default: .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .fcbk: "FCBK"
        case .cfcbk: "CFCBK"
        case .zigzag: "Zigzag"
        case .unknown(let raw): raw
        }
    }
}

// MARK: - Rules (concept p.4)

public struct Rule: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    /// What is measured, for example "Distance to habitation".
    public let check: String
    /// Minimum distance in metres. Nil for technology rules.
    public let thresholdM: Double?
    /// Technology rules only, for example "Zigzag, vertical shaft or gas".
    public let requirement: String?
    /// State-specific thresholds that replace `thresholdM` in that state.
    public let overrides: [Override]
    public let source: String

    public init(id: String, check: String, thresholdM: Double? = nil, requirement: String? = nil,
                overrides: [Override] = [], source: String) {
        self.id = id; self.check = check; self.thresholdM = thresholdM
        self.requirement = requirement; self.overrides = overrides; self.source = source
    }

    public struct Override: Codable, Hashable, Sendable {
        /// Two-letter state code, for example "UP".
        public let state: String
        public let thresholdM: Double
    }
}

// MARK: - Route (planner output, concept p.9-10)

public struct Route: Codable, Hashable, Sendable {
    public let district: String
    public let generatedAt: Date
    public let stops: [Stop]
    /// Full records for every stop, so the day works offline.
    public let kilns: [Kiln]
    public let routeId: String?
    public let depart: Date?
    /// Planning limit, not a prediction.
    public let budgetMin: Int?
    public let legs: [RouteLeg]?

    public init(district: String, generatedAt: Date, stops: [Stop], kilns: [Kiln],
                routeId: String? = nil, depart: Date? = nil, budgetMin: Int? = nil, legs: [RouteLeg]? = nil) {
        self.district = district; self.generatedAt = generatedAt; self.stops = stops; self.kilns = kilns
        self.routeId = routeId; self.depart = depart; self.budgetMin = budgetMin; self.legs = legs
    }
}

public struct Stop: Codable, Hashable, Sendable, Identifiable {
    /// 1-based visiting order.
    public let order: Int
    public let kilnId: String
    public let eta: Date
    public let sheet: InspectionSheet
    public let serviceMin: Int?
    public let access: RoadAccess?

    public init(order: Int, kilnId: String, eta: Date, sheet: InspectionSheet,
                serviceMin: Int? = nil, access: RoadAccess? = nil) {
        self.order = order; self.kilnId = kilnId; self.eta = eta; self.sheet = sheet
        self.serviceMin = serviceMin; self.access = access
    }

    public var id: String { kilnId }
}

public struct InspectionSheet: Codable, Hashable, Sendable {
    /// Rule IDs; details are in the kiln's `violations`.
    public let rulesFlagged: [String]
    public let peopleExposed: Int
    /// What to verify on the ground, for example "Chimney type".
    public let onSiteChecks: [String]
}

// MARK: - Verdict (the only thing that changes a kiln's status)

public struct Verdict: Codable, Hashable, Sendable, Identifiable {
    /// Client-generated; also the Idempotency-Key.
    public let id: UUID
    public let kilnId: String
    public let outcome: Outcome
    public let photos: [Photo]
    public let note: String
    public let recordedAt: Date

    public enum Outcome: String, Codable, Hashable, Sendable, CaseIterable {
        case confirmed, compliant
        case notAKiln = "not_a_kiln"
        case closed
    }

    public init(id: UUID = UUID(), kilnId: String, outcome: Outcome, photos: [Photo], note: String, recordedAt: Date = .now) {
        self.id = id
        self.kilnId = kilnId
        self.outcome = outcome
        self.photos = photos
        self.note = note
        self.recordedAt = recordedAt
    }
}

/// A geotagged photo. The JPEG lives in the outbox at `VerdictOutbox.fileURL(for:of:)`, named by `id`.
public struct Photo: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double
    /// Metres, from CLLocation.horizontalAccuracy.
    public let horizontalAccuracyM: Double
    public let takenAt: Date

    public init(id: UUID = UUID(), latitude: Double, longitude: Double, horizontalAccuracyM: Double, takenAt: Date) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyM = horizontalAccuracyM
        self.takenAt = takenAt
    }
}

/// Response to POST /verdicts: where to PUT each photo the server has not yet received.
public struct VerdictReceipt: Codable, Hashable, Sendable {
    public let id: UUID
    public let photoUploads: [PhotoUpload]

    public struct PhotoUpload: Codable, Hashable, Sendable {
        public let photoId: UUID
        /// Presigned S3 PUT URL. Send without the bearer token.
        public let uploadUrl: URL
    }
}


public struct RoadAccess: Codable, Hashable, Sendable {
    public let lat: Double
    public let lon: Double
    public let note: String?
    public var coordinate: Coordinate { Coordinate(latitude: lat, longitude: lon) }
}

public struct RouteLeg: Codable, Hashable, Sendable {
    public let toKilnId: String
    public let distanceM: Double?
    public let durationS: Double?
    public let geometry: RouteGeometry?
}

/// Geometry alone uses GeoJSON [longitude, latitude], rather than coordinate objects.
/// A malformed optional geometry is ignored, without losing the stops or records.
public struct RouteGeometry: Codable, Hashable, Sendable {
    public let type: String
    public let coordinates: [[Double]]

    public init(type: String, coordinates: [[Double]]) {
        self.type = type; self.coordinates = coordinates
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
        coordinates = (try? container.decode([[Double]].self, forKey: .coordinates)) ?? []
    }

    public var validatedCoordinates: [Coordinate] {
        guard type == "LineString", coordinates.count >= 2 else { return [] }
        var result: [Coordinate] = []
        for pair in coordinates {
            guard pair.count == 2 else { return [] }
            let point = Coordinate(latitude: pair[1], longitude: pair[0])
            guard point.isValid else { return [] }
            result.append(point)
        }
        return result
    }
}

extension Coordinate {
    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}
