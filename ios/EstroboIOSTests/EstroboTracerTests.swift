import XCTest
import EstroboCore
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
            EstroboAccessibilityID.globalScreen,
            EstroboAccessibilityID.globalBeep,
            EstroboAccessibilityID.globalStandby,
            EstroboAccessibilityID.testConfirmation,
            EstroboAccessibilityID.testConfirm,
            EstroboAccessibilityID.multiConfirmation,
            EstroboAccessibilityID.multiConfirm,
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
    func testCoordinatorNavigationMapsPhoneAndTabletDestinations() {
        let coordinator = AppSessionCoordinator()

        coordinator.navigate(to: .global)
        XCTAssertEqual(coordinator.phoneSection, .global)
        XCTAssertEqual(coordinator.tabletDestination, .global)

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
    }
}
