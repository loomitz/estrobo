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
            app.descendants(matching: .any)[EstroboAccessibilityID.groupRow("B")]
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
        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.globalScreen
            ].firstMatch.waitForExistence(timeout: 10)
        )
        if isPad {
            XCTAssertFalse(
                app.buttons[EstroboAccessibilityID.sidebarGlobal].firstMatch.exists
            )
        } else {
            XCTAssertEqual(app.tabBars.buttons.count, 3)
            XCTAssertFalse(
                app.descendants(matching: .any)[EstroboAccessibilityID.tabGlobal]
                    .firstMatch.exists
            )
        }
        capture(
            app,
            family: family,
            sequence: 5,
            slug: "groups-global-controls-ready-en-dark"
        )

        let standby = app.buttons[
            EstroboAccessibilityID.globalStandby
        ].firstMatch
        XCTAssertTrue(standby.waitForExistence(timeout: 5))
        XCTAssertTrue(standby.isHittable)
        standby.tap()
        expectation(
            for: NSPredicate(format: "value == 'On' AND isSelected == true"),
            evaluatedWith: standby
        )
        waitForExpectations(timeout: 5)
        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.groupStandbyOverlay("B")
            ].firstMatch.waitForExistence(timeout: 5)
        )
        capture(
            app,
            family: family,
            sequence: 7,
            slug: "groups-standby-ready-en-dark"
        )
        expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: standby
        )
        waitForExpectations(timeout: 5)
        standby.tap()
        expectation(
            for: NSPredicate(format: "value == 'Off' AND isSelected == false"),
            evaluatedWith: standby
        )
        waitForExpectations(timeout: 5)

        let groupB = app.descendants(matching: .any)[
            EstroboAccessibilityID.groupRow("B")
        ].firstMatch
        XCTAssertTrue(groupB.waitForExistence(timeout: 10))
        groupB.press(forDuration: 0.7)
        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.groupDetail("B")
            ].firstMatch.waitForExistence(timeout: 5)
        )
        let modeling = app.segmentedControls[
            EstroboAccessibilityID.groupModeling("B")
        ].firstMatch
        XCTAssertTrue(modeling.waitForExistence(timeout: 5))
        let manual = modeling.buttons["Manual"].firstMatch
        for _ in 0..<6 where !manual.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(manual.isHittable)
        manual.tap()
        XCTAssertTrue(
            app.sliders[
                EstroboAccessibilityID.groupModelingManualSlider("B")
            ].firstMatch.waitForExistence(timeout: 5)
        )
        capture(
            app,
            family: family,
            sequence: 6,
            slug: "group-detail-manual-ready-en-dark"
        )
    }

    @MainActor
    func testCaptureCompatibilityInspectionScreens() {
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

        let app = launchApp(
            fixture: "connected",
            language: "en",
            appearance: "dark"
        )
        waitForReady(in: app)

        if isPad {
            let settings = app.buttons[
                EstroboAccessibilityID.sidebarSettings
            ].firstMatch
            if !settings.waitForExistence(timeout: 5) {
                let sidebarToggle = app.navigationBars.buttons.firstMatch
                XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
                sidebarToggle.tap()
            }
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
        } else {
            let settings = app.tabBars.buttons.element(boundBy: 2)
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
        }

        let compatibility = app.buttons[
            EstroboAccessibilityID.compatibility
        ].firstMatch
        for _ in 0..<6 where !compatibility.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(compatibility.waitForExistence(timeout: 10))
        XCTAssertTrue(compatibility.isHittable)
        compatibility.tap()

        let connectedSummary = app.descendants(matching: .any)[
            EstroboAccessibilityID.compatibilityConnection
        ].firstMatch
        XCTAssertTrue(connectedSummary.waitForExistence(timeout: 10))
        capture(
            app,
            family: family,
            sequence: 8,
            slug: "compatibility-summary-connected-en-dark"
        )

        let edit = app.buttons[
            EstroboAccessibilityID.compatibilityEdit
        ].firstMatch
        for _ in 0..<6 where !edit.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(edit.isEnabled)
        XCTAssertTrue(edit.isHittable)
        edit.tap()

        let addGroups = app.buttons[
            EstroboAccessibilityID.compatibilityAddGroups
        ].firstMatch
        XCTAssertTrue(addGroups.waitForExistence(timeout: 10))
        capture(
            app,
            family: family,
            sequence: 9,
            slug: "compatibility-editor-connected-en-dark"
        )

        XCTAssertTrue(addGroups.isEnabled)
        XCTAssertTrue(addGroups.isHittable)
        addGroups.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.compatibilityAddGroupsSheet
            ].firstMatch.waitForExistence(timeout: 5)
        )
        capture(
            app,
            family: family,
            sequence: 10,
            slug: "compatibility-add-groups-grid-en-dark"
        )
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
