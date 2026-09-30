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
            if controller.isReconfiguringWorkspace {
                CompatibilityEditorView(
                    coordinator: coordinator,
                    controller: controller,
                    isOnboarding: false,
                    onCancel: { controller.cancelWorkspaceConfiguration() },
                    onComplete: {}
                )
            } else if controller.hasCompletedOnboarding {
                AdaptiveRootView(
                    coordinator: coordinator,
                    controller: controller
                )
            } else if controller.requiresPhysicalRecovery {
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
    @StateObject private var testPresentation = GroupsTestPresentation()

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
            GroupsTestFeedbackView(
                coordinator: coordinator,
                controller: controller,
                presentation: testPresentation
            )
            GlobalControlSections(
                coordinator: coordinator,
                controller: controller,
                onOpenGroupDetails: { coordinator.selectedGroup = $0 }
            )
            if controller.multiFlashGroups.isEmpty {
                Section {
                    ForEach(controller.visibleGroups) { group in
                        GroupTracerRow(
                            group: group,
                            coordinator: coordinator,
                            controller: controller,
                            onOpenDetails: { coordinator.selectedGroup = group }
                        )
                    }
                }
            }
        }
        .estroboScreenBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .groupsTestToolbar(
            coordinator: coordinator,
            controller: controller,
            presentation: testPresentation
        )
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
    @StateObject private var testPresentation = GroupsTestPresentation()
    @State private var detailGroup: GodoxGroup?

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
            GroupsTestFeedbackView(
                coordinator: coordinator,
                controller: controller,
                presentation: testPresentation
            )
            GlobalControlSections(
                coordinator: coordinator,
                controller: controller,
                onOpenGroupDetails: { detailGroup = $0 }
            )
            if controller.multiFlashGroups.isEmpty {
                Section {
                    ForEach(controller.visibleGroups) { group in
                        GroupTracerRow(
                            group: group,
                            coordinator: coordinator,
                            controller: controller,
                            onOpenDetails: { detailGroup = group }
                        )
                    }
                }
            }
        }
        .accessibilityIdentifier(EstroboAccessibilityID.groupsList)
        .estroboScreenBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .groupsTestToolbar(
            coordinator: coordinator,
            controller: controller,
            presentation: testPresentation
        )
        .sessionToolbar(coordinator: coordinator, controller: controller)
        .safeAreaInset(edge: .bottom) {
            ApplyTracerBar(coordinator: coordinator, controller: controller)
        }
        .navigationDestination(item: $detailGroup) { group in
            GroupTracerDetailView(
                group: group,
                coordinator: coordinator,
                controller: controller
            )
        }
    }
}

private struct GroupTracerRow: View {
    let group: GodoxGroup
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController
    let onOpenDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                GroupBadge(
                    group: group,
                    accessibilityName: coordinator.text(
                        "group.accessibility",
                        group.label
                    )
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.groupDraft(group).draft.operatingMode.label)
                        .font(.headline)
                    Text(confirmationText(
                        controller.groupDraft(group),
                        coordinator: coordinator
                    ))
                        .font(.caption.bold())
                        .foregroundStyle(confirmationColor(controller.groupDraft(group)))
                }
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .groupDetailLongPressFeedback(action: onOpenDetails)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                coordinator.text("group.accessibility", group.label)
            )
            .accessibilityValue(headerAccessibilityValue)
            .accessibilityHint(coordinator.text("group.detail.long-press.hint"))
            .accessibilityAction(named: Text(coordinator.text("group.detail.open"))) {
                onOpenDetails()
            }
            .accessibilityIdentifier(
                EstroboAccessibilityID.groupRow(group.label)
            )

            InlineGroupPowerControl(
                group: group,
                coordinator: coordinator,
                controller: controller
            )
        }
        .padding(.vertical, 4)
        .frame(minHeight: 108)
        .opacity(controller.isGlobalStandbyEnabled ? 0.22 : 1)
        .overlay {
            if controller.isGlobalStandbyEnabled {
                StandbyGroupOverlay(
                    group: group,
                    coordinator: coordinator
                )
            }
        }
    }

    private var headerAccessibilityValue: String {
        var values = [
            controller.groupDraft(group).draft.operatingMode.label,
            confirmationText(
                controller.groupDraft(group),
                coordinator: coordinator
            ),
            controller.groupDraft(group).baseline.power.label,
        ]
        if controller.isGlobalStandbyEnabled {
            values.insert(coordinator.text("standby.overlay.title"), at: 0)
        }
        return values.joined(separator: ", ")
    }
}

private struct InlineGroupPowerControl: View {
    let group: GodoxGroup
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController
    var showsStepButtons = true
    var usesDetailIdentifiers = false
    @State private var interactiveEditToken: GodoxSessionController.InteractiveEditToken?
    @State private var livePowerIndex: Int?

    var body: some View {
        HStack(spacing: 10) {
            if showsStepButtons {
                Button {
                    controller.adjust(group, direction: -1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(
                    interactiveEditToken != nil ||
                        !controller.canAdjustPower(group, direction: -1)
                )
                .accessibilityLabel(
                    coordinator.text(
                        "group.power.decrease.accessibility",
                        group.label
                    )
                )
                .accessibilityValue(powerLabel)
                .accessibilityIdentifier(
                    EstroboAccessibilityID.groupPowerDecrease(group.label)
                )
            }

            VStack(spacing: 4) {
                Text(powerLabel)
                    .font(.body.bold())
                    .monospacedDigit()
                    .accessibilityHidden(true)
                    .accessibilityIdentifier(
                        powerValueAccessibilityIdentifier
                    )

                ZStack {
                    SliderRulerTicks(
                        tickCount: rulerTickCount,
                        majorTickEvery: rulerMajorTickEvery
                    )
                    .offset(y: 8)
                    DeterministicSlider(
                        value: powerIndexBinding,
                        range: 0...maximumSliderIndex,
                        step: 1,
                        isEnabled: controller.canEdit(group) && allowedPowers.count >= 2,
                        accessibilityLabel: coordinator.text(
                            "group.power.accessibility",
                            group.label
                        ),
                        accessibilityValue: powerLabel,
                        accessibilityIdentifier: powerSliderAccessibilityIdentifier,
                        onInteractionBegan: beginInteractiveEdit,
                        onInteractionEnded: finishInteractiveEdit,
                        onInteractionCancelled: cancelInteractiveEdit
                    )
                    .disabled(!controller.canEdit(group) || allowedPowers.count < 2)
                    .tint(EstroboTheme.interactiveAccent)
                }
                .frame(minHeight: 44)

                HStack(spacing: 0) {
                    Text(coordinator.text("slider.minimum"))
                    Spacer()
                    Text(powerScaleLabel(fraction: 1.0 / 3.0))
                    Spacer()
                    Text(powerScaleLabel(fraction: 2.0 / 3.0))
                    Spacer()
                    Text(coordinator.text("slider.maximum"))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }

            if showsStepButtons {
                Button {
                    controller.adjust(group, direction: 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(
                    interactiveEditToken != nil ||
                        !controller.canAdjustPower(group, direction: 1)
                )
                .accessibilityLabel(
                    coordinator.text(
                        "group.power.increase.accessibility",
                        group.label
                    )
                )
                .accessibilityValue(powerLabel)
                .accessibilityIdentifier(
                    EstroboAccessibilityID.groupPowerIncrease(group.label)
                )
            }
        }
        .onChange(of: controller.canEdit(group)) {
            if !controller.canEdit(group) {
                cancelInteractiveEdit()
            }
        }
        .onDisappear(perform: cancelInteractiveEdit)
    }

    private var allowedPowers: [ManualPower] {
        controller.allowedPowers(for: group)
    }

    private var powerValueAccessibilityIdentifier: String {
        usesDetailIdentifiers
            ? EstroboAccessibilityID.groupDetailPower(group.label)
            : EstroboAccessibilityID.groupPower(group.label)
    }

    private var powerSliderAccessibilityIdentifier: String {
        usesDetailIdentifiers
            ? EstroboAccessibilityID.groupDetailPowerSlider(group.label)
            : EstroboAccessibilityID.groupPowerSlider(group.label)
    }

    private var powerLabel: String {
        if let livePowerIndex,
           allowedPowers.indices.contains(livePowerIndex) {
            return allowedPowers[livePowerIndex].label
        }
        return controller.groupDraft(group).draft.power.label
    }

    private var maximumSliderIndex: Double {
        Double(max(1, allowedPowers.count - 1))
    }

    private var rulerTickCount: Int {
        min(max(allowedPowers.count, 9), 25)
    }

    private var rulerMajorTickEvery: Int {
        max(1, (rulerTickCount - 1) / 3)
    }

    private func powerScaleLabel(fraction: Double) -> String {
        guard !allowedPowers.isEmpty else { return "—" }
        let index = min(
            allowedPowers.count - 1,
            max(0, Int((Double(allowedPowers.count - 1) * fraction).rounded()))
        )
        return allowedPowers[index].label
    }

    private var powerIndexBinding: Binding<Double> {
        Binding(
            get: {
                Double(livePowerIndex ?? controller.powerIndex(for: group))
            },
            set: { proposedIndex in
                let boundedIndex = min(
                    max(Int(proposedIndex.rounded()), 0),
                    max(0, allowedPowers.count - 1)
                )
                livePowerIndex = boundedIndex
            }
        )
    }

    private func beginInteractiveEdit() {
        guard interactiveEditToken == nil, controller.canEdit(group) else {
            return
        }
        livePowerIndex = controller.powerIndex(for: group)
        interactiveEditToken = controller.beginInteractiveEdit()
    }

    private func finishInteractiveEdit() {
        guard let interactiveEditToken else { return }
        self.interactiveEditToken = nil
        guard controller.isSceneActive, controller.canEdit(group) else {
            controller.cancelInteractiveEdit(interactiveEditToken)
            livePowerIndex = nil
            return
        }
        if let livePowerIndex {
            controller.setDraftPowerIndex(livePowerIndex, for: group)
        }
        controller.endInteractiveEdit(interactiveEditToken)
        livePowerIndex = nil
    }

    private func cancelInteractiveEdit() {
        if let interactiveEditToken {
            self.interactiveEditToken = nil
            controller.cancelInteractiveEdit(interactiveEditToken)
        }
        livePowerIndex = nil
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
                            .accessibilityValue(
                                controller.groupDraft(group).baseline.power.label
                            )
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
                InlineGroupPowerControl(
                    group: group,
                    coordinator: coordinator,
                    controller: controller,
                    showsStepButtons: false,
                    usesDetailIdentifiers: true
                )
            } header: {
                Text(coordinator.text("group.power"))
            }
            Section {
                GroupModelingControl(
                    group: group,
                    coordinator: coordinator,
                    controller: controller
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

private enum ModelingChoice: Hashable {
    case off
    case proportional
    case manual
}

private struct GroupModelingControl: View {
    let group: GodoxGroup
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    @State private var interactiveEditToken:
        GodoxSessionController.InteractiveEditToken?
    @State private var liveManualIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(
                coordinator.text("group.modeling"),
                selection: Binding(
                    get: { currentChoice },
                    set: setChoice
                )
            ) {
                ForEach(supportedChoices, id: \.self) { choice in
                    Text(title(for: choice))
                        .tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!controller.canEdit(group) || supportedChoices.count < 2)
            .accessibilityIdentifier(
                EstroboAccessibilityID.groupModeling(group.label)
            )

            if currentChoice == .manual, !manualValues.isEmpty {
                manualSlider
            }
        }
        .onChange(of: controller.canEdit(group)) { _, canEdit in
            if !canEdit { cancelInteractiveEdit() }
        }
        .onChange(of: currentChoice) { _, choice in
            if choice != .manual { cancelInteractiveEdit() }
        }
        .onDisappear(perform: cancelInteractiveEdit)
    }

    private var manualSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(coordinator.text("modeling.manual.level"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Text(coordinator.text("modeling.manual.value", displayedPercent))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .accessibilityHidden(true)

            ZStack {
                SliderRulerTicks(
                    tickCount: manualRulerTickCount,
                    majorTickEvery: manualRulerMajorTickEvery
                )
                .offset(y: 8)
                DeterministicSlider(
                    value: manualIndexBinding,
                    range: 0...maximumManualIndex,
                    step: 1,
                    isEnabled: canUseManualSlider,
                    accessibilityLabel: coordinator.text(
                        "modeling.manual.slider.accessibility",
                        group.label
                    ),
                    accessibilityValue: coordinator.text(
                        "modeling.manual.value",
                        displayedPercent
                    ),
                    accessibilityIdentifier:
                        EstroboAccessibilityID.groupModelingManualSlider(group.label),
                    onInteractionBegan: beginInteractiveEdit,
                    onInteractionEnded: finishInteractiveEdit,
                    onInteractionCancelled: cancelInteractiveEdit
                )
                .tint(EstroboTheme.interactiveAccent)
                .disabled(!canUseManualSlider)
            }
            .frame(minHeight: 44)

            HStack {
                Text(coordinator.text("modeling.manual.value", minimumManualPercent))
                Spacer()
                Text(coordinator.text("modeling.manual.value", maximumManualPercent))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
    }

    private var allowedValues: [ModelingLight] {
        controller.resolvedCapability(for: group).modeling.editableValues
    }

    private var manualValues: [ModelingLight] {
        allowedValues.filter {
            if case .fixed = $0 { return true }
            return false
        }
    }

    private var supportedChoices: [ModelingChoice] {
        var choices: [ModelingChoice] = []
        if allowedValues.contains(.off) { choices.append(.off) }
        if allowedValues.contains(.proportional) { choices.append(.proportional) }
        if !manualValues.isEmpty { choices.append(.manual) }
        return choices
    }

    private func title(for choice: ModelingChoice) -> String {
        switch choice {
        case .off: coordinator.text("modeling.off")
        case .proportional: coordinator.text("modeling.proportional")
        case .manual: coordinator.text("modeling.manual")
        }
    }

    private var currentChoice: ModelingChoice {
        switch controller.groupDraft(group).draft.modeling {
        case .off: .off
        case .proportional: .proportional
        case .fixed: .manual
        }
    }

    private var displayedManualIndex: Int {
        if let liveManualIndex {
            return boundedManualIndex(liveManualIndex)
        }
        let current = controller.groupDraft(group).draft.modeling
        return manualValues.firstIndex(of: current) ?? preferredManualIndex
    }

    private var displayedPercent: Int {
        percent(for: manualValue(at: displayedManualIndex)) ?? minimumManualPercent
    }

    private var minimumManualPercent: Int {
        percent(for: manualValues.first) ?? 10
    }

    private var maximumManualPercent: Int {
        percent(for: manualValues.last) ?? minimumManualPercent
    }

    private var preferredManualIndex: Int {
        manualValues.firstIndex(of: .fixed(percent: 25)) ?? 0
    }

    private var maximumManualIndex: Double {
        Double(max(1, manualValues.count - 1))
    }

    private var manualRulerTickCount: Int {
        min(max(manualValues.count, 9), 19)
    }

    private var manualRulerMajorTickEvery: Int {
        max(1, (manualRulerTickCount - 1) / 2)
    }

    private var canUseManualSlider: Bool {
        controller.canEdit(group) && manualValues.count >= 2
    }

    private var manualIndexBinding: Binding<Double> {
        Binding(
            get: { Double(displayedManualIndex) },
            set: { liveManualIndex = boundedManualIndex(Int($0.rounded())) }
        )
    }

    private func setChoice(_ choice: ModelingChoice) {
        guard controller.canEdit(group) else { return }
        let value: ModelingLight?
        switch choice {
        case .off:
            value = allowedValues.contains(.off) ? .off : nil
        case .proportional:
            value = allowedValues.contains(.proportional) ? .proportional : nil
        case .manual:
            value = manualValue(at: displayedManualIndex)
        }
        guard let value else { return }
        controller.setDraftModeling(group, modeling: value)
    }

    private func beginInteractiveEdit() {
        guard interactiveEditToken == nil, canUseManualSlider else { return }
        liveManualIndex = displayedManualIndex
        interactiveEditToken = controller.beginInteractiveEdit()
    }

    private func finishInteractiveEdit() {
        guard let interactiveEditToken else { return }
        self.interactiveEditToken = nil
        guard controller.isSceneActive,
              controller.canEdit(group),
              let value = manualValue(at: displayedManualIndex) else {
            controller.cancelInteractiveEdit(interactiveEditToken)
            liveManualIndex = nil
            return
        }
        controller.setDraftModeling(group, modeling: value)
        controller.endInteractiveEdit(interactiveEditToken)
        liveManualIndex = nil
    }

    private func cancelInteractiveEdit() {
        if let interactiveEditToken {
            self.interactiveEditToken = nil
            controller.cancelInteractiveEdit(interactiveEditToken)
        }
        liveManualIndex = nil
    }

    private func boundedManualIndex(_ index: Int) -> Int {
        min(max(index, 0), max(0, manualValues.count - 1))
    }

    private func percent(for value: ModelingLight?) -> Int? {
        guard case .fixed(let percent) = value else { return nil }
        return percent
    }

    private func manualValue(at index: Int) -> ModelingLight? {
        guard manualValues.indices.contains(index) else { return nil }
        return manualValues[index]
    }
}

struct RecoveryGateView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        if controller.requiresPhysicalRecovery {
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

enum AutomaticDeliveryFeedbackActivity: Equatable {
    case idle
    case synchronizing

    init(
        isDebounceScheduled: Bool,
        isIOActive: Bool,
        suppressesGlobalActionFeedback: Bool = false
    ) {
        if suppressesGlobalActionFeedback {
            self = .idle
        } else if isDebounceScheduled || isIOActive {
            self = .synchronizing
        } else {
            self = .idle
        }
    }
}

enum AutomaticDeliveryFeedbackPhase: Equatable {
    case syncing
}

func reducedAutomaticDeliveryFeedbackPhase(
    current: AutomaticDeliveryFeedbackPhase?,
    activity: AutomaticDeliveryFeedbackActivity
) -> AutomaticDeliveryFeedbackPhase? {
    switch activity {
    case .synchronizing:
        return .syncing
    case .idle:
        return nil
    }
}

struct ApplyTracerBar: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var automaticFeedbackPhase: AutomaticDeliveryFeedbackPhase?

    @ViewBuilder
    var body: some View {
        Group {
            if controller.changeDeliveryMode == .automatic,
               automaticFeedbackPhase != nil {
                automaticFeedback
            } else if controller.changeDeliveryMode == .manual,
                      shouldPresent,
                      !controller.isDirectGlobalActionPending {
                manualFeedback
            }
        }
        .onChange(of: automaticFeedbackActivity, initial: true) { _, activity in
            updateAutomaticFeedback(activity: activity)
        }
        .onChange(of: controller.changeDeliveryMode) { _, mode in
            if mode == .automatic {
                updateAutomaticFeedback(activity: automaticFeedbackActivity)
            } else {
                automaticFeedbackPhase = nil
            }
        }
        .onDisappear {
            automaticFeedbackPhase = nil
        }
    }

    @ViewBuilder
    private var manualFeedback: some View {
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

    private var automaticFeedback: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(coordinator.text("delivery.automatic.pending"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if controller.canDiscardPendingChanges {
                Button {
                    controller.discardPendingChanges()
                } label: {
                    Image(systemName: "xmark.circle")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(coordinator.text("action.discard"))
                .accessibilityIdentifier(EstroboAccessibilityID.discard)
            }
        }
        .padding(.leading)
        .padding(.trailing, 6)
        .frame(minHeight: 40)
        .background(.bar)
        .accessibilityIdentifier(
            EstroboAccessibilityID.deliveryAutomaticFeedback
        )
    }

    private func updateAutomaticFeedback(activity: AutomaticDeliveryFeedbackActivity) {
        guard controller.changeDeliveryMode == .automatic else { return }
        automaticFeedbackPhase = reducedAutomaticDeliveryFeedbackPhase(
            current: automaticFeedbackPhase,
            activity: activity
        )
    }

    private var automaticFeedbackActivity: AutomaticDeliveryFeedbackActivity {
        let isIOActive = controller.phase == .applying
            || controller.isGlobalControlPending
            || controller.applySequenceStatus != nil
        return AutomaticDeliveryFeedbackActivity(
            isDebounceScheduled: controller.isAutomaticApplyScheduled,
            isIOActive: isIOActive,
            suppressesGlobalActionFeedback: controller.isDirectGlobalActionPending
                || controller.pendingGlobalMultiFlashTransition != nil
        )
    }

    private var shouldPresent: Bool {
        controller.pendingCount > 0
            || controller.isAutomaticApplyScheduled
            || controller.canDiscardPendingChanges
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
        if controller.canDiscardPendingChanges {
            Button(coordinator.text("action.discard")) {
                controller.discardPendingChanges()
            }
            .frame(minHeight: 44)
            .disabled(!controller.canDiscardPendingChanges)
            .accessibilityIdentifier(EstroboAccessibilityID.discard)
        }
        if controller.changeDeliveryMode == .manual {
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
                        if controller.canCancelConnectionAttempt {
                            Button(coordinator.text("action.cancel"), role: .cancel) {
                                controller.cancelConnectionAttempt()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier(
                                EstroboAccessibilityID.connectionSyncCancel
                            )
                        }
                    } header: {
                        Text(coordinator.text("connection.handshake"))
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
        .onChange(of: controller.phase) { previousPhase, phase in
            if phase == .ready,
               isActiveConnectionAttempt(previousPhase) {
                coordinator.connectionPresented = false
            }
        }
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

    private func isActiveConnectionAttempt(_ phase: SessionPhase) -> Bool {
        switch phase {
        case .scanning, .connecting, .discovering, .authenticating,
             .synchronizing:
            true
        default:
            false
        }
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

private struct GroupsTestToolbarModifier: ViewModifier {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController
    @ObservedObject var presentation: GroupsTestPresentation

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentation.send(using: controller)
                } label: {
                    HStack(spacing: 5) {
                        Image(
                            systemName: controller.isTestPending
                                ? "hourglass"
                                : "bolt.fill"
                        )
                        Text(
                            controller.isTestPending
                                ? coordinator.text("test.pending")
                                : coordinator.text("test.action")
                        )
                        .font(.callout.bold())
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(EstroboTheme.amber)
                .foregroundStyle(EstroboTheme.navy)
                .disabled(!controller.canSendTest)
                .accessibilityHint(coordinator.text("test.safety.short"))
                .accessibilityIdentifier(EstroboAccessibilityID.testSend)
            }
        }
        .onChange(of: controller.testDeliveryResult) { _, result in
            presentation.resolve(result)
        }
    }
}

@MainActor
private final class GroupsTestPresentation: ObservableObject {
    @Published private(set) var result: GroupsTestResult?

    func send(using controller: GodoxSessionController) {
        guard controller.canSendTest else { return }
        result = nil
        controller.sendTestFlash()
    }

    func resolve(_ deliveryResult: TestDeliveryResult?) {
        guard let deliveryResult else {
            result = nil
            return
        }
        switch deliveryResult.outcome {
        case .simulated:
            result = .simulated
        case .delivered:
            result = .delivered
        case .failed:
            result = .failed
        }
    }
}

private enum GroupsTestResult {
    case simulated
    case delivered
    case failed

    var localizationKey: String {
        switch self {
        case .simulated: "test.result.simulated"
        case .delivered: "test.result.delivered"
        case .failed: "test.result.failed"
        }
    }

    var systemImage: String {
        switch self {
        case .simulated, .delivered: "checkmark.circle"
        case .failed: "xmark.octagon"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .simulated, .delivered: EstroboAccessibilityID.testSent
        case .failed: EstroboAccessibilityID.testFailed
        }
    }
}

private struct GroupsTestFeedbackView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController
    @ObservedObject var presentation: GroupsTestPresentation

    @ViewBuilder
    var body: some View {
        if controller.isTestPending {
            Label(
                coordinator.text("test.pending.detail"),
                systemImage: "arrow.up.circle"
            )
            .accessibilityIdentifier(EstroboAccessibilityID.testPending)
        } else if let result = presentation.result {
            Label(
                coordinator.text(result.localizationKey),
                systemImage: result.systemImage
            )
            .accessibilityIdentifier(result.accessibilityIdentifier)
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

    fileprivate func groupsTestToolbar(
        coordinator: AppSessionCoordinator,
        controller: GodoxSessionController,
        presentation: GroupsTestPresentation
    ) -> some View {
        modifier(
            GroupsTestToolbarModifier(
                coordinator: coordinator,
                controller: controller,
                presentation: presentation
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
            GodoxSessionController.redactedDeviceIdentifier(deviceID)
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
