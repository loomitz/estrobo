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
                Button {
                    coordinator.compatibilitySummaryPresented = true
                } label: {
                    HStack {
                        Label(
                            coordinator.text("compatibility.title"),
                            systemImage: "square.3.layers.3d"
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

            Section {
                SettingsExternalLink(
                    title: coordinator.text("settings.privacy"),
                    systemImage: "hand.raised",
                    destination: EstroboExternalLinks.privacyPolicy(
                        for: coordinator.language
                    ),
                    accessibilityHint: coordinator.text(
                        "settings.external-link.hint"
                    ),
                    accessibilityIdentifier: EstroboAccessibilityID.privacyPolicy
                )

                SettingsExternalLink(
                    title: coordinator.text("settings.support"),
                    systemImage: "questionmark.circle",
                    destination: EstroboExternalLinks.support(
                        for: coordinator.language
                    ),
                    accessibilityHint: coordinator.text(
                        "settings.external-link.hint"
                    ),
                    accessibilityIdentifier: EstroboAccessibilityID.support
                )
            } header: {
                Text(coordinator.text("settings.help-and-legal"))
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
        .navigationDestination(
            isPresented: $coordinator.compatibilitySummaryPresented
        ) {
            CompatibilityView(
                coordinator: coordinator,
                controller: controller
            )
        }
        .sessionToolbar(coordinator: coordinator, controller: controller)
    }
}

private struct SettingsExternalLink: View {
    let title: String
    let systemImage: String
    let destination: URL
    let accessibilityHint: String
    let accessibilityIdentifier: String

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
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

    var body: some View {
        List {
            if controller.phase == .ready {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                coordinator.text(
                                    "compatibility.connection.ready.title",
                                    controller.connectedDeviceName
                                        ?? coordinator.text("session.ready")
                                )
                            )
                            .font(.headline)
                            Text(coordinator.text("compatibility.connection.ready.detail"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.compatibilityConnection
                    )
                }
            }

            Section {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(coordinator.text("compatibility.profile"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(
                            compatibilityProfileName(
                                controller.transmitterProfile,
                                coordinator: coordinator
                            )
                        )
                        .font(.body.weight(.medium))
                    }
                    Spacer(minLength: 8)
                    if controller.phase == .ready {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(EstroboAccessibilityID.compatibilityProfile)

                LabeledContent(
                    coordinator.text("compatibility.groups"),
                    value: controller.workingGroups.map(\.label).joined(separator: ", ")
                )
                .accessibilityIdentifier(
                    EstroboAccessibilityID.compatibilityGroupsSummary
                )
            } header: {
                Text(coordinator.text("compatibility.current"))
                    .accessibilityIdentifier(EstroboAccessibilityID.compatibility)
            } footer: {
                Text(
                    coordinator.text(
                        controller.phase == .ready
                            ? "compatibility.profile.locked.detail"
                            : "compatibility.detail"
                    )
                )
            }

            Section {
                Button {
                    guard controller.canConfigureWorkspace else { return }
                    controller.beginWorkspaceConfiguration()
                } label: {
                    Label(
                        coordinator.text("compatibility.edit.groups-models"),
                        systemImage: "slider.horizontal.3"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canConfigureWorkspace)
                .accessibilityIdentifier(EstroboAccessibilityID.compatibilityEdit)
            } footer: {
                Text(
                    coordinator.text(
                        controller.canConfigureWorkspace
                            ? (controller.phase == .ready
                                ? "compatibility.edit.connected.detail"
                                : "compatibility.edit.offline.detail")
                            : "compatibility.edit.unavailable"
                    )
                )
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
        }
        .estroboScreenBackground()
        .navigationTitle(coordinator.text("compatibility.title"))
        .navigationBarTitleDisplayMode(.inline)
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
    @State private var addGroupsPresented = false
    @State private var pendingGroupsToAdd: Set<GodoxGroup> = []

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
            if isOnboarding {
                onboardingForm
            } else {
                compatibilityForm
            }
        }
        .onChange(of: selectedProfileID) {
            reconcileProfileSelection()
        }
        .sheet(isPresented: $addGroupsPresented) {
            CompatibilityAddGroupsView(
                coordinator: coordinator,
                groups: selectedProfile.supportedGroups,
                existingGroups: selectedGroups,
                selection: $pendingGroupsToAdd,
                onCancel: {
                    pendingGroupsToAdd.removeAll()
                    addGroupsPresented = false
                },
                onAdd: addPendingGroups
            )
            .presentationDetents([.large])
        }
    }

    private var onboardingForm: some View {
        Form {
            Section {
                Label(
                    coordinator.text("workspace.intro"),
                    systemImage: "slider.horizontal.3"
                )
                Text(coordinator.text("workspace.intro.detail"))
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(
                    coordinator.text("compatibility.profile"),
                    selection: $selectedProfileID
                ) {
                    ForEach(controller.availableTransmitterProfiles) { profile in
                        Text(compatibilityProfileName(profile, coordinator: coordinator))
                            .tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!controller.canConfigureHardwareProfile)
                .accessibilityIdentifier(EstroboAccessibilityID.workspaceProfile)
            } header: {
                Text(coordinator.text("compatibility.profile"))
            } footer: {
                Text(coordinator.text("workspace.profile.detail"))
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
                        EstroboAccessibilityID.workspaceGroup(group.label)
                    )
                }
            } header: {
                Text(coordinator.text("compatibility.groups"))
            } footer: {
                Text(coordinator.text("workspace.groups.detail"))
            }

            ForEach(orderedSelectedGroups) { group in
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
                        EstroboAccessibilityID.workspaceModel(group.label)
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

            validationFailureSection
        }
        .navigationTitle(coordinator.text("workspace.title"))
        .accessibilityIdentifier(EstroboAccessibilityID.workspaceSetup)
        .toolbar { editorToolbar }
    }

    private var compatibilityForm: some View {
        Form {
            Section {
                if controller.canConfigureHardwareProfile {
                    Picker(
                        coordinator.text("compatibility.profile"),
                        selection: $selectedProfileID
                    ) {
                        ForEach(controller.availableTransmitterProfiles) { profile in
                            Text(compatibilityProfileName(profile, coordinator: coordinator))
                                .tag(profile.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier(EstroboAccessibilityID.compatibilityProfile)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(coordinator.text("compatibility.profile"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(
                                compatibilityProfileName(
                                    selectedProfile,
                                    coordinator: coordinator
                                )
                            )
                            .font(.body.weight(.medium))
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(EstroboAccessibilityID.compatibilityProfile)
                }
            } header: {
                Text(coordinator.text("compatibility.profile"))
            } footer: {
                Text(
                    coordinator.text(
                        controller.phase == .ready
                            ? "compatibility.profile.locked.detail"
                            : "workspace.profile.detail"
                    )
                )
            }

            Section {
                ForEach(orderedSelectedGroups) { group in
                    NavigationLink {
                        CompatibilityModelSelectionView(
                            coordinator: coordinator,
                            group: group,
                            profile: selectedProfile,
                            selectedModelIDs: Binding(
                                get: { selectedModels[group, default: []] },
                                set: {
                                    selectedModels[group] = $0
                                    completionFailed = false
                                }
                            )
                        )
                    } label: {
                        compatibilityGroupRow(group)
                    }
                    .frame(minHeight: 56)
                    .deleteDisabled(orderedSelectedGroups.count <= 1)
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.compatibilityGroupRow(group.label)
                    )
                }
                .onDelete(perform: removeGroups)

                Button {
                    pendingGroupsToAdd.removeAll()
                    addGroupsPresented = true
                } label: {
                    Label(
                        coordinator.text("compatibility.add-groups"),
                        systemImage: "plus"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(availableGroups.isEmpty)
                .accessibilityIdentifier(EstroboAccessibilityID.compatibilityAddGroups)
            } header: {
                Text(coordinator.text("compatibility.groups"))
            } footer: {
                Text(coordinator.text("compatibility.groups.edit.detail"))
            }

            validationFailureSection
        }
        .estroboScreenBackground()
        .navigationTitle(coordinator.text("compatibility.editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(EstroboAccessibilityID.compatibilityEdit)
        .toolbar { editorToolbar }
    }

    @ViewBuilder
    private var validationFailureSection: some View {
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

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(coordinator.text("action.cancel"), action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(
                coordinator.text(isOnboarding ? "workspace.continue" : "action.save"),
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

    private var selectedProfile: TransmitterProfile {
        controller.availableTransmitterProfiles.first {
            $0.id == selectedProfileID
        } ?? controller.transmitterProfile
    }

    private var orderedSelectedGroups: [GodoxGroup] {
        selectedProfile.supportedGroups.filter(selectedGroups.contains)
    }

    private var availableGroups: [GodoxGroup] {
        selectedProfile.supportedGroups.filter { !selectedGroups.contains($0) }
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

    private func addPendingGroups() {
        selectedGroups.formUnion(pendingGroupsToAdd)
        pendingGroupsToAdd.removeAll()
        completionFailed = false
        addGroupsPresented = false
    }

    private func removeGroups(at offsets: IndexSet) {
        let removed = offsets.map { orderedSelectedGroups[$0] }
        guard selectedGroups.count - removed.count >= 1 else { return }
        selectedGroups.subtract(removed)
        completionFailed = false
    }

    private func compatibilityGroupRow(_ group: GodoxGroup) -> some View {
        let modelIDs = selectedModels[group, default: []]
        let models = selectedProfile.flashCatalog.filter { modelIDs.contains($0.id) }
        let range = commonRangeText(for: modelIDs, profile: selectedProfile)

        return HStack(spacing: 12) {
            GroupBadge(group: group)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(coordinator.text("group.title")) \(group.label)")
                    .font(.headline)
                Text(
                    models.isEmpty
                        ? coordinator.text("compatibility.group.models.missing")
                        : models.map(\.name).joined(separator: ", ")
                )
                .font(.subheadline)
                .foregroundStyle(models.isEmpty ? .red : .secondary)
                .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(range)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            coordinator.text("group.accessibility", group.label)
        )
        .accessibilityValue(
            "\(models.isEmpty ? coordinator.text("compatibility.group.models.missing") : models.map(\.name).joined(separator: ", ")). \(range)"
        )
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
        coordinator.selectedGroup = nil
        onComplete()
    }
}

private struct CompatibilityAddGroupsView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    let groups: [GodoxGroup]
    let existingGroups: Set<GodoxGroup>
    @Binding var selection: Set<GodoxGroup>
    let onCancel: () -> Void
    let onAdd: () -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 44), spacing: 8),
        count: 5
    )

    var body: some View {
        NavigationStack {
            Form {
                if groups.isEmpty {
                    ContentUnavailableView(
                        coordinator.text("compatibility.add-groups.none"),
                        systemImage: "checkmark.circle"
                    )
                } else {
                    groupSection(
                        title: coordinator.text("compatibility.add-groups.numeric"),
                        groups: groups.filter { $0.rawValue < 10 }
                    )
                    groupSection(
                        title: coordinator.text("compatibility.add-groups.lettered"),
                        groups: groups.filter { $0.rawValue >= 10 }
                    )
                }
            }
            .navigationTitle(coordinator.text("compatibility.add-groups.title"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier(EstroboAccessibilityID.compatibilityAddGroupsSheet)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(coordinator.text("action.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        coordinator.text(
                            "compatibility.add-groups.confirm",
                            Int64(selection.count)
                        ),
                        action: onAdd
                    )
                    .disabled(selection.isEmpty)
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.compatibilityAddGroupsConfirm
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func groupSection(title: String, groups: [GodoxGroup]) -> some View {
        if !groups.isEmpty {
            Section(title) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(groups) { group in
                        groupButton(group)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func groupButton(_ group: GodoxGroup) -> some View {
        let isExisting = existingGroups.contains(group)
        let isSelected = selection.contains(group)
        let showsCheckmark = isExisting || isSelected

        return Button {
            if isSelected {
                selection.remove(group)
            } else {
                selection.insert(group)
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    GroupBadge(group: group)
                        .accessibilityHidden(true)
                    if showsCheckmark {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 7, y: -7)
                            .accessibilityHidden(true)
                    }
                }
                Text(
                    isExisting
                        ? coordinator.text("compatibility.selection.active")
                        : " "
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isExisting)
        .background(
            showsCheckmark ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityLabel(coordinator.text("group.accessibility", group.label))
        .accessibilityValue(
            coordinator.text(
                isExisting
                    ? "compatibility.selection.active"
                    : (isSelected
                        ? "compatibility.selection.selected"
                        : "compatibility.selection.not-selected")
            )
        )
        .accessibilityAddTraits(showsCheckmark ? .isSelected : [])
        .accessibilityIdentifier(
            EstroboAccessibilityID.compatibilityGroupChoice(group.label)
        )
    }
}

private struct CompatibilityModelSelectionView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    let group: GodoxGroup
    let profile: TransmitterProfile
    @Binding var selectedModelIDs: Set<String>

    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                LabeledContent(
                    coordinator.text("compatibility.models.range.title"),
                    value: commonRangeText(for: selectedModelIDs, profile: profile)
                )
                if selectedModelIDs.isEmpty {
                    Label(
                        coordinator.text("compatibility.models.required"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }
            } footer: {
                Text(coordinator.text("compatibility.models.range.detail"))
            }

            Section {
                if filteredModels.isEmpty {
                    ContentUnavailableView(
                        coordinator.text("compatibility.models.search.empty"),
                        systemImage: "magnifyingglass",
                        description: Text(
                            coordinator.text("compatibility.models.search.empty.detail")
                        )
                    )
                } else {
                    ForEach(filteredModels) { model in
                        modelButton(model)
                    }
                }
            } header: {
                HStack {
                    Text(coordinator.text("compatibility.models"))
                    Spacer(minLength: 8)
                    Text(selectedModelCountText)
                        .monospacedDigit()
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.compatibilityModelCount(
                                group.label
                            )
                        )
                }
            } footer: {
                Text(coordinator.text("compatibility.models.selection.detail"))
            }
        }
        .estroboScreenBackground()
        .searchable(
            text: $searchText,
            prompt: coordinator.text("compatibility.models.search")
        )
        .navigationTitle("\(coordinator.text("group.title")) \(group.label)")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(
            EstroboAccessibilityID.compatibilityModels(group.label)
        )
    }

    private var filteredModels: [FlashCapability] {
        let matchingModels = searchText.isEmpty
            ? profile.flashCatalog
            : profile.flashCatalog.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                    $0.id.localizedCaseInsensitiveContains(searchText)
            }
        return matchingModels.filter { selectedModelIDs.contains($0.id) }
            + matchingModels.filter { !selectedModelIDs.contains($0.id) }
    }

    private var selectedModelCountText: String {
        let count = selectedModelIDs.count
        if count == 1 {
            return coordinator.text("compatibility.models.selected.one")
        }
        return coordinator.text(
            "compatibility.models.selected.many",
            Int64(count)
        )
    }

    private func modelButton(_ model: FlashCapability) -> some View {
        let isSelected = selectedModelIDs.contains(model.id)

        return Button {
            if isSelected {
                selectedModelIDs.remove(model.id)
            } else {
                selectedModelIDs.insert(model.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(
                        coordinator.text(
                            "compatibility.models.minimum",
                            Int64(model.minimumManualDenominator)
                        )
                    )
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.name)
        .accessibilityValue(
            coordinator.text(
                isSelected
                    ? "compatibility.selection.selected"
                    : "compatibility.selection.not-selected"
            )
        )
        .accessibilityHint(coordinator.text("compatibility.models.selection.hint"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(
            EstroboAccessibilityID.compatibilityModel(group.label, model: model.id)
        )
    }
}

@MainActor
private func compatibilityProfileName(
    _ profile: TransmitterProfile,
    coordinator: AppSessionCoordinator
) -> String {
    switch profile.id {
    case TransmitterProfile.observedGDBH.id:
        coordinator.text("compatibility.profile.gdbh")
    case TransmitterProfile.classicLetters.id:
        coordinator.text("compatibility.profile.letters")
    default:
        profile.name
    }
}

@MainActor
private func commonRangeText(
    for modelIDs: Set<String>,
    profile: TransmitterProfile
) -> String {
    let configuration = GroupConfiguration(
        assignedFlashModelIDs: modelIDs,
        isVisibleLocally: true,
        isEnabledOnRadio: false,
        hasCompleteBaseline: false
    )
    let capability = ResolvedGroupCapability.resolve(
        configuration: configuration,
        profile: profile
    )
    guard let denominator = capability.minimumManualDenominator else {
        return "—"
    }
    return "1/1 – 1/\(denominator)"
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
