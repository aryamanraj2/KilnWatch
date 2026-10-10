import Foundation
import Testing
@testable import KilnWatchCore

func r1Fixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "R1Fixtures")))
}
private func r1Record(_ changes: [String: Any] = [:]) throws -> Kiln {
    var object = try #require(JSONSerialization.jsonObject(with: r1Fixture("detail.recorded")) as? [String: Any])
    for (key, value) in changes { object[key] = value }
    return try JSONDecoder.kilnWatch.decode(Kiln.self, from: JSONSerialization.data(withJSONObject: object))
}
@Test func recordedR1RegistryRelationshipsAndRoundTrip() throws {
    let list = try JSONDecoder.kilnWatch.decode(KilnList.self, from: r1Fixture("list.recorded"))
    let detail = try r1Record()
    #expect(list.kilns.count == 39 && list.nextCursor == nil)
    #expect(list.kilns.reduce(0) { $0 + $1.violations.count } == 52)
    #expect(list.kilns.filter { !$0.violations.isEmpty }.count == 36)
    #expect(list.kilns.allSatisfy { $0.ruleChecks?.count == 8 && $0.exposure != nil && $0.rulesAssessment == "partially_evaluated" })
    #expect(detail.ruleChecks?.count == 8 && detail.violations.count == 1)
    #expect(detail.violations.first?.measuredDistanceM == 497 && detail.violations.first?.thresholdM == 800)
    #expect(detail.exposure?.people == 4225 && detail.exposure?.childrenUnderFive == 430 && detail.exposure?.adultsOverSixty == 294)
    #expect(detail.violations.first?.evidenceUrl == nil)
    #expect(detail.ruleChecks?.first?.status == .withinThreshold)
    #expect(detail.ruleChecks?.first?.verification == .secondarySources)
    #expect(try JSONDecoder.kilnWatch.decode(Kiln.self, from: JSONEncoder.kilnWatch.encode(detail)) == detail)
    for kiln in list.kilns {
        for flag in kiln.violations {
            let check = try #require(kiln.ruleChecks?.first { $0.ruleId == flag.ruleId })
            #expect(check.status == .withinThreshold && check.measuredDistanceM == flag.measuredDistanceM && check.thresholdM == flag.thresholdM && check.source == flag.source)
        }
    }
}
@Test func zeroFlagPartialAssessmentNeverImpliesCompletion() throws {
    let list = try JSONDecoder.kilnWatch.decode(KilnList.self, from: r1Fixture("list.recorded"))
    let records = list.kilns.filter { $0.violations.isEmpty }
    #expect(records.count == 3)
    for kiln in records {
        #expect(kiln.assessmentNote?.contains("Some rules could not be checked") == true)
        #expect(kiln.ruleChecks?.contains { $0.status == .inconclusive } == true)
        #expect(kiln.ruleChecks?.contains { $0.status == .notEvaluated } == true)
    }
}
@Test func legacyEmptyAndMissingChecksDoNotManufactureAssessment() throws {
    #expect(Fixtures.route.kilns.allSatisfy { $0.ruleChecks == nil })
    let legacy = try r1Record(["rule_checks": NSNull(), "rules_assessment": NSNull()])
    #expect(legacy.ruleChecks == nil && legacy.violations.count == 1 && legacy.assessmentNote?.contains("unavailable") == true)
    let empty = try r1Record(["rule_checks": [], "rules_assessment": "not_evaluated", "exposure": NSNull(), "violations": []])
    #expect(empty.ruleChecks == [] && empty.exposure == nil && empty.assessmentNote?.contains("not evaluated") == true)
    let incomplete = try r1Record(["rule_checks": [], "rules_assessment": "evaluated"])
    #expect(incomplete.assessmentNote?.contains("unavailable") == true)
}
@Test(arguments: ["within_threshold", "beyond_threshold", "inconclusive", "not_evaluated", "not_applicable", "future_status"])
func checkStatesRetainWireAndHonestLabels(raw: String) throws {
    let data = Data(#"{"rule_id":"C-FUTURE-2K","check":"Supplied check","status":"\#(raw)","threshold_m":800,"measured_distance_m":1200,"verification":"future_verification","source":"Supplied source"}"#.utf8)
    let check = try JSONDecoder.kilnWatch.decode(RuleCheck.self, from: data)
    #expect(check.status.rawValue == raw && check.verification == .unknown("future_verification"))
    #expect(check.verification?.label == "Threshold verification unavailable")
    #expect(check.source == "Supplied source" && check.ruleId == "C-FUTURE-2K")
    if raw == "inconclusive" { #expect(check.status.label == "Inconclusive · map data incomplete") }
    if raw == "not_applicable" { #expect(check.status.label == "Not applicable") }
    if raw == "future_status" { #expect(check.status.label.contains("unavailable")) }
    #expect(try JSONDecoder.kilnWatch.decode(RuleCheck.self, from: JSONEncoder.kilnWatch.encode(check)) == check)
}
@Test func verificationAndMissingMeasurementsStaySeparate() throws {
    let body = try r1Fixture("detail.recorded")
    let kiln = try JSONDecoder.kilnWatch.decode(Kiln.self, from: body)
    let tech = try #require(kiln.ruleChecks?.first { $0.ruleId == "C-TECH-10K" })
    #expect(tech.status == .notEvaluated && tech.verification == .unverifiedCompilation)
    #expect(tech.verification?.label == "Unverified threshold")
    #expect(tech.measuredDistanceM == nil && tech.thresholdM == nil)
    #expect(tech.measurementLine == "Distance unavailable · threshold unavailable")
    let beyond = try JSONDecoder.kilnWatch.decode(RuleCheck.self, from: Data(#"{"rule_id":"UP-NH-300","check":"Road","status":"beyond_threshold","threshold_m":300,"measured_distance_m":null,"source":"Local source"}"#.utf8))
    #expect(beyond.verification == nil && beyond.measurementLine.contains("No mapped feature found") && beyond.measurementLine.contains("Nearest distance unavailable"))
    #expect(ThresholdVerification.secondarySources.explanation.contains("gazette text"))
}
@Test func invalidBarsAndAssessedZerosArePreserved() throws {
    #expect(RuleCheck.canDrawBar(measured: 0, threshold: 800))
    for pair: (Double?, Double?) in [(nil,800),(1,nil),(1,0),(-1,800),(.nan,800),(1,.infinity)] {
        #expect(!RuleCheck.canDrawBar(measured: pair.0, threshold: pair.1))
    }
    #expect(RuleCheck.metres(0) == "0\u{00A0}m" && RuleCheck.metres(nil) == nil)
    let measuredZero = try JSONDecoder.kilnWatch.decode(RuleCheck.self, from: Data(#"{"rule_id":"C-HAB-800","check":"Homes","status":"within_threshold","threshold_m":800,"measured_distance_m":0,"verification":null,"source":"Local"}"#.utf8))
    #expect(measuredZero.measuredDistanceM == 0 && measuredZero.verification == nil)
    #expect(measuredZero.measurementLine == "0\u{00A0}m · applied threshold 800\u{00A0}m")
    let zero = try r1Record(["exposure": ["people": 0, "children_under_five": 0, "adults_over_sixty": 0]])
    let missing = try r1Record(["exposure": NSNull()])
    #expect(zero.exposure?.people == 0 && zero.exposure?.childrenUnderFive == 0 && zero.exposure?.adultsOverSixty == 0)
    #expect(missing.exposure == nil)
    #expect(throws: DecodingError.self) { try r1Record(["exposure": ["people": 0]]) }
    #expect(Exposure.attribution.contains("kiln edge") && Exposure.attribution.contains("CC BY 4.0"))
}
