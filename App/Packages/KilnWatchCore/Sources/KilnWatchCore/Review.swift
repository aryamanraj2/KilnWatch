import Foundation
import Observation

public enum ReviewGroup: Hashable, Sendable, Codable, RawRepresentable {
    case newCandidate, noLongerDetected, possibleZigzagConversion, lowConfidence, unknown(String)
    public static let ordered: [Self] = [.newCandidate, .noLongerDetected, .possibleZigzagConversion, .lowConfidence]
    public init(rawValue: String) {
        self = switch rawValue {
        case "new_candidate": .newCandidate
        case "no_longer_detected": .noLongerDetected
        case "possible_zigzag_conversion": .possibleZigzagConversion
        case "low_confidence": .lowConfidence
        default: .unknown(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .newCandidate: "new_candidate"
        case .noLongerDetected: "no_longer_detected"
        case .possibleZigzagConversion: "possible_zigzag_conversion"
        case .lowConfidence: "low_confidence"
        case .unknown(let value): value
        }
    }
    public var label: String {
        switch self {
        case .newCandidate: "Not detected in Dec 2023"
        case .noLongerDetected: "No longer detected"
        case .possibleZigzagConversion: "Possible zigzag conversion"
        case .lowConfidence: "Low detector score"
        case .unknown: "Unrecognised change"
        }
    }
    public init(from decoder: any Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

public enum ReviewState: Hashable, Sendable, Codable {
    case pending, unknown(String)
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = raw == "pending" ? .pending : .unknown(raw)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .pending: try c.encode("pending"); case .unknown(let raw): try c.encode(raw) }
    }
}

public struct ReviewQueue: Codable, Hashable, Sendable {
    public struct Baseline: Codable, Hashable, Sendable { public let run: String; public let scene: String; public let date: String }
    public struct Current: Codable, Hashable, Sendable { public let label: String; public let scene: String; public let date: String }
    public struct Counts: Codable, Hashable, Sendable {
        public let newCandidate: Int
        public let noLongerDetected: Int
        public let possibleZigzagConversion: Int
        public let lowConfidence: Int
        public subscript(group: ReviewGroup) -> Int {
            switch group {
            case .newCandidate: newCandidate
            case .noLongerDetected: noLongerDetected
            case .possibleZigzagConversion: possibleZigzagConversion
            case .lowConfidence: lowConfidence
            case .unknown: 0
            }
        }
    }
    public let baseline: Baseline?
    public let current: Current?
    public let counts: Counts
    public let truncated: Bool
    public var items: [ReviewItem]

    /// Reject foreign URLs before any view can consume the evidence.
    public func acceptingEvidence(host: String?) -> Self {
        var queue = self
        for index in queue.items.indices {
            queue.items[index].evidence = queue.items[index].evidence?.accepting(host: host)
        }
        return queue
    }
}

public struct ReviewItem: Codable, Hashable, Sendable, Identifiable {
    public struct Prediction: Codable, Hashable, Sendable { public let type: KilnType; public let score: Double }
    public struct Centroid: Codable, Hashable, Sendable {
        public let lat: Double; public let lon: Double
        public var coordinate: Coordinate { Coordinate(latitude: lat, longitude: lon) }
    }
    public struct Evidence: Codable, Hashable, Sendable {
        public var before: URL?; public var after: URL?
        public static func allows(_ url: URL, host: String?) -> Bool {
            guard let host, !host.isEmpty else { return false }
            return url.scheme?.lowercased() == "https" && url.host?.lowercased() == host.lowercased()
                && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
        }
        func accepting(host: String?) -> Self {
            Self(before: before.flatMap { Self.allows($0, host: host) ? $0 : nil },
                 after: after.flatMap { Self.allows($0, host: host) ? $0 : nil })
        }
        func sanitized() -> Self {
            func sanitize(_ url: URL?) -> URL? {
                guard let url, Self.allows(url, host: url.host), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
                parts.host = "evidence.example"; parts.query = nil; parts.fragment = nil
                return parts.url
            }
            return Self(before: sanitize(before), after: sanitize(after))
        }
    }
    public let itemId: String
    public let group: ReviewGroup
    public let state: ReviewState
    public let kilnId: String?
    public let reason: String
    public let centroid: Centroid
    public let baseline: Prediction?
    public let current: Prediction?
    public let iou: Double?
    public var evidence: Evidence?
    public let createdAt: Date
    public var id: String { itemId }
    public var displayGroup: ReviewGroup { state == .pending ? group : .unknown("state") }
}

/// Saved responses keep paths and facts, with a placeholder host on disk.
public struct ReviewCache: Sendable {
    public let fileURL: URL
    public init(directory: URL = .kilnWatchStore) { fileURL = directory.appending(path: "review.json") }
    public func save(_ response: ReviewQueue) throws {
        var safe = response
        for index in safe.items.indices { safe.items[index].evidence = safe.items[index].evidence?.sanitized() }
        let data = try JSONEncoder.kilnWatch.encode(safe)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    public func load() throws -> ReviewQueue? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder.kilnWatch.decode(ReviewQueue.self, from: Data(contentsOf: fileURL))
    }
}

@MainActor @Observable
public final class ReviewList {
    public private(set) var queue: ReviewQueue?
    public private(set) var isLoading = false
    public private(set) var offline = false
    public private(set) var message: String?
    public private(set) var cacheWarning: String?
    private var didLoad = false
    private let cache: ReviewCache
    public init(cache: ReviewCache = ReviewCache()) { self.cache = cache }

    /// First appearance, refresh, or explicit Retry only. No automatic retries or polling.
    public func load(api: KilnWatchAPI?, force: Bool = false, sample: ReviewQueue? = nil, scenario: String? = nil) async {
        guard !isLoading, force || !didLoad else { return }
        isLoading = true; message = nil; cacheWarning = nil; offline = false
        defer { isLoading = false }
        do { if queue == nil { queue = try await Self.saved(cache)?.acceptingEvidence(host: nil) } }
        catch { cacheWarning = "The saved review list could not be read." }
        if let sample {
            switch scenario {
            case "loading": didLoad = true; return
            case "empty":
                queue = ReviewQueue(baseline: nil, current: nil, counts: .init(newCandidate: 0, noLongerDetected: 0, possibleZigzagConversion: 0, lowConfidence: 0), truncated: false, items: [])
            case "offline":
                do { try await Self.save(sample, cache); queue = try await Self.saved(cache)?.acceptingEvidence(host: nil); offline = true }
                catch { message = "The sample review list could not be saved." }
            default: queue = sample.acceptingEvidence(host: nil)
            }
            didLoad = true; return
        }
        guard let api else { message = "Review is unavailable. No public data connection is configured."; didLoad = true; return }
        do {
            var response = try await api.review()
            // The public kiln read is the existing source of trusted evidence URLs.
            // Do not treat a host supplied only by a review item as trusted.
            var evidenceHost: String?
            if let id = response.items.first(where: { $0.kilnId != nil && $0.evidence != nil })?.kilnId {
                do {
                    let kiln = try await api.publicKiln(id: id, includeInspected: true)
                    evidenceHost = (kiln.evidence.after ?? kiln.evidence.before)?.host
                } catch { /* Queue remains usable without images; detail has its own recovery. */ }
            }
            try Task.checkCancellation()
            response = response.acceptingEvidence(host: evidenceHost)
            queue = response
            do { try await Self.save(response, cache); cacheWarning = nil }
            catch { cacheWarning = "This review list could not be saved for offline use." }
            didLoad = true
        } catch {
            if Task.isCancelled { message = "Review loading interrupted. Try again."; return }
            if case APIError.transport = error {
                offline = queue != nil
                message = queue == nil ? "No connection and no saved review list. Reconnect and retry." : nil
            } else if case APIError.status(503, _) = error {
                message = "Review is temporarily unavailable. Try again."
            } else { message = "The review list could not be loaded. Try again." }
            didLoad = true
        }
    }
    @concurrent private static func saved(_ cache: ReviewCache) async throws -> ReviewQueue? { try cache.load() }
    @concurrent private static func save(_ queue: ReviewQueue, _ cache: ReviewCache) async throws { try cache.save(queue) }
}
