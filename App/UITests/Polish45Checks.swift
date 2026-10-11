import XCTest
import UIKit

/// Local phase-45 rehearsal. Run through the temporary UI harness described in the report.
/// Every launch intercepts HTTP in PublicDemo and prevents verdict outbox delivery.
final class Polish45Checks: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(_ extra: [String] = [], rules: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kilnwatch.inspector")
        app.launchArguments = ["-readOnly", "YES", "-autoplay", "none"] +
            (rules ? ["-publicDemo", "loaded", "-rulesDemo", "recorded", "-requestsDemo", "recorded", "-evidenceFixture", "loaded"] : ["-planDemo", "recorded"]) + extra
        app.launch(); return app
    }
    @MainActor private func save(_ name: String, _ app: XCUIApplication) throws {
        // Only for captures: let the existing 0.42 s layout token finish and clear the press highlight.
        // Network and interaction assertions above always use condition-based waits.
        Thread.sleep(forTimeInterval: 0.6)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
        try app.debugDescription.write(to: dir.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
    }
    @MainActor private func reveal(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        for _ in 0..<5 { if element.isHittable { return element }; app.swipeUp() }
        for _ in 0..<10 { if element.isHittable { return element }; app.swipeDown() }
        return element
    }
    @MainActor func testRouteSelectionAndDetail() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["Start route"].waitForExistence(timeout: 15))
        let pin3 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Stop 3,'")).firstMatch
        let pin4 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Stop 4,'")).firstMatch
        XCTAssertTrue(pin3.waitForExistence(timeout: 10)); XCTAssertTrue(pin4.waitForExistence(timeout: 10))
        XCTAssertTrue(pin3.isHittable); XCTAssertTrue(pin4.isHittable)
        // Snapshot only after MapKit annotations are available.
        try save("today-after", app)
        XCTAssertFalse(pin3.frame.intersects(pin4.frame), "Close-stop touch targets should separate")
        for (pin, id) in [(pin3,"KW-d1000000000000000000000000000003"), (pin4,"KW-d1000000000000000000000000000004")] {
            pin.tap()
            XCTAssertTrue(app.buttons["Navigate to " + id].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Navigate to " + id].isHittable)
            XCTAssertTrue(app.buttons["Start route"].exists)
        }
        try save("close-stop-4-after", app)
        app.buttons["Route list"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5)); app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Navigate to KW-d1000000000000000000000000000004"].exists)
    }
    @MainActor func testKilnDisclosuresAndVerdictCancel() throws {
        let app = launch(["-open", "KW-0123456789abcdef0123456789abcdef"], rules: true)
        XCTAssertTrue(app.buttons["Record verdict"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.otherElements.matching(NSPredicate(format: "label CONTAINS 'Synthetic before and after'")).firstMatch.waitForExistence(timeout: 8) || app.staticTexts["Synthetic local image fixture · not satellite evidence"].exists)
        try save("kiln-after", app)
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More siting flags'")).firstMatch
        if more.exists { reveal(app, more.label).tap() }
        let checks = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'All supplied checks'")).firstMatch
        XCTAssertTrue(checks.exists)
        reveal(app, checks.label).tap(); try save("kiln-expanded-after", app)
        let request = reveal(app, "Concerns, distance and latest request")
        XCTAssertTrue(request.isHittable); request.tap(); try save("requests-expanded-after", app)
        app.buttons["Record verdict"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Compliant'")).firstMatch.exists)
        try save("verdict-after", app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Record verdict"].waitForExistence(timeout: 5))
    }
    @MainActor func testReviewDisclosureAndNavigation() throws {
        let app = launch(["-tab", "review", "-reviewDetailDemo", "YES"], rules: true)
        XCTAssertTrue(app.staticTexts["Changes since Dec 2023 · pending review"].waitForExistence(timeout: 15))
        try save("review-after", app)
        app.buttons["Reason and scores"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'This item needs review because'")).firstMatch.exists)
        try save("review-expanded-after", app)
        let record = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'KW-'")).firstMatch
        XCTAssertTrue(record.isHittable); record.tap()
        XCTAssertTrue(app.buttons["Record verdict"].waitForExistence(timeout: 10))
        try save("review-navigation-after", app)
        app.navigationBars.buttons.firstMatch.tap()
        let historical = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Not in registry'")).firstMatch
        for _ in 0..<20 { if historical.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(historical.isHittable); historical.tap()
        XCTAssertTrue(app.staticTexts["Review location"].waitForExistence(timeout: 5) || app.navigationBars["Review location"].exists)
        try save("review-historical-after", app)
    }
    @MainActor func testAskKeyboardWaitingAndAnswer() throws {
        let app = launch(["-publicDemo", "loaded", "-askDemo", "waiting", "-tab", "ask"])
        let composer = app.textFields["ask-composer"].exists ? app.textFields["ask-composer"] : app.textViews["ask-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 15)); composer.tap(); composer.typeText("How many kilns are flagged in Hapur?")
        let send = app.buttons["ask-send"]
        XCTAssertTrue(send.isHittable); send.tap()
        XCTAssertTrue(app.staticTexts["Waiting for an answer…"].waitForExistence(timeout: 5))
        try save("ask-waiting-after", app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'This local test record'")).firstMatch.waitForExistence(timeout: 25))
        try save("ask-answer-after", app)
    }
    @MainActor func testMotion() throws {
        let app = launch(["-evidenceFixture", "loaded"])
        let pin3 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Stop 3,'")).firstMatch
        XCTAssertTrue(pin3.waitForExistence(timeout: 15))
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try Data().write(to: dir.appendingPathComponent("motion-start"))
        let ready = dir.appendingPathComponent("motion-ready").path
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            FileManager.default.fileExists(atPath: ready)
        }, object: nil)], timeout: 15), .completed)
        pin3.tap()
        let pin4 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Stop 4,'")).firstMatch
        XCTAssertTrue(pin4.isHittable); pin4.tap()
        app.buttons["stop-detail-KW-d1000000000000000000000000000004"].tap()
        XCTAssertTrue(app.buttons["Record verdict"].waitForExistence(timeout: 10))
        reveal(app, "Rule source").tap()
        try save("motion-detail-expanded", app)
        try Data().write(to: dir.appendingPathComponent("motion-end"))
    }
    @MainActor func testReduceMotion() throws {
        XCTAssertTrue(UIAccessibility.isReduceMotionEnabled)
        let app = launch(["-tab", "review"])
        XCTAssertTrue(app.buttons["Reason and scores"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Reason and scores"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'This item needs review because'")).firstMatch.exists)
    }
}
