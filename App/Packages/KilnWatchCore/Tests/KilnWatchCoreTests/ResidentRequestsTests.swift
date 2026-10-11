import Foundation
import Testing
@testable import KilnWatchCore

private struct RequestFixture: Decodable {
    let kilnId: String
    let created: Bool
    let residentRequests: ResidentRequests
}

private func requestFixture() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "requests-recorded", withExtension: "json", subdirectory: "RequestFixtures"))
    return try Data(contentsOf: url)
}

private func requestRecord(_ requests: Any?) throws -> Kiln {
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.kilnWatch.encode(Fixtures.kilns[0])) as? [String: Any])
    object["resident_requests"] = requests
    return try JSONDecoder.kilnWatch.decode(Kiln.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func recordedRequestsDecodeAndRetainDateOnlyAndConcernCounts() throws {
    let fixture = try JSONDecoder.kilnWatch.decode(RequestFixture.self, from: requestFixture())
    let requests = fixture.residentRequests
    #expect(fixture.created && fixture.kilnId == "KW-0123456789abcdef0123456789abcdef")
    #expect(requests.count == 12 && requests.within1Km == 8)
    #expect(requests.concerns.smokeOrAsh == 9 && requests.concerns.nearHomes == 7)
    #expect(requests.concerns.nearSchoolOrHospital == 2 && requests.concerns.other == 1)
    #expect(requests.lastRequestOn == "2026-10-11")
    let body = try #require(JSONSerialization.jsonObject(with: requestFixture()) as? [String: Any])
    let kiln = try requestRecord(body["resident_requests"])
    #expect(kiln.residentRequests == requests)
    let encoded = try JSONEncoder.kilnWatch.encode(kiln)
    let cached = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let aggregate = try #require(cached["resident_requests"] as? [String: Any])
    #expect(aggregate["within_1km"] as? Int == 8)
    #expect(try JSONDecoder.kilnWatch.decode(Kiln.self, from: encoded) == kiln)
}

@Test func missingLegacyRequestDataDoesNotBecomeAnAuthoritativeZero() throws {
    #expect(Fixtures.kilns.allSatisfy { $0.residentRequests == nil })
    #expect(Fixtures.route.kilns.allSatisfy { $0.residentRequests == nil })
    #expect(try requestRecord(nil).residentRequests == nil)
    #expect(try requestRecord(NSNull()).residentRequests == nil)
}

@Test func authoritativeRequestZeroSurvivesListAndRouteCache() throws {
    let zero: [String: Any] = ["count": 0, "within_1km": 0,
        "concerns": ["smoke_or_ash": 0, "near_homes": 0, "near_school_or_hospital": 0, "other": 0],
        "last_request_on": NSNull()]
    let kiln = try requestRecord(zero)
    #expect(kiln.residentRequests?.count == 0 && kiln.residentRequests?.within1Km == 0)
    #expect(kiln.residentRequests?.lastRequestOn == nil)
    let list = KilnList(kilns: [kiln], nextCursor: nil)
    #expect(try JSONDecoder.kilnWatch.decode(KilnList.self, from: JSONEncoder.kilnWatch.encode(list)).kilns == [kiln])
    let route = Route(district: "Hapur", generatedAt: .now, stops: [], kilns: [kiln])
    #expect(try JSONDecoder.kilnWatch.decode(Route.self, from: JSONEncoder.kilnWatch.encode(route)).kilns == [kiln])
}

@Test func malformedRequestCountsFailRatherThanManufacturingZero() throws {
    let zero: [String: Any] = ["count": 0, "within_1km": 0,
        "concerns": ["smoke_or_ash": 0, "near_homes": 0, "near_school_or_hospital": 0, "other": 0]]
    var missing = zero
    missing["within_1km"] = nil
    #expect(throws: DecodingError.self) { try requestRecord(missing) }
    var badType = zero
    badType["count"] = "unknown"
    #expect(throws: DecodingError.self) { try requestRecord(badType) }
    var missingConcern = zero
    missingConcern["concerns"] = ["smoke_or_ash": 0]
    #expect(throws: DecodingError.self) { try requestRecord(missingConcern) }
}
