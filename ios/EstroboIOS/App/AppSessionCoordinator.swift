import Foundation
import SwiftUI
import EstroboBluetooth
import EstroboCore

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
    @Published private(set) var sceneSafetyStatus = "scene.integration.required"

    let uiTestConfiguration: UITestConfiguration
    private var scenePhaseBridge = ScenePhaseBridge.pendingControllerHooks()
    private var autoConnectionTask: Task<Void, Never>?
    private var pendingAutomaticDemoConnection: Bool?

    init(uiTestConfiguration: UITestConfiguration = .current()) {
        self.uiTestConfiguration = uiTestConfiguration
        language = uiTestConfiguration.language ?? .es
        appearance = uiTestConfiguration.appearance ?? .system

        guard uiTestConfiguration.isEnabled,
              uiTestConfiguration.fixture != .onboarding else {
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
        let live = AppRuntimeFactory.makeLive()
        replaceRuntime(with: live)
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
        case .global:
            tabletDestination = .global
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
            selectedGroup = controller.visibleGroups.first
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
    }

    func exitDemo() {
        guard runtime?.mode == .demo else { return }
        clearRuntime()
    }

    private func clearRuntime() {
        autoConnectionTask?.cancel()
        autoConnectionTask = nil
        pendingAutomaticDemoConnection = nil
        runtime?.controller.suspendForInactiveScene()
        runtime = nil
        scenePhaseBridge = .pendingControllerHooks()
        selectedGroup = nil
        phoneSection = .groups
        tabletDestination = .groups
        connectionPresented = false
        demoLabPresented = false
    }

    private func installDemo(
        scenario: SimulatedRadioScenario,
        seed: AppRuntimeFactory.DemoSeed
    ) {
        replaceRuntime(with: AppRuntimeFactory.makeDemo(scenario: scenario, seed: seed))
    }

    private func replaceRuntime(with newRuntime: AppRuntime) {
        autoConnectionTask?.cancel()
        autoConnectionTask = nil
        pendingAutomaticDemoConnection = nil
        runtime = nil
        scenePhaseBridge = .controller(newRuntime.controller)
        runtime = newRuntime
        selectedGroup = newRuntime.controller.visibleGroups.first
        tabletDestination = .groups
        phoneSection = .groups
        workspaceConfigurationError = nil
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
