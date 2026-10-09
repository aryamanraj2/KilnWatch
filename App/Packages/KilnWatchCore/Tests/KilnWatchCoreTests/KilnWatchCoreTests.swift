import Foundation
import Synchronization
import Testing
@testable import KilnWatchCore

// MARK: - Contract

@Test(arguments: ["kilns", "route_today", "rules"])
func fixtureDecodes(name: String) throws {
    let data = try Fixtures.data(name)
    switch name {
    case "kilns": _ = try JSONDecoder.kilnWatch.decode(KilnList.self, from: data)
    case "route_today": _ = try JSONDecoder.kilnWatch.decode(Route.self, from: data)
    default: _ = try JSONDecoder.kilnWatch.decode(RuleList.self, from: data)
    }
}

@Test func fixturesMatchTheConcept() throws {
    let kiln = try #require(Fixtures.kilns.first { $0.kilnId == "KW-0412" })
    #expect(kiln.type == .fcbk && kiln.typeConfidence == 0.82)
    #expect(kiln.exposure.people == 6240 && kiln.exposure.childrenUnderFive == 710)
    #expect(kiln.violations.map(\.ruleId) == ["C-HAB-800", "UP-SCH-1K", "C-TECH-10K"])
    #expect(kiln.violations[0].measuredDistanceM == 410 && kiln.violations[2].measuredDistanceM == nil)
    #expect(Fixtures.route.stops.map(\.order) == Array(1...9))
    #expect(Fixtures.route.stops.map(\.kilnId) == Fixtures.route.kilns.map(\.kilnId))
    #expect(Fixtures.rules.count == 7)
}

@Test func kilnRoundTrips() throws {
    for kiln in Fixtures.kilns {
        let decoded = try JSONDecoder.kilnWatch.decode(Kiln.self, from: JSONEncoder.kilnWatch.encode(kiln))
        #expect(decoded == kiln)
    }
}

@Test func unknownStatusAndTypeDecodeWithoutDroppingTheRecord() throws {
    let json = try #require(String(data: JSONEncoder.kilnWatch.encode(Fixtures.kilns[0]), encoding: .utf8))
        .replacingOccurrences(of: #""status":"flagged""#, with: #""status":"under_review""#)
        .replacingOccurrences(of: #""type":"FCBK""#, with: #""type":"Hoffmann""#)
    let kiln = try JSONDecoder.kilnWatch.decode(Kiln.self, from: Data(json.utf8))
    #expect(kiln.status == .unknown("under_review"))
    #expect(kiln.type == .unknown("Hoffmann"))
    // The raw value survives a trip through the route cache.
    let reencoded = try JSONDecoder.kilnWatch.decode(Kiln.self, from: JSONEncoder.kilnWatch.encode(kiln))
    #expect(reencoded.status.rawValue == "under_review")
}

@Test func datesAcceptOptionalFractionalSecondsAndOffsets() throws {
    struct Box: Decodable { let at: [Date] }
    let box = try JSONDecoder.kilnWatch.decode(Box.self, from: Data(#"{"at": ["2026-10-09T08:30:00Z", "2026-10-09T08:30:00.250000+00:00", "2026-10-09T14:00:00+05:30"]}"#.utf8))
    #expect(box.at[0] == box.at[2])
    #expect(box.at[1].timeIntervalSince(box.at[0]) == 0.25)
}

// MARK: - Client errors

@Test(arguments: [404, 503])
func httpErrorsAreTyped(code: Int) async throws {
    let stub = Stub { _ in (code, Data(#"{"error":{"code":"x","message":"y"}}"#.utf8)) }
    do {
        _ = try await stub.api.kiln(id: "KW-0412")
        Issue.record("expected a status error")
    } catch {
        guard case .status(let status, let body) = error else { Issue.record("got \(error)"); return }
        #expect(status == code)
        #expect(!body.isEmpty)
    }
}

@Test func malformedBodyNamesTheKey() async throws {
    let stub = Stub { _ in (200, Data(#"{"kilns": [{"kiln_id": 42}]}"#.utf8)) }
    do {
        _ = try await stub.api.kilns(district: "Hapur", status: .flagged)
        Issue.record("expected a decoding error")
    } catch {
        guard case .decoding(let keyPath, _) = error else { Issue.record("got \(error)"); return }
        #expect(keyPath == "kilns[0].kilnId")
    }
}

// MARK: - Outbox

private func makeVerdict() -> (Verdict, [Photo.ID: Data]) {
    let now = Date(timeIntervalSince1970: 1_791_534_600) // whole seconds: the outbox stores milliseconds
    let photos = [Photo(latitude: 28.7158, longitude: 77.6561, horizontalAccuracyM: 6, takenAt: now),
                  Photo(latitude: 28.7159, longitude: 77.6562, horizontalAccuracyM: 8, takenAt: now)]
    let verdict = Verdict(kilnId: "KW-0412", outcome: .confirmed, photos: photos, note: "Chimney fixed, coal on site", recordedAt: now)
    return (verdict, Dictionary(uniqueKeysWithValues: photos.map { ($0.id, Data("jpeg-\($0.id)".utf8)) }))
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "KilnWatchCoreTests-\(UUID().uuidString)")
}

@Test func failedFlushKeepsVerdictAndPhotos() async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let outbox = try VerdictOutbox(directory: dir)
    let (verdict, photos) = makeVerdict()
    try await outbox.enqueue(verdict, photos: photos)

    await outbox.flush(using: Stub { _ in (503, Data()) }.api)

    let pending = await outbox.pending
    #expect(pending.map(\.id) == [verdict.id])
    #expect(pending.first?.attempts == 1)
    #expect(pending.first?.lastError != nil)
    for photo in verdict.photos {
        #expect(try Data(contentsOf: outbox.fileURL(for: photo, of: verdict)) == photos[photo.id])
    }
    #expect(try await VerdictOutbox(directory: dir).pending.first?.attempts == 1) // attempt count is on disk too
}

@Test func successfulFlushRemovesVerdictAndPhotos() async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let outbox = try VerdictOutbox(directory: dir)
    let (verdict, photos) = makeVerdict()
    try await outbox.enqueue(verdict, photos: photos)

    let uploaded = Mutex<[Data]>([])
    let stub = Stub { request in
        switch (request.httpMethod, request.url?.path) {
        case ("POST", "/v1/verdicts"):
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == verdict.id.uuidString)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            let uploads = verdict.photos.map { #"{"photo_id":"\#($0.id)","upload_url":"https://\#(request.url!.host!)/upload/\#($0.id)"}"# }
            return (201, Data(#"{"id":"\#(verdict.id)","photo_uploads":[\#(uploads.joined(separator: ","))]}"#.utf8))
        case ("PUT", _):
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            uploaded.withLock { $0.append(Data()) }
            return (200, Data())
        default:
            return (404, Data())
        }
    }
    await outbox.flush(using: stub.api)

    #expect(await outbox.pending.isEmpty)
    #expect(uploaded.withLock { $0.count } == 2)
    for photo in verdict.photos {
        #expect(!FileManager.default.fileExists(atPath: outbox.fileURL(for: photo, of: verdict).path))
    }
    #expect(try await VerdictOutbox(directory: dir).pending.isEmpty)
}

@Test func queueSurvivesACrashAfterEnqueue() async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let (verdict, photos) = makeVerdict()
    do {
        let outbox = try VerdictOutbox(directory: dir)
        try await outbox.enqueue(verdict, photos: photos)
    } // the actor is gone, as after a crash

    let relaunched = try VerdictOutbox(directory: dir)
    #expect(await relaunched.pending.map(\.verdict) == [verdict])
    for photo in verdict.photos {
        #expect(FileManager.default.fileExists(atPath: relaunched.fileURL(for: photo, of: verdict).path))
    }
}

@Test func routeCacheRoundTrips() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = RouteCache(directory: dir)
    #expect(try cache.load() == nil)
    try cache.save(Fixtures.route)
    #expect(try cache.load()?.stops == Fixtures.route.stops)
}

// MARK: - URLProtocol stub

/// Routes requests for one random host to `handler`, so tests can run in parallel.
private struct Stub {
    typealias Handler = @Sendable (URLRequest) -> (Int, Data)
    static let handlers = Mutex<[String: Handler]>([:])

    let api: KilnWatchAPI

    init(_ handler: @escaping Handler) {
        let host = "\(UUID().uuidString.lowercased()).test"
        Self.handlers.withLock { $0[host] = handler }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        api = KilnWatchAPI(baseURL: URL(string: "https://\(host)/v1")!, session: URLSession(configuration: config), token: { "test-token" })
    }
}

private final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let handler = Stub.handlers.withLock({ $0[url.host ?? ""] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let (code, body) = handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
