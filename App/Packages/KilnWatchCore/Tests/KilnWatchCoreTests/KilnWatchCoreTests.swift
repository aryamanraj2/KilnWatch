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
    #expect(kiln.exposure?.people == 6240 && kiln.exposure?.childrenUnderFive == 710)
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
        if code < 0 { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - Phase 2
private func legacyRouteData() throws -> Data {
    var object = try #require(JSONSerialization.jsonObject(with: Fixtures.data("route_today")) as? [String: Any])
    for key in ["route_id", "depart", "budget_min", "legs"] { object.removeValue(forKey: key) }
    var stops = try #require(object["stops"] as? [[String: Any]])
    for index in stops.indices { for key in ["access", "service_min"] { stops[index].removeValue(forKey: key) } }
    object["stops"] = stops
    var kilns = try #require(object["kilns"] as? [[String: Any]])
    for index in kilns.indices {
        kilns[index].removeValue(forKey: "district")
        var violations = try #require(kilns[index]["violations"] as? [[String: Any]])
        for v in violations.indices { violations[v].removeValue(forKey: "measured_to") }
        kilns[index]["violations"] = violations
    }
    object["kilns"] = kilns
    return try JSONSerialization.data(withJSONObject: object)
}

@Test func legacySavedRouteKeepsStopsWithoutInventingMetadata() throws {
    let legacy = try JSONDecoder.kilnWatch.decode(Route.self, from: legacyRouteData())
    #expect(legacy.usableStops.count == 9)
    #expect(legacy.legs == nil && legacy.depart == nil && legacy.predictedSeconds == nil)
    #expect(legacy.kilns.allSatisfy { $0.district == nil && $0.violations.allSatisfy { $0.measuredTo == nil } })
    #expect(legacy.stops.allSatisfy { $0.access == nil && $0.serviceMin == nil })
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = RouteCache(directory: dir)
    try cache.save(legacy)
    #expect(try cache.load() == legacy)
}

@Test func routeFixtureMetadataAndEmbeddedRecordsAgree() throws {
    let route = Fixtures.route
    #expect(route.stops.count == 9 && route.legs?.count == 9)
    let predicted = try #require(route.predictedSeconds)
    #expect(predicted == 26_100.0)
    for kiln in route.kilns { #expect(Fixtures.kilns.first { $0.kilnId == kiln.kilnId } == kiln) }
    for stop in route.stops {
        #expect(stop.access?.coordinate.isValid == true)
        let leg = try #require(route.legs?.first { $0.toKilnId == stop.kilnId })
        #expect(leg.geometry?.validatedCoordinates.last == stop.access?.coordinate)
    }
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = RouteCache(directory: dir)
    try cache.save(route)
    #expect(try cache.load() == route)
}

@Test(arguments: [
    RouteGeometry(type: "Polygon", coordinates: [[77, 28], [78, 29]]),
    RouteGeometry(type: "LineString", coordinates: [[77, 28]]),
    RouteGeometry(type: "LineString", coordinates: [[77], [78, 29]]),
    RouteGeometry(type: "LineString", coordinates: [[77, 28, 0], [78, 29]]),
    RouteGeometry(type: "LineString", coordinates: [[181, 28], [78, 29]]),
    RouteGeometry(type: "LineString", coordinates: [[77, 91], [78, 29]]),
    RouteGeometry(type: "LineString", coordinates: [[.nan, 28], [78, 29]])
])
func malformedGeometryIsNeverMapped(geometry: RouteGeometry) { #expect(geometry.validatedCoordinates.isEmpty) }

@Test func malformedOptionalGeometryAndAxisOrder() throws {
    let malformed = try JSONDecoder.kilnWatch.decode(RouteGeometry.self, from: Data(#"{"type":"LineString","coordinates":[["bad"],[]]}"#.utf8))
    #expect(malformed.validatedCoordinates.isEmpty)
    let valid = RouteGeometry(type: "LineString", coordinates: [[77.7, 28.7], [77.8, 28.8]])
    #expect(valid.validatedCoordinates.first == Coordinate(latitude: 28.7, longitude: 77.7))
}

@Test func navigationUsesAccessThenKilnFallbackAndServerOrder() throws {
    let route = Fixtures.route
    let first = try #require(route.stops.first)
    #expect(route.destination(for: first) == first.access?.coordinate)
    let url = try #require(route.mapsURL(startingAt: route.stops[2].kilnId))
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.filter { $0.name == "waypoint" }.map(\.value) == route.stops.dropFirst(2).dropLast().map { "\($0.access!.lat),\($0.access!.lon)" })
    #expect(query.first { $0.name == "destination" }?.value == "\(route.stops.last!.access!.lat),\(route.stops.last!.access!.lon)")
    #expect(!query.contains { $0.name == "source" })
    let legacy = try JSONDecoder.kilnWatch.decode(Route.self, from: legacyRouteData())
    #expect(legacy.destination(for: legacy.stops[0]) == legacy.kilns[0].footprint.centroid)
    let single = Route(district: route.district, generatedAt: route.generatedAt, stops: [first], kilns: route.kilns)
    let singleURL = try #require(single.mapsURL(startingAt: nil))
    let singleQuery = try #require(URLComponents(url: singleURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(!singleQuery.contains { $0.name == "waypoint" })
    let empty = Route(district: "Hapur", generatedAt: route.generatedAt, stops: [], kilns: [])
    #expect(empty.mapsURL(startingAt: nil) == nil)
    let missing = Route(district: "Hapur", generatedAt: route.generatedAt, stops: [first], kilns: [])
    #expect(missing.usableStops.isEmpty && missing.mapsURL(startingAt: nil) == nil)
}

@Test(arguments: [404, 200])
func authoritativeEmptyInvalidatesSavedRouteOnly(code: Int) async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = RouteCache(directory: dir)
    try cache.save(Fixtures.route)
    let sentinel = dir.appending(path: "verdict-sentinel.json")
    try Data("unsent verdict".utf8).write(to: sentinel)
    let empty = Route(district: "Hapur", generatedAt: Fixtures.route.generatedAt, stops: [], kilns: [])
    let body = try JSONEncoder.kilnWatch.encode(empty)
    let result = try await RouteRefresh.fetch(using: Stub { _ in (code, body) }.api, cache: cache)
    guard case .empty = result else { Issue.record("Expected authoritative empty"); return }
    #expect(try cache.load() == nil)
    #expect(try Data(contentsOf: sentinel) == Data("unsent verdict".utf8))
}

@Test(arguments: [401, 403, 503, 200])
func failedRefreshPreservesValidCacheWithoutSampleFallback(code: Int) async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = RouteCache(directory: dir)
    try cache.save(Fixtures.route)
    let result = try await RouteRefresh.fetch(using: Stub { _ in (code, Data("malformed body".utf8)) }.api, cache: cache)
    guard case .failure = result else { Issue.record("Expected failure"); return }
    #expect(try cache.load() == Fixtures.route)
}

@Test func transportFailureUsesCacheAndCorruptOrAbsentCacheRecovers() async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = RouteCache(directory: dir)
    let api = Stub { _ in (-1, Data()) }.api
    let absent = try await RouteRefresh.fetch(using: api, cache: cache)
    guard case .failure = absent else { Issue.record("Expected no-cache recovery"); return }
    try cache.save(Fixtures.route)
    let saved = try await RouteRefresh.fetch(using: api, cache: cache)
    guard case .offline(let route) = saved else { Issue.record("Expected saved route"); return }
    #expect(route == Fixtures.route)
    try Data("corrupt".utf8).write(to: cache.fileURL)
    let corrupt = try await RouteRefresh.fetch(using: api, cache: cache)
    guard case .failure = corrupt else { Issue.record("Expected corrupt-cache recovery"); return }
    #expect(try Data(contentsOf: cache.fileURL) == Data("corrupt".utf8))
}

@Test func successfulRefreshSavesFullResponse() async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let data = try Fixtures.data("route_today")
    let cache = RouteCache(directory: dir)
    let result = try await RouteRefresh.fetch(using: Stub { request in
        #expect(request.url?.path == "/v1/routes/today")
        return (200, data)
    }.api, cache: cache)
    guard case .loaded(let route, nil) = result else { Issue.record("Expected loaded and saved"); return }
    #expect(try cache.load() == route)
}

@Test func unknownEmbeddedEnumsSurviveFullRouteCache() throws {
    let data = try Fixtures.data("route_today")
    let original = try #require(String(data: data, encoding: .utf8))
    let json = original.replacingOccurrences(of: #""status": "flagged""#, with: #""status": "under_review""#)
        .replacingOccurrences(of: #""type": "FCBK""#, with: #""type": "Hoffmann""#)
    let route = try JSONDecoder.kilnWatch.decode(Route.self, from: Data(json.utf8))
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = RouteCache(directory: dir)
    try cache.save(route)
    let cached = try cache.load()
    let saved = try #require(cached)
    #expect(saved.kilns[0].status == .unknown("under_review"))
    #expect(saved.kilns[0].type == .unknown("Hoffmann"))
    #expect(saved.mapsURL(startingAt: "missing-id") == nil)
}

// MARK: - Integration 1 Python producer contract (explicitly synthetic)
private func bridgeData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "BridgeFixtures"))
    return try Data(contentsOf: url)
}

@Test func pythonCandidateContractPreservesUnknownFactsAndProvenance() throws {
    let list = try JSONDecoder.kilnWatch.decode(KilnList.self, from: bridgeData("list"))
    #expect(list.kilns.count == 2)
    for kiln in list.kilns {
        #expect(kiln.exposure == nil)
        #expect(kiln.violations.isEmpty && kiln.rulesAssessment == "not_evaluated")
        #expect(kiln.typeConfidence == 0.95 && !kiln.typeMayBePresentedAsCertain)
        #expect(kiln.typeVerification == "unverified" && kiln.status == .flagged)
        #expect(kiln.evidence.before == nil && kiln.evidence.after == nil)
        #expect(kiln.provenance?.confidenceSemantics == "predicted_class_score_shared")
        #expect(kiln.provenance?.acquiredAt == kiln.lastSeen)
        let roundTrip = try JSONDecoder.kilnWatch.decode(Kiln.self, from: JSONEncoder.kilnWatch.encode(kiln))
        #expect(roundTrip == kiln)
    }
    #expect(list.kilns.contains { $0.type == .unknown("Hoffmann") })
    let detail = try JSONDecoder.kilnWatch.decode(Kiln.self, from: bridgeData("detail"))
    let meta = try #require(detail.evidence.afterMetadata)
    #expect(meta.patchPx == 256 && meta.gsdM == 10 && meta.footprintPx?.count == 4)
    #expect(meta.acquiredAt == detail.lastSeen && detail.evidence.beforeMetadata == nil)
}

@Test func apiDecodesPythonEnvelopeDetailAndEveryPage() async throws {
    let list = try bridgeData("list"), detail = try bridgeData("detail")
    let page1 = try bridgeData("page1"), page2 = try bridgeData("page2")
    let expected = try JSONDecoder.kilnWatch.decode(KilnList.self, from: list).kilns
    let expectedDetail = try JSONDecoder.kilnWatch.decode(Kiln.self, from: detail)
    let stub = Stub { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        if request.url?.path.hasSuffix("/kilns/\(expectedDetail.kilnId)") == true { return (200, detail) }
        let hasCursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "cursor" } == true
        return (200, hasCursor ? page2 : page1)
    }
    #expect(try await stub.api.kilns(district: "Hapur", status: .flagged) == expected)
    #expect(try await stub.api.kiln(id: expectedDetail.kilnId) == expectedDetail)
}

@Test func repeatedPaginationCursorFailsInsteadOfReturningPartialRegistry() async throws {
    let page = try bridgeData("page1")
    let stub = Stub { _ in (200, page) }
    do {
        _ = try await stub.api.kilns(district: "Hapur")
        Issue.record("Expected repeated-cursor failure")
    } catch {
        guard case .invalidPagination = error else { Issue.record("Unexpected error: \(error)"); return }
    }
}

@Test func incompleteExposureCountsRemainMalformed() throws {
    var object = try #require(JSONSerialization.jsonObject(with: bridgeData("detail")) as? [String: Any])
    object["exposure"] = ["people": 0]
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) { try JSONDecoder.kilnWatch.decode(Kiln.self, from: data) }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["KILNWATCH_REAL_CONTRACT_LIST"] != nil))
func localRealDetectionContractDecodesThroughExistingClient() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["KILNWATCH_REAL_CONTRACT_LIST"])
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let records = try JSONDecoder.kilnWatch.decode(KilnList.self, from: data).kilns
    #expect(!records.isEmpty)
    #expect(records.allSatisfy { $0.status == .flagged && $0.exposure == nil && $0.rulesAssessment == "not_evaluated" && !$0.typeMayBePresentedAsCertain })
    #expect(records.allSatisfy { $0.evidence.before == nil && $0.evidence.after == nil }) // local, unpublished
    #expect(records.contains { $0.evidence.afterMetadata?.patchPx == 256 && $0.evidence.beforeMetadata != nil })
    let client = Stub { _ in (200, data) }
    #expect(try await client.api.kilns(district: "Hapur") == records)
}

// MARK: - Phase 3 public reads
private func publicBody(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "PublicFixtures"))
    return try Data(contentsOf: url)
}

@Test func publicCallsNeverAskForOrSendAToken() async throws {
    let detail = try publicBody("detail")
    let near = try publicBody("near")
    let stub = Stub { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.url?.path.hasPrefix("/public/kilns") == true)
        return (200, request.url?.path == "/public/kilns" ? near : detail)
    }
    let calls = Mutex(0)
    let api = KilnWatchAPI(baseURL: stub.api.baseURL.deletingLastPathComponent(), session: stub.api.session, token: {
        calls.withLock { $0 += 1 }; throw URLError(.userAuthenticationRequired)
    })
    #expect(try await api.publicKilns(district: "Hapur").count == 1)
    #expect(try await api.publicKilns(latitude: 28.73, longitude: 77.78, radiusM: 100).count == 1)
    #expect(try await api.publicKiln(id: "KW-6b3b38da681850e5af46b024f3d3f78e").typeConfidence == 0.324)
    #expect(calls.withLock { $0 } == 0)
}

@Test func publicSessionDisablesResponseCookieAndCredentialStorage() {
    let session = KilnWatchAPI.publicReadSession()
    defer { session.invalidateAndCancel() }
    let configuration = session.configuration
    #expect(configuration.urlCache == nil)
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    #expect(configuration.httpCookieStorage == nil)
    #expect(!configuration.httpShouldSetCookies)
    #expect(configuration.urlCredentialStorage == nil)
    #expect(configuration.identifier == nil)
}

@Test func publicDistrictPagingAndQueryEncoding() async throws {
    let first = try publicBody("page1")
    let second = try publicBody("page2")
    let page = try JSONDecoder.kilnWatch.decode(KilnList.self, from: first)
    let calls = Mutex(0)
    let stub = Stub { request in
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.first { $0.name == "district" }?.value == "Hapur & nearby / scan")
        let index = calls.withLock { c in c += 1; return c }
        if index == 1 { return (200, first) }
        #expect(query.first { $0.name == "cursor" }?.value == page.nextCursor)
        return (200, second.replacingJSONValue(key: "next_cursor", value: NSNull()))
    }
    let api = KilnWatchAPI(baseURL: stub.api.baseURL.deletingLastPathComponent(), session: stub.api.session)
    #expect(try await api.publicKilns(district: "Hapur & nearby / scan").count == 4)
    #expect(calls.withLock { $0 } == 2)
}

@Test func publicNearQueryUsesDocumentedKeys() async throws {
    let body = try publicBody("near")
    let stub = Stub { request in
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(Set(query.map(\.name)) == Set(["lat", "lon", "radius_m"]))
        #expect(query.first { $0.name == "lat" }?.value == "28.73")
        #expect(query.first { $0.name == "lon" }?.value == "77.78")
        #expect(query.first { $0.name == "radius_m" }?.value == "2000.0")
        return (200, body)
    }
    let api = KilnWatchAPI(baseURL: stub.api.baseURL.deletingLastPathComponent(), session: stub.api.session)
    #expect(try await api.publicKilns(latitude: 28.73, longitude: 77.78, radiusM: 2000).count == 1)
}

@Test(arguments: [400, 404, 429, 503, -1])
func publicFailuresRemainTyped(code: Int) async throws {
    let stub = Stub { _ in (code, Data(#"{"error":"unavailable"}"#.utf8)) }
    do {
        _ = try await stub.api.publicKiln(id: "missing")
        Issue.record("Expected public request failure")
    } catch {
        if code == -1 { guard case .transport = error else { Issue.record("Expected transport"); return } }
        else {
            guard case .status(let actual, _) = error else { Issue.record("Expected HTTP status"); return }
            #expect(actual == code)
            #expect(error.isSystemic == [429, 503].contains(code))
        }
    }
}

@Test(arguments: ["page1", "page2", "near", "detail"])
func recordedPublicBodiesDecode(name: String) throws {
    let data = try publicBody(name)
    let kilns = name == "detail" ? [try JSONDecoder.kilnWatch.decode(Kiln.self, from: data)]
                                : try JSONDecoder.kilnWatch.decode(KilnList.self, from: data).kilns
    #expect(!kilns.isEmpty)
    for kiln in kilns {
        #expect(kiln.status == .flagged && kiln.typeVerification == "unverified")
        #expect(kiln.exposure == nil && kiln.violations.isEmpty && kiln.rulesAssessment == "not_evaluated")
        #expect(kiln.provenance == nil)
        #expect(!kiln.typeMayBePresentedAsCertain)
    }
}

@Test(arguments: ["repeated", "empty", "emptyPage"])
func publicCursorProtection(kind: String) async throws {
    let first = try publicBody("page1")
    let stub = Stub { request in
        let hasCursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.contains { $0.name == "cursor" }
        if !hasCursor { return (200, first) }
        switch kind {
        case "empty": return (200, first.replacingJSONValue(key: "next_cursor", value: ""))
        case "emptyPage": return (200, first.replacingJSONValue(key: "kilns", value: []))
        default: return (200, first)
        }
    }
    do {
        _ = try await stub.api.publicKilns(district: "Hapur")
        Issue.record("Expected unsafe cursor rejection")
    } catch { guard case .invalidPagination = error else { Issue.record("Expected pagination error"); return } }
}

private extension Data {
    func replacingJSONValue(key: String, value: Any) -> Data {
        var object = (try? JSONSerialization.jsonObject(with: self)) as? [String: Any] ?? [:]
        object[key] = value
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}

@Test func evidenceLocalFixtureUsesTheImageLoadingPath() async throws {
    let url = try #require(Bundle.module.url(forResource: "image", withExtension: "png", subdirectory: "PublicFixtures"))
    let data = try await EvidenceImageData.load(from: url)
    #expect(data.starts(with: [137, 80, 78, 71]))
    // IHDR carries the actual 256 × 256 raster dimensions.
    #expect(Array(data[16..<24]) == [0, 0, 1, 0, 0, 0, 1, 0])
    let directory = tempDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let invalid = directory.appending(path: "invalid.png")
    try Data("not a PNG".utf8).write(to: invalid)
    do {
        _ = try await EvidenceImageData.load(from: invalid)
        Issue.record("Expected invalid image failure")
    } catch { #expect(error as? EvidenceImageError == .invalidPNG) }
}
