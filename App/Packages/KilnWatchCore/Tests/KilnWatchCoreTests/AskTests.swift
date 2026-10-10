import Foundation
import Synchronization
import Testing
@testable import KilnWatchCore

private func askFixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "AskFixtures")))
}
private struct AskStub {
    typealias Handler = @Sendable (URLRequest) -> (Int, Data)
    static let handlers = Mutex<[String: Handler]>([:])
    let api: KilnWatchAPI
    init(_ handler: @escaping Handler) {
        let host = "\(UUID().uuidString.lowercased()).test"
        Self.handlers.withLock { $0[host] = handler }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AskStubProtocol.self]
        api = KilnWatchAPI(baseURL: URL(string: "https://\(host)/v1")!, session: URLSession(configuration: config), token: {
            Issue.record("Public Ask called the token provider"); return "test"
        })
    }
}
private final class AskStubProtocol: URLProtocol, @unchecked Sendable {
    private let stopped = Mutex(false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { stopped.withLock { $0 = true } }
    override func startLoading() {
        guard let handler = AskStub.handlers.withLock({ $0[request.url?.host ?? ""] }) else { return }
        let (code, body) = handler(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.06) { [self] in
            guard !stopped.withLock({ $0 }) else { return }
            if code < 0 { client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: code))); return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        }
    }
}
private func readBody(_ request: URLRequest) -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }
    var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
    }
    return data
}
@Test func askPOSTIsPublicStatelessAndOmitsAbsentFields() async throws {
    let data = try askFixture("normal_answer"); let calls = Mutex(0)
    let stub = AskStub { request in
        calls.withLock { $0 += 1 }
        #expect(request.httpMethod == "POST" && request.url?.path == "/v1/ask")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.timeoutInterval == 35 && request.cachePolicy == .reloadIgnoringLocalCacheData)
        let object = try? JSONSerialization.jsonObject(with: readBody(request)) as? [String: Any]
        #expect(object?.keys.sorted() == ["question"])
        #expect(object?["question"] as? String == "How many kilns?")
        return (200, data)
    }
    let answer = try await stub.api.ask(question: " \nHow many kilns? \n")
    #expect(answer.steps.first?.summary == "39 found" && !answer.fallback)
    #expect(calls.withLock { $0 } == 1)
}
@Test func askContextUsesFullIDAndCoordinates() throws {
    let id = "KW-00000000000000000000000000000001"
    let input = try AskRequest(question: "Explain this record", kilnId: id, lat: 28.7, lon: 77.7)
    let object = try #require(JSONSerialization.jsonObject(with: input.body()) as? [String: Any])
    #expect(object.keys.sorted() == ["kiln_id", "lat", "lon", "question"])
    #expect(object["kiln_id"] as? String == id && object["lat"] as? Double == 28.7)
}
@Test(arguments: ["", " \n", String(repeating: "a", count: 501), String(repeating: "e\u{301}", count: 251)])
func invalidAskQuestionsDoNotReachNetwork(question: String) async {
    let calls = Mutex(0)
    let stub = AskStub { _ in calls.withLock { $0 += 1 }; return (200, Data()) }
    await #expect(throws: AskError.invalidInput(.question)) { try await stub.api.ask(question: question) }
    #expect(calls.withLock { $0 } == 0)
}
@Test func askUnicodeAndBodyBoundsAreHonest() throws {
    #expect(try AskRequest(question: " " + String(repeating: "a", count: 500) + " ").question.unicodeScalars.count == 500)
    #expect(try AskRequest(question: String(repeating: "e\u{301}", count: 250)).question.unicodeScalars.count == 500)
    #expect(try AskRequest(question: String(repeating: "😀", count: 500)).body().count <= 2048)
    #expect(throws: AskError.invalidInput(.bodySize)) { try AskRequest(question: String(repeating: "\u{0001}", count: 500)) }
    #expect(throws: AskError.invalidInput(.bodySize)) { try AskRequest(question: String(repeating: "😀", count: 500), kilnId: "KW-00000000000000000000000000000001", lat: 28.7, lon: 77.7) }
}
@Test func invalidAskContextFailsSafely() {
    for pair: (Double?, Double?) in [(1, nil), (nil, 1), (.nan, 0), (0, .infinity), (91, 0), (0, -181)] {
        #expect(throws: AskError.invalidInput(.coordinates)) { try AskRequest(question: "Record?", lat: pair.0, lon: pair.1) }
    }
    #expect(throws: AskError.invalidInput(.kiln)) { try AskRequest(question: "Record?", kilnId: "KW-short") }
}
@Test(arguments: [(400, "invalid_request", false), (429, "daily_cap_reached", false), (503, "model_unavailable", false)])
func askRecordedErrorsHaveCodesAndRetryability(row: (Int, String, Bool)) async throws {
    let body = try askFixture(row.1); let calls = Mutex(0)
    let stub = AskStub { _ in calls.withLock { $0 += 1 }; return (row.0, body) }
    do { _ = try await stub.api.ask(question: "Count?"); Issue.record("Expected service error") }
    catch {
        guard case .service(let status, let detail) = error else { Issue.record("Expected typed service error"); return }
        #expect(status == row.0 && detail?.code == row.1 && detail?.retryable == row.2 && !error.canRetry)
    }
    #expect(calls.withLock { $0 } == 1)
}
@Test func askGatewayThrottleDiffersFromDailyCap() async throws {
    let body = try askFixture("gateway_throttled"); let stub = AskStub { _ in (429, body) }
    await #expect(throws: AskError.gatewayThrottled) { try await stub.api.ask(question: "Count?") }
    #expect(AskError.gatewayThrottled.canRetry && AskError.gatewayThrottled.retryDelay > 0)
}
@Test(arguments: ["assistant_unavailable", "upstream_unavailable", "model_unavailable"])
func askTemporaryErrorsHonorRetryFlag(code: String) async {
    let body = Data(#"{"error":{"code":"\#(code)","message":"Unavailable","retryable":true}}"#.utf8)
    do { _ = try await AskStub { _ in (503, body) }.api.ask(question: "Count?"); Issue.record("Expected failure") }
    catch { #expect(error.canRetry && error.message.contains("temporarily unavailable")) }
}
@Test func askFallbackCarriesCitationsEvenWithoutInlineIDs() async throws {
    let data = try askFixture("fallback.synthetic")
    let answer = try await AskStub { _ in (200, data) }.api.ask(question: "Record?")
    #expect(answer.fallback && answer.citations.count == 1 && !answer.answer.contains(answer.citations[0]) && !answer.disclaimer.isEmpty)
}
@Test func askEmptyRepeatedFailedStepsAndCitationOrder() async throws {
    let id = "KW-00000000000000000000000000000001"
    for steps: [AskStep] in [[], [.init(tool: "kiln_detail", label: "Reading", summary: "Found", ok: true), .init(tool: "kiln_detail", label: "Reading again", summary: "Invalid input", ok: false)]] {
        let original = AskAnswer(answer: "First paragraph.\n\nRecord \(id).", citations: [id, "KW-0412", id], steps: steps, fallback: false, disclaimer: "Pending inspection")
        let data = try JSONEncoder().encode(original)
        let answer = try await AskStub { _ in (200, data) }.api.ask(question: "Record?")
        #expect(answer == original && answer.uniqueCitations == [id, "KW-0412"])
    }
}
@Test(arguments: [#"{}"#, #"{"answer":"x","citations":[],"steps":[],"fallback":false}"#, #"{"answer":"x","citations":[],"steps":[],"disclaimer":"d"}"#, #"{"answer":"x","citations":["KW-short"],"steps":[],"fallback":false,"disclaimer":"d"}"#])
func malformedAskNeverBecomesSample(body: String) async {
    await #expect(throws: AskError.malformedResponse) { try await AskStub { _ in (200, Data(body.utf8)) }.api.ask(question: "Count?") }
}
@Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cancelled, .cannotConnectToHost])
func askTransportIsTypedAndNotRetried(code: URLError.Code) async {
    let calls = Mutex(0)
    let stub = AskStub { _ in calls.withLock { $0 += 1 }; return (code.rawValue, Data()) }
    await #expect(throws: code == .cancelled ? AskError.cancelled : AskError.transport(code)) { try await stub.api.ask(question: "Count?") }
    #expect(calls.withLock { $0 } == 1)
}
@MainActor private func settle(_ conversation: AskConversation) async throws {
    for _ in 0..<100 {
        if !conversation.isSending { return }; try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Request did not settle")
}
@Test @MainActor func askLifecycleGuardsDuplicatesAndPreservesNewDraft() async throws {
    let calls = Mutex(0); let data = try askFixture("normal_answer")
    let conversation = AskConversation(api: AskStub { _ in calls.withLock { $0 += 1 }; return (200, data) }.api)
    conversation.prefill(kilnId: "KW-00000000000000000000000000000001")
    #expect(conversation.exchanges.isEmpty && conversation.kilnId != nil)
    #expect(conversation.send()); #expect(!conversation.send()); conversation.draft = "A different question"
    #expect(conversation.kilnId == nil); try await settle(conversation)
    #expect(conversation.draft == "A different question" && calls.withLock { $0 } == 1)
    #expect(!conversation.retry(conversation.exchanges[0].id))
}
@Test @MainActor func askFailureRetainsDraftAndRetryMakesOneRequest() async throws {
    let calls = Mutex(0); let data = try askFixture("normal_answer")
    let conversation = AskConversation(api: AskStub { _ in
        let count = calls.withLock { $0 += 1; return $0 }; return count == 1 ? (503, Data()) : (200, data)
    }.api)
    conversation.draft = "Count?"; #expect(conversation.send()); try await settle(conversation)
    #expect(conversation.draft == "Count?" && calls.withLock { $0 } == 1)
    #expect(conversation.retry(conversation.exchanges[0].id)); #expect(!conversation.retry(conversation.exchanges[0].id))
    try await settle(conversation)
    #expect(conversation.draft.isEmpty && conversation.exchanges.count == 1 && calls.withLock { $0 } == 2)
}
@Test @MainActor func askCancellationDiscardsStaleResponseWithoutResubmitting() async throws {
    let data = try askFixture("normal_answer"); let calls = Mutex(0)
    let conversation = AskConversation(api: AskStub { _ in calls.withLock { $0 += 1 }; return (200, data) }.api)
    conversation.draft = "Count?"; #expect(conversation.send())
    try await Task.sleep(for: .milliseconds(20)); conversation.cancel(); try await Task.sleep(for: .milliseconds(100))
    #expect(!conversation.isSending && conversation.draft == "Count?")
    guard case .failed(.cancelled, _) = conversation.exchanges[0].state else { Issue.record("Expected cancelled state"); return }
    #expect(calls.withLock { $0 } == 1)
}

@Test @MainActor func askDailyLimitBlocksAllNewQuestionsUntilUTCReset() async throws {
    let body = try askFixture("daily_cap_reached"); let calls = Mutex(0)
    let conversation = AskConversation(api: AskStub { _ in calls.withLock { $0 += 1 }; return (429, body) }.api)
    conversation.draft = "Count?"; #expect(conversation.send()); try await settle(conversation)
    conversation.draft = "Another question?"
    #expect(!conversation.send() && !conversation.retry(conversation.exchanges[0].id))
    let reset = try #require(conversation.submissionResumeDate)
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
    #expect(utc.component(.hour, from: reset) == 0 && reset > .now)
    #expect(conversation.canSubmit(now: reset) && calls.withLock { $0 } == 1)
    conversation.draft = "Count?"
    #expect(conversation.canSubmit(now: reset))
}
@Test @MainActor func askNonretryableFailureDoesNotOfferSameQuestionAgain() async throws {
    let data = try askFixture("model_unavailable")
    let conversation = AskConversation(api: AskStub { _ in (503, data) }.api)
    conversation.draft = "Count?"; #expect(conversation.send()); try await settle(conversation)
    #expect(!conversation.send() && !conversation.retry(conversation.exchanges[0].id))
}

@Test @MainActor func askDailyLimitAlsoBlocksRetryingAnEarlierFailure() async throws {
    let calls = Mutex(0); let cap = try askFixture("daily_cap_reached")
    let conversation = AskConversation(api: AskStub { _ in
        let count = calls.withLock { $0 += 1; return $0 }
        return count == 1 ? (503, Data()) : (429, cap)
    }.api)
    conversation.draft = "First question?"; #expect(conversation.send()); try await settle(conversation)
    let oldID = conversation.exchanges[0].id
    conversation.draft = "Second question?"; #expect(conversation.send()); try await settle(conversation)
    #expect(!conversation.retry(oldID) && calls.withLock { $0 } == 2)
}
