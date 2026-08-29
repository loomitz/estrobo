import SwiftUI
import EstroboBluetooth
import EstroboCore

struct SettingsControlView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    coordinator.text("settings.runtime"),
                    value: controller.isSimulation
                        ? coordinator.text("runtime.demo")
                        : coordinator.text("runtime.live")
                )
            } header: {
                Text(coordinator.text("settings.runtime"))
                    .accessibilityIdentifier(EstroboAccessibilityID.settingsScreen)
            }

            Section {
                NavigationLink {
                    CompatibilityView(
                        coordinator: coordinator,
                        controller: controller
                    )
                } label: {
                    Label(
                        coordinator.text("compatibility.title"),
                        systemImage: "square.3.layers.3d"
                    )
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier(EstroboAccessibilityID.compatibility)

                NavigationLink {
                    SavedRadiosView(
                        coordinator: coordinator,
                        controller: controller
                    )
                } label: {
                    Label(
                        coordinator.text("saved.title"),
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier(EstroboAccessibilityID.savedRadios)
            } header: {
                Text(coordinator.text("settings.configuration"))
            }

            DeliveryModeSettingsSection(
                coordinator: coordinator,
                controller: controller
            )

            Section {
                Picker(
                    coordinator.text("settings.language"),
                    selection: $coordinator.language
                ) {
                    ForEach(EstroboLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(EstroboAccessibilityID.language)
            } header: {
                Text(coordinator.text("settings.language"))
            }

            Section {
                Picker(
                    coordinator.text("settings.appearance"),
                    selection: $coordinator.appearance
                ) {
                    Text(coordinator.text("appearance.system"))
                        .tag(EstroboAppearance.system)
                    Text(coordinator.text("appearance.light"))
                        .tag(EstroboAppearance.light)
                    Text(coordinator.text("appearance.dark"))
                        .tag(EstroboAppearance.dark)
                }
                .accessibilityIdentifier(EstroboAccessibilityID.appearance)
            } header: {
                Text(coordinator.text("settings.appearance"))
            }

            Section {
                Label(
                    coordinator.text(coordinator.sceneSafetyStatus),
                    systemImage: controller.isSceneActive
                        ? "checkmark.shield"
                        : "pause.circle"
                )
                .accessibilityIdentifier(EstroboAccessibilityID.sceneSafety)
            } header: {
                Text(coordinator.text("settings.foreground"))
            }

            if coordinator.isDemo {
                Section {
                    NavigationLink {
                        DemoLabView(coordinator: coordinator)
                    } label: {
                        Label(
                            coordinator.text("demo.lab.title"),
                            systemImage: "waveform.path.ecg"
                        )
                        .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier(EstroboAccessibilityID.demoLab)
                } header: {
                    Text("Demo")
                }
            }
        }
        .navigationTitle(coordinator.text("tab.settings"))
        .sessionToolbar(coordinator: coordinator, controller: controller)
    }
}

private struct DeliveryModeSettingsSection: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        Section {
            Picker(
                coordinator.text("delivery.title"),
                selection: Binding(
                    get: { controller.changeDeliveryMode },
                    set: { controller.setChangeDeliveryMode($0) }
                )
            ) {
                Text(coordinator.text("delivery.automatic"))
                    .tag(ChangeDeliveryMode.automatic)
                Text(coordinator.text("delivery.manual"))
                    .tag(ChangeDeliveryMode.manual)
            }
            .pickerStyle(.segmented)
            .disabled(!controller.canChangeDeliveryMode)
            .accessibilityIdentifier(EstroboAccessibilityID.deliveryMode)
        } header: {
            Text(coordinator.text("delivery.title"))
        } footer: {
            Text(
                controller.changeDeliveryMode == .automatic
                    ? coordinator.text("delivery.automatic.detail")
                    : coordinator.text("delivery.manual.detail")
            )
        }
    }
}

struct CompatibilityView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    @State private var editorPresented = false

    var body: some View {
        List {
            Section {
                LabeledContent(
                    coordinator.text("compatibility.profile"),
                    value: controller.transmitterProfile.name
                )
                LabeledContent(
                    coordinator.text("compatibility.groups"),
                    value: controller.workingGroups.map(\.label).joined(separator: ", ")
                )
            } header: {
                Text(coordinator.text("compatibility.title"))
                    .accessibilityIdentifier(EstroboAccessibilityID.compatibility)
            } footer: {
                Text(coordinator.text("compatibility.detail"))
            }

            Section {
                ForEach(controller.workingGroups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            GroupBadge(
                                group: group,
                                accessibilityName: coordinator.text(
                                    "group.accessibility",
                                    group.label
                                )
                            )
                            Text("\(coordinator.text("group.title")) \(group.label)")
                                .font(.headline)
                        }
                        Text(modelNames(for: group))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(coordinator.text("compatibility.assignments"))
            }

            Section {
                Button {
                    editorPresented = true
                } label: {
                    Label(
                        coordinator.text("compatibility.edit"),
                        systemImage: "slider.horizontal.3"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canConfigureWorkspace || controller.phase != .idle)
                .accessibilityIdentifier(EstroboAccessibilityID.compatibilityEdit)
            }
        }
        .estroboScreenBackground()
        .navigationTitle(coordinator.text("compatibility.title"))
        .sheet(isPresented: $editorPresented) {
            CompatibilityEditorView(
                coordinator: coordinator,
                controller: controller,
                isOnboarding: false,
                onCancel: { editorPresented = false },
                onComplete: { editorPresented = false }
            )
        }
    }

    private func modelNames(for group: GodoxGroup) -> String {
        let configuration = controller.groupConfiguration(group)
        let names = controller.transmitterProfile.flashCatalog.compactMap { model in
            configuration.assignedFlashModelIDs.contains(model.id) ? model.name : nil
        }
        return names.isEmpty
            ? coordinator.text("compatibility.models.none")
            : names.joined(separator: ", ")
    }
}

struct CompatibilityEditorView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController
    let isOnboarding: Bool
    let onCancel: () -> Void
    let onComplete: () -> Void

    @State private var selectedProfileID: String
    @State private var selectedGroups: Set<GodoxGroup>
    @State private var selectedModels: [GodoxGroup: Set<String>]
    @State private var completionFailed = false

    init(
        coordinator: AppSessionCoordinator,
        controller: GodoxSessionController,
        isOnboarding: Bool,
        onCancel: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.controller = controller
        self.isOnboarding = isOnboarding
        self.onCancel = onCancel
        self.onComplete = onComplete
        _selectedProfileID = State(initialValue: controller.transmitterProfile.id)
        if isOnboarding {
            _selectedGroups = State(initialValue: [])
            _selectedModels = State(initialValue: [:])
        } else {
            _selectedGroups = State(initialValue: Set(controller.workingGroups))
            _selectedModels = State(
                initialValue: Dictionary(uniqueKeysWithValues: controller.workingGroups.map {
                    ($0, controller.groupConfiguration($0).assignedFlashModelIDs)
                })
            )
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isOnboarding {
                    Section {
                        Label(
                            coordinator.text("workspace.intro"),
                            systemImage: "slider.horizontal.3"
                        )
                        Text(coordinator.text("workspace.intro.detail"))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker(
                        coordinator.text("compatibility.profile"),
                        selection: $selectedProfileID
                    ) {
                        ForEach(controller.availableTransmitterProfiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!controller.canConfigureHardwareProfile)
                    .accessibilityIdentifier(
                        isOnboarding
                            ? EstroboAccessibilityID.workspaceProfile
                            : EstroboAccessibilityID.compatibility
                    )
                } header: {
                    Text(coordinator.text("compatibility.profile"))
                } footer: {
                    if isOnboarding {
                        Text(coordinator.text("workspace.profile.detail"))
                    }
                }

                Section {
                    ForEach(selectedProfile.supportedGroups) { group in
                        Toggle(
                            isOn: groupBinding(group)
                        ) {
                            HStack {
                                GroupBadge(
                                    group: group,
                                    accessibilityName: coordinator.text(
                                        "group.accessibility",
                                        group.label
                                    )
                                )
                                Text("\(coordinator.text("group.title")) \(group.label)")
                            }
                        }
                        .accessibilityIdentifier(
                            isOnboarding
                                ? EstroboAccessibilityID.workspaceGroup(group.label)
                                : EstroboAccessibilityID.compatibilityGroup(group.label)
                        )
                    }
                } header: {
                    Text(coordinator.text("compatibility.groups"))
                } footer: {
                    Text(coordinator.text("workspace.groups.detail"))
                }

                ForEach(selectedProfile.supportedGroups.filter(selectedGroups.contains)) { group in
                    Section {
                        Menu {
                            ForEach(selectedProfile.flashCatalog) { model in
                                Button {
                                    toggleModel(model.id, for: group)
                                } label: {
                                    if selectedModels[group, default: []].contains(model.id) {
                                        Label(model.name, systemImage: "checkmark")
                                    } else {
                                        Text(model.name)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Label(
                                    coordinator.text("compatibility.models"),
                                    systemImage: "bolt.horizontal"
                                )
                                Spacer()
                                Text("\(selectedModels[group, default: []].count)")
                                    .monospacedDigit()
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier(
                            isOnboarding
                                ? EstroboAccessibilityID.workspaceModel(group.label)
                                : EstroboAccessibilityID.compatibilityGroup(group.label)
                                    + ".models"
                        )

                        ForEach(selectedCapabilityModels(for: group)) { model in
                            capabilitySummary(model, group: group)
                        }
                    } header: {
                        Text("\(coordinator.text("group.title")) \(group.label)")
                    } footer: {
                        if selectedModels[group, default: []].isEmpty {
                            Text(coordinator.text("compatibility.models.required"))
                                .foregroundStyle(.red)
                        }
                    }
                }

                if completionFailed {
                    Section {
                        Label(
                            coordinator.text("workspace.validation.error"),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(
                coordinator.text(
                    isOnboarding ? "workspace.title" : "compatibility.edit"
                )
            )
            .accessibilityIdentifier(
                isOnboarding
                    ? EstroboAccessibilityID.workspaceSetup
                    : EstroboAccessibilityID.compatibilityEdit
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(coordinator.text("action.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        coordinator.text(
                            isOnboarding ? "workspace.continue" : "action.save"
                        ),
                        action: save
                    )
                        .disabled(!canSave)
                        .accessibilityIdentifier(
                            isOnboarding
                                ? EstroboAccessibilityID.workspaceContinue
                                : EstroboAccessibilityID.compatibilitySave
                        )
                }
            }
        }
        .onChange(of: selectedProfileID) {
            reconcileProfileSelection()
        }
    }

    private var selectedProfile: TransmitterProfile {
        controller.availableTransmitterProfiles.first {
            $0.id == selectedProfileID
        } ?? controller.transmitterProfile
    }

    private var canSave: Bool {
        !selectedGroups.isEmpty
            && selectedGroups.allSatisfy {
                !selectedModels[$0, default: []].isEmpty
            }
            && controller.canConfigureWorkspace
    }

    private func groupBinding(_ group: GodoxGroup) -> Binding<Bool> {
        Binding(
            get: { selectedGroups.contains(group) },
            set: { enabled in
                if enabled {
                    selectedGroups.insert(group)
                    if !isOnboarding,
                       selectedModels[group, default: []].isEmpty,
                       let firstModel = selectedProfile.flashCatalog.first {
                        selectedModels[group] = [firstModel.id]
                    }
                } else {
                    selectedGroups.remove(group)
                }
                completionFailed = false
            }
        )
    }

    private func toggleModel(_ modelID: String, for group: GodoxGroup) {
        if selectedModels[group, default: []].contains(modelID) {
            selectedModels[group, default: []].remove(modelID)
        } else {
            selectedModels[group, default: []].insert(modelID)
        }
        completionFailed = false
    }

    private func reconcileProfileSelection() {
        let supported = Set(selectedProfile.supportedGroups)
        let catalogIDs = Set(selectedProfile.flashCatalog.map(\.id))
        selectedGroups.formIntersection(supported)
        for group in selectedProfile.supportedGroups {
            selectedModels[group, default: []].formIntersection(catalogIDs)
        }
        completionFailed = false
    }

    @ViewBuilder
    private func capabilitySummary(
        _ model: FlashCapability,
        group: GodoxGroup
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.name)
                .font(.subheadline.bold())
            LabeledContent(
                coordinator.text("workspace.capability.power"),
                value: "1/1 – 1/\(model.minimumManualDenominator)"
            )
            LabeledContent(
                coordinator.text("workspace.capability.evidence"),
                value: evidenceText(model.evidence)
            )
            Label(
                coordinator.text(
                    model.multiLimitProfile == nil
                        ? "workspace.capability.multi.unverified"
                        : "workspace.capability.multi.verified"
                ),
                systemImage: model.multiLimitProfile == nil
                    ? "exclamationmark.triangle"
                    : "checkmark.seal"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            EstroboAccessibilityID.workspaceCapability(
                group.label,
                model: model.id
            )
        )
    }

    private func selectedCapabilityModels(for group: GodoxGroup) -> [FlashCapability] {
        selectedProfile.flashCatalog.filter {
            selectedModels[group, default: []].contains($0.id)
        }
    }

    private func evidenceText(_ evidence: CapabilityEvidence) -> String {
        switch evidence {
        case .apkCatalog:
            coordinator.text("workspace.evidence.catalog")
        case .protocolGeneric:
            coordinator.text("workspace.evidence.protocol")
        case .observedLocalData:
            coordinator.text("workspace.evidence.observed")
        case .manufacturerSpecification:
            coordinator.text("workspace.evidence.manufacturer")
        }
    }

    private func save() {
        guard canSave else { return }
        let completed: Bool
        if isOnboarding {
            completed = coordinator.completeWorkspace(
                profileID: selectedProfileID,
                groups: selectedGroups,
                models: selectedModels
            )
        } else {
            completed = controller.completeWorkspaceConfiguration(
                profileID: selectedProfileID,
                selectedGroups: selectedGroups,
                assignedFlashModelIDs: selectedModels
            )
        }
        completionFailed = !completed
        guard completed else { return }
        coordinator.selectedGroup = controller.visibleGroups.first
        onComplete()
    }
}

struct DemoLabView: View {
    @ObservedObject var coordinator: AppSessionCoordinator

    @State private var exitConfirmationPresented = false

    var body: some View {
        List {
            Section {
                LabeledContent(
                    coordinator.text("demo.lab.current"),
                    value: scenarioTitle(currentScenario)
                )
                Text(coordinator.text("demo.lab.detail"))
                    .foregroundStyle(.secondary)
            } header: {
                Text(coordinator.text("demo.lab.title"))
                    .accessibilityIdentifier(EstroboAccessibilityID.demoLab)
            }

            Section {
                ForEach(SimulatedRadioScenario.allCases, id: \.self) { scenario in
                    Button {
                        coordinator.resetDemo(scenario: scenario)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scenarioTitle(scenario))
                                    .font(.body)
                                Text(scenarioDetail(scenario))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if scenario == currentScenario {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(EstroboTheme.interactiveAccent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.demoScenario(scenario)
                    )
                }
            } header: {
                Text(coordinator.text("demo.lab.scenarios"))
            }

            Section {
                Button {
                    coordinator.resetDemo(scenario: currentScenario)
                } label: {
                    Label(
                        coordinator.text("demo.restart"),
                        systemImage: "arrow.counterclockwise"
                    )
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier(EstroboAccessibilityID.demoRestart)

                Button(role: .destructive) {
                    exitConfirmationPresented = true
                } label: {
                    Label(
                        coordinator.text("demo.exit"),
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier(EstroboAccessibilityID.demoExit)
            }
        }
        .estroboScreenBackground()
        .navigationTitle(coordinator.text("demo.lab.title"))
        .confirmationDialog(
            coordinator.text("demo.exit.confirm"),
            isPresented: $exitConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(coordinator.text("demo.exit"), role: .destructive) {
                coordinator.exitDemo()
            }
            Button(coordinator.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(coordinator.text("demo.exit.detail"))
        }
    }

    private var currentScenario: SimulatedRadioScenario {
        coordinator.runtime?.demoScenario ?? .normal
    }

    private func scenarioTitle(_ scenario: SimulatedRadioScenario) -> String {
        coordinator.text("demo.scenario.\(scenario.rawValue).title")
    }

    private func scenarioDetail(_ scenario: SimulatedRadioScenario) -> String {
        coordinator.text("demo.scenario.\(scenario.rawValue).detail")
    }
}
