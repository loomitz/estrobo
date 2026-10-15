import XCTest

final class EstroboSettingsLinksUITests: XCTestCase {
    @MainActor
    func testSettingsExposePrivacyAndSupportLinks() {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        defer {
            if isPad {
                XCUIDevice.shared.orientation = .portrait
            }
        }

        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-testing",
            "--fixture=workspace",
            "--language=en",
            "--appearance=light",
        ]
        app.launch()

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
            // SwiftUI's phone TabView currently exposes the tab buttons by
            // position rather than forwarding each label's identifier.
            let settingsTab = app.tabBars.buttons.element(boundBy: 2)
            XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
            settingsTab.tap()
        }

        let privacy = app.descendants(matching: .any)[
            EstroboAccessibilityID.privacyPolicy
        ]
        let support = app.descendants(matching: .any)[
            EstroboAccessibilityID.support
        ]

        for _ in 0..<4 where !privacy.exists || !support.exists {
            app.swipeUp()
        }

        XCTAssertTrue(privacy.waitForExistence(timeout: 3))
        XCTAssertTrue(support.waitForExistence(timeout: 3))
        XCTAssertEqual(privacy.label, "Privacy policy")
        XCTAssertEqual(support.label, "Support")
    }
}
