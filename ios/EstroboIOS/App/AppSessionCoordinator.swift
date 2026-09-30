import Foundation
import SwiftUI
import EstroboBluetooth
import EstroboCore

struct LaunchConnectionOffer: Identifiable, Equatable {
    let id: UUID
    let name: String
}

@MainActor
final class AppSessionCoordinator: ObservableObject {
    @Published private(set) var runtime: AppRuntime?
    @Published var language: EstroboLanguage
    @Published var appearance: EstroboAppearance
    @Published var phoneSection: PhoneWorkspaceSection = .groups
    @Published var tabletDestination: TabletDestination = .groups
    @Published var selectedGroup: GodoxGroup?
    @Published var connectionPresented = false
    @Published var demoLabPresented = false
    @Published var bluetoothEducationPresented = false
    @Published var bluetoothEducationAcknowledged = false
    @Published var workspaceConfigurationError: String?
    @Published var launchConnectionOffer: LaunchConnectionOffer? = nil
    @Published var compatibilitySummaryPresented = false
    @Published private(set) var sceneSafetyStatus = "scene.integration.required"

    let uiTestConfiguration: UITestConfiguration
    private var scenePhaseBridge = ScenePhaseBridge.pendingControllerHooks()
    private var autoConnectionTask: Task<Void, Never>?
    private var pendingAutomaticDemoConnection: Bool?
    private var didHandleInitialRememberedConnection = false

    init(
        uiTestConfiguration: UITestConfiguration = .current(),
        restoreRememberedLiveRuntime: Bool = false
    ) {
        self.uiTestConfiguration = uiTestConfiguration
        language = uiTestConfiguration.language ?? .es
        appearance = uiTestConfiguration.appearance ?? .system

        guard uiTestConfiguration.isEnabled else {
            if restoreRememberedLiveRuntime,
               let restored = AppRuntimeFactory.makeLiveRestoringRememberedRadio() {
                installRuntime(restored)
            }
            return
        }
        guard uiTestConfiguration.fixture != .onboarding else {
            return
        }

        let seed: AppRuntimeFactory.DemoSeed
        switch uiTestConfiguration.fixture {
        case .workspace, .connected, .permissionDenied:
            seed = .workspace
        case .recoveryWrongUUID:
            seed = .recoveryWrongUUID
        case .savedRadios:
            seed = .savedRadios
        case .onboarding:
            seed = .empty
        }
        installDemo(scenario: uiTestConfiguration.scenario, seed: seed)
        if uiTestConfiguration.fixture == .connected {
            // The fixture must obey the same foreground contract as the app:
            // scanning cannot begin until SwiftUI reports an active scene.
            pendingAutomaticDemoConnection = true
        }
    }

    var locale: Locale { language.locale }
    var controller: GodoxSessionController? { runtime?.controller }
    var isDemo: Bool { runtime?.mode == .demo }

    func text(_ key: String) -> String {
        language.localized(key)
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: language.localized(key),
            locale: locale,
            arguments: arguments
        )
    }

    func chooseDemo() {
        installDemo(scenario: .normal, seed: .empty)
    }

    func startLiveAfterEducation() {
        guard bluetoothEducationAcknowledged else { return }
        replaceRuntime {
            AppRuntimeFactory.makeLive()
        }
        bluetoothEducationPresented = false
    }

    func cancelWorkspaceSetup() {
        clearRuntime()
        bluetoothEducationAcknowledged = false
    }

    func resetDemo(scenario: SimulatedRadioScenario) {
        demoLabPresented = false
        installDemo(scenario: scenario, seed: .workspace)
    }

    func navigate(to section: PhoneWorkspaceSection) {
        phoneSection = section
        switch section {
        case .groups:
            tabletDestination = .groups
        case .presets:
            tabletDestination = .presets
        case .settings:
            tabletDestination = .settings
        }
    }

    @discardableResult
    func completeWorkspace(
        profileID: String,
        groups: Set<GodoxGroup>,
        models: [GodoxGroup: Set<String>]
    ) -> Bool {
        guard let controller else { return false }
        let completed = controller.completeWorkspaceConfiguration(
            profileID: profileID,
            selectedGroups: groups,
            assignedFlashModelIDs: models
        )
        if completed {
            workspaceConfigurationError = nil
            selectedGroup = nil
            tabletDestination = .groups
            connectionPresented = true
        } else {
            workspaceConfigurationError = text("workspace.validation.error")
        }
        return completed
    }

    func handleScenePhase(_ phase: ScenePhase) {
        if phase != .active {
            autoConnectionTask?.cancel()
            autoConnectionTask = nil
        }
        scenePhaseBridge.handle(phase)
        if scenePhaseBridge.integration == .controllerHooksRequired {
            sceneSafetyStatus = scenePhaseBridge.isSuspended
                ? "scene.integration.suspended"
                : "scene.integration.required"
        } else {
            sceneSafetyStatus = scenePhaseBridge.isSuspended
                ? "scene.integration.safe"
                : "scene.integration.active"
        }
        if phase == .active,
           let remember = pendingAutomaticDemoConnection {
            pendingAutomaticDemoConnection = nil
            scheduleAutomaticDemoConnection(remember: remember)
        }
        if phase == .active {
            if controller?.foregroundSessionRequirement != nil {
                _ = controller?.reconnectInterruptedSessionIfPossible()
            } else {
                handleInitialRememberedConnectionIfNeeded()
            }
        }
    }

    func connectLaunchOffer(_ presentedOffer: LaunchConnectionOffer? = nil) {
        guard let offer = presentedOffer ?? launchConnectionOffer,
              let controller else { return }
        launchConnectionOffer = nil
        connectionPresented = true
        controller.connectSavedRadioWhenDiscovered(offer.id)
    }

    func dismissLaunchConnectionOffer() {
        launchConnectionOffer = nil
    }

    func exitDemo() {
        guard runtime?.mode == .demo else { return }
        clearRuntime()
    }

    private func clearRuntime() {
        releaseCurrentRuntime()
        selectedGroup = nil
        phoneSection = .groups
        tabletDestination = .groups
        connectionPresented = false
        demoLabPresented = false
        compatibilitySummaryPresented = false
    }

    private func installDemo(
        scenario: SimulatedRadioScenario,
        seed: AppRuntimeFactory.DemoSeed
    ) {
        replaceRuntime {
            AppRuntimeFactory.makeDemo(scenario: scenario, seed: seed)
        }
    }

    private func releaseCurrentRuntime() {
        autoConnectionTask?.cancel()
        autoConnectionTask = nil
        pendingAutomaticDemoConnection = nil
        launchConnectionOffer = nil
        didHandleInitialRememberedConnection = false
        runtime?.controller.suspendForInactiveScene()
        scenePhaseBridge = .pendingControllerHooks()
        runtime = nil
    }

    /// Module-internal so the app integration tests can assert that teardown
    /// completes before the replacement factory is invoked.
    func replaceRuntime(using makeRuntime: () -> AppRuntime) {
        releaseCurrentRuntime()
        installRuntime(makeRuntime())
    }

    private func installRuntime(_ newRuntime: AppRuntime) {
        scenePhaseBridge = .controller(newRuntime.controller)
        runtime = newRuntime
        selectedGroup = nil
        tabletDestination = .groups
        phoneSection = .groups
        workspaceConfigurationError = nil
        compatibilitySummaryPresented = false
    }

    private func handleInitialRememberedConnectionIfNeeded() {
        guard !didHandleInitialRememberedConnection, let controller else { return }
        guard controller.hasCompletedOnboarding,
              controller.restorationPoints.isEmpty else {
            didHandleInitialRememberedConnection = true
            return
        }

        if let automatic = controller.automaticConnectionSavedRadio {
            switch controller.phase {
            case .idle, .unavailable:
                guard controller.connectSavedRadioWhenDiscovered(
                    automatic.deviceID
                ) else { return }
                didHandleInitialRememberedConnection = true
                connectionPresented = true
            default:
                // A pre-existing connection operation owns the transport.
                // Retry only on a later foreground activation.
                return
            }
        } else if let last = controller.lastConnectedSavedRadio {
            didHandleInitialRememberedConnection = true
            launchConnectionOffer = LaunchConnectionOffer(
                id: last.deviceID,
                name: last.name
            )
        } else {
            didHandleInitialRememberedConnection = true
        }
    }

    private func scheduleAutomaticDemoConnection(remember: Bool) {
        guard let controller else { return }
        controller.startScanning()
        autoConnectionTask = Task { @MainActor [weak self, weak controller] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, let controller,
                  !Task.isCancelled,
                  controller.isSceneActive,
                  self.controller === controller else { return }
            controller.selectDevice(RadioTransportFactory.simulatedCandidate.id)
            controller.radioCode = "123456"
            controller.rememberSelectedRadio = remember
            controller.connectSelectedDevice()
            self.autoConnectionTask = nil
        }
    }
}
