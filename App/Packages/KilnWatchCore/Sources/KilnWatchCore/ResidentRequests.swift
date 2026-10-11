import Foundation

/// Public aggregate only. No browser identifier or individual request is decoded or retained.
public struct ResidentRequests: Codable, Hashable, Sendable {
    public let count: Int
    public let within1Km: Int
    public let concerns: Concerns
    /// Calendar date in IST, kept as a date-only value without applying the device's time zone.
    public let lastRequestOn: String?

    public struct Concerns: Codable, Hashable, Sendable {
        public let smokeOrAsh: Int
        public let nearHomes: Int
        public let nearSchoolOrHospital: Int
        public let other: Int
    }

    // convertFromSnakeCase maps within_1km to within1Km, while convertToSnakeCase
    // would produce within1_km. Preserve the contract spelling when caching records.
    private enum DecodeKeys: String, CodingKey { case count, within1Km, concerns, lastRequestOn }
    private enum EncodeKeys: String, CodingKey {
        case count, within1Km = "within_1km", concerns, lastRequestOn
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DecodeKeys.self)
        count = try container.decode(Int.self, forKey: .count)
        within1Km = try container.decode(Int.self, forKey: .within1Km)
        concerns = try container.decode(Concerns.self, forKey: .concerns)
        lastRequestOn = try container.decodeIfPresent(String.self, forKey: .lastRequestOn)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EncodeKeys.self)
        try container.encode(count, forKey: .count)
        try container.encode(within1Km, forKey: .within1Km)
        try container.encode(concerns, forKey: .concerns)
        try container.encodeIfPresent(lastRequestOn, forKey: .lastRequestOn)
    }
}
