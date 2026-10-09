import Foundation

extension JSONDecoder {
    /// snake_case keys and RFC 3339 dates, with or without fractional seconds
    /// (Python's isoformat() drops them when zero, so one payload can mix both).
    public static var kilnWatch: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an RFC 3339 date with offset, got \(string)")
        }
        return decoder
    }
}

extension JSONEncoder {
    public static var kilnWatch: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date))
        }
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

/// Response envelopes. Objects, not bare arrays, so fields like a pagination cursor can be added later.
struct KilnList: Codable { let kilns: [Kiln] }
struct RuleList: Codable { let rules: [Rule] }

/// The JSON fixtures, which are also the examples in docs/api-contract.md. For previews and tests.
public enum Fixtures {
    public static let kilns: [Kiln] = load(KilnList.self, "kilns").kilns
    public static let route: Route = load(Route.self, "route_today")
    public static let rules: [Rule] = load(RuleList.self, "rules").rules

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T {
        do {
            return try JSONDecoder.kilnWatch.decode(T.self, from: data(name))
        } catch {
            fatalError("Fixture \(name).json is broken: \(error)") // tests decode every fixture, so this cannot ship
        }
    }
}
