import Foundation
import Testing
@testable import KilnWatchCore
#if canImport(MapKit)
import MapKit
#endif

private func polishPlan() throws -> Route {
    let file = try #require(Bundle.module.url(forResource: "plan-people.recorded", withExtension: "json", subdirectory: "P1Fixtures"))
    return try JSONDecoder.kilnWatch.decode(Route.self, from: Data(contentsOf: file))
}

@Test func passedPlanUsesKolkataDayBoundary() throws {
    let route = try polishPlan()
    let parse = { (text: String) in try Date.ISO8601FormatStyle().parse(text) }
    #expect(!route.hasPassed(now: try parse("2026-10-10T23:59:59+05:30")))
    #expect(!route.hasPassed(now: try parse("2026-10-11T23:59:59+05:30")))
    #expect(route.hasPassed(now: try parse("2026-10-11T18:30:00Z")))
    #expect(route.dayLabel(now: try parse("2026-10-12T00:00:00+05:30"), locale: Locale(identifier: "en_GB")) == "Sun 11 Oct")
}

@Test func passedPlanFallsBackToFirstOrderedArrivalThenGeneratedDay() throws {
    let plan = try polishPlan()
    var body = try #require(JSONSerialization.jsonObject(with: JSONEncoder.kilnWatch.encode(plan)) as? [String: Any])
    body["depart"] = nil
    body["stops"] = (body["stops"] as? [[String: Any]])?.reversed().map { $0 }
    let arrivalPlan = try JSONDecoder.kilnWatch.decode(Route.self, from: JSONSerialization.data(withJSONObject: body))
    let now = try Date.ISO8601FormatStyle().parse("2026-10-11T18:30:00Z")
    #expect(arrivalPlan.hasPassed(now: now))
    body["stops"] = []
    body["generated_at"] = "2026-10-11T18:29:59Z"
    let empty = try JSONDecoder.kilnWatch.decode(Route.self, from: JSONSerialization.data(withJSONObject: body))
    #expect(empty.hasPassed(now: now))
    #expect(!empty.hasPassed(now: now.addingTimeInterval(-1)))
}

#if canImport(MapKit)
@Test func framingContainsEveryDrawnStopAndLegWithBoundedPadding() throws {
    for route in [try polishPlan(), Fixtures.route] {
        let rect = try #require(route.overviewRect())
        let ids = Set(route.usableStops.map(\.kilnId))
        let coordinates = route.kilns.filter { ids.contains($0.kilnId) }.map(\.footprint.centroid)
            + (route.legs ?? []).filter { ids.contains($0.toKilnId) }.flatMap { $0.geometry?.validatedCoordinates ?? [] }
        let points = coordinates.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        for point in points { #expect(rect.contains(point)) }
        let minX = try #require(points.map(\.x).min()), maxX = try #require(points.map(\.x).max())
        let minY = try #require(points.map(\.y).min()), maxY = try #require(points.map(\.y).max())
        #expect(minX - rect.minX >= 200 && minX - rect.minX <= 2_000)
        #expect(minY - rect.minY >= 200 && minY - rect.minY <= 2_000)
        #expect(rect.maxX - maxX <= 2_001 && rect.maxY - maxY <= 2_001)
        // A freshly loaded record can differ from the plan's embedded snapshot.
        let refreshed = Coordinate(latitude: 28.9, longitude: 77.9)
        let updatedRect = try #require(route.overviewRect(stopCoordinates: [refreshed]))
        #expect(updatedRect.contains(MKMapPoint(CLLocationCoordinate2D(latitude: refreshed.latitude, longitude: refreshed.longitude))))
    }
}

@Test func singletonFramingHasAMinimumAndEmptyFramingIsAbsent() throws {
    let route = try polishPlan()
    var body = try #require(JSONSerialization.jsonObject(with: JSONEncoder.kilnWatch.encode(route)) as? [String: Any])
    body["legs"] = nil
    body["stops"] = (body["stops"] as? [[String: Any]])?.prefix(1).map { $0 }
    let single = try JSONDecoder.kilnWatch.decode(Route.self, from: JSONSerialization.data(withJSONObject: body))
    let rect = try #require(single.overviewRect())
    #expect(rect.width == 401 && rect.height == 401)
    body["stops"] = []
    let empty = try JSONDecoder.kilnWatch.decode(Route.self, from: JSONSerialization.data(withJSONObject: body))
    #expect(empty.overviewRect() == nil)
}
#endif
