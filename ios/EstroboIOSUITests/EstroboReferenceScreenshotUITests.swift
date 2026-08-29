import XCTest
import UIKit

/// Produces deterministic, reviewable reference captures from the same Demo
/// fixtures exercised by the UI suite. Simulator images are product/UI
/// evidence only; they do not imply physical Bluetooth validation.
final class EstroboReferenceScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureReferenceScreens() {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let family = isPad
            ? "ipad"
            : "iphone"
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        defer {
            if isPad {
                XCUIDevice.shared.orientation = .portrait
            }
        }

        var app = launchApp(
            fixture: "onboarding",
            language: "es",
            appearance: "light"
        )
        let demo = app.buttons[EstroboAccessibilityID.runtimeDemo].firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        capture(app, family: family, sequence: 1, slug: "runtime-es-light")

        demo.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.workspaceSetup
            ].firstMatch.waitForExistence(timeout: 10)
        )
        capture(app, family: family, sequence: 2, slug: "workspace-setup-es-light")
        app.terminate()

        app = launchApp(
            fixture: "workspace",
            language: "es",
            appearance: "light"
        )
        XCTAssertTrue(
            app.buttons[EstroboAccessibilityID.groupRow("B")]
                .firstMatch.waitForExistence(timeout: 10)
        )
        capture(app, family: family, sequence: 3, slug: "groups-es-light")

        let status = app.buttons[
            EstroboAccessibilityID.sessionStatus
        ].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        status.tap()
        XCTAssertTrue(
            app.buttons[EstroboAccessibilityID.connectionScan]
                .firstMatch.waitForExistence(timeout: 10)
        )
        capture(app, family: family, sequence: 4, slug: "connection-es-light")
        app.terminate()

        app = launchApp(
            fixture: "connected",
            language: "en",
            appearance: "dark"
        )
        waitForReady(in: app)
        capture(app, family: family, sequence: 5, slug: "groups-ready-en-dark")

        if isPad {
            let global = app.buttons[
                EstroboAccessibilityID.sidebarGlobal
            ].firstMatch
            XCTAssertTrue(global.waitForExistence(timeout: 10))
            global.tap()
        } else {
            let global = app.tabBars.buttons.element(boundBy: 1)
            XCTAssertTrue(global.waitForExistence(timeout: 10))
            global.tap()
        }
        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.globalScreen
            ].firstMatch.waitForExistence(timeout: 10)
        )
        capture(app, family: family, sequence: 6, slug: "global-ready-en-dark")
    }

    @MainActor
    private func launchApp(
        fixture: String,
        language: String,
        appearance: String
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--fixture=\(fixture)",
            "--language=\(language)",
            "--appearance=\(appearance)",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func waitForReady(in app: XCUIApplication) {
        let status = app.buttons[
            EstroboAccessibilityID.sessionStatus
        ].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        expectation(
            for: NSPredicate(format: "label CONTAINS[c] 'Ready'"),
            evaluatedWith: status
        )
        waitForExpectations(timeout: 15)
    }

    @MainActor
    private func capture(
        _ app: XCUIApplication,
        family: String,
        sequence: Int,
        slug: String
    ) {
        XCTAssertEqual(app.state, .runningForeground)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(
            format: "estrobo-reference-%@-%02d-%@.png",
            family,
            sequence,
            slug
        )
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
