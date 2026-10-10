import XCTest
import UIKit

/// All POSTs in this harness are intercepted local stubs. No live playback.
final class Phase4Checks: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(_ scenario: String, play: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kilnwatch.inspector")
        app.launchArguments = ["-tab", "ask", "-askDemo", scenario, "-autoplay", "none", "-askPlay", play ? "YES" : "NO"] + extra
        app.launch(); return app
    }
    @MainActor private func text(_ app: XCUIApplication, _ value: String, timeout: Double = 10) {
        XCTAssertTrue(app.staticTexts[value].firstMatch.waitForExistence(timeout: timeout), value)
    }
    @MainActor private func shot(_ name: String, _ app: XCUIApplication) throws {
        let screenshot = app.screenshot()
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }
    @MainActor func testLocalStates() throws {
        for (scenario, message) in [
            ("normal", "1 step"), ("fallback", "REGISTRY FALLBACK"),
            ("dailyLimit", "Ask has reached today's limit"), ("throttle", "Too many questions, wait a moment"),
            ("unavailable", "Ask isn't available right now"), ("retryable", "Ask is temporarily unavailable. Try again later."),
            ("malformed", "Ask returned an unreadable answer. You can try again.")
        ] {
            let app = launch(scenario); text(app, message); text(app, "Sample data")
            XCTAssertEqual(app.buttons["Retry"].exists, ["throttle", "retryable", "malformed"].contains(scenario))
            if ["dailyLimit", "unavailable"].contains(scenario) { XCTAssertFalse(app.buttons["ask-send"].isEnabled) }
            try shot("stub-" + scenario.lowercased(), app)
        }
        let app = launch("waiting"); text(app, "Waiting for an answer…")
        XCTAssertFalse(app.staticTexts["Reading kiln details"].exists)
        XCTAssertFalse(app.buttons["ask-send"].isEnabled); try shot("stub-waiting", app)
        app.buttons["Cancel question"].tap(); text(app, "Question cancelled. It may still count toward today's limit.")
        XCTAssertTrue(app.buttons["ask-send"].isEnabled)
    }
    @MainActor func testFullCitationAndPrefill() throws {
        let id = "KW-00000000000000000000000000000001"
        let app = launch("repeated"); text(app, "2 steps"); app.buttons["2 steps"].tap()
        text(app, "Tool input wasn't accepted"); text(app, "Invalid tool input")
        XCTAssertEqual(app.staticTexts.matching(identifier: "Reading kiln details").count, 2)
        app.buttons["2 steps"].tap()
        let chip = app.buttons[id].firstMatch; XCTAssertTrue(chip.waitForExistence(timeout: 5)); chip.tap()
        text(app, "Model score 0.82"); text(app, id)
        text(app, "Satellite images not yet published"); XCTAssertFalse(app.buttons["Record verdict"].exists)
        for _ in 0..<8 { if app.buttons["Ask about this kiln"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["Ask about this kiln"].isHittable); app.buttons["Ask about this kiln"].tap()
        let composer = app.textFields["ask-composer"].firstMatch.exists ? app.textFields["ask-composer"].firstMatch : app.textViews["ask-composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5)); XCTAssertEqual(composer.value as? String, "Explain this kiln's registry record: " + id)
        XCTAssertFalse(app.staticTexts["Waiting for an answer…"].exists)
        try shot("stub-prefill", app)
    }
    @MainActor func testOfflineRecoveryAndRetry() throws {
        let app = launch("offlineRecovery", play: false); text(app, "Offline · Ask needs a connection")
        XCTAssertFalse(app.buttons["ask-send"].isEnabled); try shot("stub-offline", app)
        app.buttons["Restore test connection"].tap()
        let suggestion = app.buttons["How many kilns are flagged in Hapur?"].firstMatch
        XCTAssertTrue(suggestion.isEnabled); suggestion.tap(); XCTAssertTrue(app.buttons["ask-send"].isEnabled)
        app.buttons["ask-send"].tap(); text(app, "1 step")
        let retry = launch("recovery"); text(retry, "Ask is temporarily unavailable. Try again later.")
        retry.buttons["Retry"].tap(); text(retry, "1 step"); XCTAssertFalse(retry.buttons["Retry"].exists)
        try shot("stub-recovered", retry)
    }
    @MainActor func testComposerLimitsAndEmptySteps() throws {
        let app = launch("emptySteps", play: false)
        let composer = app.descendants(matching: .any)["ask-composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5)); composer.tap(); composer.typeText(String(repeating: "a", count: 500))
        text(app, "500/500 characters"); XCTAssertTrue(app.buttons["ask-send"].isEnabled)
        composer.typeText("a"); text(app, "501/500 characters"); XCTAssertFalse(app.buttons["ask-send"].isEnabled)
        text(app, "Use a question of 1–500 characters."); try shot("stub-composer-501", app)
        composer.typeText(XCUIKeyboardKey.delete.rawValue); XCTAssertTrue(app.buttons["ask-send"].isEnabled)
        app.buttons["ask-send"].tap()
        text(app, "Answers cite registry records. Agents never record verdicts. Kilns are flagged by satellite and pending inspection.")
        XCTAssertFalse(app.staticTexts["0 steps"].exists); try shot("stub-empty-steps", app)
    }
    @MainActor func testPasteLimits() throws {
        defer { UIPasteboard.general.items = [] }
        for count in [500, 501] {
            let app = launch("normal", play: false)
            let composer = app.descendants(matching: .any)["ask-composer"].firstMatch
            XCTAssertTrue(composer.waitForExistence(timeout: 5)); composer.tap()
            UIPasteboard.general.string = String(repeating: "a", count: count)
            composer.press(forDuration: 1.2)
            let paste = app.menuItems["Paste"].exists ? app.menuItems["Paste"] : app.buttons["Paste"]
            XCTAssertTrue(paste.waitForExistence(timeout: 5)); paste.tap()
            try shot("stub-paste-" + String(count), app)
            text(app, String(count) + "/500 characters")
            XCTAssertEqual(app.buttons["ask-send"].isEnabled, count == 500)
        }
    }

    @MainActor func testAppearance() throws {
        if ProcessInfo.processInfo.environment["ASK_REDUCE_MOTION"] == "YES" { XCTAssertTrue(UIAccessibility.isReduceMotionEnabled) }
        let app = launch("normal"); text(app, "1 step")
        XCTAssertTrue(app.buttons["KW-00000000000000000000000000000001"].firstMatch.waitForExistence(timeout: 5))
        let chip = app.buttons["KW-00000000000000000000000000000001"].firstMatch
        chip.tap() // XCTest scrolls the native answer region to the citation before tapping.
        text(app, "Model score 0.82")
        XCTAssertFalse(app.buttons["Record verdict"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        let suffix = ProcessInfo.processInfo.environment["ASK_CAPTURE_SUFFIX"] ?? "appearance"
        try shot("stub-" + suffix, app)
    }
    @MainActor func testSampleAndRegression() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kilnwatch.inspector")
        app.launchArguments = ["-fixtures", "YES", "-signedIn", "YES", "-tab", "ask", "-askPlay", "YES"]
        app.launch(); text(app, "Sample data")
        text(app, "Sample answer. Answers cite registry records. Agents never record verdicts.", timeout: 20)
        try shot("scripted-sample", app)
        app.launchArguments = ["-fixtures", "YES", "-signedIn", "YES", "-tab", "today"]
        app.launch(); XCTAssertTrue(app.buttons["Start route"].waitForExistence(timeout: 10)); app.buttons["Start route"].tap()
        XCTAssertTrue(app.buttons["End route"].waitForExistence(timeout: 5))
        app.launchArguments = ["-publicDemo", "loaded", "-tab", "kilns"]
        app.launch(); text(app, "HAPUR · 11 KILNS")
        app.launchArguments = ["-publicDemo", "loaded", "-tab", "today"]
        app.launch(); text(app, "Route planning isn't available yet")
    }
    @MainActor func testReduceMotionSample() throws {
        XCTAssertTrue(UIAccessibility.isReduceMotionEnabled)
        let app = XCUIApplication(bundleIdentifier: "com.kilnwatch.inspector")
        app.launchArguments = ["-fixtures", "YES", "-signedIn", "YES", "-tab", "ask", "-askPlay", "YES"]
        app.launch(); text(app, "Sample answer. Answers cite registry records. Agents never record verdicts.", timeout: 5)
        try shot("scripted-reduce-motion", app)
    }

    @MainActor func testNonretryableSubmissionControls() throws {
        for scenario in ["dailyLimit", "unavailable"] {
            let app = launch(scenario)
            text(app, scenario == "dailyLimit" ? "Ask has reached today's limit" : "Ask isn't available right now")
            XCTAssertFalse(app.buttons["ask-send"].isEnabled); XCTAssertFalse(app.buttons["Retry"].exists)
            try shot("stub-" + scenario.lowercased(), app)
        }
    }

}
