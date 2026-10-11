import Foundation
import Synchronization
import Testing
@testable import KilnWatchCore

private func reviewData() throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: "review.recorded", withExtension: "json", subdirectory: "ReviewFixtures")))
}
private func reviewQueue() throws -> ReviewQueue { try JSONDecoder.kilnWatch.decode(ReviewQueue.self, from: reviewData()) }
private func reviewCache() -> ReviewCache { ReviewCache(directory: FileManager.default.temporaryDirectory.appending(path: "ReviewTests-\(UUID().uuidString)")) }

@Test func recordedReviewDecodesAllGroupsAndNulls() throws {
    let queue = try reviewQueue()
    #expect(queue.items.count == 45 && !queue.truncated)
    #expect(ReviewGroup.ordered.map { queue.counts[$0] } == [24, 17, 0, 4])
    #expect(queue.baseline?.date == "2023-12-05" && queue.current?.date == "2026-10-05")
    #expect(queue.baseline?.run == "m0-before" && queue.current?.label == "registry")
    #expect(queue.items.filter { $0.group == .newCandidate }.allSatisfy { $0.baseline == nil && $0.iou == nil && $0.kilnId != nil && $0.current != nil })
    #expect(queue.items.filter { $0.group == .noLongerDetected }.allSatisfy { $0.kilnId == nil && $0.current == nil && $0.iou == nil && $0.evidence == nil && $0.baseline != nil })
    #expect(queue.items.filter { $0.group == .lowConfidence }.allSatisfy { $0.baseline != nil && $0.current != nil && $0.iou != nil })
    #expect(queue.items.allSatisfy { $0.state == .pending && $0.centroid.coordinate.isValid })
    #expect(try JSONDecoder.kilnWatch.decode(ReviewQueue.self, from: JSONEncoder.kilnWatch.encode(queue)) == queue)
}

@Test(arguments: [true, false]) func unknownReviewValuesStayVisible(group: Bool) throws {
    var object = try #require(JSONSerialization.jsonObject(with: reviewData()) as? [String: Any])
    var items = try #require(object["items"] as? [[String: Any]])
    items[0][group ? "group" : "state"] = "future_case"; object["items"] = items
    let queue = try JSONDecoder.kilnWatch.decode(ReviewQueue.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(queue.items.count == 45 && queue.items[0].displayGroup.label == "Unrecognised change")
    if group { #expect(queue.items[0].group == .unknown("future_case")) }
    else { #expect(queue.items[0].state == .unknown("future_case")) }
    #expect(try JSONDecoder.kilnWatch.decode(ReviewQueue.self, from: JSONEncoder.kilnWatch.encode(queue)) == queue)
}

@Test func emptyAndPartialEvidenceReviewDecode() throws {
    let empty = Data(#"{"baseline":null,"current":null,"counts":{"new_candidate":0,"no_longer_detected":0,"possible_zigzag_conversion":0,"low_confidence":0},"truncated":false,"items":[]}"#.utf8)
    let queue = try JSONDecoder.kilnWatch.decode(ReviewQueue.self, from: empty)
    #expect(queue.items.isEmpty && queue.baseline == nil && queue.current == nil)
    var sample = try reviewQueue()
    sample.items[0].evidence = .init(before: nil, after: URL(string: "https://evidence.example/image.png"))
    let decoded = try JSONDecoder.kilnWatch.decode(ReviewQueue.self, from: JSONEncoder.kilnWatch.encode(sample))
    #expect(decoded.items[0].evidence?.before == nil && decoded.items[0].evidence?.after != nil)
}

@Test func reviewGETIsPublicAndHasNoQueryOrBody() async throws {
    let data = try reviewData()
    let stub = AskStub { request in
        #expect(request.httpMethod == "GET" && request.url?.path == "/v1/public/review")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil && request.url?.query == nil && request.httpBody == nil)
        return (200, data)
    }
    #expect(try await stub.api.review().items.count == 45)
}

@Test(arguments: [400, 503, -1009]) func reviewMapsPublicErrors(status: Int) async throws {
    let body = Data(#"{"error":{"code":"review_unavailable","retryable":true}}"#.utf8)
    do { _ = try await AskStub { _ in (status, body) }.api.review(); Issue.record("Expected an error") }
    catch {
        switch error {
        case .status(let code, let data): #expect(code == status && data == body && error.isSystemic == (status == 503))
        case .transport: #expect(status == -1009)
        default: Issue.record("Unexpected error mapping")
        }
    }
}

@Test func reviewCacheRoundTripAndHostRedaction() throws {
    let cache = reviewCache(); defer { try? FileManager.default.removeItem(at: cache.fileURL.deletingLastPathComponent()) }
    #expect(try cache.load() == nil)
    let queue = try reviewQueue(); try cache.save(queue)
    #expect(try cache.load() == queue)
    var response = queue
    response.items[0].evidence = .init(before: URL(string: "https://trusted.test/before.png"), after: nil)
    try cache.save(response)
    let saved = try String(contentsOf: cache.fileURL, encoding: .utf8)
    #expect(!saved.contains("trusted.test") && saved.contains("evidence.example"))
    #expect(try cache.load()?.items[0].evidence?.before?.path == "/before.png")
}

@Test func reviewEvidenceRequiresExactTrustedHost() throws {
    let allowed = URL(string: "https://evidence.example/a.png")!
    #expect(ReviewItem.Evidence.allows(allowed, host: "evidence.example"))
    for address in ["http://evidence.example/a.png", "https://other.example/a.png", "https://evidence.example.other.test/a.png", "https://evidence.example:444/a.png"] {
        #expect(!ReviewItem.Evidence.allows(URL(string: address)!, host: "evidence.example"))
    }
    var credentialed = URLComponents(url: allowed, resolvingAgainstBaseURL: false)!
    credentialed.user = "sample"
    #expect(!ReviewItem.Evidence.allows(credentialed.url!, host: "evidence.example"))
    #expect(!ReviewItem.Evidence.allows(allowed, host: nil))
    var queue = try reviewQueue(); queue.items[0].evidence = .init(before: allowed, after: URL(string: "https://other.example/a.png"))
    let safe = queue.acceptingEvidence(host: "evidence.example")
    #expect(safe.items[0].evidence?.before == allowed && safe.items[0].evidence?.after == nil)
}

@MainActor @Test func reviewLoadsOnceAndKeepsSavedCopyOnFailure() async throws {
    let cache = reviewCache(); defer { try? FileManager.default.removeItem(at: cache.fileURL.deletingLastPathComponent()) }
    let queue = try reviewQueue(); try cache.save(queue)
    let calls = Mutex(0)
    let stub = AskStub { _ in calls.withLock { $0 += 1 }; return (-1009, Data()) }
    let list = ReviewList(cache: cache)
    await list.load(api: stub.api)
    #expect(list.queue == queue.acceptingEvidence(host: nil) && list.offline && list.message == nil)
    await list.load(api: stub.api)
    #expect(calls.withLock { $0 } == 1)
    await list.load(api: AskStub { _ in (503, Data()) }.api, force: true)
    #expect(list.queue == queue.acceptingEvidence(host: nil) && list.message == "Review is temporarily unavailable. Try again.")
    #expect(try cache.load() == queue)
}

@MainActor @Test func reviewWithoutCacheShowsRetryableHonestError() async {
    let list = ReviewList(cache: reviewCache())
    await list.load(api: AskStub { _ in (-1009, Data()) }.api)
    #expect(list.queue == nil && !list.offline && list.message == "No connection and no saved review list. Reconnect and retry.")
}
