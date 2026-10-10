import Foundation

/// Mapped siting signals, separately from an inspector's verdict and threshold verification.
public struct RuleCheck: Codable, Hashable, Sendable {
    public let ruleId: String
    public let check: String
    public let status: RuleCheckStatus
    public let thresholdM: Double?
    public let measuredDistanceM: Double?
    public let verification: ThresholdVerification?
    public let source: String

    public var measurementLine: String {
        if let measured = Self.metres(measuredDistanceM) {
            return "\(measured) · " + (Self.metres(thresholdM).map { "applied threshold \($0)" } ?? "threshold unavailable")
        }
        if status == .beyondThreshold {
            return "No mapped feature found within " + (Self.metres(thresholdM).map { "the \($0) threshold" } ?? "the threshold") + ". Nearest distance unavailable."
        }
        return "Distance unavailable" + (Self.metres(thresholdM).map { " · applied threshold \($0)" } ?? " · threshold unavailable")
    }

    /// Distance bars require a valid nonnegative measurement and positive threshold.
    public static func canDrawBar(measured: Double?, threshold: Double?) -> Bool {
        guard let measured, let threshold else { return false }
        return measured.isFinite && measured >= 0 && threshold.isFinite && threshold > 0
    }
    public static func metres(_ value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value.formatted(.number.precision(.fractionLength(0))) + "\u{00A0}m"
    }
}

public enum RuleCheckStatus: Codable, Hashable, Sendable, RawRepresentable {
    case withinThreshold, beyondThreshold, inconclusive, notEvaluated, notApplicable
    case unknown(String)
    public init(rawValue: String) {
        self = switch rawValue {
        case "within_threshold": .withinThreshold
        case "beyond_threshold": .beyondThreshold
        case "inconclusive": .inconclusive
        case "not_evaluated": .notEvaluated
        case "not_applicable": .notApplicable
        default: .unknown(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .withinThreshold: "within_threshold"
        case .beyondThreshold: "beyond_threshold"
        case .inconclusive: "inconclusive"
        case .notEvaluated: "not_evaluated"
        case .notApplicable: "not_applicable"
        case .unknown(let raw): raw
        }
    }
    public var label: String {
        switch self {
        case .withinThreshold: "Siting flag · needs inspection"
        case .beyondThreshold: "Beyond threshold"
        case .inconclusive: "Inconclusive · map data incomplete"
        case .notEvaluated: "Not evaluated · no usable data"
        case .notApplicable: "Not applicable"
        case .unknown: "Check state unavailable · unsupported result"
        }
    }
}

public enum ThresholdVerification: Codable, Hashable, Sendable, RawRepresentable {
    case secondarySources, unverifiedCompilation
    case unknown(String)
    public init(rawValue: String) {
        self = switch rawValue {
        case "secondary_sources": .secondarySources
        case "unverified_compilation": .unverifiedCompilation
        default: .unknown(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .secondarySources: "secondary_sources"
        case .unverifiedCompilation: "unverified_compilation"
        case .unknown(let raw): raw
        }
    }
    public var label: String {
        switch self {
        case .secondarySources: "Secondary sources · gazette text not checked"
        case .unverifiedCompilation: "Unverified threshold"
        case .unknown: "Threshold verification unavailable"
        }
    }
    public var explanation: String {
        switch self {
        case .secondarySources: "Threshold from secondary sources; not checked against the gazette text."
        case .unverifiedCompilation: "Unverified threshold from an academic compilation; not checked against the gazette text."
        case .unknown: "Threshold verification unavailable."
        }
    }
}

extension Kiln {
    public var assessmentNote: String? {
        switch rulesAssessment {
        case "partially_evaluated": "Some rules could not be checked from map data. Check on site."
        case "not_evaluated": "Rules not evaluated. No usable assessment is available."
        case "evaluated": (ruleChecks ?? []).isEmpty ? "Rule checks unavailable. Assessment details could not be verified." : nil
        default: "Rule assessment unavailable. Check on site."
        }
    }
}

extension Exposure {
    public static let attribution = "Modelled estimate of residents within 800 m of the kiln edge. Population: Meta and CIESIN High Resolution Settlement Layer (HRSL) v1.5.2, CC BY 4.0. Age groups are modelled shares of the same estimate."
}
