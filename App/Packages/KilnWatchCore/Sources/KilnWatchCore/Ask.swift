import Foundation
import Observation

public struct AskRequest: Codable, Sendable, Equatable {
    public let question: String
    public let kilnId: String?
    public let lat: Double?
    public let lon: Double?

    public init(question: String, kilnId: String? = nil, lat: Double? = nil, lon: Double? = nil) throws(AskError) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= 500 else { throw .invalidInput(.question) }
        if let kilnId, !Self.isFullKilnID(kilnId) { throw .invalidInput(.kiln) }
        guard (lat == nil) == (lon == nil) else { throw .invalidInput(.coordinates) }
        if let lat, let lon {
            guard lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else {
                throw .invalidInput(.coordinates)
            }
        }
        self.question = trimmed; self.kilnId = kilnId; self.lat = lat; self.lon = lon
        _ = try body()
    }

    public static func isFullKilnID(_ id: String) -> Bool {
        id.range(of: #"^KW-(?:[0-9a-f]{32}|[0-9]{4,})$"#, options: .regularExpression) != nil
    }

    public func body() throws(AskError) -> Data {
        guard let data = try? JSONEncoder.kilnWatch.encode(self), data.count <= 2_048 else { throw .invalidInput(.bodySize) }
        return data
    }
}

public struct AskStep: Codable, Sendable, Equatable {
    public let tool: String
    public let label: String
    public let summary: String
    public let ok: Bool
    public init(tool: String, label: String, summary: String, ok: Bool) {
        self.tool = tool; self.label = label; self.summary = summary; self.ok = ok
    }
}

public struct AskAnswer: Codable, Sendable, Equatable {
    public let answer: String
    public let citations: [String]
    public let steps: [AskStep]
    public let fallback: Bool
    public let disclaimer: String
    public init(answer: String, citations: [String], steps: [AskStep], fallback: Bool, disclaimer: String) {
        self.answer = answer; self.citations = citations; self.steps = steps
        self.fallback = fallback; self.disclaimer = disclaimer
    }

    /// Only returned citations are navigable; preserve server first-appearance order.
    public var uniqueCitations: [String] {
        var seen: Set<String> = []
        return citations.filter { seen.insert($0).inserted }
    }
}

public struct AskServiceError: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let retryable: Bool
}
private struct AskErrorEnvelope: Decodable { let error: AskServiceError }

public enum AskInputError: Sendable, Equatable { case question, kiln, coordinates, bodySize }
public enum AskError: Error, Sendable, Equatable {
    case invalidInput(AskInputError)
    case service(status: Int, detail: AskServiceError?)
    case gatewayThrottled
    case transport(URLError.Code)
    case malformedResponse
    case cancelled

    public var message: String {
        switch self {
        case .invalidInput(.question): "Use a question of 1–500 characters."
        case .invalidInput(.bodySize): "This question uses too many bytes. Shorten it before sending."
        case .invalidInput(.kiln): "Use the full kiln ID."
        case .invalidInput(.coordinates): "The supplied location is invalid."
        case .service(400, _): "The question is too long or invalid. Edit it and send again."
        case .service(429, let detail) where detail?.code == "daily_cap_reached": "Ask has reached today's limit"
        case .gatewayThrottled: "Too many questions, wait a moment"
        case .service(503, let detail) where detail?.retryable == false: "Ask isn't available right now"
        case .service(503, _): "Ask is temporarily unavailable. Try again later."
        case .transport(.notConnectedToInternet): "Ask needs a connection. Reconnect and try again."
        case .transport(.timedOut): "The answer took too long. You can try again."
        case .cancelled: "Question cancelled. It may still count toward today's limit."
        case .malformedResponse: "Ask returned an unreadable answer. You can try again."
        default: "The answer couldn't be loaded. You can try again."
        }
    }
    public var canRetry: Bool {
        switch self {
        case .invalidInput, .service(400, _): false
        case .service(429, let detail) where detail?.code == "daily_cap_reached": false
        case .service(_, let detail): detail?.retryable ?? true
        default: true
        }
    }
    public var retryDelay: TimeInterval { self == .gatewayThrottled ? 3 : 0 }
}

extension KilnWatchAPI {
    /// Cost-bearing, stateless public POST. Exactly one attempt; never uses registry backoff or authentication.
    public func ask(question: String, kilnId: String? = nil, lat: Double? = nil, lon: Double? = nil) async throws(AskError) -> AskAnswer {
        let input = try AskRequest(question: question, kilnId: kilnId, lat: lat, lon: lon)
        var request = URLRequest(url: baseURL.appending(path: "ask"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.httpBody = try input.body()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw .cancelled }
            throw .transport((error as? URLError)?.code ?? .unknown)
        }
        guard !Task.isCancelled else { throw .cancelled }
        guard let response = response as? HTTPURLResponse else { throw .malformedResponse }
        guard response.statusCode == 200 else {
            let detail = (try? JSONDecoder().decode(AskErrorEnvelope.self, from: data))?.error
            if response.statusCode == 429, detail == nil { throw .gatewayThrottled }
            throw .service(status: response.statusCode, detail: detail)
        }
        guard let answer = try? JSONDecoder().decode(AskAnswer.self, from: data),
              !answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !answer.disclaimer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              answer.citations.allSatisfy(AskRequest.isFullKilnID) else { throw .malformedResponse }
        return answer
    }
}

public struct AskExchange: Identifiable, Sendable {
    public enum State: Sendable { case waiting, answered(AskAnswer), failed(AskError, retryAfter: Date) }
    public let id: UUID
    public let request: AskRequest
    public var state: State
}

/// In-memory ownership survives view appearance changes. Submission only happens from explicit actions.
@MainActor @Observable public final class AskConversation {
    public var draft = "" {
        didSet { if let kilnId, !draft.contains(kilnId) { self.kilnId = nil } }
    }
    public private(set) var kilnId: String?
    public private(set) var exchanges: [AskExchange] = []
    public private(set) var isSending = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let api: KilnWatchAPI?

    public init(api: KilnWatchAPI?) { self.api = api }
    public var validation: AskError? {
        do { _ = try AskRequest(question: draft, kilnId: kilnId); return nil } catch { return error }
    }
    public func prefill(kilnId: String) {
        draft = "Explain this kiln's registry record: \(kilnId)"
        self.kilnId = kilnId
    }
    public var submissionResumeDate: Date? {
        exchanges.compactMap { exchange -> Date? in
            guard case .failed(let error, let date) = exchange.state, date > .now else { return nil }
            if case .service(429, let detail) = error, detail?.code == "daily_cap_reached" { return date }
            if error == .gatewayThrottled { return date }
            return nil
        }.max()
    }
    public func canSubmit(now: Date = .now) -> Bool {
        guard !isSending, api != nil else { return false }
        for exchange in exchanges {
            guard case .failed(let error, let date) = exchange.state else { continue }
            if case .service(429, let detail) = error, detail?.code == "daily_cap_reached", now < date { return false }
            if error == .gatewayThrottled, now < date { return false }
        }
        if let last = exchanges.last, case .failed(let error, let date) = last.state, !error.canRetry,
           draft.trimmingCharacters(in: .whitespacesAndNewlines) == last.request.question,
           kilnId == last.request.kilnId {
            if case .service(429, let detail) = error, detail?.code == "daily_cap_reached", now >= date { return true }
            return false
        }
        return true
    }
    @discardableResult public func send() -> Bool {
        guard canSubmit(), let request = try? AskRequest(question: draft, kilnId: kilnId) else { return false }
        let exchange = AskExchange(id: UUID(), request: request, state: .waiting)
        exchanges.append(exchange)
        perform(id: exchange.id, request: request, submittedDraft: draft)
        return true
    }
    @discardableResult public func retry(_ id: UUID, now: Date = .now) -> Bool {
        guard !isSending, let exchange = exchanges.first(where: { $0.id == id }),
              case .failed(let error, let date) = exchange.state, error.canRetry, now >= date else { return false }
        if let date = submissionResumeDate, now < date { return false }
        perform(id: id, request: exchange.request, submittedDraft: draft == exchange.request.question ? draft : nil)
        return true
    }
    public func cancel() {
        guard isSending else { return }
        generation = UUID(); task?.cancel(); task = nil; isSending = false
        if let index = exchanges.firstIndex(where: { if case .waiting = $0.state { return true }; return false }) {
            exchanges[index].state = .failed(.cancelled, retryAfter: .now)
        }
    }
    private func perform(id: UUID, request: AskRequest, submittedDraft: String?) {
        guard let api, let index = exchanges.firstIndex(where: { $0.id == id }) else { return }
        exchanges[index].state = .waiting; isSending = true
        let current = UUID(); generation = current
        task = Task { [weak self] in
            let result: Result<AskAnswer, AskError>
            do { result = .success(try await api.ask(question: request.question, kilnId: request.kilnId, lat: request.lat, lon: request.lon)) }
            catch { result = .failure((error as? AskError) ?? .malformedResponse) }
            guard let self, self.generation == current, let index = self.exchanges.firstIndex(where: { $0.id == id }) else { return }
            self.isSending = false; self.task = nil
            switch result {
            case .success(let answer):
                self.exchanges[index].state = .answered(answer)
                if let submittedDraft, self.draft == submittedDraft { self.draft = ""; self.kilnId = nil }
            case .failure(let error):
                var retryAfter = Date.now.addingTimeInterval(error.retryDelay)
                if case .service(429, let detail) = error, detail?.code == "daily_cap_reached" {
                    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
                    retryAfter = utc.date(byAdding: .day, value: 1, to: utc.startOfDay(for: .now)) ?? .distantFuture
                }
                self.exchanges[index].state = .failed(error, retryAfter: retryAfter)
            }
        }
    }
}
