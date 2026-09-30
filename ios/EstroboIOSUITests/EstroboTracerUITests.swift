import XCTest
import UIKit

final class EstroboTracerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoScanReadyAdjustAndApplyTracer() throws {
        XCUIDevice.shared.orientation = .portrait
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
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertLessThan(app.frame.width, app.frame.height)
        }
        revealTabletGroupsWorkspaceIfNeeded(in: app)

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
        // Finishing the bounded scan must not erase the selected radio or the
        // code while the user is reading the connection form.
        waitForEnabled(scan, timeout: 15)
        if !connect.isEnabled {
            attachFailureState(named: "scan-timeout-lost-radio-credentials", of: app)
        }
        XCTAssertTrue(
            connect.isEnabled,
            "Ending a scan must preserve the selected radio and its six-digit code"
        )
        reveal(connect, in: app)
        connect.tap()

        let connectionStarted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false OR isEnabled == false"),
            object: connect
        )
        let connectionStartResult = XCTWaiter.wait(
            for: [connectionStarted],
            timeout: 5
        )
        if connectionStartResult != .completed {
            attachFailureState(named: "connection-did-not-start", of: app)
        }
        XCTAssertEqual(connectionStartResult, .completed)

        let connectionSheet = app.descendants(matching: .any)[
            EstroboAccessibilityID.connectionSheet
        ].firstMatch
        waitForDisappearance(connectionSheet, timeout: 15, app: app)
        revealTabletGroupsWorkspaceIfNeeded(in: app)
        waitForReady(in: app, label: "Listo")

        let slider = app.sliders[
            EstroboAccessibilityID.groupPowerSlider("B")
        ].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertTrue(slider.isEnabled)
        XCTAssertEqual(slider.value as? String, "1/512 +0.0")

        let decrease = app.buttons[
            EstroboAccessibilityID.groupPowerDecrease("B")
        ].firstMatch
        XCTAssertTrue(decrease.waitForExistence(timeout: 10))
        XCTAssertFalse(decrease.isEnabled)

        let increase = app.buttons[
            EstroboAccessibilityID.groupPowerIncrease("B")
        ].firstMatch
        XCTAssertTrue(increase.waitForExistence(timeout: 10))
        XCTAssertTrue(increase.isEnabled)
        increase.tap()

        let nextPower = NSPredicate(format: "value == '1/512 +0.3'")
        expectation(for: nextPower, evaluatedWith: slider)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(decrease.isEnabled)

        let pending = app.descendants(matching: .any)[
            EstroboAccessibilityID.groupRow("B")
        ].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        XCTAssertTrue((pending.value as? String)?.contains("PENDIENTE") == true)

        let apply = app.buttons[EstroboAccessibilityID.apply].firstMatch
        XCTAssertTrue(apply.isEnabled)
        apply.tap()

        let fec8 = NSPredicate(format: "value CONTAINS 'FEC8'")
        expectation(for: fec8, evaluatedWith: pending)
        waitForExpectations(timeout: 15)
    }

    @MainActor
    func testOpeningConnectionFromReadyKeepsSheetAccessible() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")

        openConnection(in: app)

        let connectionSheet = app.descendants(matching: .any)[
            EstroboAccessibilityID.connectionSheet
        ].firstMatch
        XCTAssertTrue(connectionSheet.waitForExistence(timeout: 5))

        let unexpectedDismissal = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: connectionSheet
        )
        unexpectedDismissal.isInverted = true
        XCTAssertEqual(
            XCTWaiter.wait(for: [unexpectedDismissal], timeout: 1),
            .completed
        )

        let close = app.buttons[
            EstroboAccessibilityID.connectionDismiss
        ].firstMatch
        XCTAssertTrue(close.exists)
        XCTAssertTrue(close.isEnabled)
        close.tap()
        waitForDisappearance(connectionSheet)
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
            app.descendants(matching: .any)[EstroboAccessibilityID.groupRow("B")]
                .firstMatch.waitForExistence(timeout: 10)
        )
    }

    @MainActor
    func testDeliveryModeExistsOnlyInSettings() {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        defer {
            if isPad {
                XCUIDevice.shared.orientation = .portrait
            }
        }

        let app = launchApp(fixture: "workspace", language: "es")
        let deliveryMode = app.descendants(matching: .any)[
            EstroboAccessibilityID.deliveryMode
        ].firstMatch

        let groupsSurface = app.descendants(matching: .any)[
            EstroboAccessibilityID.groupRow("B")
        ].firstMatch
        XCTAssertTrue(groupsSurface.waitForExistence(timeout: 10))
        XCTAssertFalse(deliveryMode.exists)

        let settings = app.buttons[
            EstroboAccessibilityID.sidebarSettings
        ].firstMatch
        if isPad {
            if !settings.waitForExistence(timeout: 5) {
                let sidebarToggle = app.navigationBars.buttons.firstMatch
                XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
                sidebarToggle.tap()
            }
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
        } else {
            selectPhoneSection(EstroboAccessibilityID.tabSettings, in: app)
        }

        XCTAssertTrue(deliveryMode.waitForExistence(timeout: 10))
    }

    @MainActor
    func testConnectedCompatibilityAddsGroupAfterAssigningRequiredModel() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")

        selectPhoneSection(EstroboAccessibilityID.tabSettings, in: app)
        let compatibility = app.buttons[
            EstroboAccessibilityID.compatibility
        ].firstMatch
        XCTAssertTrue(compatibility.waitForExistence(timeout: 10))
        compatibility.tap()

        let connectedSummary = app.descendants(matching: .any)[
            EstroboAccessibilityID.compatibilityConnection
        ].firstMatch
        XCTAssertTrue(connectedSummary.waitForExistence(timeout: 10))
        attachScreenshot(
            named: "Compatibilidad 01 - Resumen conectado",
            of: app
        )

        let edit = app.buttons[
            EstroboAccessibilityID.compatibilityEdit
        ].firstMatch
        reveal(edit, in: app)
        waitForEnabled(edit)
        edit.tap()

        let addGroups = app.buttons[
            EstroboAccessibilityID.compatibilityAddGroups
        ].firstMatch
        XCTAssertTrue(addGroups.waitForExistence(timeout: 10))
        XCTAssertTrue(addGroups.isEnabled)
        addGroups.tap()

        let addGroupsSheet = app.descendants(matching: .any)[
            EstroboAccessibilityID.compatibilityAddGroupsSheet
        ].firstMatch
        XCTAssertTrue(addGroupsSheet.waitForExistence(timeout: 5))

        let groupDChoice = app.descendants(matching: .any)[
            EstroboAccessibilityID.compatibilityGroupChoice("D")
        ].firstMatch
        reveal(groupDChoice, in: app, bottomClearance: 72)
        attachScreenshot(
            named: "Compatibilidad 02 - Grid anadir grupos",
            of: app
        )
        groupDChoice.tap()

        let confirmGroups = app.buttons[
            EstroboAccessibilityID.compatibilityAddGroupsConfirm
        ].firstMatch
        waitForEnabled(confirmGroups)
        confirmGroups.tap()
        waitForDisappearance(addGroupsSheet)

        let save = app.buttons[
            EstroboAccessibilityID.compatibilitySave
        ].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(
            save.isEnabled,
            "A newly added group must require at least one flash model before Save."
        )

        let groupDRow = app.descendants(matching: .any)[
            EstroboAccessibilityID.compatibilityGroupRow("D")
        ].firstMatch
        reveal(groupDRow, in: app)
        groupDRow.tap()

        let modelList = app.descendants(matching: .any)[
            EstroboAccessibilityID.compatibilityModels("D")
        ].firstMatch
        XCTAssertTrue(modelList.waitForExistence(timeout: 5))
        let selectedModelCount = app.staticTexts[
            EstroboAccessibilityID.compatibilityModelCount("D")
        ].firstMatch
        XCTAssertTrue(selectedModelCount.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedModelCount.label, "0 seleccionados")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("AD400Pro II")

        let model = app.descendants(matching: .any)[
            EstroboAccessibilityID.compatibilityModel(
                "D",
                model: "ad400pro-ii"
            )
        ].firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        model.tap()
        expectation(
            for: NSPredicate(format: "label == '1 seleccionado'"),
            evaluatedWith: selectedModelCount
        )
        waitForExpectations(timeout: 5)

        let closeSearch = app.toolbars.buttons["close"].firstMatch
        XCTAssertTrue(closeSearch.waitForExistence(timeout: 5))
        closeSearch.tap()

        let firstUnselectedModel = app.descendants(matching: .any)[
            EstroboAccessibilityID.compatibilityModel("D", model: "p2400")
        ].firstMatch
        XCTAssertTrue(firstUnselectedModel.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            model.frame.minY,
            firstUnselectedModel.frame.minY,
            "Selected models must move above the remaining catalog."
        )
        attachScreenshot(
            named: "Compatibilidad 04 - Modelos seleccionados primero",
            of: app
        )

        let modelBack = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(modelBack.waitForExistence(timeout: 5))
        modelBack.tap()

        XCTAssertTrue(groupDRow.waitForExistence(timeout: 5))
        reveal(groupDRow, in: app)
        XCTAssertTrue((groupDRow.value as? String)?.contains("AD400Pro II") == true)
        waitForEnabled(save)
        attachScreenshot(
            named: "Compatibilidad 03 - Editor D con AD400Pro II",
            of: app
        )
        save.tap()

        XCTAssertTrue(
            connectedSummary.waitForExistence(timeout: 10),
            "Saving connected compatibility must return to its summary."
        )
        let groupsSummary = app.descendants(matching: .any)[
            EstroboAccessibilityID.compatibilityGroupsSummary
        ].firstMatch
        XCTAssertTrue(groupsSummary.waitForExistence(timeout: 5))
        let summaryText = "\(groupsSummary.label) \(groupsSummary.value ?? "")"
        XCTAssertTrue(
            summaryText.contains("D"),
            "The compatibility summary must include the saved group D."
        )
    }

    @MainActor
    func testInlineSliderStagesManualValueThenAppliesThatValue() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")

        let slider = app.sliders[
            EstroboAccessibilityID.groupPowerSlider("B")
        ].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertTrue(slider.isEnabled)
        let initialPower = try XCTUnwrap(slider.value as? String)

        let confirmation = app.descendants(matching: .any)[
            EstroboAccessibilityID.groupRow("B")
        ].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue((confirmation.value as? String)?.contains("FEC8") == true)
        XCTAssertTrue((confirmation.value as? String)?.contains(initialPower) == true)

        drag(slider, from: 0.02, to: 0.35)
        expectation(
            for: NSPredicate(format: "value != %@", initialPower),
            evaluatedWith: slider
        )
        waitForExpectations(timeout: 2)
        let displayedPower = try XCTUnwrap(slider.value as? String)

        expectation(
            for: NSPredicate(format: "value CONTAINS 'PENDIENTE'"),
            evaluatedWith: confirmation
        )
        waitForExpectations(timeout: 3)

        let apply = app.buttons[EstroboAccessibilityID.apply].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        waitForEnabled(apply)
        apply.tap()

        expectation(
            for: NSPredicate(
                format: "value CONTAINS 'FEC8' AND value CONTAINS %@",
                displayedPower
            ),
            evaluatedWith: confirmation
        )
        waitForExpectations(timeout: 15)
        XCTAssertEqual(slider.value as? String, displayedPower)
    }

    @MainActor
    func testInlineSliderUpdatesPresentationAndShowsAutomaticDeliveryFeedback() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")

        selectPhoneSection(EstroboAccessibilityID.tabSettings, in: app)
        let deliveryMode = app.segmentedControls[
            EstroboAccessibilityID.deliveryMode
        ].firstMatch
        XCTAssertTrue(deliveryMode.waitForExistence(timeout: 10))
        let automatic = deliveryMode.buttons["Automática"].firstMatch
        XCTAssertTrue(automatic.waitForExistence(timeout: 5))
        automatic.tap()
        expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: automatic
        )
        waitForExpectations(timeout: 5)

        selectPhoneSection(EstroboAccessibilityID.tabGroups, in: app)
        let slider = app.sliders[
            EstroboAccessibilityID.groupPowerSlider("B")
        ].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertTrue(slider.isEnabled)
        let initialPower = try XCTUnwrap(slider.value as? String)

        let confirmation = app.descendants(matching: .any)[
            EstroboAccessibilityID.groupRow("B")
        ].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue((confirmation.value as? String)?.contains("FEC8") == true)
        XCTAssertTrue((confirmation.value as? String)?.contains(initialPower) == true)

        drag(slider, from: 0.02, to: 0.35)
        let changedPower = NSPredicate(format: "value != %@", initialPower)
        expectation(for: changedPower, evaluatedWith: slider)
        waitForExpectations(timeout: 2)

        let displayedPower = try XCTUnwrap(slider.value as? String)
        XCTAssertNotEqual(displayedPower, initialPower)
        XCTAssertEqual(
            app.buttons[EstroboAccessibilityID.groupPowerDecrease("B")]
                .firstMatch.value as? String,
            displayedPower
        )
        XCTAssertEqual(
            app.buttons[EstroboAccessibilityID.groupPowerIncrease("B")]
                .firstMatch.value as? String,
            displayedPower
        )
        XCTAssertFalse(app.buttons[EstroboAccessibilityID.apply].firstMatch.exists)

        expectation(
            for: NSPredicate(
                format: "value CONTAINS 'FEC8' AND value CONTAINS %@",
                displayedPower
            ),
            evaluatedWith: confirmation
        )
        waitForExpectations(timeout: 15)
        XCTAssertEqual(slider.value as? String, displayedPower)
    }

    @MainActor
    func testGlobalPowerSliderAppliesOneRelativeEditThenRecenters() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")

        let groupPower = app.sliders[
            EstroboAccessibilityID.groupPowerSlider("B")
        ].firstMatch
        XCTAssertTrue(groupPower.waitForExistence(timeout: 10))
        let initialPower = try XCTUnwrap(groupPower.value as? String)

        let globalPower = app.sliders[
            EstroboAccessibilityID.globalPowerSlider
        ].firstMatch
        reveal(globalPower, in: app)
        XCTAssertTrue(globalPower.isEnabled)
        XCTAssertEqual(globalPower.value as? String, "0.0 EV")

        drag(globalPower, from: 0.5, to: 0.68)

        expectation(
            for: NSPredicate(format: "value != %@", initialPower),
            evaluatedWith: groupPower
        )
        waitForExpectations(timeout: 3)
        expectation(
            for: NSPredicate(format: "value == '0.0 EV'"),
            evaluatedWith: globalPower
        )
        waitForExpectations(timeout: 2)
        XCTAssertFalse(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.globalPowerStatus
            ].firstMatch.exists
        )
    }

    @MainActor
    func testDirectGlobalActionsNeverPresentAutomaticConfirmationBar() throws {
        try requirePhoneForDenseControlFlow()
        let directActions = [
            EstroboAccessibilityID.globalBeep,
            EstroboAccessibilityID.globalModeling,
            EstroboAccessibilityID.globalStandby,
            EstroboAccessibilityID.multiToggle,
        ]

        for identifier in directActions {
            let app = launchApp(fixture: "connected", language: "es")
            waitForReady(in: app, label: "Listo")

            selectPhoneSection(EstroboAccessibilityID.tabSettings, in: app)
            let deliveryMode = app.segmentedControls[
                EstroboAccessibilityID.deliveryMode
            ].firstMatch
            XCTAssertTrue(deliveryMode.waitForExistence(timeout: 10))
            let automatic = deliveryMode.buttons["Automática"].firstMatch
            automatic.tap()
            expectation(
                for: NSPredicate(format: "isSelected == true"),
                evaluatedWith: automatic
            )
            waitForExpectations(timeout: 5)

            selectPhoneSection(EstroboAccessibilityID.tabGroups, in: app)
            let automaticFeedback = app.descendants(matching: .any)[
                EstroboAccessibilityID.deliveryAutomaticFeedback
            ].firstMatch
            let action = app.buttons[identifier].firstMatch
            revealAbove(action, in: app)
            waitForEnabled(action)
            action.tap()
            assertRemainsAbsent(
                automaticFeedback,
                for: 1.5,
                message: "Direct global actions must not flash the automatic confirmation bar"
            )
            app.terminate()
        }
    }

    @MainActor
    func testDirectBeepModelingAndStandbyNeverPresentManualApplyBar() throws {
        try requirePhoneForDenseControlFlow()

        for identifier in [
            EstroboAccessibilityID.globalBeep,
            EstroboAccessibilityID.globalModeling,
            EstroboAccessibilityID.globalStandby,
        ] {
            let app = launchApp(fixture: "connected", language: "es")
            waitForReady(in: app, label: "Listo")

            let apply = app.buttons[EstroboAccessibilityID.apply].firstMatch
            XCTAssertFalse(apply.exists)
            let action = app.buttons[identifier].firstMatch
            revealAbove(action, in: app)
            waitForEnabled(action)
            action.tap()
            assertRemainsAbsent(
                apply,
                for: 1.5,
                message: "Direct Beep and Standby must not flash the manual Apply bar"
            )
            app.terminate()
        }
    }

    @MainActor
    func testSuccessfulDirectGlobalActionsNeverExposeRecoveryGate() throws {
        try requirePhoneForDenseControlFlow()
        let directActions = [
            EstroboAccessibilityID.globalBeep,
            EstroboAccessibilityID.globalModeling,
            EstroboAccessibilityID.globalStandby,
        ]
        var actionsThatExposedRecovery: [String] = []
        let app = launchApp(
            fixture: "connected",
            language: "es",
            extraArguments: ["--scenario=delayed-success"]
        )
        defer { app.terminate() }
        waitForReady(in: app, label: "Listo", timeout: 20)
        let recoveryGate = app.descendants(matching: .any)[
            EstroboAccessibilityID.recoveryGate
        ].firstMatch

        for identifier in directActions {
            XCTAssertFalse(
                recoveryGate.exists,
                "Recovery must be absent before the direct action starts"
            )

            let action = app.buttons[identifier].firstMatch
            scrollToHittable(action, in: app)
            waitForEnabled(action)
            let initialValue = try XCTUnwrap(action.value as? String)
            action.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).tap()

            if recoveryGate.exists || recoveryGate.waitForExistence(timeout: 0.25) {
                actionsThatExposedRecovery.append(identifier)
            }

            let stable = XCTNSPredicateExpectation(
                predicate: NSPredicate { object, _ in
                    guard let element = object as? XCUIElement else { return false }
                    return element.exists
                        && element.isEnabled
                        && element.value as? String != initialValue
                },
                object: action
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [stable], timeout: 8),
                .completed,
                "The direct action must return enabled with its new stable value"
            )
            XCTAssertFalse(
                recoveryGate.exists,
                "Recovery must be absent after the successful action settles"
            )
        }

        XCTAssertTrue(
            actionsThatExposedRecovery.isEmpty,
            "Successful forward journals exposed recovery for: "
                + actionsThatExposedRecovery.joined(separator: ", ")
        )
    }

    @MainActor
    func testGlobalActionTilesExposeSelectedStateAndStandbyOverlay() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")

        let modeling = app.buttons[
            EstroboAccessibilityID.globalModeling
        ].firstMatch
        revealAbove(modeling, in: app)
        waitForEnabled(modeling)
        XCTAssertEqual(modeling.value as? String, "Encendido")
        XCTAssertTrue(modeling.isSelected)

        modeling.tap()
        expectation(
            for: NSPredicate(format: "value == 'Apagado' AND isSelected == false"),
            evaluatedWith: modeling
        )
        waitForExpectations(timeout: 5)
        waitForEnabled(modeling)

        let beep = app.buttons[EstroboAccessibilityID.globalBeep].firstMatch
        XCTAssertEqual(beep.value as? String, "Apagado")
        XCTAssertFalse(beep.isSelected)
        beep.tap()
        expectation(
            for: NSPredicate(format: "value == 'Encendido' AND isSelected == true"),
            evaluatedWith: beep
        )
        waitForExpectations(timeout: 5)

        let standby = app.buttons[
            EstroboAccessibilityID.globalStandby
        ].firstMatch
        waitForEnabled(standby)
        XCTAssertFalse(standby.isSelected)
        standby.tap()
        expectation(
            for: NSPredicate(format: "value == 'Encendido' AND isSelected == true"),
            evaluatedWith: standby
        )
        waitForExpectations(timeout: 5)

        for group in ["B", "C"] {
            let overlay = app.descendants(matching: .any)[
                EstroboAccessibilityID.groupStandbyOverlay(group)
            ].firstMatch
            revealForInspection(overlay, in: app)
            XCTAssertTrue(overlay.waitForExistence(timeout: 5))
            XCTAssertTrue(
                overlay.label.localizedCaseInsensitiveContains("Standby")
            )
            let increase = app.buttons[
                EstroboAccessibilityID.groupPowerIncrease(group)
            ].firstMatch
            XCTAssertTrue(increase.waitForExistence(timeout: 5))
            XCTAssertFalse(increase.isEnabled)
        }

        revealAbove(standby, in: app)
        waitForEnabled(standby)
        standby.tap()
        expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.descendants(matching: .any)[
                EstroboAccessibilityID.groupStandbyOverlay("B")
            ].firstMatch
        )
        waitForExpectations(timeout: 5)
        XCTAssertFalse(standby.isSelected)
    }

    @MainActor
    func testReturningFromAnotherAppKeepsTheReadySessionAvailable() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")

        let slider = app.sliders[
            EstroboAccessibilityID.groupPowerSlider("B")
        ].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertTrue(slider.isEnabled)

        XCUIDevice.shared.press(.home)
        let backgrounded = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let application = object as? XCUIApplication else {
                    return false
                }
                return application.state == .runningBackground
                    || application.state == .runningBackgroundSuspended
            },
            object: app
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [backgrounded], timeout: 5),
            .completed
        )

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitForReady(in: app, label: "Listo")
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertTrue(slider.isEnabled)
    }

    @MainActor
    func testOffGroupDisablesItsInlinePowerControls() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")

        let slider = app.sliders[
            EstroboAccessibilityID.groupPowerSlider("C")
        ].firstMatch
        reveal(slider, in: app)
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertTrue(slider.isEnabled)
        // This scenario verifies the disabled-state contract, not gesture
        // interpolation. Start on C's known fixture thumb and drag beyond the
        // first tick; revealing the taller ruler card is required first.
        drag(slider, from: 0.23, to: 0.02)

        let minimumReached = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '1/512 +0.0'"),
            object: slider
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [minimumReached], timeout: 5),
            .completed,
            "Expected the minimum power, got \(String(describing: slider.value))"
        )

        openGroupDetails("C", in: app)

        let mode = app.segmentedControls[
            EstroboAccessibilityID.groupMode("C")
        ].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        let off = mode.buttons["Off"].firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        off.tap()

        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()

        let decrease = app.buttons[
            EstroboAccessibilityID.groupPowerDecrease("C")
        ].firstMatch
        let increase = app.buttons[
            EstroboAccessibilityID.groupPowerIncrease("C")
        ].firstMatch
        XCTAssertTrue(decrease.waitForExistence(timeout: 5))
        XCTAssertTrue(increase.waitForExistence(timeout: 5))
        XCTAssertTrue(slider.exists)
        XCTAssertEqual(slider.value as? String, "1/512 +0.0")
        XCTAssertFalse(decrease.isEnabled)
        XCTAssertFalse(increase.isEnabled)
        XCTAssertFalse(slider.isEnabled)
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
            // NavigationSplitView can initially show only content and detail
            // on iOS 18. Reveal its native sidebar before checking all columns.
            if !regularSidebar.waitForExistence(timeout: 5) {
                let sidebarToggle = app.navigationBars.buttons["ToggleSidebar"]
                    .firstMatch
                XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
                sidebarToggle.tap()
            }
            XCTAssertTrue(regularSidebar.waitForExistence(timeout: 10))
            XCTAssertFalse(app.tabBars.firstMatch.exists)
            XCTAssertFalse(
                app.buttons[EstroboAccessibilityID.sidebarGlobal].firstMatch.exists
            )
            XCTAssertTrue(
                app.descendants(matching: .any)[EstroboAccessibilityID.globalScreen]
                    .firstMatch.waitForExistence(timeout: 5)
            )
            XCTAssertTrue(
                app.staticTexts["Select a group"].firstMatch
                    .waitForExistence(timeout: 5)
            )
            XCTAssertFalse(
                app.descendants(matching: .any)[
                    EstroboAccessibilityID.groupDetail("B")
                ].firstMatch.exists
            )

            app.terminate()
            let compact = launchApp(
                fixture: "workspace",
                language: "en",
                extraArguments: ["--layout=compact"]
            )
            XCTAssertTrue(compact.tabBars.firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(compact.tabBars.buttons.count, 3)
            XCTAssertFalse(
                compact.descendants(matching: .any)[EstroboAccessibilityID.tabGlobal]
                    .firstMatch.exists
            )
            XCTAssertFalse(
                compact.buttons[EstroboAccessibilityID.sidebarGroups]
                    .firstMatch.exists
            )
            XCTAssertTrue(
                compact.descendants(matching: .any)[EstroboAccessibilityID.globalScreen]
                    .firstMatch.waitForExistence(timeout: 5)
            )
            XCTAssertTrue(
                compact.descendants(matching: .any)[
                    EstroboAccessibilityID.groupRow("B")
                ]
                    .firstMatch.waitForExistence(timeout: 5)
            )
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(app.tabBars.buttons.count, 3)
            XCTAssertFalse(
                app.descendants(matching: .any)[EstroboAccessibilityID.tabGlobal]
                    .firstMatch.exists
            )
            XCTAssertFalse(
                app.buttons[EstroboAccessibilityID.sidebarGroups]
                    .firstMatch.exists
            )
            XCTAssertTrue(
                app.descendants(matching: .any)[EstroboAccessibilityID.globalScreen]
                    .firstMatch.waitForExistence(timeout: 5)
            )
            XCTAssertTrue(
                app.descendants(matching: .any)[
                    EstroboAccessibilityID.groupRow("B")
                ]
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
    func testTestFlashSendsDirectlyFromGroupsWithoutConfirmation() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")

        let send = app.buttons[
            EstroboAccessibilityID.testSend
        ].firstMatch
        reveal(send, in: app)
        waitForEnabled(send)
        XCTAssertFalse(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.testConfirmation
            ].firstMatch.exists
        )

        send.tap()

        XCTAssertFalse(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.testConfirmation
            ].firstMatch.exists
        )

        XCTAssertTrue(
            app.descendants(matching: .any)[EstroboAccessibilityID.testSent]
                .firstMatch
                .waitForExistence(timeout: 10)
        )

        selectPhoneSection(EstroboAccessibilityID.tabPresets, in: app)
        XCTAssertFalse(
            app.buttons[EstroboAccessibilityID.testSend].firstMatch.exists
        )
        selectPhoneSection(EstroboAccessibilityID.tabSettings, in: app)
        XCTAssertFalse(
            app.buttons[EstroboAccessibilityID.testSend].firstMatch.exists
        )
    }

    @MainActor
    func testMultiTogglesDirectlyAndScrubsItsNumericDraft() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "connected", language: "es")
        waitForReady(in: app, label: "Listo")

        let multiToggle = app.buttons[
            EstroboAccessibilityID.multiToggle
        ].firstMatch
        reveal(multiToggle, in: app)
        waitForEnabled(multiToggle)
        XCTAssertEqual(multiToggle.value as? String, "Multi inactivo")
        XCTAssertFalse(multiToggle.isSelected)
        XCTAssertFalse(
            app.buttons[EstroboAccessibilityID.groupDetailOpen("B")]
                .firstMatch.exists
        )
        let inlinePower = app.sliders[
            EstroboAccessibilityID.groupPowerSlider("B")
        ].firstMatch
        reveal(inlinePower, in: app)
        XCTAssertTrue(inlinePower.waitForExistence(timeout: 5))
        revealAbove(multiToggle, in: app)
        let globalPower = app.sliders[
            EstroboAccessibilityID.globalPowerSlider
        ].firstMatch
        XCTAssertTrue(globalPower.waitForExistence(timeout: 5))
        multiToggle.tap()
        XCTAssertFalse(app.navigationBars["Multi"].firstMatch.exists)
        waitForDisappearance(globalPower)
        for actionID in [
            EstroboAccessibilityID.globalBeep,
            EstroboAccessibilityID.globalModeling,
            EstroboAccessibilityID.globalStandby,
            EstroboAccessibilityID.multiToggle,
        ] {
            XCTAssertTrue(
                app.buttons[actionID].firstMatch.exists,
                "Global action \(actionID) must remain visible while Multi is active."
            )
        }
        attachScreenshot(
            named: "Multi 01 - Acciones sin potencia global",
            of: app
        )

        let participantB = app.switches[
            EstroboAccessibilityID.multiParticipant("B")
        ].firstMatch
        reveal(participantB, in: app)
        XCTAssertTrue(participantB.exists)
        XCTAssertFalse(
            app.buttons[EstroboAccessibilityID.groupDetailOpen("B")]
                .firstMatch.exists
        )
        waitForDisappearance(inlinePower)

        openGroupDetails("B", in: app)
        let detailBack = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(detailBack.waitForExistence(timeout: 5))
        detailBack.tap()

        let count = app.sliders[EstroboAccessibilityID.multiCount].firstMatch
        reveal(count, in: app)
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.isEnabled)
        let initialCount = try XCTUnwrap(count.value as? String)
        drag(count, from: 0.48, to: 0.78)
        expectation(
            for: NSPredicate(format: "value != %@", initialCount),
            evaluatedWith: count
        )
        waitForExpectations(timeout: 5)

        let hertz = app.sliders[EstroboAccessibilityID.multiHertz].firstMatch
        reveal(hertz, in: app)
        XCTAssertTrue(hertz.waitForExistence(timeout: 5))
        XCTAssertTrue(hertz.isEnabled)
        hertz.adjust(toNormalizedSliderPosition: 1.0)
        expectation(
            for: NSPredicate(format: "value == '199 Hz'"),
            evaluatedWith: hertz
        )
        waitForExpectations(timeout: 5)

        let apply = app.buttons[EstroboAccessibilityID.apply].firstMatch
        waitForEnabled(apply)
        apply.tap()

        revealAbove(multiToggle, in: app)
        waitForEnabled(multiToggle)
        XCTAssertEqual(multiToggle.value as? String, "Multi activo")
        XCTAssertTrue(multiToggle.isSelected)
        multiToggle.tap()
        XCTAssertFalse(app.navigationBars["Multi"].firstMatch.exists)
        expectation(
            for: NSPredicate(
                format: "value == 'Multi inactivo' AND isSelected == false"
            ),
            evaluatedWith: multiToggle
        )
        waitForExpectations(timeout: 5)
        waitForDisappearance(participantB)
        XCTAssertTrue(globalPower.waitForExistence(timeout: 5))
        XCTAssertTrue(inlinePower.waitForExistence(timeout: 5))
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
        let notNow = app.alerts.buttons["Ahora no"].firstMatch
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        notNow.tap()
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

        let autoConnect = app.switches[
            EstroboAccessibilityID.savedRadioAutoConnect(primaryID)
        ].firstMatch
        reveal(autoConnect, in: app)
        XCTAssertTrue(autoConnect.waitForExistence(timeout: 5))
        XCTAssertTrue(autoConnect.isEnabled)
        XCTAssertEqual(autoConnect.value as? String, "0")
        autoConnect.coordinate(
            withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)
        ).tap()
        expectation(
            for: NSPredicate(format: "value == '1'"),
            evaluatedWith: autoConnect
        )
        waitForExpectations(timeout: 5)

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
    func testLaunchOffersTheLastConnectedTransmitter() throws {
        try requirePhoneForDenseControlFlow()
        let app = launchApp(fixture: "saved-radios", language: "es")

        let alert = app.alerts["Último radio"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(
            alert.staticTexts[
                "¿Quieres buscar y conectarte a ESTROBO SIMULADO?"
            ].exists
        )
        let connect = alert.buttons["Buscar y conectar"].firstMatch
        XCTAssertTrue(connect.exists)
        connect.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[EstroboAccessibilityID.connectionSheet]
                .firstMatch.waitForExistence(timeout: 5)
        )
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

        let englishGroupB = english.descendants(matching: .any)[
            EstroboAccessibilityID.groupRow("B")
        ].firstMatch
        reveal(englishGroupB, in: english)
        XCTAssertTrue(englishGroupB.waitForExistence(timeout: 5))
        englishGroupB.tap()
        XCTAssertFalse(
            english.descendants(matching: .any)[
                EstroboAccessibilityID.groupDetail("B")
            ].firstMatch.exists
        )

        let increase = english.buttons[
            EstroboAccessibilityID.groupPowerIncrease("B")
        ].firstMatch
        reveal(increase, in: english)
        waitForEnabled(increase)
        increase.tap()

        let confirmation = english.descendants(matching: .any)[
            EstroboAccessibilityID.groupRow("B")
        ].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue((confirmation.value as? String)?.contains("PENDING") == true)

        let discard = english.buttons[
            EstroboAccessibilityID.discard
        ].firstMatch
        reveal(discard, in: english)
        waitForEnabled(discard)
        discard.tap()
        expectation(
            for: NSPredicate(format: "NOT (value CONTAINS 'PENDING')"),
            evaluatedWith: confirmation
        )
        waitForExpectations(timeout: 5)

        openGroupDetails("B", in: english)

        let detailPower = english.sliders[
            EstroboAccessibilityID.groupDetailPowerSlider("B")
        ].firstMatch
        XCTAssertTrue(detailPower.waitForExistence(timeout: 5))

        let modeling = english.segmentedControls[
            EstroboAccessibilityID.groupModeling("B")
        ].firstMatch
        XCTAssertTrue(modeling.waitForExistence(timeout: 5))
        XCTAssertTrue(modeling.buttons["Off"].exists)
        XCTAssertTrue(modeling.buttons["Proportional"].exists)
        let manual = modeling.buttons["Manual"].firstMatch
        XCTAssertTrue(manual.exists)
        manual.tap()

        let manualModeling = english.sliders[
            EstroboAccessibilityID.groupModelingManualSlider("B")
        ].firstMatch
        reveal(manualModeling, in: english)
        XCTAssertTrue(manualModeling.isEnabled)
        manualModeling.adjust(toNormalizedSliderPosition: 0.0)
        expectation(
            for: NSPredicate { object, _ in
                (object as? XCUIElement)?.value as? String == "10%"
            },
            evaluatedWith: manualModeling
        )
        waitForExpectations(timeout: 5)

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
            fixture: "connected",
            language: "en",
            appearance: "dark",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        )
        waitForReady(in: app, label: "Ready")

        for identifier in [
            EstroboAccessibilityID.globalBeep,
            EstroboAccessibilityID.globalModeling,
            EstroboAccessibilityID.globalStandby,
            EstroboAccessibilityID.multiToggle,
        ] {
            let action = app.buttons[identifier].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 10))
            reveal(action, in: app)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            XCTAssertFalse(action.label.isEmpty)
        }

        let increase = app.buttons[
            EstroboAccessibilityID.groupPowerIncrease("B")
        ].firstMatch
        XCTAssertTrue(increase.waitForExistence(timeout: 10))
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
    private func attachScreenshot(named name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func attachFailureState(named name: String, of app: XCUIApplication) {
        attachScreenshot(named: name, of: app)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    @MainActor
    private func drag(
        _ slider: XCUIElement,
        from startOffset: CGFloat,
        to endOffset: CGFloat
    ) {
        let start = slider.coordinate(
            withNormalizedOffset: CGVector(dx: startOffset, dy: 0.5)
        )
        let end = slider.coordinate(
            withNormalizedOffset: CGVector(dx: endOffset, dy: 0.5)
        )
        start.press(
            forDuration: 0.2,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
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
        case EstroboAccessibilityID.tabPresets:
            index = 1
        case EstroboAccessibilityID.tabSettings:
            index = 2
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
    private func revealTabletGroupsWorkspaceIfNeeded(in app: XCUIApplication) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let status = app.buttons[EstroboAccessibilityID.sessionStatus].firstMatch
        // A regular-width three-column split can start with just the inspector
        // in portrait. Its first native sidebar toggle reveals the content.
        if !status.waitForExistence(timeout: 3) {
            let toggle = app.navigationBars.buttons["ToggleSidebar"].firstMatch
            guard toggle.waitForExistence(timeout: 5) else {
                attachFailureState(named: "tablet-content-navigation-missing", of: app)
                XCTFail("The native split navigation must reveal Groups")
                return
            }
            toggle.tap()
        }
        guard status.waitForExistence(timeout: 10) else {
            attachFailureState(named: "tablet-content-did-not-appear", of: app)
            XCTFail("Groups must expose the session action after native navigation")
            return
        }
        XCTAssertTrue(status.isHittable)
        XCTAssertTrue(
            app.descendants(matching: .any)[EstroboAccessibilityID.globalScreen]
                .firstMatch.waitForExistence(timeout: 5)
        )
    }

    @MainActor
    private func openGroupDetails(_ group: String, in app: XCUIApplication) {
        let cardHeader = app.descendants(matching: .any)[
            EstroboAccessibilityID.groupRow(group)
        ].firstMatch
        reveal(cardHeader, in: app)
        XCTAssertTrue(cardHeader.waitForExistence(timeout: 10))
        cardHeader.press(forDuration: 0.7)
        XCTAssertTrue(
            app.descendants(matching: .any)[
                EstroboAccessibilityID.groupDetail(group)
            ].firstMatch.waitForExistence(timeout: 5)
        )
    }

    @MainActor
    private func waitForReady(
        in app: XCUIApplication,
        label: String,
        timeout: TimeInterval = 15
    ) {
        let status = app.buttons[EstroboAccessibilityID.sessionStatus].firstMatch
        guard status.waitForExistence(timeout: 10) else {
            attachFailureState(named: "session-status-did-not-appear", of: app)
            XCTFail("The session status must remain accessible")
            return
        }
        let ready = NSPredicate(
            format: "label CONTAINS[c] %@",
            label
        )
        let readiness = XCTNSPredicateExpectation(predicate: ready, object: status)
        let result = XCTWaiter.wait(for: [readiness], timeout: timeout)
        if result != .completed {
            attachFailureState(named: "session-did-not-reach-ready", of: app)
        }
        XCTAssertEqual(result, .completed, "The session must reach Ready")
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
    private func revealForInspection(
        _ element: XCUIElement,
        in app: XCUIApplication,
        bottomClearance: CGFloat = 96
    ) {
        let unobscuredBottom = app.frame.maxY - bottomClearance
        for _ in 0..<8 where
            !element.exists || element.frame.maxY > unobscuredBottom {
            app.swipeUp()
        }
        XCTAssertTrue(element.exists)
        XCTAssertLessThanOrEqual(element.frame.maxY, unobscuredBottom)
    }

    @MainActor
    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let topClearance = app.frame.minY + 110
        let bottomClearance = app.frame.maxY - 96

        for _ in 0..<10 where !element.isHittable {
            if element.frame.minY < topClearance {
                app.swipeDown()
            } else if element.frame.maxY > bottomClearance {
                app.swipeUp()
            } else {
                break
            }
        }

        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func revealAbove(
        _ element: XCUIElement,
        in app: XCUIApplication,
        topClearance: CGFloat = 160
    ) {
        let unobscuredTop = app.frame.minY + topClearance
        for _ in 0..<8 where
            !element.isHittable || element.frame.minY < unobscuredTop {
            app.swipeDown()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.minY, unobscuredTop)
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
        timeout: TimeInterval = 5,
        app: XCUIApplication? = nil
    ) {
        let gone = NSPredicate(format: "exists == false")
        let disappearance = XCTNSPredicateExpectation(predicate: gone, object: element)
        let result = XCTWaiter.wait(for: [disappearance], timeout: timeout)
        if result != .completed, let app {
            attachFailureState(named: "connection-sheet-did-not-dismiss", of: app)
        }
        XCTAssertEqual(result, .completed, "The presented element must disappear")
    }

    @MainActor
    private func assertRemainsAbsent(
        _ element: XCUIElement,
        for duration: TimeInterval,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let appearance = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: element
        )
        appearance.isInverted = true
        XCTAssertEqual(
            XCTWaiter.wait(for: [appearance], timeout: duration),
            .completed,
            message,
            file: file,
            line: line
        )
    }
}
