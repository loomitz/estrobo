import XCTest
import UIKit

final class EstroboTracerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoScanReadyAdjustAndApplyTracer() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--fixture=workspace",
            "--language=es",
            "--appearance=light",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[EstroboAccessibilityID.demoBanner]
                .waitForExistence(timeout: 10)
        )

        let status = app.buttons[
            EstroboAccessibilityID.sessionStatus
        ].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        status.tap()

        let scan = app.buttons[EstroboAccessibilityID.connectionScan]
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        scan.tap()

        let candidate = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "estrobo.connection.candidate."
            )
        ).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 10))
        XCTAssertTrue(candidate.label.localizedCaseInsensitiveContains("UUID"))
        XCTAssertTrue(candidate.label.contains("000001"))
        candidate.tap()

        let code = app.secureTextFields[
            EstroboAccessibilityID.connectionRadioCode
        ]
        XCTAssertTrue(code.waitForExistence(timeout: 5))

        let connect = app.buttons[EstroboAccessibilityID.connectionConnect]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: connect)
        waitForExpectations(timeout: 5)
        connect.tap()

        XCTAssertTrue(
            app.staticTexts[EstroboAccessibilityID.connectionPWOK]
                .waitForExistence(timeout: 15)
        )
        XCTAssertTrue(
            app.staticTexts[EstroboAccessibilityID.connectionSync]
                .waitForExistence(timeout: 15)
        )
        let ready = app.buttons[EstroboAccessibilityID.connectionReady]
        XCTAssertTrue(ready.waitForExistence(timeout: 15))
        ready.tap()

        let groupB = app.buttons[EstroboAccessibilityID.groupRow("B")]
        XCTAssertTrue(groupB.waitForExistence(timeout: 10))
        groupB.tap()

        let increase = app.buttons[
            EstroboAccessibilityID.groupPowerIncrease("B")
        ]
        XCTAssertTrue(increase.waitForExistence(timeout: 10))
        XCTAssertTrue(increase.isEnabled)
        increase.tap()

        let pending = app.staticTexts[
            EstroboAccessibilityID.groupConfirmation("B")
        ].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        XCTAssertEqual(pending.label, "PENDIENTE")

        let apply = app.buttons[EstroboAccessibilityID.apply].firstMatch
        XCTAssertTrue(apply.isEnabled)
        apply.tap()

        let fec8 = NSPredicate(format: "label == 'FEC8'")
        expectation(for: fec8, evaluatedWith: pending)
        waitForExpectations(timeout: 15)
    }

    @MainActor
    func testFreshDemoConfiguresProfileGroupsAndCapabilitiesBeforeControl() {
        let app = launchApp(fixture: "onboarding", language: "es")

        let demo = app.buttons[EstroboAccessibilityID.runtimeDemo]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        demo.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.workspaceSetup
            ].firstMatch.waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.demoBanner
            ].firstMatch.exists
        )

        let profile = app.descendants(matching: .any)[
            EstroboAccessibilityID.workspaceProfile
        ].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()

        let classicProfile = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "grupos A–F")
        ).firstMatch
        XCTAssertTrue(classicProfile.waitForExistence(timeout: 5))
        classicProfile.tap()

        let groupB = app.switches[
            EstroboAccessibilityID.workspaceGroup("B")
        ].firstMatch
        reveal(groupB, in: app)
        groupB.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()

        let modelMenu = app.buttons[
            EstroboAccessibilityID.workspaceModel("B")
        ].firstMatch
        reveal(modelMenu, in: app, bottomClearance: 32)
        modelMenu.tap()

        let model = app.buttons["AD400Pro II"].firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        model.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.workspaceCapability(
                    "B",
                    model: "ad400pro-ii"
                )
            ].firstMatch.waitForExistence(timeout: 5)
        )

        let continueButton = app.buttons[
            EstroboAccessibilityID.workspaceContinue
        ].firstMatch
        waitForEnabled(continueButton)
        continueButton.tap()

        XCTAssertTrue(
            app.buttons[EstroboAccessibilityID.connectionScan]
                .firstMatch.waitForExistence(timeout: 10)
        )
        app.buttons[
            EstroboAccessibilityID.connectionDismiss
        ].firstMatch.tap()

        XCTAssertTrue(
            app.buttons[EstroboAccessibilityID.groupRow("B")]
                .firstMatch.waitForExistence(timeout: 10)
        )
    }

    @MainActor
    func testAdaptiveRootMatchesCurrentIdiom() throws {
        let device = XCUIDevice.shared
        defer { device.orientation = .portrait }

        device.orientation = UIDevice.current.userInterfaceIdiom == .pad
            ? .landscapeLeft
            : .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--fixture=workspace",
            "--language=en",
        ]
        app.launch()

        if UIDevice.current.userInterfaceIdiom == .pad {
            let regularSidebar = app.buttons[
                EstroboAccessibilityID.sidebarGroups
            ].firstMatch
            XCTAssertTrue(regularSidebar.waitForExistence(timeout: 10))
            XCTAssertFalse(app.tabBars.firstMatch.exists)

            app.buttons[EstroboAccessibilityID.sidebarGlobal].firstMatch.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)[EstroboAccessibilityID.globalScreen]
                    .firstMatch.waitForExistence(timeout: 5)
            )
            XCTAssertFalse(app.staticTexts["Inspector"].firstMatch.exists)

            app.terminate()
            let compact = launchApp(
                fixture: "workspace",
                language: "en",
                extraArguments: ["--layout=compact"]
            )
            XCTAssertTrue(compact.tabBars.firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(
                compact.buttons[EstroboAccessibilityID.sidebarGroups]
                    .firstMatch.exists
            )
            XCTAssertTrue(
                compact.buttons[EstroboAccessibilityID.groupRow("B")]
                    .firstMatch.waitForExistence(timeout: 5)
            )
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(
                app.buttons[EstroboAccessibilityID.sidebarGroups]
                    .firstMatch.exists
            )
            XCTAssertTrue(
                app.buttons[EstroboAccessibilityID.groupRow("B")]
                    .firstMatch.waitForExistence(timeout: 5)
            )

            device.orientation = .landscapeLeft
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(
                app.buttons[EstroboAccessibilityID.sessionStatus]
                    .firstMatch.waitForExistence(timeout: 5)
            )
        }
    }

    @MainActor
    func testTestFlashCanBeCancelledThenConfirmed() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")
        selectPhoneSection(
            EstroboAccessibilityID.tabGlobal,
            in: app
        )

        let openConfirmation = app.buttons[
            EstroboAccessibilityID.testOpenConfirmation
        ].firstMatch
        reveal(openConfirmation, in: app)
        waitForEnabled(openConfirmation)
        openConfirmation.tap()

        let confirmation = app.buttons[
            EstroboAccessibilityID.testConfirm
        ].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        app.buttons[EstroboAccessibilityID.testCancel].firstMatch.tap()
        waitForDisappearance(confirmation)

        reveal(openConfirmation, in: app)
        openConfirmation.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        app.buttons[EstroboAccessibilityID.testConfirm].firstMatch.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[EstroboAccessibilityID.testSent]
                .firstMatch
                .waitForExistence(timeout: 10)
        )
    }

    @MainActor
    func testMultiRequiresConfirmationAndAppliesItsDraft() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")
        selectPhoneSection(EstroboAccessibilityID.tabGlobal, in: app)

        let openConfirmation = app.buttons[
            EstroboAccessibilityID.multiOpenConfirmation
        ].firstMatch
        reveal(openConfirmation, in: app)
        waitForEnabled(openConfirmation)
        openConfirmation.tap()

        let confirmation = app.buttons[
            EstroboAccessibilityID.multiConfirm
        ].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Entrarán o seguirán en Multi"]
                .firstMatch.waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Pasarán a Off"].firstMatch.exists)
        app.buttons[EstroboAccessibilityID.multiCancel].firstMatch.tap()
        waitForDisappearance(confirmation)

        reveal(openConfirmation, in: app)
        openConfirmation.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        app.buttons[EstroboAccessibilityID.multiConfirm].firstMatch.tap()

        let participantB = app.switches[
            EstroboAccessibilityID.multiParticipant("B")
        ].firstMatch
        reveal(participantB, in: app)
        XCTAssertTrue(participantB.exists)

        let apply = app.buttons[EstroboAccessibilityID.apply].firstMatch
        waitForEnabled(apply)
        apply.tap()

        let applied = NSPredicate(
            format: "label CONTAINS[c] %@",
            "Sin cambios Multi pendientes"
        )
        expectation(
            for: applied,
            evaluatedWith: app.staticTexts[
                EstroboAccessibilityID.multiEnabled
            ].firstMatch
        )
        waitForExpectations(timeout: 15)
    }

    @MainActor
    func testPresetSaveLoadLocalSyncAndDelete() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")
        selectPhoneSection(EstroboAccessibilityID.tabPresets, in: app)

        let name = app.textFields[EstroboAccessibilityID.presetName].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("UI Studio")
        if app.keyboards.firstMatch.exists {
            app.keyboards.firstMatch.swipeDown()
        }

        let save = app.buttons[EstroboAccessibilityID.presetSave].firstMatch
        waitForEnabled(save)
        save.tap()
        waitForDisappearance(app.keyboards.firstMatch)

        let loadLocal = dynamicPresetButton(suffix: ".load-local", in: app)
        reveal(loadLocal, in: app)
        waitForEnabled(loadLocal)
        loadLocal.tap()

        let synchronize = dynamicPresetButton(suffix: ".sync", in: app)
        reveal(synchronize, in: app)
        waitForEnabled(synchronize)
        synchronize.tap()

        let delete = dynamicPresetButton(suffix: ".delete", in: app)
        reveal(delete, in: app)
        waitForEnabled(delete, timeout: 15)
        delete.tap()

        let deleteConfirm = app.buttons[
            EstroboAccessibilityID.presetDeleteConfirm
        ].firstMatch
        XCTAssertTrue(deleteConfirm.waitForExistence(timeout: 5))
        deleteConfirm.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[EstroboAccessibilityID.presetEmpty]
                .firstMatch.waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testSavedTransmittersForgetsOnlyTheChosenOne() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "saved-radios", language: "es")
        selectPhoneSection(EstroboAccessibilityID.tabSettings, in: app)

        let savedLink = app.buttons[EstroboAccessibilityID.savedRadios].firstMatch
        XCTAssertTrue(savedLink.waitForExistence(timeout: 10))
        savedLink.tap()

        let primaryID = UUID(
            uuidString: "E5700B00-0000-4000-8000-000000000001"
        )!
        let reserveID = UUID(
            uuidString: "E5700B00-0000-4000-8000-000000000002"
        )!
        let primary = app.descendants(matching: .any)[
            EstroboAccessibilityID.savedRadio(primaryID)
        ].firstMatch
        let reserve = app.descendants(matching: .any)[
            EstroboAccessibilityID.savedRadio(reserveID)
        ].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertTrue(reserve.waitForExistence(timeout: 5))

        let forget = app.buttons[
            EstroboAccessibilityID.savedRadioForget(primaryID)
        ].firstMatch
        reveal(forget, in: app)
        waitForEnabled(forget)
        forget.tap()
        let forgetConfirm = app.buttons[
            EstroboAccessibilityID.savedRadioForgetConfirm
        ].firstMatch
        XCTAssertTrue(forgetConfirm.waitForExistence(timeout: 5))
        forgetConfirm.tap()

        waitForDisappearance(primary)
        XCTAssertTrue(reserve.exists)
    }

    @MainActor
    func testRecoveryRejectsASelectedTransmitterWithTheWrongUUID() throws {
        let app = launchApp(fixture: "recovery-wrong-uuid", language: "es")
        openConnection(in: app)

        let scan = app.buttons[EstroboAccessibilityID.connectionScan].firstMatch
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        scan.tap()

        let candidate = dynamicCandidate(in: app)
        XCTAssertTrue(candidate.waitForExistence(timeout: 10))
        candidate.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.recoveryWrongDevice
            ].firstMatch.waitForExistence(timeout: 5)
        )
        let connect = app.buttons[
            EstroboAccessibilityID.connectionConnect
        ].firstMatch
        for _ in 0..<4 where !connect.exists {
            app.swipeUp()
        }
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertFalse(connect.isEnabled)
    }

    @MainActor
    func testPermissionDeniedScenarioIsExplicitAndDoesNotOfferDelayedConnect() throws {
        let app = launchApp(fixture: "permission-denied", language: "en")
        openConnection(in: app)

        let scan = app.buttons[EstroboAccessibilityID.connectionScan].firstMatch
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        scan.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.connectionPermissionDenied
            ].firstMatch.waitForExistence(timeout: 10)
        )
        XCTAssertFalse(
            app.buttons[EstroboAccessibilityID.connectionConnect].firstMatch.exists
        )
    }

    @MainActor
    func testLiveBluetoothEducationRequiresAcknowledgementBeforeStarting() {
        let app = launchApp(fixture: "onboarding", language: "en")

        let education = app.buttons[
            EstroboAccessibilityID.runtimeLiveEducation
        ].firstMatch
        XCTAssertTrue(education.waitForExistence(timeout: 10))
        education.tap()

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@",
                    "only while the app is open"
                )
            ).firstMatch.waitForExistence(timeout: 5)
        )
        let acknowledge = app.switches[
            EstroboAccessibilityID.runtimeLiveAcknowledge
        ].firstMatch
        let start = app.buttons[
            EstroboAccessibilityID.runtimeLiveStart
        ].firstMatch
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 5))
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled)

        acknowledge.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        waitForEnabled(start)
        XCTAssertFalse(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.workspaceSetup
            ].firstMatch.exists
        )
    }

    @MainActor
    func testSpanishLightAndEnglishDarkPreferencesReachTheWorkspace() throws {
        try requirePhoneForDenseControlFlow()
        let spanish = launchApp(
            fixture: "workspace",
            language: "es",
            appearance: "light"
        )
        let spanishGroups = spanish.tabBars.buttons.element(boundBy: 0)
        XCTAssertTrue(spanishGroups.waitForExistence(timeout: 10))
        XCTAssertTrue(spanishGroups.label.localizedCaseInsensitiveContains("Grupos"))
        selectPhoneSection(EstroboAccessibilityID.tabSettings, in: spanish)
        let spanishLanguage = spanish.descendants(matching: .any)[
            EstroboAccessibilityID.language
        ].firstMatch
        reveal(spanishLanguage, in: spanish)
        let spanishLanguageState = "\(spanishLanguage.label) \(spanishLanguage.value ?? "")"
        XCTAssertTrue(
            spanishLanguageState.localizedCaseInsensitiveContains("Español")
                || spanishLanguage.buttons["Español"].isSelected
        )
        let lightAppearance = spanish.descendants(matching: .any)[
            EstroboAccessibilityID.appearance
        ].firstMatch
        reveal(lightAppearance, in: spanish)
        let lightState = "\(lightAppearance.label) \(lightAppearance.value ?? "")"
        XCTAssertTrue(lightState.localizedCaseInsensitiveContains("Claro"))
        spanish.terminate()

        let english = launchApp(
            fixture: "connected",
            language: "en",
            appearance: "dark"
        )
        waitForReady(in: english, label: "Ready")
        let englishGroups = english.tabBars.buttons.element(boundBy: 0)
        XCTAssertTrue(englishGroups.waitForExistence(timeout: 10))
        XCTAssertTrue(englishGroups.label.localizedCaseInsensitiveContains("Groups"))

        let englishGroupB = english.buttons[
            EstroboAccessibilityID.groupRow("B")
        ].firstMatch
        XCTAssertTrue(englishGroupB.waitForExistence(timeout: 5))
        englishGroupB.tap()

        let modeling = english.descendants(matching: .any)[
            EstroboAccessibilityID.groupModeling("B")
        ].firstMatch
        XCTAssertTrue(modeling.waitForExistence(timeout: 5))
        let modelingState = "\(modeling.label) \(modeling.value ?? "")"
        XCTAssertTrue(
            modelingState.localizedCaseInsensitiveContains("Off")
                || modelingState.localizedCaseInsensitiveContains("Proportional")
        )
        XCTAssertFalse(modelingState.localizedCaseInsensitiveContains("Apagada"))

        let increase = english.buttons[
            EstroboAccessibilityID.groupPowerIncrease("B")
        ].firstMatch
        reveal(increase, in: english)
        waitForEnabled(increase)
        increase.tap()

        let confirmation = english.staticTexts
            .matching(
                identifier: EstroboAccessibilityID.groupConfirmation("B")
            )
            .matching(NSPredicate(format: "label == 'PENDING'"))
            .firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))

        let discard = english.buttons[
            EstroboAccessibilityID.discard
        ].firstMatch
        reveal(discard, in: english)
        waitForEnabled(discard)
        discard.tap()
        waitForDisappearance(confirmation)

        selectPhoneSection(EstroboAccessibilityID.tabSettings, in: english)
        let appearance = english.descendants(matching: .any)[
            EstroboAccessibilityID.appearance
        ].firstMatch
        reveal(appearance, in: english)
        let appearanceState = "\(appearance.label) \(appearance.value ?? "")"
        XCTAssertTrue(appearanceState.localizedCaseInsensitiveContains("Dark"))
    }

    @MainActor
    func testAccessibilityDynamicTypeKeepsCoreControlsReachable() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(
            fixture: "workspace",
            language: "en",
            appearance: "dark",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        )

        let groupB = app.buttons[
            EstroboAccessibilityID.groupRow("B")
        ].firstMatch
        XCTAssertTrue(groupB.waitForExistence(timeout: 10))
        groupB.tap()

        let increase = app.buttons[
            EstroboAccessibilityID.groupPowerIncrease("B")
        ].firstMatch
        reveal(increase, in: app)
        increase.tap()

        XCTAssertTrue(
            app.buttons[EstroboAccessibilityID.apply]
                .firstMatch.waitForExistence(timeout: 5)
        )
    }

    @MainActor
    private func launchApp(
        fixture: String,
        language: String,
        appearance: String = "light",
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--fixture=\(fixture)",
            "--language=\(language)",
            "--appearance=\(appearance)",
        ] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func requirePhoneForDenseControlFlow() throws {
        if UIDevice.current.userInterfaceIdiom == .pad {
            throw XCTSkip(
                "The iPad adaptive split is covered by its layout tracer; "
                    + "dense phone controls run on the iPhone destination."
            )
        }
    }

    @MainActor
    private func selectPhoneSection(_ identifier: String, in app: XCUIApplication) {
        let index: Int
        switch identifier {
        case EstroboAccessibilityID.tabGroups:
            index = 0
        case EstroboAccessibilityID.tabGlobal:
            index = 1
        case EstroboAccessibilityID.tabPresets:
            index = 2
        case EstroboAccessibilityID.tabSettings:
            index = 3
        default:
            XCTFail("Unknown phone tab identifier: \(identifier)")
            return
        }
        let tab = app.tabBars.buttons.element(boundBy: index)
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
    }

    @MainActor
    private func openConnection(in app: XCUIApplication) {
        let status = app.buttons[EstroboAccessibilityID.sessionStatus].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        status.tap()
    }

    @MainActor
    private func waitForReady(
        in app: XCUIApplication,
        label: String,
        timeout: TimeInterval = 15
    ) {
        let status = app.buttons[EstroboAccessibilityID.sessionStatus].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let ready = NSPredicate(
            format: "label CONTAINS[c] %@",
            label
        )
        expectation(for: ready, evaluatedWith: status)
        waitForExpectations(timeout: timeout)
    }

    @MainActor
    private func dynamicCandidate(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "estrobo.connection.candidate."
            )
        ).firstMatch
    }

    @MainActor
    private func dynamicPresetButton(
        suffix: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                "estrobo.preset.",
                suffix
            )
        ).firstMatch
    }

    @MainActor
    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        bottomClearance: CGFloat = 96
    ) {
        let unobscuredBottom = app.frame.maxY - bottomClearance
        for _ in 0..<8 where
            !element.isHittable || element.frame.maxY > unobscuredBottom {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertLessThanOrEqual(element.frame.maxY, unobscuredBottom)
    }

    @MainActor
    private func waitForEnabled(
        _ element: XCUIElement,
        timeout: TimeInterval = 10
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    @MainActor
    private func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) {
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }
}
