import Foundation
import Synchronization
import Testing
@testable import KilnWatchCore

private func planFixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "P1Fixtures")))
}
private func planDirectory() -> URL { FileManager.default.temporaryDirectory.appending(path: "KilnWatchP1-\(UUID().uuidString)") }
private func errorBody(_ code: String, retryable: Bool) -> Data {
    Data(#"{"error":{"code":"\#(code)","message":"Server text that must never be shown","retryable":\#(retryable)}}"#.utf8)
}

@Test func planPOSTSendsExactPublicBody() async throws {
    let data = try planFixture("plan-people.recorded"); let calls = Mutex(0)
    let stub = AskStub { request in
        calls.withLock { $0 += 1 }
        #expect(request.httpMethod == "POST" && request.url?.path == "/v1/routes/plan")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.timeoutInterval == 35 && request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(String(decoding: readBody(request), as: UTF8.self) == #"{"district":"Hapur","max_stops":8,"priority":"people"}"#)
        return (200, data)
    }
    let route = try await stub.api.planRoute(district: "Hapur")
    #expect(route.stops.count == 8 && route.legs?.count == 8 && route.notes?.count == 4)
    #expect(calls.withLock { $0 } == 1)
}

@Test(arguments: [("plan-people.recorded", 8, 4), ("plan-start.recorded", 5, 3)])
func recordedPlansDecode(name: String, stops: Int, notes: Int) throws {
    let route = try JSONDecoder.kilnWatch.decode(Route.self, from: planFixture(name))
    #expect(route.stops.count == stops && route.legs?.count == stops && route.usableStops.count == stops)
    #expect(route.notes?.count == notes && route.notes?.contains("Access points are kiln centroids, not verified entrances.") == true)
    #expect(route.stops.allSatisfy { $0.access?.note == "Kiln centroid, not a verified entrance · confirm on site" && $0.access?.coordinate.isValid == true })
    #expect(route.legs?.allSatisfy { $0.geometry?.validatedCoordinates.isEmpty == false } == true)
    #expect(route.predictedSeconds != nil && route.depart != nil)
    #expect(route.stops.allSatisfy { AskRequest.isFullKilnID($0.kilnId) })
}

@Test func emptyFlagStopStaysInThePlan() throws {
    let route = try JSONDecoder.kilnWatch.decode(Route.self, from: planFixture("plan-people.recorded"))
    let stop = try #require(route.stops.first { $0.sheet.rulesFlagged.isEmpty })
    let kiln = try #require(route.kilns.first { $0.kilnId == stop.kilnId })
    #expect(route.usableStops.contains(stop) && kiln.status == .flagged)
    #expect(kiln.assessmentNote == "Some rules could not be checked from map data. Check on site.")
}

@Test func notesAreOptionalForOlderRoutesAndRoundTripInCache() throws {
    #expect(Fixtures.route.notes == nil)
    let cache = RouteCache(directory: planDirectory())
    try cache.save(Fixtures.route)
    #expect(try cache.load()?.notes == nil)
    let plan = try JSONDecoder.kilnWatch.decode(Route.self, from: planFixture("plan-people.recorded"))
    try cache.save(plan)
    #expect(try cache.load() == plan)
}

@Test func planWithoutLegsKeepsStopsAndInventsNoTotal() throws {
    var object = try #require(JSONSerialization.jsonObject(with: planFixture("plan-people.recorded")) as? [String: Any])
    object["legs"] = nil
    let route = try JSONDecoder.kilnWatch.decode(Route.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(route.legs == nil && route.usableStops.count == 8 && route.predictedSeconds == nil)
    #expect(!route.summary(stopCount: 8).contains("est.") && route.summary(stopCount: 8).hasPrefix("8 stops · leave "))
    #expect(route.stops.allSatisfy { !route.arrival(for: $0, compact: true).contains("drive") })
}

@Test(arguments: [
    (400, "recorded", "The plan request was rejected.", false),
    (404, "no_kilns", "No flagged kilns with population estimates in Hapur to plan.", false),
    (429, "daily_cap_reached", "Route planning has reached today's limit. It resets at 05:30 IST (00:00 UTC).", false),
    (429, "gateway", "Too many requests. Wait a moment.", true),
    (503, "routing_unavailable", "Route planning is unavailable right now.", true),
    (503, "upstream_unavailable", "Route planning is unavailable right now.", true),
    (503, "routing_final", "Route planning is unavailable right now.", false),
    (-1009, "offline", "You're offline. Reconnect to plan a route.", true),
    (-1001, "timeout", "The plan took too long to arrive. Check your connection and try again.", true),
    (200, "undecodable", "The plan could not be read.", false),
    (200, "noStops", "The plan could not be read.", false),
    (418, "future_code", "Route planning failed. Try again later.", false),
])
func planErrorsAreTypedAndWorded(status: Int, kind: String, message: String, retry: Bool) async throws {
    let body: Data = switch kind {
    case "recorded": try planFixture("plan-invalid.recorded")
    case "gateway": Data(#"{"message":"Too Many Requests"}"#.utf8)
    case "routing_final": errorBody("routing_unavailable", retryable: false)
    case "undecodable": Data(#"{"stops":"no"}"#.utf8)
    case "noStops": Data(#"{"district":"Hapur","generated_at":"2026-10-10T11:09:57Z","stops":[],"kilns":[]}"#.utf8)
    default: errorBody(kind, retryable: status == 503)
    }
    let stub = AskStub { _ in (status, body) }
    do {
        _ = try await stub.api.planRoute(district: "Hapur")
        Issue.record("Expected a plan error")
    } catch {
        #expect(error.message(district: "Hapur") == message)
        #expect(error.canRetry == retry)
        #expect(error.isDailyCap == (kind == "daily_cap_reached"))
        #expect(!error.message(district: "Hapur").contains("Server text"))
        if kind == "gateway" { #expect(error == .gatewayThrottled) }
    }
}

@MainActor @Test func failedPlanKeepsSavedPlanAndSuccessReplacesIt() async throws {
    let cache = RouteCache(directory: planDirectory())
    let saved = try JSONDecoder.kilnWatch.decode(Route.self, from: planFixture("plan-start.recorded"))
    try cache.save(saved)
    let replies = Mutex([(503, errorBody("routing_unavailable", retryable: true)), (-1009, Data()), (200, try planFixture("plan-people.recorded"))])
    let planner = RoutePlanner(api: AskStub { _ in replies.withLock { $0.removeFirst() } }.api, district: "Hapur", cache: cache)
    #expect(await planner.plan() == nil && planner.failure == .service(status: 503, detail: AskServiceError(code: "routing_unavailable", message: "Server text that must never be shown", retryable: true)))
    #expect(try cache.load() == saved && planner.canPlan())
    #expect(await planner.plan() == nil && planner.failure == .transport(.notConnectedToInternet))
    #expect(try cache.load() == saved)
    let result = try #require(await planner.plan())
    #expect(result.route.stops.count == 8 && result.cacheWarning == nil && planner.failure == nil)
    #expect(try cache.load() == result.route && planner.attempts == 3)
}

@MainActor @Test func launchPathAndInitSendNoRequest() async throws {
    let calls = Mutex(0)
    let cache = RouteCache(directory: planDirectory())
    try cache.save(JSONDecoder.kilnWatch.decode(Route.self, from: planFixture("plan-people.recorded")))
    let planner = RoutePlanner(api: AskStub { _ in calls.withLock { $0 += 1 }; return (500, Data()) }.api, district: "Hapur", cache: cache)
    #expect(try await RouteRefresh.saved(in: cache)?.stops.count == 8)
    #expect(calls.withLock { $0 } == 0 && planner.attempts == 0 && !planner.isPlanning)
}

@MainActor @Test func doubleTapSendsOnePlanAndDailyCapBlocksUntilUTCMidnight() async throws {
    let calls = Mutex(0)
    let planner = RoutePlanner(api: AskStub { _ in
        calls.withLock { $0 += 1 }; return (429, errorBody("daily_cap_reached", retryable: false))
    }.api, district: "Hapur", cache: RouteCache(directory: planDirectory()))
    async let first = planner.plan()
    async let second = planner.plan()
    _ = await (first, second)
    #expect(calls.withLock { $0 } == 1 && planner.attempts == 1)
    #expect(!planner.canPlan() && planner.failure?.isDailyCap == true)
    #expect(await planner.plan() == nil && calls.withLock { $0 } == 1)
    #expect(planner.canPlan(now: .now.addingTimeInterval(86_401)))
}

@Test func estimatedTimesNeverShowABareETA() throws {
    let route = try JSONDecoder.kilnWatch.decode(Route.self, from: planFixture("plan-people.recorded"))
    for candidate in [route, Fixtures.route] {
        for stop in candidate.stops {
            let compact = candidate.arrival(for: stop, compact: true), full = candidate.arrival(for: stop, compact: false)
            #expect(compact.hasPrefix("Est. ") && full.hasPrefix("Estimated arrival "))
            #expect(!compact.contains("ETA") && !full.contains("ETA"))
        }
        #expect(!candidate.summary(stopCount: candidate.stops.count).contains("ETA"))
    }
    #expect(route.summary(stopCount: 8).range(of: #"^8 stops · est\. \d+\sh \d+\sm · leave 09:00$"#, options: .regularExpression) != nil)
    #expect(route.arrival(for: route.stops[0], compact: true).range(of: #"^Est\. \d{2}:\d{2} · \d+\smin drive$"#, options: .regularExpression) != nil)
    let gb = Locale(identifier: "en_GB")
    let ist = { (s: String) in try Date.ISO8601FormatStyle().parse(s) }
    #expect(route.dayLabel(now: try ist("2026-10-10T12:00:00+05:30"), locale: gb) == "Tomorrow")
    #expect(route.dayLabel(now: try ist("2026-10-11T08:00:00+05:30"), locale: gb) == "Today")
    #expect(route.dayLabel(now: try ist("2026-10-09T12:00:00+05:30"), locale: gb) == "Sun 11 Oct")
}
