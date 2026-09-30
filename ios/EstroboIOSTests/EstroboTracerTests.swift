import XCTest
import EstroboCore
import SwiftUI
@testable import EstroboIOS

final class EstroboTracerTests: XCTestCase {
    @MainActor
    func testDemoRuntimeUsesOneSimulatedControllerAndMemoryIsolation() {
        let runtime = AppRuntimeFactory.makeDemo(seed: .workspace)

        XCTAssertEqual(runtime.mode, .demo)
        XCTAssertEqual(runtime.isolation, .inMemoryOnly)
        XCTAssertTrue(runtime.controller.isSimulation)
        XCTAssertTrue(runtime.controller.hasCompletedOnboarding)
        XCTAssertEqual(runtime.controller.workingGroups, [.b, .c])
        XCTAssertEqual(runtime.controller.changeDeliveryMode, .manual)
    }

    @MainActor
    func testHumanDemoRequiresExplicitWorkspaceConfiguration() {
        let configuration = UITestConfiguration(
            isEnabled: false,
            fixture: .onboarding,
            scenario: .normal,
            language: .es,
            appearance: .light
        )
        let coordinator = AppSessionCoordinator(uiTestConfiguration: configuration)

        coordinator.chooseDemo()

        let controller = coordinator.controller
        XCTAssertNotNil(controller)
        XCTAssertTrue(controller?.isSimulation == true)
        XCTAssertFalse(controller?.hasCompletedOnboarding == true)
        XCTAssertFalse(coordinator.connectionPresented)

        let completed = coordinator.completeWorkspace(
            profileID: TransmitterProfile.classicLetters.id,
            groups: [.b],
            models: [.b: ["ad400pro-ii"]]
        )

        XCTAssertTrue(completed)
        XCTAssertTrue(controller?.hasCompletedOnboarding == true)
        XCTAssertEqual(controller?.workingGroups, [.b])
        XCTAssertTrue(coordinator.connectionPresented)
    }

    func testFixtureArgumentsAreIgnoredWithoutUITestingGate() {
        let configuration = UITestConfiguration.parse(arguments: [
            "Estrobo",
            "--fixture=connected",
            "--scenario=bluetoothDenied",
        ])

        XCTAssertFalse(configuration.isEnabled)
        XCTAssertEqual(configuration.fixture, .onboarding)
        XCTAssertEqual(configuration.scenario, .normal)
    }

    func testFixtureArgumentsAreParsedBehindUITestingGate() {
        let configuration = UITestConfiguration.parse(arguments: [
            "Estrobo",
            "--ui-testing",
            "--fixture", "connected",
            "--language=en",
            "--appearance=dark",
        ])

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertEqual(configuration.fixture, .connected)
        XCTAssertEqual(configuration.language, .en)
        XCTAssertEqual(configuration.appearance, .dark)
    }

    @MainActor
    func testForegroundContractSuspendsAndResumesWithoutImplicitWork() {
        let runtime = AppRuntimeFactory.makeDemo(seed: .workspace)
        let controller = runtime.controller

        controller.suspendForInactiveScene()
        XCTAssertFalse(controller.isSceneActive)
        XCTAssertEqual(controller.phase, .idle)

        controller.resumeActiveScene()
        XCTAssertTrue(controller.isSceneActive)
        XCTAssertNil(controller.foregroundSessionRequirement)
        XCTAssertEqual(controller.phase, .idle)
    }

    @MainActor
    func testScenePhaseBridgeSuspendsAndResumesExactlyOnceAcrossBackground() {
        var suspendCount = 0
        var resumeCount = 0
        var bridge = ScenePhaseBridge(
            integration: .connected,
            suspend: { suspendCount += 1 },
            resume: { resumeCount += 1 }
        )

        bridge.handle(.inactive)
        bridge.handle(.background)
        bridge.handle(.active)
        bridge.handle(.active)

        XCTAssertEqual(suspendCount, 1)
        XCTAssertEqual(resumeCount, 1)
        XCTAssertFalse(bridge.isSuspended)
    }

    func testCoreAccessibilityIdentifiersAreStableAndUnique() {
        let identifiers = [
            EstroboAccessibilityID.appRoot,
            EstroboAccessibilityID.onboardingRoot,
            EstroboAccessibilityID.runtimeDemo,
            EstroboAccessibilityID.demoBanner,
            EstroboAccessibilityID.workspaceRoot,
            EstroboAccessibilityID.sessionStatus,
            EstroboAccessibilityID.connectionScan,
            EstroboAccessibilityID.connectionConnect,
            EstroboAccessibilityID.apply,
            EstroboAccessibilityID.discard,
            EstroboAccessibilityID.deliveryMode,
            EstroboAccessibilityID.deliveryAutomaticFeedback,
            EstroboAccessibilityID.globalScreen,
            EstroboAccessibilityID.globalBeep,
            EstroboAccessibilityID.globalModeling,
            EstroboAccessibilityID.globalStandby,
            EstroboAccessibilityID.testSend,
            EstroboAccessibilityID.testConfirmation,
            EstroboAccessibilityID.testConfirm,
            EstroboAccessibilityID.multiToggle,
            EstroboAccessibilityID.presetSave,
            EstroboAccessibilityID.savedRadios,
            EstroboAccessibilityID.recoveryGate,
            EstroboAccessibilityID.recoveryWrongDevice,
            EstroboAccessibilityID.compatibility,
            EstroboAccessibilityID.demoLab,
        ]

        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("estrobo.") })
    }

    func testInlineGroupPowerAccessibilityIdentifiersAreStableAndUnique() {
        let identifiers = ["B", "C"].flatMap { group in
            [
                EstroboAccessibilityID.groupPower(group),
                EstroboAccessibilityID.groupPowerSlider(group),
                EstroboAccessibilityID.groupPowerDecrease(group),
                EstroboAccessibilityID.groupPowerIncrease(group),
                EstroboAccessibilityID.groupDetailPower(group),
                EstroboAccessibilityID.groupDetailPowerSlider(group),
                EstroboAccessibilityID.groupModelingManualSlider(group),
                EstroboAccessibilityID.groupStandbyOverlay(group),
            ]
        }

        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("estrobo.group.") })
    }

    func testMultiHertzScaleUsesTheRequestedDiscreteValues() {
        XCTAssertEqual(
            MultiHertzScale.values,
            Array(1...20)
                + Array(stride(from: 25, through: 50, by: 5))
                + Array(stride(from: 60, through: 190, by: 10))
                + [199]
        )
        XCTAssertEqual(MultiHertzScale.values.count, 41)
        XCTAssertEqual(MultiHertzScale.values.first, 1)
        XCTAssertEqual(MultiHertzScale.values.last, 199)
        XCTAssertEqual(
            Array(MultiHertzScale.values[18...22]),
            [19, 20, 25, 30, 35]
        )
        XCTAssertEqual(
            Array(MultiHertzScale.values.suffix(3)),
            [180, 190, 199]
        )
    }

    @MainActor
    func testDeterministicSliderFinishesOneContinuousTouchInteraction() {
        var boundValue = 0.0
        var lifecycle: [String] = []
        let slider = DeterministicSlider(
            value: Binding(
                get: { boundValue },
                set: { boundValue = $0 }
            ),
            range: 0...10,
            step: 1,
            isEnabled: true,
            accessibilityLabel: "Power",
            accessibilityValue: "0",
            accessibilityIdentifier: "slider",
            onInteractionBegan: { lifecycle.append("began") },
            onInteractionEnded: { lifecycle.append("ended") },
            onInteractionCancelled: { lifecycle.append("cancelled") }
        )
        let coordinator = slider.makeCoordinator()

        coordinator.beginInteraction()
        coordinator.changeInteractionValue(2.2, isTracking: true)
        coordinator.changeInteractionValue(6.7, isTracking: true)

        XCTAssertTrue(coordinator.isInteracting)
        XCTAssertEqual(boundValue, 7)
        XCTAssertEqual(lifecycle, ["began"])

        coordinator.endInteraction()
        coordinator.endInteraction()

        XCTAssertFalse(coordinator.isInteracting)
        XCTAssertEqual(lifecycle, ["began", "ended"])
    }

    @MainActor
    func testDeterministicSliderClosesNonTouchChangesAndCancelsExactlyOnce() {
        var boundValue = 0.0
        var lifecycle: [String] = []
        let slider = DeterministicSlider(
            value: Binding(
                get: { boundValue },
                set: { boundValue = $0 }
            ),
            range: 0...10,
            step: 1,
            isEnabled: true,
            accessibilityLabel: "Power",
            accessibilityValue: "0",
            accessibilityIdentifier: "slider",
            onInteractionBegan: { lifecycle.append("began") },
            onInteractionEnded: { lifecycle.append("ended") },
            onInteractionCancelled: { lifecycle.append("cancelled") }
        )
        let coordinator = slider.makeCoordinator()

        coordinator.changeInteractionValue(3.6, isTracking: false)

        XCTAssertEqual(boundValue, 4)
        XCTAssertFalse(coordinator.isInteracting)
        XCTAssertEqual(lifecycle, ["began", "ended"])

        coordinator.beginInteraction()
        coordinator.changeInteractionValue(8.1, isTracking: true)
        DeterministicSlider.dismantleUIView(
            UISlider(),
            coordinator: coordinator
        )
        coordinator.cancelInteraction()

        XCTAssertEqual(boundValue, 8)
        XCTAssertFalse(coordinator.isInteracting)
        XCTAssertEqual(lifecycle, ["began", "ended", "began", "cancelled"])
    }

    @MainActor
    func testDeterministicSliderCancelsChangedTouchCancellationAndHardCancelSafely() {
        var boundValue = 0.0
        var lifecycle: [String] = []
        let slider = DeterministicSlider(
            value: Binding(
                get: { boundValue },
                set: { boundValue = $0 }
            ),
            range: 0...10,
            step: 1,
            isEnabled: true,
            accessibilityLabel: "Power",
            accessibilityValue: "0",
            accessibilityIdentifier: "slider",
            onInteractionBegan: { lifecycle.append("began") },
            onInteractionEnded: { lifecycle.append("ended") },
            onInteractionCancelled: { lifecycle.append("cancelled") }
        )
        let coordinator = slider.makeCoordinator()

        coordinator.beginInteraction()
        coordinator.changeInteractionValue(6.2, isTracking: true)
        coordinator.touchCancelled(UISlider())

        XCTAssertEqual(boundValue, 6)
        XCTAssertFalse(coordinator.isInteracting)
        XCTAssertEqual(lifecycle, ["began", "cancelled"])

        coordinator.beginInteraction()
        coordinator.changeInteractionValue(8.1, isTracking: true)
        coordinator.cancelInteraction()

        XCTAssertEqual(boundValue, 8)
        XCTAssertFalse(coordinator.isInteracting)
        XCTAssertEqual(lifecycle, ["began", "cancelled", "began", "cancelled"])
    }

    @MainActor
    func testDeterministicSliderAccessibilityMovesExactlyOneStep() {
        let slider = SteppedUISlider()
        slider.minimumValue = 0
        slider.maximumValue = 10
        slider.value = 4
        slider.accessibilityStep = 1

        slider.accessibilityIncrement()
        XCTAssertEqual(slider.value, 5)

        slider.accessibilityDecrement()
        XCTAssertEqual(slider.value, 4)

        slider.value = slider.maximumValue
        slider.accessibilityIncrement()
        XCTAssertEqual(slider.value, slider.maximumValue)
    }

    func testAutomaticDeliveryFeedbackOnlySynchronizesForDebounceOrIO() {
        XCTAssertEqual(
            AutomaticDeliveryFeedbackActivity(
                isDebounceScheduled: false,
                isIOActive: false
            ),
            .idle
        )
        XCTAssertEqual(
            AutomaticDeliveryFeedbackActivity(
                isDebounceScheduled: true,
                isIOActive: false
            ),
            .synchronizing
        )
        XCTAssertEqual(
            AutomaticDeliveryFeedbackActivity(
                isDebounceScheduled: false,
                isIOActive: true
            ),
            .synchronizing
        )
        XCTAssertEqual(
            AutomaticDeliveryFeedbackActivity(
                isDebounceScheduled: false,
                isIOActive: true
            ),
            .synchronizing
        )
        XCTAssertEqual(
            AutomaticDeliveryFeedbackActivity(
                isDebounceScheduled: false,
                isIOActive: false
            ),
            .idle
        )
        XCTAssertEqual(
            AutomaticDeliveryFeedbackActivity(
                isDebounceScheduled: true,
                isIOActive: true,
                suppressesGlobalActionFeedback: true
            ),
            .idle
        )
    }

    func testAutomaticDeliveryFeedbackDisappearsWhenSynchronizationFinishes() {
        XCTAssertNil(
            reducedAutomaticDeliveryFeedbackPhase(
                current: .syncing,
                activity: .idle
            )
        )
    }

    func testRedesignLocalizationKeysResolveInSpanishAndEnglish() {
        let keys = [
            "group.power",
            "group.power.accessibility",
            "group.power.decrease.accessibility",
            "group.power.increase.accessibility",
            "group.detail.open",
            "group.detail.long-press.hint",
            "global.power.slider.title",
            "global.power.slider.reset",
            "global.power.slider.accessibility",
            "slider.minimum",
            "slider.maximum",
            "group.detail.open.accessibility",
            "modeling.manual",
            "modeling.manual.level",
            "modeling.manual.value",
            "modeling.manual.slider.accessibility",
            "delivery.title",
            "delivery.automatic",
            "delivery.automatic.pending",
            "delivery.automatic.unscheduled",
            "delivery.automatic.complete",
            "delivery.manual",
            "launch.connection.title",
            "launch.connection.message",
            "launch.connection.connect",
            "launch.connection.not-now",
            "saved.last-connected",
            "saved.auto-connect",
            "saved.auto-connect.detail",
            "test.title",
            "test.action",
            "test.pending",
            "test.block.pending",
        ]

        for language in EstroboLanguage.allCases {
            for key in keys {
                XCTAssertNotEqual(
                    language.localized(key),
                    key,
                    "Missing \(language.rawValue) localization for \(key)."
                )
            }
            XCTAssertEqual(language.localized("test.action"), "Test")
        }
        XCTAssertEqual(
            EstroboLanguage.es.localized("modeling.off"),
            "Apagado"
        )
        XCTAssertEqual(
            EstroboLanguage.es.localized("global.power.slider.title"),
            "Control Global"
        )
    }

    func testPeripheralAccessibilityIdentifiersRedactCoreBluetoothUUIDs() {
        let identifier = UUID(
            uuidString: "E5700B00-0000-4000-8000-00000000C0DE"
        )!
        let fullIdentifier = identifier.uuidString.lowercased()
        let identifiers = [
            EstroboAccessibilityID.candidate(identifier),
            EstroboAccessibilityID.savedRadio(identifier),
            EstroboAccessibilityID.savedRadioForget(identifier),
        ]

        XCTAssertTrue(identifiers.allSatisfy { !$0.contains(fullIdentifier) })
        XCTAssertTrue(identifiers.allSatisfy { $0.contains("redacted-c0de") })
    }

    @MainActor
    func testForegroundRecoveryNoticeRedactsCoreBluetoothUUID() throws {
        let runtime = AppRuntimeFactory.makeDemo(seed: .recoveryWrongUUID)
        let controller = runtime.controller
        let requiredIdentifier = try XCTUnwrap(
            controller.restorationPoints.values.first?.deviceID
        )

        controller.suspendForInactiveScene()
        controller.resumeActiveScene()

        let notice = try XCTUnwrap(controller.foregroundInterruptionNotice)
        XCTAssertFalse(notice.contains(requiredIdentifier.uuidString))
        XCTAssertTrue(notice.contains("CB-REDACTED-DEAD"))
        XCTAssertFalse(
            controller.activity.contains {
                $0.message.contains(requiredIdentifier.uuidString)
            }
        )
    }

    func testDemoLabExposesExactlyTheSevenSupportedScenarios() {
        let expected = Set([
            "normal",
            "authenticationRejected",
            "syncTimeout",
            "controlWriteFailure",
            "fec8Timeout",
            "disconnectDuringWrite",
            "bluetoothDenied",
        ])
        let parsed = Set(expected.map { rawValue in
            UITestConfiguration.parse(arguments: [
                "Estrobo",
                "--ui-testing",
                "--scenario=\(rawValue)",
            ]).scenario.rawValue
        })

        XCTAssertEqual(parsed, expected)
    }

    @MainActor
    func testWorkspaceDestinationsExcludeStandaloneGlobalAndMapRemainingTabs() {
        let coordinator = AppSessionCoordinator()

        XCTAssertEqual(
            PhoneWorkspaceSection.allCases.map(\.rawValue),
            ["groups", "presets", "settings"]
        )
        XCTAssertEqual(
            TabletDestination.allCases.map(\.rawValue),
            ["connection", "groups", "presets", "savedRadios", "settings", "demo"]
        )

        coordinator.navigate(to: .groups)
        XCTAssertEqual(coordinator.phoneSection, .groups)
        XCTAssertEqual(coordinator.tabletDestination, .groups)

        coordinator.navigate(to: .presets)
        XCTAssertEqual(coordinator.phoneSection, .presets)
        XCTAssertEqual(coordinator.tabletDestination, .presets)

        coordinator.navigate(to: .settings)
        XCTAssertEqual(coordinator.phoneSection, .settings)
        XCTAssertEqual(coordinator.tabletDestination, .settings)
    }

    @MainActor
    func testExitDemoReturnsToRuntimeChoiceWithoutReusingController() {
        let configuration = UITestConfiguration(
            isEnabled: true,
            fixture: .workspace,
            scenario: .normal,
            language: .es,
            appearance: .light
        )
        let coordinator = AppSessionCoordinator(uiTestConfiguration: configuration)
        let originalController = coordinator.controller

        XCTAssertNotNil(originalController)
        XCTAssertTrue(coordinator.isDemo)

        coordinator.exitDemo()

        XCTAssertNil(coordinator.runtime)
        XCTAssertNil(coordinator.controller)
        XCTAssertFalse(coordinator.isDemo)
        XCTAssertEqual(coordinator.phoneSection, .groups)
        XCTAssertEqual(coordinator.tabletDestination, .groups)
    }

    @MainActor
    func testResetDemoSuspendsRetainedControllerBeforeInstallingReplacement() async throws {
        let configuration = UITestConfiguration(
            isEnabled: true,
            fixture: .workspace,
            scenario: .normal,
            language: .es,
            appearance: .light
        )
        let coordinator = AppSessionCoordinator(uiTestConfiguration: configuration)
        let originalController = try XCTUnwrap(coordinator.controller)

        originalController.startScanning()
        XCTAssertEqual(originalController.phase, .scanning)

        var factoryObservedReleasedRuntime = false
        coordinator.replaceRuntime {
            factoryObservedReleasedRuntime = true
            XCTAssertNil(coordinator.runtime)
            XCTAssertFalse(originalController.isSceneActive)
            XCTAssertEqual(originalController.phase, .idle)
            return AppRuntimeFactory.makeDemo(
                scenario: .authenticationRejected,
                seed: .workspace
            )
        }

        let replacementController = try XCTUnwrap(coordinator.controller)
        XCTAssertTrue(factoryObservedReleasedRuntime)
        XCTAssertFalse(originalController === replacementController)
        XCTAssertFalse(originalController.isSceneActive)
        XCTAssertEqual(originalController.phase, .idle)
        XCTAssertEqual(coordinator.runtime?.demoScenario, .authenticationRejected)

        try await Task.sleep(for: .milliseconds(180))

        XCTAssertFalse(originalController.isSceneActive)
        XCTAssertEqual(originalController.phase, .idle)
        XCTAssertTrue(originalController.devices.isEmpty)
    }

    @MainActor
    func testRecoveryFixtureRequiresTheOriginalPhysicalUUID() {
        let runtime = AppRuntimeFactory.makeDemo(seed: .recoveryWrongUUID)
        let requiredIDs = Set(runtime.controller.restorationPoints.values.map(\.deviceID))
        let simulatedID = UUID(
            uuidString: "E5700B00-0000-4000-8000-000000000001"
        )!

        XCTAssertEqual(requiredIDs.count, 1)
        XCTAssertFalse(requiredIDs.contains(simulatedID))
        XCTAssertFalse(runtime.controller.canApply)
    }

    @MainActor
    func testSavedRadioFixtureForgetsOnlyOneTransmitterAndIsMemoryIsolated() {
        let first = AppRuntimeFactory.makeDemo(seed: .savedRadios)
        let controller = first.controller
        let originalIDs = Set(controller.savedRadios.map(\.deviceID))
        let simulatedID = UUID(
            uuidString: "E5700B00-0000-4000-8000-000000000001"
        )!

        XCTAssertEqual(originalIDs.count, 2)
        controller.forgetSavedRadio(simulatedID)
        XCTAssertEqual(controller.savedRadios.count, 1)
        XCTAssertFalse(
            controller.savedRadios.contains {
                $0.deviceID == simulatedID
            }
        )

        let second = AppRuntimeFactory.makeDemo(seed: .savedRadios)
        XCTAssertEqual(Set(second.controller.savedRadios.map(\.deviceID)), originalIDs)
    }

    @MainActor
    func testOpeningWithLastRadioOffersConnectionBeforeScanning() throws {
        let configuration = UITestConfiguration(
            isEnabled: true,
            fixture: .savedRadios,
            scenario: .normal,
            language: .es,
            appearance: .light
        )
        let coordinator = AppSessionCoordinator(uiTestConfiguration: configuration)
        let controller = try XCTUnwrap(coordinator.controller)
        let last = try XCTUnwrap(controller.lastConnectedSavedRadio)

        coordinator.handleScenePhase(.active)

        XCTAssertEqual(
            coordinator.launchConnectionOffer,
            LaunchConnectionOffer(id: last.deviceID, name: last.name)
        )
        XCTAssertEqual(controller.phase, .idle)

        // SwiftUI clears an item-backed alert binding as it dismisses. The
        // button action must therefore use the offer captured by the alert,
        // not depend on the binding still being populated.
        let presentedOffer = try XCTUnwrap(coordinator.launchConnectionOffer)
        coordinator.launchConnectionOffer = nil
        coordinator.connectLaunchOffer(presentedOffer)

        XCTAssertNil(coordinator.launchConnectionOffer)
        XCTAssertTrue(coordinator.connectionPresented)
        XCTAssertEqual(controller.pendingSavedRadioConnectionID, last.deviceID)
        XCTAssertEqual(controller.phase, .scanning)
    }

    @MainActor
    func testOpeningStillOffersLastRadioWhenBluetoothIsUnavailable() async throws {
        let configuration = UITestConfiguration(
            isEnabled: true,
            fixture: .savedRadios,
            scenario: .bluetoothDenied,
            language: .es,
            appearance: .light
        )
        let coordinator = AppSessionCoordinator(uiTestConfiguration: configuration)
        let controller = try XCTUnwrap(coordinator.controller)
        let last = try XCTUnwrap(controller.lastConnectedSavedRadio)

        controller.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(controller.phase, .unavailable("permission denied"))

        coordinator.handleScenePhase(.active)

        XCTAssertEqual(
            coordinator.launchConnectionOffer,
            LaunchConnectionOffer(id: last.deviceID, name: last.name)
        )
    }

    @MainActor
    func testAutomaticRadioPreferenceStartsExactSearchWithoutOffer() throws {
        let configuration = UITestConfiguration(
            isEnabled: true,
            fixture: .savedRadios,
            scenario: .normal,
            language: .es,
            appearance: .light
        )
        let coordinator = AppSessionCoordinator(uiTestConfiguration: configuration)
        let controller = try XCTUnwrap(coordinator.controller)
        let last = try XCTUnwrap(controller.lastConnectedSavedRadio)
        controller.setAutomaticConnectionEnabled(true, for: last.deviceID)

        coordinator.handleScenePhase(.active)

        XCTAssertNil(coordinator.launchConnectionOffer)
        XCTAssertTrue(coordinator.connectionPresented)
        XCTAssertEqual(controller.pendingSavedRadioConnectionID, last.deviceID)
        XCTAssertEqual(controller.phase, .scanning)
    }

    @MainActor
    func testAutomaticRadioPreferenceRemainsPendingWhileBluetoothIsUnavailable() async throws {
        let configuration = UITestConfiguration(
            isEnabled: true,
            fixture: .savedRadios,
            scenario: .bluetoothDenied,
            language: .es,
            appearance: .light
        )
        let coordinator = AppSessionCoordinator(uiTestConfiguration: configuration)
        let controller = try XCTUnwrap(coordinator.controller)
        let last = try XCTUnwrap(controller.lastConnectedSavedRadio)
        controller.setAutomaticConnectionEnabled(true, for: last.deviceID)
        controller.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(controller.phase, .unavailable("permission denied"))

        coordinator.handleScenePhase(.active)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(coordinator.connectionPresented)
        XCTAssertNil(coordinator.launchConnectionOffer)
        XCTAssertEqual(controller.phase, .unavailable("permission denied"))
        XCTAssertEqual(controller.pendingSavedRadioConnectionID, last.deviceID)
    }

    func testPermissionDeniedFixtureForcesBluetoothDeniedScenario() {
        let configuration = UITestConfiguration.parse(arguments: [
            "Estrobo",
            "--ui-testing",
            "--fixture=permission-denied",
            "--scenario=normal",
        ])

        XCTAssertEqual(configuration.fixture, .permissionDenied)
        XCTAssertEqual(configuration.scenario, .bluetoothDenied)
    }

    @MainActor
    func testConnectedFixtureBecomesReadyForDeliberateControls() async throws {
        let configuration = UITestConfiguration.parse(arguments: [
            "Estrobo",
            "--ui-testing",
            "--fixture=connected",
        ])
        let coordinator = AppSessionCoordinator(uiTestConfiguration: configuration)
        coordinator.handleScenePhase(.active)

        try await Task.sleep(for: .seconds(4))

        let controller = try XCTUnwrap(coordinator.controller)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(controller.canSendTest)
        XCTAssertTrue(controller.canSetGlobalMultiFlashEnabled(true))
        XCTAssertEqual(controller.groupDraft(.b).draft.power.label, "1/512 +0.0")
        XCTAssertFalse(controller.canAdjustPower(.b, direction: -1))
        XCTAssertTrue(controller.canAdjustPower(.b, direction: 1))
    }
}
