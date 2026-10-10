import XCTest
import UIKit

/// Sequential local harness; Ask scenarios intercept every request. Live mode sends GETs only.
final class Phase4cChecks: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private let reference = "KW-00000000000000000000000000000001"
    @MainActor private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kilnwatch.inspector")
        app.launchArguments = ["-autoplay", "none", "-askPlay", "NO"] + args
        app.launch(); return app
    }
    @MainActor private func text(_ app: XCUIApplication, _ value: String, timeout: Double = 10) {
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", value)).firstMatch.waitForExistence(timeout: timeout), value)
    }
    @MainActor private func reveal(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        let element = app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
        for _ in 0..<14 {
            if element.exists && element.isHittable { return element }
            app.swipeUp()
        }
        return element
    }
    @MainActor private func shot(_ name: String, _ app: XCUIApplication) throws {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }
    @MainActor func testRecordedListDetailSourcesAndPrefill() throws {
        let app = launch(["-rulesDemo", "recorded", "-tab", "kilns"])
        text(app, "Sample data"); text(app, "HAPUR · 3 KILNS"); text(app, ExposureText.attribution)
        text(app, "4,225 modelled residents within 800 m")
        text(app, "C-HAB-800 · 497\u{00A0}m · requires 800\u{00A0}m")
        try shot("recorded-list-attribution", app)
        app.buttons["kiln-row-" + reference].firstMatch.tap()
        text(app, reference); text(app, "Flagged by satellite · pending inspection")
        let result = reveal(app, "497\u{00A0}m · requires 800\u{00A0}m")
        XCTAssertTrue(result.isHittable); try shot("recorded-reference-flags", app)
        app.buttons["C-HAB-800"].firstMatch.tap()
        text(app, "Rule source"); text(app, "497\u{00A0}m · applied threshold 800\u{00A0}m")
        text(app, "Secondary sources · gazette text not checked")
        try shot("recorded-secondary-source", app)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(reveal(app, "4,225").isHittable)
        text(app, "430 under 5 · 294 over 60"); try shot("recorded-reference-exposure", app)
        for _ in 0..<10 { if app.buttons["Ask about this kiln"].isHittable { break }; app.swipeUp() }
        app.buttons["Ask about this kiln"].tap()
        let composer = app.descendants(matching: .any)["ask-composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Explain this kiln's registry record: " + reference)
        XCTAssertFalse(app.staticTexts["Waiting for an answer…"].exists)
    }
    @MainActor func testRecordedZeroFlagsAndUnverifiedSource() throws {
        let app = launch(["-rulesDemo", "recorded", "-tab", "kilns", "-open", "KW-00000000000000000000000000000002", "-scroll", "rules"])
        text(app, "No rule flags measured")
        text(app, "Some rules could not be checked from map data. Check on site.")
        try shot("recorded-zero-flags-partial", app)
        let flagged = launch(["-rulesDemo", "recorded", "-tab", "kilns", "-open", "KW-00000000000000000000000000000003", "-scroll", "rules"])
        text(flagged, "Unverified threshold")
        // This recorded example carries a railway siting flag.
        let chip = flagged.buttons["UP-RAIL-200"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5)); chip.tap()
        text(flagged, "Rule source"); text(flagged, "Unverified threshold")
        try shot("recorded-unverified-source", flagged)
        flagged.buttons["Close"].firstMatch.tap()
    }
    @MainActor func testSyntheticStatesAndPopulationEdges() throws {
        let app = launch(["-rulesDemo", "states", "-tab", "kilns", "-open", reference, "-scroll", "ruleChecks", "-checksExpanded", "YES"])
        text(app, "Siting flag · needs inspection")
        XCTAssertTrue(reveal(app, "Beyond threshold").isHittable)
        text(app, "No mapped feature found within the 1,000\u{00A0}m threshold. Nearest distance unavailable.")
        try shot("synthetic-checks-distance", app)
        XCTAssertTrue(reveal(app, "Inconclusive · map data incomplete").isHittable)
        text(app, "1,200\u{00A0}m · applied threshold 800\u{00A0}m")
        XCTAssertTrue(reveal(app, "Not evaluated · no usable data").isHittable)
        try shot("synthetic-checks-unfinished", app)
        XCTAssertTrue(reveal(app, "Not applicable").isHittable)
        XCTAssertTrue(reveal(app, "Check state unavailable · unsupported result").isHittable)
        // Previous screenshot includes the unknown state without an extra duplicate.
        let missing = launch(["-rulesDemo", "missing", "-tab", "kilns", "-open", reference, "-scroll", "exposure"])
        text(missing, "Population exposure not assessed"); try shot("synthetic-missing-exposure", missing)
        let zero = launch(["-rulesDemo", "zero", "-tab", "kilns", "-open", reference, "-scroll", "exposure"])
        text(zero, "0 under 5 · 0 over 60"); text(zero, "0")
        try shot("synthetic-zero-exposure", zero)
    }
    @MainActor func testAskRecordedAndMixedNavigation() throws {
        let app = launch(["-askDemo", "r1Recorded", "-rulesDemo", "recorded", "-tab", "ask", "-askPlay", "YES"])
        text(app, "1 step"); XCTAssertFalse(app.buttons["C-HAB-800"].exists)
        XCTAssertTrue(app.buttons[reference].firstMatch.waitForExistence(timeout: 5))
        try shot("recorded-ask-prose-rule", app)
        app.buttons[reference].firstMatch.tap(); text(app, reference)
        app.navigationBars.buttons.firstMatch.tap()
        let mixed = launch(["-askDemo", "r1Mixed", "-rulesDemo", "recorded", "-tab", "ask", "-askPlay", "YES"])
        text(mixed, "2 steps"); mixed.buttons["2 steps"].tap()
        text(mixed, "Gathering evidence again"); text(mixed, "Invalid tool input")
        text(mixed, "Tool input wasn't accepted"); mixed.buttons["2 steps"].tap()
        XCTAssertTrue(mixed.buttons["C-HAB-800"].firstMatch.waitForExistence(timeout: 5))
        try shot("synthetic-ask-mixed", mixed)
        mixed.buttons["C-HAB-800"].firstMatch.tap()
        text(mixed, "Rule source"); text(mixed, "Reference only. No kiln measurement or check result supplied.")
        try shot("synthetic-ask-rule-reference", mixed)
        mixed.buttons["Close"].firstMatch.tap()
        mixed.buttons["C-FUTURE-2K"].firstMatch.tap(); text(mixed, "Rule details unavailable")
        text(mixed, "Threshold verification unavailable"); mixed.buttons["Close"].firstMatch.tap()
        mixed.buttons[reference].firstMatch.tap(); text(mixed, reference)
    }
    @MainActor func testAppearance() throws {
        let app = launch(["-rulesDemo", "recorded", "-tab", "kilns", "-open", reference, "-scroll", "exposure"])
        text(app, "4,225"); text(app, "430 under 5 · 294 over 60")
        let suffix = ProcessInfo.processInfo.environment["RULES_CAPTURE_SUFFIX"] ?? "appearance"
        try shot("recorded-" + suffix, app)
        XCTAssertTrue(reveal(app, ExposureText.attribution).isHittable)
        app.swipeUp() // Show the end of the wrapping attribution at accessibility sizes.
        try shot("recorded-attribution-" + suffix, app)
        if ProcessInfo.processInfo.environment["RULES_REDUCE_MOTION"] == "YES" { XCTAssertTrue(UIAccessibility.isReduceMotionEnabled) }
        let chip = app.buttons["C-HAB-800"].firstMatch
        for _ in 0..<14 { if chip.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(chip.isHittable); chip.tap(); text(app, "Rule source")
        XCTAssertTrue(reveal(app, "Secondary sources · gazette text not checked").isHittable)
        try shot("recorded-source-" + suffix, app)
        app.buttons["Close"].firstMatch.tap()
    }
    @MainActor func testTodayAndFixtures() throws {
        let publicApp = launch(["-rulesDemo", "recorded", "-tab", "today"])
        text(publicApp, "Route planning isn't available yet")
        let sample = launch(["-fixtures", "YES", "-signedIn", "YES", "-tab", "kilns", "-open", "KW-0412", "-scroll", "exposure"])
        text(sample, "Sample data"); text(sample, "Sample population figures · illustrative, not an HRSL calculation")
        XCTAssertTrue(sample.buttons["Record verdict"].exists)
    }
    @MainActor func testLiveZeroAndList() throws {
        let id = try XCTUnwrap(ProcessInfo.processInfo.environment["RULES_ZERO_ID"])
        let app = launch(["-tab", "kilns", "-open", id, "-scroll", "rules", "-askPlay", "NO"])
        text(app, "Live data"); text(app, "No rule flags measured", timeout: 35)
        text(app, "Some rules could not be checked from map data. Check on site.")
        try shot("live-zero-flags-partial", app)
        app.navigationBars.buttons.firstMatch.tap()
        text(app, "HAPUR · 39 KILNS"); text(app, ExposureText.attribution)
        try shot("live-list-attribution", app)
    }
    @MainActor func testLiveGETScreens() throws {
        let reference = "KW-6b3b38da681850e5af46b024f3d3f78e"
        let app = launch(["-tab", "kilns", "-open", reference, "-scroll", "rules"])
        text(app, "Live data"); text(app, "497\u{00A0}m · requires 800\u{00A0}m", timeout: 35)
        try shot("live-reference-flags", app)
        XCTAssertTrue(reveal(app, "4,225").isHittable)
        text(app, "430 under 5 · 294 over 60"); try shot("live-reference-exposure", app)
        // Same live session: inspect existing published per-kiln imagery, without any POST.
        let comparator = app.descendants(matching: .any)["satellite-comparator"].firstMatch
        XCTAssertTrue(comparator.waitForExistence(timeout: 25))
        for _ in 0..<8 { if comparator.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(comparator.isHittable)
        try shot("live-published-imagery", app)
        XCTAssertFalse(app.buttons["Record verdict"].exists)
    }
}
private enum ExposureText {
    static let attribution = "Modelled estimate of residents within 800 m of the kiln edge. Population: Meta and CIESIN High Resolution Settlement Layer (HRSL) v1.5.2, CC BY 4.0. Age groups are modelled shares of the same estimate."
}
