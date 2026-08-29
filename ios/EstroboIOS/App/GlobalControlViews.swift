import SwiftUI
import EstroboCore

struct GlobalControlView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    @State private var activeConfirmation: GlobalConfirmation?
    @State private var testWasStarted = false
    @State private var testResult: TestPresentationResult?
    @State private var globalPowerFeedback: String?

    var body: some View {
        List {
            RecoveryGateView(coordinator: coordinator, controller: controller)
            globalPowerSection
            globalSwitchesSection
            testSection
            multiSection
        }
        .estroboScreenBackground()
        .navigationTitle(coordinator.text("tab.global"))
        .sessionToolbar(coordinator: coordinator, controller: controller)
        .safeAreaInset(edge: .bottom) {
            ApplyTracerBar(coordinator: coordinator, controller: controller)
        }
        .sheet(item: $activeConfirmation) { confirmation in
            switch confirmation {
            case .test(let isMulti):
                TestConfirmationView(
                    coordinator: coordinator,
                    isMulti: isMulti,
                    onCancel: { activeConfirmation = nil },
                    onConfirm: {
                        testResult = nil
                        testWasStarted = true
                        controller.sendTestFlash()
                        activeConfirmation = nil
                    }
                )
            case .multi(let enabled):
                MultiConfirmationView(
                    coordinator: coordinator,
                    enabled: enabled,
                    enteringOrRemainingMultiGroups: multiGroupsEnteringOrRemaining,
                    movingToOffGroups: multiGroupsMovingToOff,
                    restoringToManualGroups: controller.workingGroups,
                    onCancel: { activeConfirmation = nil },
                    onConfirm: {
                        controller.setGlobalMultiFlashEnabled(enabled)
                        activeConfirmation = nil
                    }
                )
            case .standby(let enabled):
                StandbyConfirmationView(
                    coordinator: coordinator,
                    enabled: enabled,
                    onCancel: { activeConfirmation = nil },
                    onConfirm: {
                        controller.setGlobalStandby(enabled)
                        activeConfirmation = nil
                    }
                )
            }
        }
        .onChange(of: controller.activity.count) {
            guard testWasStarted,
                  !controller.isTestPending,
                  let latestActivity = controller.activity.last else { return }
            switch latestActivity.level {
            case .success:
                testResult = controller.isSimulation ? .simulated : .delivered
                testWasStarted = false
            case .error:
                testResult = .failed
                testWasStarted = false
            case .info, .warning:
                break
            }
        }
    }

    /// Mirrors the effects of `initialMultiScenePlan()` using only the
    /// controller's public presentation state. The controller remains the
    /// authority and revalidates the plan when the user confirms.
    private var multiGroupsEnteringOrRemaining: [GodoxGroup] {
        controller.workingGroups.filter { group in
            switch controller.groupDraft(group).draft.operatingMode {
            case .multi:
                return true
            case .manual, .autoTTL:
                return controller.supportsMultiFlash(group)
            case .off:
                return false
            }
        }
    }

    /// Active groups without Multi support are the only groups the activation
    /// plan moves to Off. Groups that are already Off remain unchanged.
    private var multiGroupsMovingToOff: [GodoxGroup] {
        controller.workingGroups.filter { group in
            switch controller.groupDraft(group).draft.operatingMode {
            case .manual, .autoTTL:
                return !controller.supportsMultiFlash(group)
            case .multi, .off:
                return false
            }
        }
    }

    private var globalPowerSection: some View {
        Section {
            HStack(spacing: 20) {
                Button {
                    adjustGlobalPower(direction: -1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!controller.canAdjustGlobalPower(direction: -1))
                .accessibilityLabel(coordinator.text("global.power.decrease"))
                .accessibilityIdentifier(EstroboAccessibilityID.globalPowerDecrease)

                VStack(spacing: 4) {
                    Text(coordinator.text("global.power.relative"))
                        .font(.headline)
                    Text(globalPowerGroupsText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let globalPowerFeedback {
                        Text(globalPowerFeedback)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(
                                EstroboAccessibilityID.globalPowerStatus
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

                Button {
                    adjustGlobalPower(direction: 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!controller.canAdjustGlobalPower(direction: 1))
                .accessibilityLabel(coordinator.text("global.power.increase"))
                .accessibilityIdentifier(EstroboAccessibilityID.globalPowerIncrease)
            }
        } header: {
            Text(coordinator.text("global.power.title"))
                .accessibilityIdentifier(EstroboAccessibilityID.globalScreen)
        } footer: {
            Text(coordinator.text("global.power.detail"))
        }
    }

    private var globalSwitchesSection: some View {
        Section {
            Toggle(
                coordinator.text("global.beep"),
                isOn: Binding(
                    get: { controller.globalBeepEnabled },
                    set: { controller.setGlobalBeep($0) }
                )
            )
            .disabled(!controller.canToggleGlobalBeep)
            .accessibilityIdentifier(EstroboAccessibilityID.globalBeep)

            Button {
                activeConfirmation = .standby(
                    enabled: !controller.isGlobalStandbyEnabled
                )
            } label: {
                HStack {
                    Label(
                        coordinator.text("global.standby"),
                        systemImage: "power"
                    )
                    Spacer()
                    Text(
                        controller.isGlobalStandbyEnabled
                            ? coordinator.text("value.on")
                            : coordinator.text("value.off")
                    )
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!controller.canToggleGlobalStandby)
            .accessibilityIdentifier(EstroboAccessibilityID.globalStandby)
        } header: {
            Text(coordinator.text("global.status"))
        } footer: {
            if controller.isGlobalStandbyEnabled {
                Text(coordinator.text("global.standby.active-detail"))
            }
        }
    }

    private var testSection: some View {
        Section {
            Button {
                activeConfirmation = .test(
                    isMulti: !controller.multiFlashGroups.isEmpty
                )
            } label: {
                Label(
                    controller.isTestPending
                        ? coordinator.text("test.pending")
                        : coordinator.text("test.action"),
                    systemImage: controller.isTestPending
                        ? "hourglass"
                        : "bolt.fill"
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(EstroboTheme.amber)
            .foregroundStyle(EstroboTheme.navy)
            .disabled(!controller.canSendTest)
            .accessibilityIdentifier(EstroboAccessibilityID.testOpenConfirmation)

            if controller.isTestPending {
                Label(
                    coordinator.text("test.pending.detail"),
                    systemImage: "arrow.up.circle"
                )
                .accessibilityIdentifier(EstroboAccessibilityID.testPending)
            } else if let testResult {
                Label(
                    coordinator.text(testResult.localizationKey),
                    systemImage: testResult.systemImage
                )
                .accessibilityIdentifier(testResult.accessibilityIdentifier)
            }
        } header: {
            Text(coordinator.text("test.title"))
        } footer: {
            Text(testFooter)
        }
    }

    private var testFooter: String {
        if controller.canSendTest {
            return coordinator.text("test.safety.short")
        }
        if !controller.isSceneActive {
            return coordinator.text("test.block.foreground")
        }
        if controller.isInteractiveEditActive {
            return coordinator.text("test.block.gesture")
        }
        if controller.isTestPending {
            return coordinator.text("test.block.pending")
        }
        if controller.recoveryBlockReason != nil
            || !controller.restorationPoints.isEmpty {
            return coordinator.text("test.block.recovery")
        }
        if controller.phase != .ready {
            return coordinator.text("test.block.connection")
        }
        if controller.isGlobalStandbyEnabled {
            return coordinator.text("test.block.standby")
        }
        if controller.pendingCount > 0 {
            return coordinator.text("test.block.changes")
        }
        return coordinator.text("test.block.operation")
    }

    private var multiSection: some View {
        Section {
            Button {
                activeConfirmation = .multi(
                    enabled: controller.multiFlashGroups.isEmpty
                )
            } label: {
                HStack {
                    Label(
                        controller.multiFlashGroups.isEmpty
                            ? coordinator.text("multi.activate")
                            : coordinator.text("multi.deactivate"),
                        systemImage: "waveform.path"
                    )
                    Spacer()
                    Text(
                        controller.multiFlashGroups.isEmpty
                            ? coordinator.text("multi.inactive")
                            : coordinator.text("multi.active")
                    )
                    .font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(
                !controller.canSetGlobalMultiFlashEnabled(
                    controller.multiFlashGroups.isEmpty
                )
            )
            .accessibilityIdentifier(EstroboAccessibilityID.multiOpenConfirmation)

            Label(
                controller.hasPendingMultiFlashChange
                    ? coordinator.text("multi.pending")
                    : coordinator.text("multi.applied"),
                systemImage: controller.hasPendingMultiFlashChange
                    ? "clock"
                    : "checkmark.circle"
            )
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(EstroboAccessibilityID.multiEnabled)

            if !controller.multiFlashGroups.isEmpty {
                participants
                multiPowerPicker
                multiCountStepper
                multiHertzStepper
                multiLimitSummary
            }
        } header: {
            Text("Multi")
        } footer: {
            Text(coordinator.text("multi.safety"))
        }
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(coordinator.text("multi.participants"))
                .font(.subheadline.bold())
            ForEach(controller.workingGroups) { group in
                Toggle(
                    isOn: Binding(
                        get: { controller.multiFlashGroups.contains(group) },
                        set: {
                            controller.setMultiFlashParticipation(
                                group,
                                enabled: $0
                            )
                        }
                    )
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
                .disabled(
                    !controller.canSetMultiFlashParticipation(
                        group,
                        enabled: !controller.multiFlashGroups.contains(group)
                    )
                )
                .accessibilityIdentifier(
                    EstroboAccessibilityID.multiParticipant(group.label)
                )
            }
        }
    }

    private var multiPowerPicker: some View {
        Picker(
            coordinator.text("multi.power"),
            selection: Binding(
                get: { controller.multiFlashDraft.power },
                set: { controller.setMultiFlashPower($0) }
            )
        ) {
            ForEach(controller.allowedMultiFlashPowers) { power in
                Text(power.label).tag(power)
            }
        }
        .disabled(!controller.canEditMultiFlashSettings)
        .accessibilityIdentifier(EstroboAccessibilityID.multiPower)
    }

    private var multiCountStepper: some View {
        Stepper(
            value: Binding(
                get: { controller.multiFlashDraft.count },
                set: { controller.setMultiFlashCount($0) }
            ),
            in: controller.multiFlashCountRange
        ) {
            LabeledContent(
                coordinator.text("multi.count"),
                value: "\(controller.multiFlashDraft.count)"
            )
        }
        .disabled(!controller.canEditMultiFlashSettings)
        .accessibilityIdentifier(EstroboAccessibilityID.multiCount)
    }

    private var multiHertzStepper: some View {
        Stepper(
            value: Binding(
                get: { controller.multiFlashDraft.hertz },
                set: { controller.setMultiFlashHertz($0) }
            ),
            in: MultiFlashSettings.hertzRange
        ) {
            LabeledContent(
                coordinator.text("multi.hertz"),
                value: "\(controller.multiFlashDraft.hertz) Hz"
            )
        }
        .disabled(!controller.canEditMultiFlashSettings)
        .accessibilityIdentifier(EstroboAccessibilityID.multiHertz)
    }

    private var multiLimitSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(
                coordinator.text("multi.maximum"),
                value: "\(controller.multiFlashMaximumCount)"
            )
            LabeledContent(
                coordinator.text("multi.minimum-exposure"),
                value: minimumExposureText
            )
            Label(limitEvidenceText, systemImage: limitEvidenceSymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .accessibilityIdentifier(EstroboAccessibilityID.multiLimit)
    }

    private var globalPowerGroupsText: String {
        let labels = controller.globalPowerGroups.map(\.label).joined(separator: ", ")
        return labels.isEmpty
            ? coordinator.text("global.power.none")
            : formatted("global.power.groups", labels)
    }

    private var minimumExposureText: String {
        String(
            format: coordinator.text("multi.exposure.value"),
            locale: coordinator.locale,
            controller.multiFlashDraft.minimumExposureSeconds
        )
    }

    private var limitEvidenceText: String {
        if controller.hasUnverifiedMultiFlashCountLimit {
            return coordinator.text("multi.limit.unverified")
        }
        if controller.hasConservativeMultiFlashCountLimit {
            return coordinator.text("multi.limit.conservative")
        }
        if controller.hasVerifiedMultiFlashCountLimit {
            return coordinator.text("multi.limit.verified")
        }
        return coordinator.text("multi.limit.generic")
    }

    private var limitEvidenceSymbol: String {
        controller.hasVerifiedMultiFlashCountLimit
            ? "checkmark.seal"
            : "exclamationmark.triangle"
    }

    private func adjustGlobalPower(direction: Int) {
        let outcome = controller.adjustGlobalPower(direction: direction)
        switch outcome {
        case .applied(let steps):
            globalPowerFeedback = formatted("global.power.applied", steps)
        case .limited(let steps, let cause):
            let boundary: String
            switch cause {
            case .visualWindow:
                boundary = coordinator.text("global.power.limit.window")
            case .groups(let groups):
                boundary = groups.map(\.label).joined(separator: ", ")
            }
            globalPowerFeedback = formatted(
                "global.power.limited",
                steps,
                boundary
            )
        case .unavailable:
            globalPowerFeedback = coordinator.text("global.power.unavailable")
        }
    }

    private func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: coordinator.text(key),
            locale: coordinator.locale,
            arguments: arguments
        )
    }
}

private enum GlobalConfirmation: Identifiable {
    case test(isMulti: Bool)
    case multi(enabled: Bool)
    case standby(enabled: Bool)

    var id: String {
        switch self {
        case .test: "test"
        case .multi: "multi"
        case .standby: "standby"
        }
    }
}

private enum TestPresentationResult {
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

private struct TestConfirmationView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    let isMulti: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        isMulti
                            ? coordinator.text("test.confirm.multi")
                            : coordinator.text("test.confirm.single"),
                        systemImage: "eye.trianglebadge.exclamationmark"
                    )
                    .accessibilityIdentifier(EstroboAccessibilityID.testConfirmation)
                    Text(coordinator.text("test.confirm.detail"))
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(coordinator.text("action.cancel"), action: onCancel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier(EstroboAccessibilityID.testCancel)
                    Button(coordinator.text("test.confirm.action"), action: onConfirm)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(.borderedProminent)
                        .tint(EstroboTheme.amber)
                        .foregroundStyle(EstroboTheme.navy)
                        .accessibilityIdentifier(EstroboAccessibilityID.testConfirm)
                }
            }
            .navigationTitle(coordinator.text("test.confirm.title"))
        }
        .presentationDetents([.large])
    }
}

private struct MultiConfirmationView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    let enabled: Bool
    let enteringOrRemainingMultiGroups: [GodoxGroup]
    let movingToOffGroups: [GodoxGroup]
    let restoringToManualGroups: [GodoxGroup]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        enabled
                            ? coordinator.text("multi.confirm.activate")
                            : coordinator.text("multi.confirm.deactivate"),
                        systemImage: "waveform.path"
                    )
                    .accessibilityIdentifier(EstroboAccessibilityID.multiConfirmation)
                    Text(
                        enabled
                            ? coordinator.text("multi.confirm.activate.detail")
                            : coordinator.text("multi.confirm.deactivate.detail")
                    )
                    .foregroundStyle(.secondary)
                    if enabled {
                        LabeledContent(
                            coordinator.text("multi.confirm.enter-or-remain"),
                            value: groupList(enteringOrRemainingMultiGroups)
                        )
                        LabeledContent(
                            coordinator.text("multi.confirm.move-off"),
                            value: groupList(movingToOffGroups)
                        )
                    } else {
                        LabeledContent(
                            coordinator.text("multi.confirm.restore-manual"),
                            value: groupList(restoringToManualGroups)
                        )
                    }
                }
                Section {
                    Button(coordinator.text("action.cancel"), action: onCancel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier(EstroboAccessibilityID.multiCancel)
                    Button(
                        enabled
                            ? coordinator.text("multi.activate")
                            : coordinator.text("multi.deactivate"),
                        action: onConfirm
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(EstroboAccessibilityID.multiConfirm)
                }
            }
            .navigationTitle("Multi")
        }
        .presentationDetents([.large])
    }

    private func groupList(_ groups: [GodoxGroup]) -> String {
        guard !groups.isEmpty else { return coordinator.text("multi.confirm.none") }
        return groups.map(\.label).joined(separator: ", ")
    }
}

private struct StandbyConfirmationView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    let enabled: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        enabled
                            ? coordinator.text("standby.confirm.activate")
                            : coordinator.text("standby.confirm.deactivate"),
                        systemImage: "power"
                    )
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.globalStandbyConfirmation
                    )
                    Text(coordinator.text("standby.confirm.detail"))
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(coordinator.text("action.cancel"), action: onCancel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.globalStandbyCancel
                        )
                    Button(
                        enabled
                            ? coordinator.text("standby.activate")
                            : coordinator.text("standby.deactivate"),
                        action: onConfirm
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.globalStandbyConfirm
                    )
                }
            }
            .navigationTitle(coordinator.text("global.standby"))
        }
        .presentationDetents([.large])
    }
}
