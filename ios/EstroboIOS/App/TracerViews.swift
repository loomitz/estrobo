import SwiftUI
import EstroboCore

struct EstroboRootView: View {
    @ObservedObject var coordinator: AppSessionCoordinator

    var body: some View {
        Group {
            if let runtime = coordinator.runtime {
                ControllerTracerRoot(
                    coordinator: coordinator,
                    runtime: runtime,
                    controller: runtime.controller
                )
            } else {
                RuntimeChoiceView(coordinator: coordinator)
            }
        }
        .accessibilityIdentifier(EstroboAccessibilityID.appRoot)
    }
}

private struct RuntimeChoiceView: View {
    @ObservedObject var coordinator: AppSessionCoordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(EstroboTheme.interactiveAccent)
                            .accessibilityHidden(true)
                        Text("Estrobo")
                            .font(.largeTitle.bold())
                            .foregroundStyle(EstroboTheme.ink)
                        Text(coordinator.text("runtime.intro"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }

                Section {
                    Button {
                        coordinator.chooseDemo()
                    } label: {
                        Label(
                            coordinator.text("runtime.demo"),
                            systemImage: "play.circle.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(EstroboTheme.amber)
                    .foregroundStyle(EstroboTheme.navy)
                    .accessibilityIdentifier(EstroboAccessibilityID.runtimeDemo)

                    Button {
                        coordinator.bluetoothEducationPresented = true
                    } label: {
                        Label(
                            coordinator.text("runtime.live"),
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                        .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.runtimeLiveEducation
                    )
                } header: {
                    Text(coordinator.text("runtime.choose"))
                } footer: {
                    Text(coordinator.text("runtime.demo.detail"))
                }
            }
            .estroboScreenBackground()
            .navigationTitle(coordinator.text("runtime.title"))
        }
        .accessibilityIdentifier(EstroboAccessibilityID.onboardingRoot)
        .sheet(isPresented: $coordinator.bluetoothEducationPresented) {
            NavigationStack {
                Form {
                    Section {
                        Text(coordinator.text("runtime.live.education"))
                    }
                    Section {
                        Toggle(
                            coordinator.text("runtime.live.acknowledge"),
                            isOn: $coordinator.bluetoothEducationAcknowledged
                        )
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.runtimeLiveAcknowledge
                        )
                    }
                    Section {
                        Button(coordinator.text("runtime.live.start")) {
                            coordinator.startLiveAfterEducation()
                        }
                        .disabled(!coordinator.bluetoothEducationAcknowledged)
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.runtimeLiveStart
                        )
                    }
                }
                .navigationTitle(coordinator.text("runtime.live"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(coordinator.text("action.cancel")) {
                            coordinator.bluetoothEducationPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct ControllerTracerRoot: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    let runtime: AppRuntime
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        VStack(spacing: 0) {
            if runtime.mode == .demo {
                DemoBanner(coordinator: coordinator)
            }
            if controller.hasCompletedOnboarding {
                AdaptiveRootView(
                    coordinator: coordinator,
                    controller: controller
                )
            } else if !controller.restorationPoints.isEmpty {
                RecoveryBootstrapView(
                    coordinator: coordinator,
                    controller: controller
                )
            } else {
                CompatibilityEditorView(
                    coordinator: coordinator,
                    controller: controller,
                    isOnboarding: true,
                    onCancel: { coordinator.cancelWorkspaceSetup() },
                    onComplete: {}
                )
            }
        }
        .background(EstroboTheme.ivory)
        .sheet(isPresented: $coordinator.connectionPresented) {
            ConnectionDemoView(
                coordinator: coordinator,
                controller: controller
            )
        }
    }
}

private struct RecoveryBootstrapView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        NavigationStack {
            List {
                RecoveryGateView(
                    coordinator: coordinator,
                    controller: controller
                )
                Section {
                    Button {
                        coordinator.connectionPresented = true
                    } label: {
                        Label(
                            coordinator.text("connection.open"),
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.sessionStatus
                    )
                } footer: {
                    Text(coordinator.text("recovery.same-uuid"))
                }
            }
            .estroboScreenBackground()
            .navigationTitle(coordinator.text("recovery.title"))
        }
    }
}

private struct DemoBanner: View {
    @ObservedObject var coordinator: AppSessionCoordinator

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path")
                .accessibilityHidden(true)
            Text(coordinator.text("demo.banner"))
                .font(.subheadline.bold())
                .accessibilityIdentifier(EstroboAccessibilityID.demoBanner)
            Spacer()
            Image(
                systemName: UIDevice.current.userInterfaceIdiom == .pad
                    ? "ipad.landscape"
                    : "iphone"
            )
            .accessibilityLabel(
                UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
            )
        }
        .foregroundStyle(EstroboTheme.navy)
        .padding(.horizontal)
        .frame(minHeight: 36)
        .background(EstroboTheme.amber)
        .accessibilityElement(children: .contain)
    }
}

private struct AdaptiveRootView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                TabletTracerRoot(
                    coordinator: coordinator,
                    controller: controller
                )
            } else {
                PhoneTracerRoot(
                    coordinator: coordinator,
                    controller: controller
                )
            }
        }
        .accessibilityIdentifier(EstroboAccessibilityID.workspaceRoot)
    }
}

private struct PhoneTracerRoot: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        TabView(selection: $coordinator.phoneSection) {
            NavigationStack {
                GroupsTracerView(
                    coordinator: coordinator,
                    controller: controller
                )
            }
            .tabItem {
                Label(coordinator.text("tab.groups"), systemImage: "slider.horizontal.3")
                    .accessibilityIdentifier(EstroboAccessibilityID.tabGroups)
            }
            .tag(PhoneWorkspaceSection.groups)

            NavigationStack {
                GlobalTracerView(
                    coordinator: coordinator,
                    controller: controller
                )
            }
            .tabItem {
                Label(coordinator.text("tab.global"), systemImage: "dial.high")
                    .accessibilityIdentifier(EstroboAccessibilityID.tabGlobal)
            }
            .tag(PhoneWorkspaceSection.global)

            NavigationStack {
                PresetsTracerView(
                    coordinator: coordinator,
                    controller: controller
                )
            }
            .tabItem {
                Label(coordinator.text("tab.presets"), systemImage: "bookmark")
                    .accessibilityIdentifier(EstroboAccessibilityID.tabPresets)
            }
            .tag(PhoneWorkspaceSection.presets)

            NavigationStack {
                SettingsTracerView(
                    coordinator: coordinator,
                    controller: controller
                )
            }
            .tabItem {
                Label(coordinator.text("tab.settings"), systemImage: "gearshape")
                    .accessibilityIdentifier(EstroboAccessibilityID.tabSettings)
            }
            .tag(PhoneWorkspaceSection.settings)
        }
        .accessibilityIdentifier(EstroboAccessibilityID.phoneLayout)
    }
}

private struct TabletTracerRoot: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            PhoneTracerRoot(
                coordinator: coordinator,
                controller: controller
            )
        } else {
            regularWidthRoot
        }
    }

    private var regularWidthRoot: some View {
        Group {
            if coordinator.tabletDestination == .groups {
                groupsSplitView
            } else {
                workspaceSplitView
            }
        }
        .accessibilityIdentifier(EstroboAccessibilityID.tabletLayout)
    }

    private var groupsSplitView: some View {
        NavigationSplitView {
            tabletSidebar
        } content: {
            NavigationStack {
                TabletGroupsWorkspaceView(
                    coordinator: coordinator,
                    controller: controller
                )
            }
        } detail: {
            NavigationStack {
                if let group = coordinator.selectedGroup {
                    GroupTracerDetailView(
                        group: group,
                        coordinator: coordinator,
                        controller: controller
                    )
                } else {
                    ContentUnavailableView(
                        coordinator.text("inspector.title"),
                        systemImage: "sidebar.right",
                        description: Text(coordinator.text("inspector.detail"))
                    )
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var workspaceSplitView: some View {
        NavigationSplitView {
            tabletSidebar
        } detail: {
            NavigationStack {
                tabletDestinationView
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var tabletSidebar: some View {
        List {
            Section {
                sidebarButton(
                    .connection,
                    title: coordinator.text("sidebar.connection"),
                    systemImage: "antenna.radiowaves.left.and.right",
                    identifier: EstroboAccessibilityID.sidebarConnection
                )
                sidebarButton(
                    .groups,
                    title: coordinator.text("tab.groups"),
                    systemImage: "slider.horizontal.3",
                    identifier: EstroboAccessibilityID.sidebarGroups
                )
                sidebarButton(
                    .global,
                    title: coordinator.text("sidebar.global"),
                    systemImage: "dial.high",
                    identifier: EstroboAccessibilityID.sidebarGlobal
                )
                sidebarButton(
                    .presets,
                    title: coordinator.text("tab.presets"),
                    systemImage: "bookmark",
                    identifier: EstroboAccessibilityID.sidebarPresets
                )
                sidebarButton(
                    .savedRadios,
                    title: coordinator.text("saved.title"),
                    systemImage: "dot.radiowaves.left.and.right",
                    identifier: EstroboAccessibilityID.sidebarSavedRadios
                )
                sidebarButton(
                    .settings,
                    title: coordinator.text("tab.settings"),
                    systemImage: "gearshape",
                    identifier: EstroboAccessibilityID.sidebarSettings
                )
            }
            if coordinator.isDemo {
                Section {
                    sidebarButton(
                        .demo,
                        title: coordinator.text("demo.lab.title"),
                        systemImage: "waveform.path.ecg",
                        identifier: EstroboAccessibilityID.sidebarDemo
                    )
                }
            }
        }
        .navigationTitle("Estrobo")
    }

    @ViewBuilder
    private var tabletDestinationView: some View {
        switch coordinator.tabletDestination {
        case .connection:
            ConnectionLandingView(
                coordinator: coordinator,
                controller: controller
            )
        case .groups:
            TabletGroupsWorkspaceView(
                coordinator: coordinator,
                controller: controller
            )
        case .global:
            GlobalTracerView(
                coordinator: coordinator,
                controller: controller
            )
        case .presets:
            PresetsTracerView(
                coordinator: coordinator,
                controller: controller
            )
        case .savedRadios:
            SavedRadiosView(
                coordinator: coordinator,
                controller: controller
            )
        case .settings:
            SettingsTracerView(
                coordinator: coordinator,
                controller: controller
            )
        case .demo:
            DemoLabView(coordinator: coordinator)
        }
    }

    private func sidebarButton(
        _ destination: TabletDestination,
        title: String,
        systemImage: String,
        identifier: String
    ) -> some View {
        Button {
            coordinator.tabletDestination = destination
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if coordinator.tabletDestination == destination {
                    Image(systemName: "checkmark")
                        .foregroundStyle(EstroboTheme.interactiveAccent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            coordinator.tabletDestination == destination ? .isSelected : []
        )
        .accessibilityIdentifier(identifier)
    }
}

private struct TabletGroupsWorkspaceView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        List {
            RecoveryGateView(coordinator: coordinator, controller: controller)
            Section {
                ForEach(controller.visibleGroups) { group in
                    Button {
                        coordinator.selectedGroup = group
                    } label: {
                        GroupTracerRow(
                            group: group,
                            coordinator: coordinator,
                            controller: controller
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.groupRow(group.label)
                    )
                }
            } header: {
                Text(coordinator.text("groups.header"))
            }
        }
        .estroboScreenBackground()
        .navigationTitle(coordinator.text("tab.groups"))
        .sessionToolbar(coordinator: coordinator, controller: controller)
        .safeAreaInset(edge: .bottom) {
            ApplyTracerBar(coordinator: coordinator, controller: controller)
        }
    }
}

private struct ConnectionLandingView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        List {
            Section {
                LabeledContent(
                    coordinator.text("connection.status"),
                    value: sessionText(controller.phase, coordinator: coordinator)
                )
                Button {
                    coordinator.connectionPresented = true
                } label: {
                    Label(
                        coordinator.text("connection.open"),
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier(EstroboAccessibilityID.sessionStatus)
            }
            RecoveryGateView(coordinator: coordinator, controller: controller)
        }
        .estroboScreenBackground()
        .navigationTitle(coordinator.text("sidebar.connection"))
    }
}

private struct GroupsTracerView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        List {
            if let notice = foregroundNotice(
                controller,
                coordinator: coordinator
            ) {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            RecoveryGateView(coordinator: coordinator, controller: controller)
            DeliveryModeSection(coordinator: coordinator, controller: controller)
            Section {
                ForEach(controller.visibleGroups) { group in
                    NavigationLink {
                        GroupTracerDetailView(
                            group: group,
                            coordinator: coordinator,
                            controller: controller
                        )
                    } label: {
                        GroupTracerRow(
                            group: group,
                            coordinator: coordinator,
                            controller: controller
                        )
                    }
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.groupRow(group.label)
                    )
                }
            } header: {
                Text(coordinator.text("groups.header"))
            } footer: {
                Text(coordinator.text("groups.footer"))
            }
        }
        .estroboScreenBackground()
        .navigationTitle(coordinator.text("tab.groups"))
        .sessionToolbar(coordinator: coordinator, controller: controller)
        .safeAreaInset(edge: .bottom) {
            ApplyTracerBar(coordinator: coordinator, controller: controller)
        }
        .accessibilityIdentifier(EstroboAccessibilityID.groupsList)
    }
}

private struct GroupTracerRow: View {
    let group: GodoxGroup
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        HStack(spacing: 12) {
            GroupBadge(
                group: group,
                accessibilityName: coordinator.text(
                    "group.accessibility",
                    group.label
                )
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("\(controller.groupDraft(group).draft.operatingMode.label) · \(controller.groupDraft(group).draft.power.label)")
                    .font(.body)
                    .monospacedDigit()
                Text(confirmationText(
                    controller.groupDraft(group),
                    coordinator: coordinator
                ))
                    .font(.caption.bold())
                    .foregroundStyle(confirmationColor(controller.groupDraft(group)))
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.groupConfirmation(group.label)
                    )
            }
            Spacer()
        }
        .frame(minHeight: 52)
    }
}

private struct GroupTracerDetailView: View {
    let group: GodoxGroup
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        List {
            RecoveryGateView(coordinator: coordinator, controller: controller)
            Section {
                HStack {
                    GroupBadge(
                        group: group,
                        accessibilityName: coordinator.text(
                            "group.accessibility",
                            group.label
                        )
                    )
                    VStack(alignment: .leading) {
                        Text("\(coordinator.text("group.title")) \(group.label)")
                            .font(.headline)
                            .accessibilityIdentifier(
                                EstroboAccessibilityID.groupDetail(group.label)
                            )
                        Text(confirmationText(
                            controller.groupDraft(group),
                            coordinator: coordinator
                        ))
                            .font(.subheadline.bold())
                            .foregroundStyle(confirmationColor(controller.groupDraft(group)))
                            .accessibilityIdentifier(
                                EstroboAccessibilityID.groupConfirmation(group.label)
                            )
                    }
                }
            }
            Section {
                Picker(
                    coordinator.text("group.mode"),
                    selection: Binding(
                        get: { controller.groupDraft(group).draft.operatingMode },
                        set: setOperatingMode
                    )
                ) {
                    Text("M").tag(GroupOperatingMode.manual)
                    Text("TTL").tag(GroupOperatingMode.autoTTL)
                    Text("Off").tag(GroupOperatingMode.off)
                }
                .pickerStyle(.segmented)
                .disabled(controller.groupDraft(group).draft.operatingMode == .multi)
                .accessibilityIdentifier(
                    EstroboAccessibilityID.groupMode(group.label)
                )

                if controller.groupDraft(group).draft.operatingMode == .multi {
                    Label(
                        coordinator.text("group.multi.global"),
                        systemImage: "waveform.path"
                    )
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text(coordinator.text("group.mode"))
            }
            Section {
                HStack {
                    Button {
                        controller.adjust(group, direction: -1)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(!controller.canEdit(group))
                    .accessibilityLabel(
                        coordinator.text(
                            "group.power.decrease.accessibility",
                            group.label
                        )
                    )
                    .accessibilityValue(
                        controller.groupDraft(group).draft.power.label
                    )
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.groupPowerDecrease(group.label)
                    )

                    Spacer()
                    Text(controller.groupDraft(group).draft.power.label)
                        .font(.title3.bold())
                        .monospacedDigit()
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.groupPower(group.label)
                        )
                    Spacer()

                    Button {
                        controller.adjust(group, direction: 1)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(!controller.canEdit(group))
                    .accessibilityLabel(
                        coordinator.text(
                            "group.power.increase.accessibility",
                            group.label
                        )
                    )
                    .accessibilityValue(
                        controller.groupDraft(group).draft.power.label
                    )
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.groupPowerIncrease(group.label)
                    )
                }
            } header: {
                Text(coordinator.text("group.power"))
            }
            Section {
                Picker(
                    coordinator.text("group.modeling"),
                    selection: Binding(
                        get: { controller.groupDraft(group).draft.modeling },
                        set: { controller.setDraftModeling(group, modeling: $0) }
                    )
                ) {
                    ForEach(modelingValues, id: \.self) { modeling in
                        Text(modelingText(
                            modeling,
                            coordinator: coordinator
                        )).tag(modeling)
                    }
                }
                .disabled(controller.allowedModelingLights(for: group).isEmpty)
                .accessibilityIdentifier(
                    EstroboAccessibilityID.groupModeling(group.label)
                )
            } header: {
                Text(coordinator.text("group.modeling"))
            } footer: {
                if controller.groupDraft(group).draft.operatingMode != .manual {
                    Text(coordinator.text("group.modeling.manual-only"))
                }
            }
        }
        .estroboScreenBackground()
        .navigationTitle("\(coordinator.text("group.title")) \(group.label)")
        .navigationBarTitleDisplayMode(.inline)
        .sessionToolbar(coordinator: coordinator, controller: controller)
        .safeAreaInset(edge: .bottom) {
            ApplyTracerBar(coordinator: coordinator, controller: controller)
        }
    }

    private var modelingValues: [ModelingLight] {
        let allowed = controller.allowedModelingLights(for: group)
        return allowed.isEmpty
            ? [controller.groupDraft(group).draft.modeling]
            : allowed
    }

    private func setOperatingMode(_ mode: GroupOperatingMode) {
        let current = controller.groupDraft(group).draft.operatingMode
        guard mode != current else { return }
        switch mode {
        case .off:
            controller.setDraftRadioEnabled(group, enabled: false)
        case .manual, .autoTTL:
            if current == .off {
                controller.setDraftRadioEnabled(group, enabled: true)
            }
            if controller.groupDraft(group).draft.operatingMode != mode {
                controller.setDraftOperatingMode(group, mode: mode)
            }
        case .multi:
            break
        }
    }
}

private struct DeliveryModeSection: View {
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

struct RecoveryGateView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        if !controller.restorationPoints.isEmpty {
            Section {
                Label(
                    coordinator.text("recovery.title"),
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.headline)
                .foregroundStyle(.orange)
                .accessibilityIdentifier(EstroboAccessibilityID.recoveryGate)

                Text(coordinator.text("recovery.detail"))
                    .foregroundStyle(.secondary)

                LabeledContent(
                    coordinator.text("recovery.required-device"),
                    value: requiredDeviceSuffix
                )
                .accessibilityIdentifier(EstroboAccessibilityID.recoveryRequiredDevice)

                if isWrongSelectedDevice {
                    Label(
                        coordinator.text("recovery.wrong-device"),
                        systemImage: "xmark.octagon.fill"
                    )
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(EstroboAccessibilityID.recoveryWrongDevice)
                }

                Button {
                    for group in recoveryGroups {
                        controller.prepareBaselineRestoration(for: group)
                    }
                } label: {
                    Label(
                        coordinator.text("recovery.prepare"),
                        systemImage: "arrow.uturn.backward.circle"
                    )
                    .frame(minHeight: 44)
                }
                .disabled(isPrepared)
                .accessibilityIdentifier(EstroboAccessibilityID.recoveryPrepare)

                Button {
                    controller.applyPendingChanges()
                } label: {
                    Label(
                        coordinator.text("recovery.apply"),
                        systemImage: "checkmark.shield"
                    )
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isPrepared || !controller.canApply)
                .accessibilityIdentifier(EstroboAccessibilityID.recoveryApply)
            } header: {
                Text(coordinator.text("recovery.gate"))
            } footer: {
                Text(coordinator.text("recovery.same-uuid"))
            }
        }
    }

    private var recoveryGroups: [GodoxGroup] {
        GodoxGroup.allCases.filter { controller.restorationPoints[$0] != nil }
    }

    private var isPrepared: Bool {
        Set(recoveryGroups) == controller.preparedRestorations
    }

    private var requiredDeviceID: UUID? {
        controller.restorationPoints.values.first?.deviceID
    }

    private var requiredDeviceSuffix: String {
        requiredDeviceID.map { String($0.uuidString.suffix(8)) } ?? "—"
    }

    private var isWrongSelectedDevice: Bool {
        guard let requiredDeviceID, let selected = controller.selectedDeviceID else {
            return false
        }
        return selected != requiredDeviceID
    }
}

struct ApplyTracerBar: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    pendingStatus
                    HStack(spacing: 12) {
                        Spacer()
                        actions
                    }
                }
            } else {
                HStack(spacing: 12) {
                    pendingStatus
                    Spacer()
                    actions
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(minHeight: 58)
        .background(.bar)
    }

    private var pendingStatus: some View {
        Text(
            controller.pendingCount == 0
                ? coordinator.text("changes.none")
                : coordinator.text(
                    "changes.pending.count",
                    controller.pendingCount
                )
        )
        .font(.subheadline.bold())
        .accessibilityIdentifier(EstroboAccessibilityID.pendingStatus)
    }

    @ViewBuilder
    private var actions: some View {
        Group {
            Button(coordinator.text("action.discard")) {
                controller.discardPendingChanges()
            }
            .frame(minHeight: 44)
            .disabled(!controller.canDiscardPendingChanges)
            .accessibilityIdentifier(EstroboAccessibilityID.discard)
            Button(coordinator.text("action.apply")) {
                controller.applyPendingChanges()
            }
            .frame(minHeight: 44)
            .buttonStyle(.borderedProminent)
            .disabled(!controller.canApply)
            .accessibilityIdentifier(EstroboAccessibilityID.apply)
        }
    }
}

private struct GlobalTracerView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        GlobalControlView(coordinator: coordinator, controller: controller)
    }
}

private struct PresetsTracerView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        PresetsLibraryView(coordinator: coordinator, controller: controller)
    }
}

private struct SettingsTracerView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        SettingsControlView(coordinator: coordinator, controller: controller)
    }
}

private struct ConnectionDemoView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle()
                            .fill(sessionColor(controller.phase))
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(sessionText(controller.phase, coordinator: coordinator))
                    }
                    if controller.phase.isBusy {
                        ProgressView()
                    }
                    if permissionDenied {
                        Label(
                            coordinator.text("connection.permission-denied"),
                            systemImage: "exclamationmark.bluetooth"
                        )
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.connectionPermissionDenied
                        )
                    }
                } header: {
                    Text(coordinator.text("connection.status"))
                }

                if controller.phase != .ready {
                    Section {
                        Button {
                            controller.startScanning()
                        } label: {
                            Label(
                                coordinator.text("connection.scan"),
                                systemImage: "dot.radiowaves.left.and.right"
                            )
                            .frame(minHeight: 44)
                        }
                        .disabled(controller.phase.isBusy)
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.connectionScan
                        )

                        ForEach(controller.devices) { device in
                            Button {
                                controller.selectDevice(device.id)
                                if controller.isSimulation {
                                    controller.radioCode = "000000"
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(device.name)
                                        Text(coordinator.text(
                                            "connection.candidate.detail",
                                            device.rssi,
                                            controller.deviceIdentifierSuffix(device)
                                        ))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    Spacer()
                                    if controller.selectedDeviceID == device.id {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                            .accessibilityIdentifier(
                                EstroboAccessibilityID.candidate(device.id)
                            )
                        }
                    } header: {
                        Text(coordinator.text("connection.radio"))
                    } footer: {
                        if controller.hasDuplicateDeviceNames {
                            Text(coordinator.text(
                                "connection.duplicate-names"
                            ))
                        }
                    }

                    if controller.selectedDevice != nil {
                        Section {
                            if !selectedDeviceMatchesRecovery {
                                Label(
                                    coordinator.text("recovery.wrong-device"),
                                    systemImage: "xmark.octagon.fill"
                                )
                                .foregroundStyle(.red)
                                .accessibilityIdentifier(
                                    EstroboAccessibilityID.recoveryWrongDevice
                                )
                            }
                            SecureField(
                                coordinator.text("connection.code"),
                                text: $controller.radioCode
                            )
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .privacySensitive()
                            .accessibilityIdentifier(
                                EstroboAccessibilityID.connectionRadioCode
                            )
                            Toggle(
                                coordinator.text("connection.remember"),
                                isOn: $controller.rememberSelectedRadio
                            )
                            .accessibilityIdentifier(
                                EstroboAccessibilityID.connectionRemember
                            )
                            Button(coordinator.text("connection.connect")) {
                                controller.connectSelectedDevice()
                            }
                            .disabled(
                                !controller.isRadioCodeValid
                                    || !canBeginConnection(controller.phase)
                                    || !selectedDeviceMatchesRecovery
                            )
                            .accessibilityIdentifier(
                                EstroboAccessibilityID.connectionConnect
                            )
                        } header: {
                            Text(coordinator.text("connection.credentials"))
                        }
                    }
                }

                if controller.phase == .synchronizing || controller.phase == .ready {
                    Section {
                        Label("PWOK", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityIdentifier(
                                EstroboAccessibilityID.connectionPWOK
                            )
                        Label(
                            controller.phase == .ready
                                ? coordinator.text("connection.sync.complete")
                                : coordinator.text("connection.sync.pending"),
                            systemImage: controller.phase == .ready
                                ? "checkmark.circle.fill"
                                : "clock"
                        )
                        .foregroundStyle(controller.phase == .ready ? .green : .secondary)
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.connectionSync
                        )
                    } header: {
                        Text(coordinator.text("connection.handshake"))
                    }
                }

                if controller.phase == .ready {
                    Section {
                        Button(coordinator.text("action.done")) {
                            coordinator.connectionPresented = false
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.connectionReady
                        )
                    }
                }
            }
            .estroboScreenBackground()
            .navigationTitle(coordinator.text("connection.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(coordinator.text("action.close")) {
                        coordinator.connectionPresented = false
                    }
                    .disabled(controller.phase.isBusy)
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.connectionDismiss
                    )
                }
            }
        }
        .interactiveDismissDisabled(controller.phase.isBusy)
        .accessibilityIdentifier(EstroboAccessibilityID.connectionSheet)
    }

    private var permissionDenied: Bool {
        let message: String
        switch controller.phase {
        case .unavailable(let detail), .failed(let detail):
            message = detail
        default:
            return false
        }
        return message.localizedCaseInsensitiveContains("permission")
            || message.localizedCaseInsensitiveContains("denied")
    }

    private var selectedDeviceMatchesRecovery: Bool {
        guard let requiredDeviceID = controller.restorationPoints.values.first?.deviceID,
              let selectedDeviceID = controller.selectedDeviceID else {
            return true
        }
        return requiredDeviceID == selectedDeviceID
    }
}

struct SessionToolbarModifier: ViewModifier {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    coordinator.connectionPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(sessionColor(controller.phase))
                            .frame(width: 8, height: 8)
                        Text(sessionText(controller.phase, coordinator: coordinator))
                            .lineLimit(1)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier(EstroboAccessibilityID.sessionStatus)
            }
        }
    }
}

extension View {
    func sessionToolbar(
        coordinator: AppSessionCoordinator,
        controller: GodoxSessionController
    ) -> some View {
        modifier(
            SessionToolbarModifier(
                coordinator: coordinator,
                controller: controller
            )
        )
    }
}

@MainActor
private func confirmationText(
    _ draft: GroupDraft,
    coordinator: AppSessionCoordinator
) -> String {
    if draft.hasPendingChange {
        return coordinator.text("confirmation.pending")
    }
    return switch draft.confirmation {
    case .unread: "—"
    case .gattAccepted: coordinator.text("confirmation.gatt")
    case .radioResponded: coordinator.text("confirmation.fec8")
    case .failed: coordinator.text("confirmation.error")
    }
}

@MainActor
private func modelingText(
    _ modeling: ModelingLight,
    coordinator: AppSessionCoordinator
) -> String {
    switch modeling {
    case .off:
        return coordinator.text("modeling.off")
    case .proportional:
        return coordinator.text("modeling.proportional")
    case .fixed(let percent):
        return coordinator.text("modeling.fixed", percent)
    }
}

@MainActor
private func foregroundNotice(
    _ controller: GodoxSessionController,
    coordinator: AppSessionCoordinator
) -> String? {
    switch controller.foregroundSessionState {
    case .active:
        return nil
    case .inactive(requirement: nil):
        return coordinator.text("foreground.paused")
    case .inactive(requirement: .some(.reconnectAndSynchronize)),
         .actionRequired(.reconnectAndSynchronize):
        return coordinator.text("foreground.reconnect")
    case .inactive(requirement: .some(.recover(let deviceID))),
         .actionRequired(.recover(let deviceID)):
        return coordinator.text(
            "foreground.recover",
            deviceID.uuidString
        )
    }
}

private func confirmationColor(_ draft: GroupDraft) -> Color {
    if draft.hasPendingChange { return .orange }
    return switch draft.confirmation {
    case .unread: Color.secondary
    case .gattAccepted: Color.blue
    case .radioResponded: Color.green
    case .failed: Color.red
    }
}

@MainActor
private func sessionText(
    _ phase: SessionPhase,
    coordinator: AppSessionCoordinator
) -> String {
    let key: String
    switch phase {
    case .idle: key = "session.idle"
    case .scanning: key = "session.scanning"
    case .connecting: key = "session.connecting"
    case .discovering: key = "session.discovering"
    case .authenticating: key = "session.authenticating"
    case .synchronizing: key = "session.synchronizing"
    case .ready: key = "session.ready"
    case .applying: key = "session.applying"
    case .disconnecting: key = "session.disconnecting"
    case .unavailable: key = "session.unavailable"
    case .failed: key = "session.failed"
    }
    return coordinator.text(key)
}

private func sessionColor(_ phase: SessionPhase) -> Color {
    return switch phase {
    case .ready: Color.green
    case .failed, .unavailable: Color.red
    case .idle: Color.secondary
    default: EstroboTheme.interactiveAccent
    }
}

private func canBeginConnection(_ phase: SessionPhase) -> Bool {
    switch phase {
    case .idle, .scanning, .failed:
        true
    default:
        false
    }
}
