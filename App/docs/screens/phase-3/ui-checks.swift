import XCTest
import UIKit

final class Phase3Checks: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kilnwatch.inspector")
        app.launchArguments = ["-tab", "kilns", "-autoplay", "none"] + args
        app.launch()
        return app
    }
    @MainActor private func text(_ app: XCUIApplication, _ value: String, timeout: Double = 12) {
        XCTAssertTrue(app.staticTexts[value].firstMatch.waitForExistence(timeout: timeout), value)
    }
    @MainActor private func noClaims(_ app: XCUIApplication) {
        let labels = app.descendants(matching: .any).allElementsBoundByIndex.map(\.label).joined(separator: "\n").lowercased()
        XCTAssertFalse(labels.contains("illegal")); XCTAssertFalse(labels.contains("800 m"))
        XCTAssertFalse(app.buttons["Record verdict"].exists)
        XCTAssertFalse(app.buttons["Ask about this kiln"].exists)
    }
    @MainActor private func shot(_ name: String, _ app: XCUIApplication) {
        let screenshot = app.screenshot()
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try! screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
        let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    @MainActor func testLiveListDetailAndToday() throws {
        let app = launch()
        text(app, "HAPUR · 39 KILNS", timeout: 25)
        text(app, "Live data")
        noClaims(app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.exists); search.tap(); search.typeText("KW-6b3b38da681850e5af46b024f3d3f78e")
        let row = app.descendants(matching: .any)["kiln-row-KW-6b3b38da681850e5af46b024f3d3f78e"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        text(app, "Model score 0.32")
        text(app, "Predicted FCBK · unverified")
        text(app, "Satellite images not yet published")
        noClaims(app)
        app.swipeUp()
        text(app, "Rules not evaluated")
        text(app, "Population exposure not assessed")
        noClaims(app)
        print("LIVE_AFTER_SEARCH_CROSS_TAB_UNVERIFIED_NATIVE_BETA_SELECTOR")
        app.launchArguments = ["-tab", "today", "-autoplay", "none"]
        app.launch()
        text(app, "39 satellite-flagged candidates")
        text(app, "Route planning isn't available yet")
        XCTAssertFalse(app.buttons["Start route"].exists)
        let pins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "kiln-pin-"))
        XCTAssertTrue(pins.firstMatch.waitForExistence(timeout: 5))
        let pin = try XCTUnwrap(pins.allElementsBoundByIndex.first { $0.isHittable })
        pin.tap()
        text(app, "Satellite images not yet published")
        noClaims(app)
    }
    @MainActor func testPublicListStates() throws {
        for (scenario, message) in [
            ("loading", "Loading satellite records"),
            ("empty", "No flagged kilns in Hapur in the scanned imagery"),
            ("offline", "You're offline"),
            ("503", "KilnWatch data is temporarily unavailable"),
            ("429", "The service is still busy. Please retry shortly.")
        ] {
            let app = launch(["-publicDemo", scenario]); text(app, message)
            text(app, "Sample data"); noClaims(app)
            XCTAssertTrue(app.buttons["Retry"].exists)
            if scenario != "loading" { XCTAssertTrue(app.buttons["Retry"].isEnabled); app.buttons["Retry"].tap(); text(app, message) }
        }
        let app = launch(["-publicDemo", "429Recovery"])
        text(app, "HAPUR · 11 KILNS"); text(app, "Sample data"); noClaims(app)
    }
    @MainActor func testPublicDetailFailuresAndRecovery() throws {
        for (scenario, message) in [("404", "Kiln not found"), ("offline", "You're offline"), ("503", "KilnWatch data is temporarily unavailable"), ("recovery", "KilnWatch data is temporarily unavailable")] {
            let app = launch(["-publicDemo", "loaded", "-publicDetail", scenario, "-open", "KW-0412"])
            text(app, message); text(app, "Sample data"); noClaims(app)
            XCTAssertTrue(app.buttons["Retry"].isEnabled); app.buttons["Retry"].tap()
            if scenario == "recovery" { text(app, "Model score 0.82"); text(app, "Satellite images not yet published") }
            else { text(app, message) }
            noClaims(app)
        }
    }
    @MainActor func testFixtureRouteRegression() throws {
        let app = launch(["-fixtures", "YES", "-signedIn", "YES", "-tab", "today"])
        XCTAssertTrue(app.buttons["Start route"].waitForExistence(timeout: 12)); text(app, "Sample data · illustrative routing")
        app.buttons["Stop 2, KW-0388"].tap(); XCTAssertTrue(app.buttons["Navigate to KW-0388"].waitForExistence(timeout: 5))
        app.buttons["Start route"].tap(); XCTAssertTrue(app.buttons["End route"].waitForExistence(timeout: 5))
        app.buttons["Route list"].tap(); XCTAssertTrue(app.navigationBars["Route · 9 stops"].waitForExistence(timeout: 5))
    }
    @MainActor func testSyntheticEvidenceStatesAndAdjustableComparator() throws {
        for state in ["loaded", "loading", "failed"] {
            let app = launch(["-publicDemo", "loaded", "-open", "KW-0412", "-evidenceFixture", state])
            text(app, "Model score 0.82"); app.swipeUp()
            text(app, "Synthetic local image fixture · not satellite evidence")
            if state == "loaded" {
                let image = app.descendants(matching: .any)["satellite-comparator"].firstMatch
                XCTAssertTrue(image.waitForExistence(timeout: 5)); XCTAssertEqual(image.value as? String, "Divider at 50 percent")
                let from = image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let to = image.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
                from.press(forDuration: 0.1, thenDragTo: to)
                XCTAssertNotEqual(image.value as? String, "Divider at 50 percent")
                shot("synthetic-evidence-loaded", app)
            } else if state == "loading" { text(app, "Loading satellite images"); shot("synthetic-evidence-loading", app) }
            else { text(app, "Satellite images couldn't be loaded"); app.buttons["Retry images"].tap(); text(app, "Satellite images couldn't be loaded"); shot("synthetic-evidence-failed", app) }
            noClaims(app)
        }
    }
    @MainActor func testRequiredScreenshots() throws {
        for mode in ["Dark"] {
            let suffix = mode.lowercased()
            var app = launch(["-UIUserInterfaceStyle", mode]); text(app, "HAPUR · 39 KILNS", timeout: 25); shot("kilns-\(suffix)", app)
            app = launch(["-UIUserInterfaceStyle", mode, "-open", "KW-6b3b38da681850e5af46b024f3d3f78e"])
            text(app, "Model score 0.32"); shot("detail-top-\(suffix)", app)
            app.swipeUp(); app.swipeUp(); text(app, "Sign-in coming soon. Inspection actions aren't available yet."); shot("detail-bottom-\(suffix)", app)
            app = launch(["-UIUserInterfaceStyle", mode, "-tab", "today"]); text(app, "39 satellite-flagged candidates", timeout: 25); shot("today-\(suffix)", app)
            for state in ["503", "offline"] {
                app = launch(["-UIUserInterfaceStyle", mode, "-publicDemo", state]); text(app, state == "503" ? "KilnWatch data is temporarily unavailable" : "You're offline"); shot("\(state)-\(suffix)", app)
            }
        }
    }
    @MainActor func testDetailCancellationBackoffAndRetryGuard() throws {
        for scenario in ["slow", "429"] {
            let app = launch(["-publicDemo", "loaded", "-publicDetail", scenario])
            text(app, "HAPUR · 11 KILNS")
            let row = app.descendants(matching: .any)["kiln-row-KW-0412"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            for _ in 0..<3 {
                row.tap()
                let expected = scenario == "slow" ? "Loading satellite records" : "Busy, retrying"
                let pending = app.staticTexts[expected].firstMatch
                if pending.exists { XCTAssertFalse(app.buttons["Retry"].isEnabled) }
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(row.waitForExistence(timeout: 5))
            }
            row.tap()
            if scenario == "slow" {
                let interrupted = app.staticTexts["Loading interrupted"].firstMatch
                if interrupted.exists { XCTAssertTrue(app.buttons["Retry"].isEnabled); app.buttons["Retry"].tap() }
                text(app, "Model score 0.82")
            } else {
                text(app, "The service is still busy. Please retry shortly.")
                XCTAssertTrue(app.buttons["Retry"].isEnabled)
                app.buttons["Retry"].tap()
                let busy = app.staticTexts["Busy, retrying"].firstMatch
                XCTAssertTrue(busy.exists)
                if app.staticTexts["We'll try once more in a moment."].exists { XCTAssertFalse(app.buttons["Retry"].isEnabled) }
                text(app, "The service is still busy. Please retry shortly.")
                XCTAssertTrue(app.buttons["Retry"].isEnabled)
            }
        }
    }
    @MainActor func testAXAndReduceMotion() throws {
        XCTAssertTrue(UIAccessibility.isReduceMotionEnabled)
        let app = launch()
        text(app, "HAPUR · 39 KILNS", timeout: 25); shot("kilns-ax5", app)
        let first = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "kiln-row-")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5)); let fullID = first.identifier.replacingOccurrences(of: "kiln-row-", with: "")
        XCTAssertTrue(first.label.contains(fullID)); first.tap()
        for _ in 0..<6 { if app.staticTexts["Rules not evaluated"].isHittable { break }; app.swipeUp() }
        text(app, "Rules not evaluated"); noClaims(app); shot("detail-ax5", app)
        app.navigationBars.buttons.firstMatch.tap()
        if app.buttons["Cancel"].exists && app.buttons["Cancel"].isHittable { app.buttons["Cancel"].tap() }
        app.swipeDown()
        if !app.tabBars.buttons["Today"].exists { app.tabBars.buttons["Kilns"].tap() }
        app.tabBars.buttons["Today"].tap(); text(app, "Route planning isn't available yet"); shot("today-ax5", app)
        let appError = launch(["-publicDemo", "503"]); text(appError, "KilnWatch data is temporarily unavailable"); XCTAssertTrue(appError.buttons["Retry"].isHittable); shot("503-ax5", appError)
    }
}
