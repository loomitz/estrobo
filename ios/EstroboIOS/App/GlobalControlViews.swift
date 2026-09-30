import SwiftUI
import EstroboCore

enum MultiHertzScale {
    static let values =
        Array(1...20)
        + Array(stride(from: 25, through: 50, by: 5))
        + Array(stride(from: 60, through: 190, by: 10))
        + [199]
}

private enum GlobalActionKind {
    case beep
    case modeling
    case standby
}

/// Content-only global controls that can be placed directly inside an existing
/// `List`. Screen-level recovery, navigation, toolbars, and apply affordances
/// remain the responsibility of the host screen.
struct GlobalControlSections: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController
    let onOpenGroupDetails: (GodoxGroup) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var globalPowerOffsetSteps = 0
    @State private var globalPowerAnchor: [GodoxGroup: ManualPower] = [:]
    @State private var globalPowerInteractiveEditToken:
        GodoxSessionController.InteractiveEditToken?
    @State private var pendingDirectAction: GlobalActionKind?

    var body: some View {
        globalControlSection
    }

    /// Mirrors the effects of `initialMultiScenePlan()` using only the
    /// controller's public presentation state. The controller remains the
    /// authority and revalidates the plan when the direct action is requested.
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

    private var globalControlSection: some View {
        Section {
            if controller.multiFlashGroups.isEmpty {
                globalPowerRow
            }
            globalActionsRow

            if !controller.multiFlashGroups.isEmpty {
                participants
                multiPowerPicker
                multiCountScrubber
                multiHertzScrubber
                multiLimitSummary
            }
        }
    }

    private var globalPowerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(coordinator.text("global.power.slider.title"))
                    .font(.headline)
                    .accessibilityIdentifier(EstroboAccessibilityID.globalScreen)
                Spacer(minLength: 8)
                Text(globalPowerOffsetText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(
                        globalPowerOffsetSteps == 0
                            ? Color.secondary
                            : EstroboTheme.interactiveAccent
                    )
            }

            HStack(spacing: 10) {
                Button {
                    adjustGlobalPower(direction: -1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(
                    globalPowerInteractiveEditToken != nil
                        || !controller.canAdjustGlobalPower(direction: -1)
                )
                .accessibilityLabel(coordinator.text("global.power.decrease"))
                .accessibilityIdentifier(EstroboAccessibilityID.globalPowerDecrease)

                VStack(spacing: 2) {
                    ZStack {
                        SliderRulerTicks(tickCount: 19, majorTickEvery: 3)
                            .offset(y: 8)
                        DeterministicSlider(
                            value: globalPowerSliderBinding,
                            range: -9...9,
                            step: 1,
                            isEnabled: canUseGlobalPowerSlider,
                            accessibilityLabel: coordinator.text(
                                "global.power.slider.accessibility"
                            ),
                            accessibilityValue: globalPowerOffsetText,
                            accessibilityIdentifier: EstroboAccessibilityID.globalPowerSlider,
                            onInteractionBegan: beginGlobalPowerInteraction,
                            onInteractionEnded: finishGlobalPowerInteraction,
                            onInteractionCancelled: cancelGlobalPowerInteraction
                        )
                        .tint(EstroboTheme.interactiveAccent)
                    }
                    .frame(minHeight: 44)

                    HStack {
                        Text("−3")
                        Spacer()
                        Text("0")
                        Spacer()
                        Text("+3")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                }

                Button {
                    adjustGlobalPower(direction: 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(
                    globalPowerInteractiveEditToken != nil
                        || !controller.canAdjustGlobalPower(direction: 1)
                )
                .accessibilityLabel(coordinator.text("global.power.increase"))
                .accessibilityIdentifier(EstroboAccessibilityID.globalPowerIncrease)
            }

            Text(coordinator.text("global.power.slider.reset"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .onChange(of: controller.isSceneActive) { _, isActive in
            if !isActive { cancelGlobalPowerInteraction() }
        }
        .onDisappear(perform: cancelGlobalPowerInteraction)
    }

    private var globalActionsRow: some View {
        LazyVGrid(columns: globalActionColumns, spacing: 8) {
            globalBeepAction
            globalModelingAction
            globalStandbyAction
            globalMultiAction
        }
        .padding(.vertical, 4)
        .onChange(of: controller.isDirectGlobalActionPending) { _, isPending in
            if !isPending {
                pendingDirectAction = nil
            }
        }
    }

    private var globalActionColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 8),
            count: count
        )
    }

    private var globalBeepAction: some View {
        Button {
            performDirectAction(.beep) {
                controller.setGlobalBeep(!controller.globalBeepEnabled)
            }
        } label: {
            compactActionLabel(
                coordinator.text("global.beep"),
                value: onOffText(controller.globalBeepEnabled),
                systemImage: controller.globalBeepEnabled
                    ? "speaker.wave.2.fill"
                    : "speaker.slash",
                isActive: controller.globalBeepEnabled,
                isPending: pendingDirectAction == .beep
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(!controller.canToggleGlobalBeep)
        .accessibilityLabel(coordinator.text("global.beep"))
        .accessibilityValue(onOffText(controller.globalBeepEnabled))
        .accessibilityAddTraits(controller.globalBeepEnabled ? .isSelected : [])
        .accessibilityIdentifier(EstroboAccessibilityID.globalBeep)
        .sensoryFeedback(.selection, trigger: controller.globalBeepEnabled)
    }

    private var globalModelingAction: some View {
        Button {
            performDirectAction(.modeling) {
                controller.setGlobalModelingLightEnabled(
                    !controller.isGlobalModelingLightEnabled
                )
            }
        } label: {
            compactActionLabel(
                coordinator.text("global.modeling"),
                value: onOffText(controller.isGlobalModelingLightEnabled),
                systemImage: controller.isGlobalModelingLightEnabled
                    ? "lightbulb.fill"
                    : "lightbulb.slash",
                isActive: controller.isGlobalModelingLightEnabled,
                isPending: pendingDirectAction == .modeling
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(!controller.canToggleGlobalModelingLight)
        .accessibilityLabel(coordinator.text("global.modeling"))
        .accessibilityValue(onOffText(controller.isGlobalModelingLightEnabled))
        .accessibilityHint(coordinator.text("global.modeling.hint"))
        .accessibilityAddTraits(
            controller.isGlobalModelingLightEnabled ? .isSelected : []
        )
        .accessibilityIdentifier(EstroboAccessibilityID.globalModeling)
        .sensoryFeedback(
            .selection,
            trigger: controller.isGlobalModelingLightEnabled
        )
    }

    private var globalStandbyAction: some View {
        Button {
            performDirectAction(.standby) {
                controller.setGlobalStandby(!controller.isGlobalStandbyEnabled)
            }
        } label: {
            compactActionLabel(
                coordinator.text("global.standby"),
                value: onOffText(controller.isGlobalStandbyEnabled),
                systemImage: "power",
                isActive: controller.isGlobalStandbyEnabled,
                isPending: pendingDirectAction == .standby
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(!controller.canToggleGlobalStandby)
        .accessibilityLabel(coordinator.text("global.standby"))
        .accessibilityValue(onOffText(controller.isGlobalStandbyEnabled))
        .accessibilityHint(coordinator.text("standby.direct.hint"))
        .accessibilityAddTraits(
            controller.isGlobalStandbyEnabled ? .isSelected : []
        )
        .accessibilityIdentifier(EstroboAccessibilityID.globalStandby)
        .sensoryFeedback(.selection, trigger: controller.isGlobalStandbyEnabled)
    }

    private var globalMultiAction: some View {
        Button {
            controller.setGlobalMultiFlashEnabled(
                controller.multiFlashGroups.isEmpty
            )
        } label: {
            compactActionLabel(
                "Multi",
                value: multiStateText,
                systemImage: "waveform.path",
                isActive: !controller.multiFlashGroups.isEmpty,
                isPending: false
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(
            !controller.canSetGlobalMultiFlashEnabled(
                controller.multiFlashGroups.isEmpty
            )
        )
        .accessibilityLabel(
            controller.multiFlashGroups.isEmpty
                ? coordinator.text("multi.activate")
                : coordinator.text("multi.deactivate")
        )
        .accessibilityValue(multiStateText)
        .accessibilityHint(multiDirectEffectSummary)
        .accessibilityAddTraits(
            controller.multiFlashGroups.isEmpty ? [] : .isSelected
        )
        .accessibilityIdentifier(EstroboAccessibilityID.multiToggle)
        .sensoryFeedback(
            .selection,
            trigger: !controller.multiFlashGroups.isEmpty
        )
    }

    private func compactActionLabel(
        _ title: String,
        value: String,
        systemImage: String,
        isActive: Bool,
        isPending: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .frame(width: 20)
                .foregroundStyle(
                    isActive ? EstroboTheme.interactiveAccent : Color.secondary
                )
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                Text(
                    isPending
                        ? coordinator.text("global.action.pending")
                        : value
                )
                .font(.caption.weight(isActive || isPending ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(
                    isActive || isPending
                        ? EstroboTheme.interactiveAccent
                        : Color.secondary
                )
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .tint(EstroboTheme.interactiveAccent)
                    .accessibilityHidden(true)
            } else if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(EstroboTheme.interactiveAccent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(
            isActive
                ? EstroboTheme.interactiveAccent.opacity(0.14)
                : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isActive
                        ? EstroboTheme.interactiveAccent
                        : Color.secondary.opacity(0.24),
                    lineWidth: isActive ? 2 : 1
                )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: isActive
        )
        .contentShape(Rectangle())
    }

    private func performDirectAction(
        _ action: GlobalActionKind,
        operation: () -> Void
    ) {
        pendingDirectAction = action
        operation()
        if !controller.isDirectGlobalActionPending {
            pendingDirectAction = nil
        }
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(coordinator.text("multi.participants"))
                .font(.subheadline.bold())
            ForEach(controller.workingGroups) { group in
                ZStack {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            GroupBadge(
                                group: group,
                                accessibilityName: coordinator.text(
                                    "group.accessibility",
                                    group.label
                                )
                            )
                            Text("\(coordinator.text("group.title")) \(group.label)")
                            Spacer(minLength: 8)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .groupDetailLongPressFeedback {
                            onOpenGroupDetails(group)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            coordinator.text("group.accessibility", group.label)
                        )
                        .accessibilityValue(
                            controller.isGlobalStandbyEnabled
                                ? coordinator.text("standby.overlay.title")
                                : ""
                        )
                        .accessibilityHint(
                            coordinator.text("group.detail.long-press.hint")
                        )
                        .accessibilityAction(
                            named: Text(coordinator.text("group.detail.open"))
                        ) {
                            onOpenGroupDetails(group)
                        }
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.groupRow(group.label)
                        )

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
                        ) { EmptyView() }
                        .labelsHidden()
                        .disabled(
                            !controller.canSetMultiFlashParticipation(
                                group,
                                enabled: !controller.multiFlashGroups.contains(group)
                            )
                        )
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.multiParticipant(group.label)
                        )
                        .accessibilityLabel(
                            coordinator.text("group.accessibility", group.label)
                        )
                    }
                    .opacity(controller.isGlobalStandbyEnabled ? 0.22 : 1)

                    if controller.isGlobalStandbyEnabled {
                        StandbyGroupOverlay(
                            group: group,
                            coordinator: coordinator
                        )
                    }
                }
                .frame(minHeight: 60)
            }
        }
    }

    private var multiPowerPicker: some View {
        MultiPowerScrubber(
            coordinator: coordinator,
            controller: controller
        )
    }

    private var multiCountScrubber: some View {
        MultiNumericScrubber(
            title: coordinator.text("multi.count"),
            value: controller.multiFlashDraft.count,
            values: Array(controller.multiFlashCountRange),
            displayValue: { "\($0)×" },
            accessibilityValue: {
                coordinator.text("multi.count.value", $0)
            },
            accessibilityHint: coordinator.text("multi.scrubber.hint"),
            accessibilityIdentifier: EstroboAccessibilityID.multiCount,
            isEnabled: controller.canEditMultiFlashSettings,
            controller: controller,
            setValue: controller.setMultiFlashCount
        )
    }

    private var multiHertzScrubber: some View {
        MultiNumericScrubber(
            title: coordinator.text("multi.hertz"),
            value: controller.multiFlashDraft.hertz,
            values: MultiHertzScale.values,
            displayValue: { "\($0) Hz" },
            accessibilityValue: {
                coordinator.text("multi.hertz.value", $0)
            },
            accessibilityHint: coordinator.text("multi.scrubber.hint"),
            accessibilityIdentifier: EstroboAccessibilityID.multiHertz,
            isEnabled: controller.canEditMultiFlashSettings,
            controller: controller,
            setValue: controller.setMultiFlashHertz
        )
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

    private var multiStateText: String {
        controller.multiFlashGroups.isEmpty
            ? coordinator.text("multi.inactive")
            : coordinator.text("multi.active")
    }

    private var multiDirectEffectSummary: String {
        if controller.multiFlashGroups.isEmpty {
            return formatted(
                "multi.direct.activate.summary",
                groupList(multiGroupsEnteringOrRemaining),
                groupList(multiGroupsMovingToOff)
            )
        }
        return formatted(
            "multi.direct.deactivate.summary",
            groupList(controller.workingGroups)
        )
    }

    private func groupList(_ groups: [GodoxGroup]) -> String {
        guard !groups.isEmpty else { return coordinator.text("multi.none") }
        return groups.map(\.label).joined(separator: ", ")
    }

    private func onOffText(_ enabled: Bool) -> String {
        enabled ? coordinator.text("value.on") : coordinator.text("value.off")
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
        _ = controller.adjustGlobalPower(direction: direction)
    }

    private var canUseGlobalPowerSlider: Bool {
        !controller.makeGlobalPowerAnchor().isEmpty
    }

    private var globalPowerSliderBinding: Binding<Double> {
        Binding(
            get: { Double(globalPowerOffsetSteps) },
            set: { proposedValue in
                globalPowerOffsetSteps = min(
                    9,
                    max(-9, Int(proposedValue.rounded()))
                )
            }
        )
    }

    private var globalPowerOffsetText: String {
        guard globalPowerOffsetSteps != 0 else { return "0.0 EV" }
        return String(
            format: "%+.1f EV",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(globalPowerOffsetSteps) / 3
        )
    }

    private func beginGlobalPowerInteraction() {
        let anchor = controller.makeGlobalPowerAnchor()
        guard globalPowerInteractiveEditToken == nil, !anchor.isEmpty else {
            return
        }
        globalPowerOffsetSteps = 0
        globalPowerAnchor = anchor
        globalPowerInteractiveEditToken = controller.beginInteractiveEdit()
    }

    private func finishGlobalPowerInteraction() {
        let offsetSteps = globalPowerOffsetSteps
        let anchor = globalPowerAnchor
        withAnimation(.snappy(duration: 0.2)) {
            globalPowerOffsetSteps = 0
        }
        globalPowerAnchor = [:]
        guard let globalPowerInteractiveEditToken else { return }
        self.globalPowerInteractiveEditToken = nil
        guard controller.isSceneActive, !anchor.isEmpty else {
            controller.cancelInteractiveEdit(globalPowerInteractiveEditToken)
            return
        }
        if offsetSteps != 0 {
            _ = controller.adjustGlobalPower(
                offsetSteps: offsetSteps,
                from: anchor
            )
        }
        controller.endInteractiveEdit(globalPowerInteractiveEditToken)
    }

    private func cancelGlobalPowerInteraction() {
        if let globalPowerInteractiveEditToken {
            self.globalPowerInteractiveEditToken = nil
            controller.cancelInteractiveEdit(globalPowerInteractiveEditToken)
        }
        globalPowerOffsetSteps = 0
        globalPowerAnchor = [:]
    }

    private func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: coordinator.text(key),
            locale: coordinator.locale,
            arguments: arguments
        )
    }
}

struct GroupDetailLongPressFeedbackModifier: ViewModifier {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressing = false
    @State private var feedbackTrigger = false

    func body(content: Content) -> some View {
        content
            .background(
                isPressing
                    ? EstroboTheme.interactiveAccent.opacity(0.14)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if isPressing {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EstroboTheme.interactiveAccent, lineWidth: 1.5)
                }
            }
            .scaleEffect(isPressing && !reduceMotion ? 0.985 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: isPressing
            )
            .onLongPressGesture(
                minimumDuration: 0.55,
                maximumDistance: 18,
                perform: {
                    isPressing = false
                    feedbackTrigger.toggle()
                    action()
                },
                onPressingChanged: { pressing in
                    isPressing = pressing
                }
            )
            .sensoryFeedback(
                .impact(weight: .medium),
                trigger: feedbackTrigger
            )
    }
}

extension View {
    func groupDetailLongPressFeedback(
        action: @escaping () -> Void
    ) -> some View {
        modifier(GroupDetailLongPressFeedbackModifier(action: action))
    }
}

struct StandbyGroupOverlay: View {
    let group: GodoxGroup
    @ObservedObject var coordinator: AppSessionCoordinator

    var body: some View {
        HStack(spacing: 12) {
            GroupBadge(
                group: group,
                accessibilityName: coordinator.text(
                    "group.accessibility",
                    group.label
                )
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("\(coordinator.text("group.title")) \(group.label)")
                    .font(.subheadline.bold())
                Label(
                    coordinator.text("standby.overlay.title"),
                    systemImage: "power"
                )
                .font(.caption.bold())
                .foregroundStyle(EstroboTheme.interactiveAccent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EstroboTheme.interactiveAccent.opacity(0.72), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            coordinator.text("standby.overlay.accessibility", group.label)
        )
        .accessibilityIdentifier(
            EstroboAccessibilityID.groupStandbyOverlay(group.label)
        )
        .transition(.opacity)
    }
}

/// Multi power uses the same final-value-only interaction contract as the
/// numeric scrubbers, while exposing the radio's real discrete power scale.
private struct MultiPowerScrubber: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    @State private var interactiveEditToken:
        GodoxSessionController.InteractiveEditToken?
    @State private var livePowerIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(coordinator.text("multi.power"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Text(displayedPower.label)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .accessibilityHidden(true)

            ZStack {
                SliderRulerTicks(tickCount: 17, majorTickEvery: 4)
                    .offset(y: 8)
                DeterministicSlider(
                    value: powerIndexBinding,
                    range: 0...maximumSliderIndex,
                    step: 1,
                    isEnabled: canInteract,
                    accessibilityLabel: coordinator.text("multi.power"),
                    accessibilityValue: displayedPower.label,
                    accessibilityIdentifier: EstroboAccessibilityID.multiPower,
                    onInteractionBegan: beginInteractiveEdit,
                    onInteractionEnded: finishInteractiveEdit,
                    onInteractionCancelled: cancelInteractiveEdit
                )
                .tint(EstroboTheme.interactiveAccent)
            }
            .frame(minHeight: 44)

            HStack {
                Text(allowedPowers.first?.label ?? "—")
                Spacer()
                Text(middlePowerLabel)
                Spacer()
                Text(allowedPowers.last?.label ?? "—")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .onChange(of: controller.canEditMultiFlashSettings) { _, enabled in
            if !enabled { cancelInteractiveEdit() }
        }
        .onDisappear(perform: cancelInteractiveEdit)
    }

    private var allowedPowers: [ManualPower] {
        controller.allowedMultiFlashPowers
    }

    private var middlePowerLabel: String {
        guard !allowedPowers.isEmpty else { return "—" }
        return allowedPowers[allowedPowers.count / 2].label
    }

    private var canInteract: Bool {
        controller.canEditMultiFlashSettings && allowedPowers.count >= 2
    }

    private var displayedPowerIndex: Int {
        let persisted = allowedPowers.firstIndex(of: controller.multiFlashDraft.power) ?? 0
        return min(max(livePowerIndex ?? persisted, 0), max(0, allowedPowers.count - 1))
    }

    private var displayedPower: ManualPower {
        guard allowedPowers.indices.contains(displayedPowerIndex) else {
            return controller.multiFlashDraft.power
        }
        return allowedPowers[displayedPowerIndex]
    }

    private var maximumSliderIndex: Double {
        Double(max(1, allowedPowers.count - 1))
    }

    private var powerIndexBinding: Binding<Double> {
        Binding(
            get: { Double(displayedPowerIndex) },
            set: { proposedIndex in
                let nextIndex = min(
                    max(Int(proposedIndex.rounded()), 0),
                    max(0, allowedPowers.count - 1)
                )
                guard allowedPowers.indices.contains(nextIndex) else { return }
                livePowerIndex = nextIndex
            }
        )
    }

    private func beginInteractiveEdit() {
        guard interactiveEditToken == nil, canInteract else { return }
        livePowerIndex = displayedPowerIndex
        interactiveEditToken = controller.beginInteractiveEdit()
    }

    private func finishInteractiveEdit() {
        guard let interactiveEditToken else { return }
        self.interactiveEditToken = nil
        guard controller.isSceneActive,
              controller.canEditMultiFlashSettings,
              allowedPowers.indices.contains(displayedPowerIndex) else {
            controller.cancelInteractiveEdit(interactiveEditToken)
            livePowerIndex = nil
            return
        }
        controller.setMultiFlashPower(allowedPowers[displayedPowerIndex])
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

/// A fast integer scrubber for Multi. The controller's interactive-edit token
/// keeps every intermediate tick local: persistence and automatic delivery are
/// armed only when the drag ends, while cancellation remains fail-closed.
private struct MultiNumericScrubber: View {
    let title: String
    let value: Int
    let values: [Int]
    let displayValue: (Int) -> String
    let accessibilityValue: (Int) -> String
    let accessibilityHint: String
    let accessibilityIdentifier: String
    let isEnabled: Bool
    @ObservedObject var controller: GodoxSessionController
    let setValue: (Int) -> Void

    @State private var interactiveEditToken:
        GodoxSessionController.InteractiveEditToken?
    @State private var liveIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Text(displayValue(displayedValue))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .accessibilityHidden(true)

            ZStack {
                SliderRulerTicks(tickCount: 17, majorTickEvery: 4)
                    .offset(y: 8)
                DeterministicSlider(
                    value: valueBinding,
                    range: 0...maximumIndex,
                    step: 1,
                    isEnabled: canInteract,
                    accessibilityLabel: title,
                    accessibilityValue: accessibilityValue(displayedValue),
                    accessibilityIdentifier: accessibilityIdentifier,
                    onInteractionBegan: beginInteractiveEdit,
                    onInteractionEnded: finishInteractiveEdit,
                    onInteractionCancelled: cancelInteractiveEdit
                )
                .tint(EstroboTheme.interactiveAccent)
                .disabled(!canInteract)
                .accessibilityHint(accessibilityHint)
            }
            .frame(minHeight: 44)

            HStack {
                Text("\(values.first ?? value)")
                Spacer()
                Text("\(values.last ?? value)")
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { cancelInteractiveEdit() }
        }
        .onDisappear(perform: cancelInteractiveEdit)
    }

    private var canInteract: Bool {
        isEnabled && values.count >= 2
    }

    private var displayedValue: Int {
        guard let liveIndex else {
            // Persisted workspaces created by older clients may contain a
            // value outside this editor's discrete choices. Keep showing the
            // real draft until the user deliberately edits this control.
            return value
        }
        guard values.indices.contains(liveIndex) else { return value }
        return values[liveIndex]
    }

    private var displayedIndex: Int {
        if let liveIndex {
            return boundedIndex(liveIndex)
        }
        return values.firstIndex(of: value) ?? nearestIndex(to: value)
    }

    private var maximumIndex: Double {
        Double(max(1, values.count - 1))
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { Double(displayedIndex) },
            set: { proposedValue in
                liveIndex = boundedIndex(Int(proposedValue.rounded()))
            }
        )
    }

    private func boundedIndex(_ proposedIndex: Int) -> Int {
        min(max(proposedIndex, 0), max(0, values.count - 1))
    }

    private func nearestIndex(to proposedValue: Int) -> Int {
        values.enumerated().min { lhs, rhs in
            let lhsDistance = abs(lhs.element - proposedValue)
            let rhsDistance = abs(rhs.element - proposedValue)
            if lhsDistance == rhsDistance {
                return lhs.element < rhs.element
            }
            return lhsDistance < rhsDistance
        }?.offset ?? 0
    }

    private func beginInteractiveEdit() {
        guard interactiveEditToken == nil, canInteract else { return }
        liveIndex = displayedIndex
        interactiveEditToken = controller.beginInteractiveEdit()
    }

    private func finishInteractiveEdit() {
        guard let interactiveEditToken else { return }
        if liveIndex != nil {
            setValue(displayedValue)
        }
        self.interactiveEditToken = nil
        controller.endInteractiveEdit(interactiveEditToken)
        liveIndex = nil
    }

    private func cancelInteractiveEdit() {
        if let interactiveEditToken {
            self.interactiveEditToken = nil
            controller.cancelInteractiveEdit(interactiveEditToken)
        }
        liveIndex = nil
    }
}
