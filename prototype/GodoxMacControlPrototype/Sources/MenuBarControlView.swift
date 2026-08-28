import AppKit
import SwiftUI

/// Compact, session-aware controls for photographers who keep Capture One in
/// the foreground. This view intentionally shares the app's controller: it is
/// another presentation of the same drafts and safety gates, never a second
/// Bluetooth session or a second source of truth.
@MainActor
struct MenuBarControlView: View {
    @ObservedObject var controller: GodoxSessionController

    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.openWindow) private var openWindow

    private let panelWidth: CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(PrototypePalette.divider)
                .frame(height: 1)

            if let blockingMessage {
                blockingBanner(blockingMessage)
            }

            groupContent

            Rectangle()
                .fill(PrototypePalette.divider)
                .frame(height: 1)

            footer
        }
        .frame(width: panelWidth)
        .background(PrototypePalette.windowBackground)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            if controller.phase.isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }

            Text(connectionLabel)
                .font(controller.isSynchronizingValues ? .caption : .callout.weight(.semibold))
                .foregroundStyle(
                    controller.isSynchronizingValues
                        ? PrototypePalette.secondaryText
                        : PrototypePalette.primaryText
                )
                .lineLimit(1)
        }
        .padding(.horizontal, MenuBarLayout.rowHorizontalPadding)
        .frame(height: MenuBarLayout.headerHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(languageStore.language.localizedMessage(controller.statusTitle))
        .help(languageStore.language.localizedMessage(controller.statusTitle))
    }

    @ViewBuilder
    private var groupContent: some View {
        if displayedGroups.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(PrototypePalette.secondaryText)

                Text(languageStore.language.localized("menubar.noGroups.title"))
                    .font(.headline)
                    .foregroundStyle(PrototypePalette.primaryText)

                Text(languageStore.language.localized("menubar.noGroups.detail"))
                    .font(.callout)
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 150)
            .accessibilityElement(children: .combine)
        } else {
            if MenuBarLayout.requiresScrolling(groupCount: displayedGroups.count) {
                ScrollView(.vertical) {
                    groupRows
                }
                .scrollIndicators(.visible)
                .frame(height: groupListHeight)
            } else {
                groupRows
            }
        }
    }

    private var groupRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayedGroups.enumerated()), id: \.element) { index, group in
                MenuBarPowerRow(controller: controller, group: group)

                if index < displayedGroups.count - 1 {
                    Rectangle()
                        .fill(PrototypePalette.divider)
                        .frame(height: 1)
                        .padding(.horizontal, MenuBarLayout.rowHorizontalPadding)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 9) {
            if controller.pendingCount > 0 {
                pendingControls
            }

            HStack(spacing: 10) {
                Button(action: showMainWindow) {
                    Label(
                        languageStore.language.localized("menubar.openApp"),
                        systemImage: "macwindow"
                    )
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderless)
                .menuBarAccessibleButton(MenuBarAccessibilityDescriptors.openApp(
                    language: languageStore.language
                ))

                Spacer()

                if controller.isSimulation {
                    Text(languageStore.language.localized("mock.badge"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PrototypePalette.accent)
                }

                Button {
                    controller.sendTestFlash()
                } label: {
                    HStack(spacing: 5) {
                        if controller.isTestPending {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "bolt.fill")
                        }

                        Text(languageStore.language.localized("menubar.test"))
                    }
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 56)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(PrototypePalette.accent)
                .disabled(!controller.canSendTest)
                .help(testHelp)
                .menuBarAccessibleButton(MenuBarAccessibilityDescriptors.test(
                    isPending: controller.isTestPending,
                    isEnabled: controller.canSendTest,
                    hint: testHelp,
                    language: languageStore.language
                ))

                Rectangle()
                    .fill(PrototypePalette.divider)
                    .frame(width: 1, height: 24)
                    .accessibilityHidden(true)

                Button(action: requestTermination) {
                    Label(
                        languageStore.language.localized("menubar.quitShort"),
                        systemImage: "xmark.circle"
                    )
                    .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help(languageStore.language.localized("menubar.quit"))
                .menuBarAccessibleButton(MenuBarAccessibilityDescriptors.quit(
                    language: languageStore.language
                ))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PrototypePalette.footerSurface)
    }

    private var pendingControls: some View {
        HStack(spacing: 8) {
            if isGlobalUpdateInProgress {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(PrototypePalette.warning)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }

            Text(pendingLabel)
                .font(.caption)
                .foregroundStyle(PrototypePalette.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if canManagePendingChangesFromMenuBar {
                Button {
                    controller.discardPendingChanges()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(
                    !controller.canDiscardPendingChanges ||
                        controller.phase == .applying ||
                        controller.isInteractiveEditActive
                )
                .help(languageStore.language.localized("Descartar"))
                .menuBarAccessibleButton(MenuBarAccessibilityDescriptor(
                    label: languageStore.language.localized("Descartar"),
                    isEnabled: controller.canDiscardPendingChanges &&
                        controller.phase != .applying &&
                        !controller.isInteractiveEditActive
                ))

                if controller.changeDeliveryMode == .manual {
                    Button {
                        controller.applyPendingChanges()
                    } label: {
                        Label(
                            languageStore.language.localized("menubar.apply"),
                            systemImage: "arrow.right"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PrototypePalette.accent)
                    .foregroundStyle(PrototypePalette.accentText)
                    .controlSize(.small)
                    .disabled(!controller.canApply)
                    .help(languageStore.language.localizedMessage(
                        controller.applyBlockReason ?? "menubar.apply"
                    ))
                    .menuBarAccessibleButton(MenuBarAccessibilityDescriptor(
                        label: languageStore.language.localized("menubar.apply"),
                        hint: languageStore.language.localizedMessage(
                            controller.applyBlockReason ?? "menubar.apply"
                        ),
                        isEnabled: controller.canApply
                    ))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var displayedGroups: [GodoxGroup] {
        controller.visibleGroups.filter { controller.workingGroups.contains($0) }
    }

    private var groupListHeight: CGFloat {
        let rowCount = min(displayedGroups.count, 5)
        return CGFloat(rowCount) * MenuBarLayout.groupRowHeight + CGFloat(max(rowCount - 1, 0))
    }

    private var connectionLabel: String {
        switch controller.phase {
        case .ready, .applying:
            languageStore.language.localized("menubar.connected")
        default:
            languageStore.language.localizedMessage(controller.phase.title)
        }
    }

    private var connectionColor: Color {
        switch controller.phase {
        case .ready:
            PrototypePalette.success
        case .applying, .scanning, .connecting, .discovering, .authenticating, .synchronizing,
             .disconnecting:
            PrototypePalette.warning
        case .failed, .unavailable:
            PrototypePalette.error
        case .idle:
            PrototypePalette.muted
        }
    }

    private var blockingMessage: String? {
        if let recoveryBlockReason = controller.recoveryBlockReason {
            return languageStore.language.localizedMessage(recoveryBlockReason)
        }
        if controller.isGlobalStandbyEnabled {
            return languageStore.language.localized("menubar.standby")
        }
        return nil
    }

    private var pendingLabel: String {
        if isGlobalUpdateInProgress {
            return languageStore.language.localized("menubar.updatingSettings")
        }
        if !canManagePendingChangesFromMenuBar {
            return languageStore.language.localized("menubar.reviewPending")
        }
        if controller.changeDeliveryMode == .automatic {
            return languageStore.language.localized("menubar.automaticPending")
        }
        return MenuBarStrings.pendingChanges(
            controller.pendingCount,
            language: languageStore.language
        )
    }

    private var isGlobalUpdateInProgress: Bool {
        controller.phase == .applying || controller.isAutomaticApplyScheduled
    }

    private var testHelp: String {
        if controller.isSimulation {
            return languageStore.language.localized("mock.testHelp")
        }
        if !controller.multiFlashGroups.isEmpty, controller.testBlockReason == nil {
            return languageStore.language.localized(
                "Ejecuta la secuencia Multi aplicada en los grupos activos; Bluetooth no confirma cuántos destellos ocurrieron"
            )
        }
        if let testBlockReason = controller.testBlockReason {
            return languageStore.language.localizedMessage(testBlockReason)
        }
        return languageStore.language.localized("menubar.testHelp")
    }

    /// Applying from a compact surface is safe only when every pending field is
    /// visible here. Advanced, hidden, Multi, or recovery work must be reviewed
    /// in the full workspace before it can be sent or discarded.
    private var canManagePendingChangesFromMenuBar: Bool {
        MenuBarPendingPolicy.canManage(
            displayedGroups: displayedGroups,
            pendingGroups: controller.pendingGroups,
            pendingFields: Dictionary(uniqueKeysWithValues: controller.pendingGroups.map {
                ($0, controller.groupDraft($0).pendingFields)
            }),
            groupStates: Dictionary(uniqueKeysWithValues: controller.pendingGroups.map {
                ($0, controller.groupDraft($0))
            }),
            hasPendingMultiFlashChange: controller.hasPendingMultiFlashChange,
            hasPendingRestoration: !controller.restorationPoints.isEmpty
        )
    }

    private func blockingBanner(_ message: String) -> some View {
        Label(message, systemImage: "lock.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(PrototypePalette.warning)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(PrototypePalette.warning.opacity(0.09))
            .accessibilityElement(children: .combine)
    }

    private func showMainWindow() {
        if let existingWindow = NSApplication.shared.windows.first(where: {
            !($0 is NSPanel) && $0.title.lowercased() == "estrobo"
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func requestTermination() {
        if controller.terminationBlockReason != nil {
            showMainWindow()
        }
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
struct MenuBarStatusLabel: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let mark = Self.templateMark {
                    Image(nsImage: mark)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "bolt.circle")
                }
            }
            .frame(width: 17, height: 17)

            if controller.pendingCount > 0 {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: -1)
            }
        }
        .frame(width: 19, height: 18)
        .accessibilityLabel(Text(verbatim: "estrobo"))
        .accessibilityValue(statusAccessibilityValue)
    }

    private static let templateMark: NSImage? = {
        guard let source = EstroboBrandAssets.menuBarMarkImage,
              let image = source.copy() as? NSImage else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    private var statusAccessibilityValue: String {
        let status = languageStore.language.localizedMessage(controller.statusTitle)
        guard controller.pendingCount > 0 else { return status }
        return status + ". " + MenuBarStrings.pendingChanges(
            controller.pendingCount,
            language: languageStore.language
        )
    }
}

@MainActor
private struct MenuBarPowerRow: View {
    @ObservedObject var controller: GodoxSessionController
    let group: GodoxGroup

    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        let state = controller.groupDraft(group)
        let allowedPowers = controller.allowedPowers(for: group)
        let canEdit = controller.canEdit(group)
        let canToggle = MenuBarPendingPolicy.canToggleRadioEnabled(
            controllerAllowsToggle: controller.canToggleRadioEnabled(group),
            hasActiveMultiFlashScene: !controller.multiFlashGroups.isEmpty
        )
        let isOn = state.draft.isEnabledOnRadio
        let currentIndex = allowedPowers.firstIndex(of: state.draft.power)
        let canDecrease = canEdit && currentIndex.map { $0 > 0 } == true
        let canIncrease = canEdit && currentIndex.map { $0 < allowedPowers.count - 1 } == true
        let groupAccessibility = MenuBarAccessibilityDescriptors.groupToggle(
            group: group,
            isOn: isOn,
            isEnabled: canToggle,
            disabledHint: toggleDisabledReason(),
            language: languageStore.language
        )
        let decreaseAccessibility = MenuBarAccessibilityDescriptors.step(
            group: group,
            direction: .decrement,
            power: state.draft.power,
            isEnabled: canDecrease,
            hint: stepHint(
                enabled: canDecrease,
                state: state,
                limitKey: "menubar.minimumPower"
            ),
            language: languageStore.language
        )
        let increaseAccessibility = MenuBarAccessibilityDescriptors.step(
            group: group,
            direction: .increment,
            power: state.draft.power,
            isEnabled: canIncrease,
            hint: stepHint(
                enabled: canIncrease,
                state: state,
                limitKey: "menubar.maximumPower"
            ),
            language: languageStore.language
        )
        let powerAccessibility = MenuBarAccessibilityDescriptors.power(
            group: group,
            value: accessibilityValue(state: state, canEdit: canEdit),
            hint: canEdit
                ? languageStore.language.localized("menubar.choosePower")
                : disabledReason(state: state),
            isEnabled: canEdit && !allowedPowers.isEmpty,
            language: languageStore.language
        )

        HStack(spacing: 10) {
            MenuBarGroupControl(
                group: group,
                isOn: isOn,
                accessibility: groupAccessibility
            ) {
                controller.setDraftRadioEnabled(group, enabled: !isOn)
            }

            ZStack {
                HStack(spacing: 0) {
                    MenuBarStepButton(
                        systemImage: "minus",
                        accessibility: decreaseAccessibility
                    ) {
                        controller.adjust(group, direction: -1)
                    }

                    Spacer(minLength: MenuBarLayout.minimumReadoutClearance)

                    MenuBarStepButton(
                        systemImage: "plus",
                        accessibility: increaseAccessibility
                    ) {
                        controller.adjust(group, direction: 1)
                    }
                }

                VStack(spacing: 3) {
                    Menu {
                        ForEach(allowedPowers) { power in
                            Button {
                                controller.setDraftPower(group, power: power)
                            } label: {
                                if power == state.draft.power {
                                    Label(power.label, systemImage: "checkmark")
                                } else {
                                    Text(power.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(state.draft.power.label)
                                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                                .monospacedDigit()

                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .frame(width: MenuBarLayout.powerReadoutWidth, alignment: .center)
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .disabled(!powerAccessibility.isEnabled)
                    .foregroundStyle(
                        canEdit ? PrototypePalette.primaryText : PrototypePalette.muted
                    )
                    .accessibilityLabel(Text(verbatim: powerAccessibility.label))
                    .accessibilityValue(Text(verbatim: powerAccessibility.value))
                    .accessibilityHint(Text(verbatim: powerAccessibility.hint))
                    .accessibilityAdjustableAction { direction in
                        MenuBarAccessibilityActions.adjustPower(
                            direction,
                            controller: controller,
                            group: group,
                            enabled: canEdit
                        )
                    }
                    .help(languageStore.language.localized("menubar.choosePower"))

                    Text(verbatim: state.draft.operatingMode.label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PrototypePalette.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(width: MenuBarLayout.powerReadoutWidth, alignment: .center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, MenuBarLayout.rowHorizontalPadding)
        .frame(height: MenuBarLayout.groupRowHeight)
        .background(PrototypePalette.windowBackground)
    }

    private func disabledReason(state: GroupDraft) -> String {
        if controller.phase != .ready {
            return languageStore.language.localized("menubar.connectToEdit")
        }
        if state.draft.operatingMode != .manual {
            return languageStore.language.localizedFormat(
                "menubar.manualOnly",
                state.draft.operatingMode.label
            )
        }
        return languageStore.language.localized("menubar.openForDetails")
    }

    private func toggleDisabledReason() -> String {
        if controller.phase != .ready {
            return languageStore.language.localized("menubar.connectToEdit")
        }
        if controller.isGlobalStandbyEnabled {
            return languageStore.language.localized("menubar.standby")
        }
        return languageStore.language.localized("menubar.openForDetails")
    }

    private func accessibilityValue(state: GroupDraft, canEdit: Bool) -> String {
        var components = [state.draft.operatingMode.label, state.draft.power.label]
        if !canEdit {
            components.append(languageStore.language.localized("menubar.locked"))
        }
        return components.joined(separator: ", ")
    }

    private func stepHint(
        enabled: Bool,
        state: GroupDraft,
        limitKey: String
    ) -> String {
        guard !enabled else { return "" }
        guard controller.canEdit(group) else {
            return disabledReason(state: state)
        }
        return languageStore.language.localized(limitKey)
    }
}

private struct MenuBarGroupControl: View {
    let group: GodoxGroup
    let isOn: Bool
    let accessibility: MenuBarAccessibilityDescriptor
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            MenuBarGroupBadge(
                group: group,
                isOn: isOn,
                isHovering: isHovering && accessibility.isEnabled
            )
        }
        .buttonStyle(.plain)
        .help(accessibility.isEnabled ? accessibility.label : accessibility.hint)
        .menuBarAccessibleButton(accessibility)
        .onHover { isHovering = $0 }
        .frame(
            width: MenuBarLayout.groupControlSize,
            height: MenuBarLayout.groupControlSize
        )
    }
}

private struct MenuBarGroupBadge: View {
    let group: GodoxGroup
    let isOn: Bool
    let isHovering: Bool

    var body: some View {
        let identity = group.visualIdentity

        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    Color(estroboRGB: identity.fillRGB)
                        .opacity(isOn ? 1 : 0.28)
                )

            Text(group.label)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(badgeForeground(identity: identity))
                .offset(x: -2, y: -2)
        }
        .frame(
            width: MenuBarLayout.groupControlSize,
            height: MenuBarLayout.groupControlSize
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(badgeBorder, lineWidth: isHovering ? 1.5 : 1)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "power")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(badgeForeground(identity: identity))
                .padding(5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private func badgeForeground(identity: GroupVisualIdentity) -> Color {
        guard isOn else { return PrototypePalette.secondaryText }
        return Color(estroboRGB: identity.foregroundRGB)
    }

    private var badgeBorder: Color {
        if isHovering {
            return PrototypePalette.primaryText.opacity(0.62)
        }
        return PrototypePalette.primaryText.opacity(isOn ? 0.18 : 0.12)
    }
}

private struct MenuBarStepButton: View {
    let systemImage: String
    let accessibility: MenuBarAccessibilityDescriptor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(MenuBarStepButtonStyle())
        .menuBarAccessibleButton(accessibility)
        .help(accessibility.hint)
    }
}

private struct MenuBarStepButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                isEnabled ? PrototypePalette.primaryText : PrototypePalette.muted
            )
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isEnabled
                            ? PrototypePalette.surfaceRaised
                            : PrototypePalette.surface
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(PrototypePalette.divider, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct MenuBarAccessibilityDescriptor: Equatable {
    let label: String
    let value: String
    let hint: String
    let isEnabled: Bool

    init(
        label: String,
        value: String = "",
        hint: String = "",
        isEnabled: Bool = true
    ) {
        self.label = label
        self.value = value
        self.hint = hint
        self.isEnabled = isEnabled
    }
}

enum MenuBarAccessibilityDescriptors {
    static func groupToggle(
        group: GodoxGroup,
        isOn: Bool,
        isEnabled: Bool,
        disabledHint: String,
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> MenuBarAccessibilityDescriptor {
        MenuBarAccessibilityDescriptor(
            label: language.localizedFormat(
                isOn ? "menubar.turnOffGroup" : "menubar.turnOnGroup",
                group.label,
                bundle: bundle
            ),
            value: language.localizedString(
                isOn ? "menubar.groupOn" : "menubar.groupOff",
                bundle: bundle
            ),
            hint: isEnabled
                ? language.localizedString("menubar.togglePendingHint", bundle: bundle)
                : disabledHint,
            isEnabled: isEnabled
        )
    }

    static func step(
        group: GodoxGroup,
        direction: AccessibilityAdjustmentDirection,
        power: ManualPower,
        isEnabled: Bool,
        hint: String,
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> MenuBarAccessibilityDescriptor {
        let key: String
        switch direction {
        case .decrement:
            key = "menubar.decreaseGroup"
        case .increment:
            key = "menubar.increaseGroup"
        @unknown default:
            key = "menubar.powerGroup"
        }
        return MenuBarAccessibilityDescriptor(
            label: language.localizedFormat(key, group.label, bundle: bundle),
            value: power.label,
            hint: hint,
            isEnabled: isEnabled
        )
    }

    static func power(
        group: GodoxGroup,
        value: String,
        hint: String,
        isEnabled: Bool,
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> MenuBarAccessibilityDescriptor {
        MenuBarAccessibilityDescriptor(
            label: language.localizedFormat(
                "menubar.powerGroup",
                group.label,
                bundle: bundle
            ),
            value: value,
            hint: hint,
            isEnabled: isEnabled
        )
    }

    static func openApp(
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> MenuBarAccessibilityDescriptor {
        MenuBarAccessibilityDescriptor(
            label: language.localizedString("menubar.openApp", bundle: bundle)
        )
    }

    static func test(
        isPending: Bool,
        isEnabled: Bool,
        hint: String,
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> MenuBarAccessibilityDescriptor {
        MenuBarAccessibilityDescriptor(
            label: language.localizedString("menubar.testAccessibility", bundle: bundle),
            value: isPending
                ? language.localizedString("menubar.testSending", bundle: bundle)
                : "",
            hint: hint,
            isEnabled: isEnabled
        )
    }

    static func quit(
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> MenuBarAccessibilityDescriptor {
        MenuBarAccessibilityDescriptor(
            label: language.localizedString("menubar.quit", bundle: bundle)
        )
    }
}

private struct MenuBarAccessibleButtonModifier: ViewModifier {
    let descriptor: MenuBarAccessibilityDescriptor

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(verbatim: descriptor.label))
            .accessibilityValue(Text(verbatim: descriptor.value))
            .accessibilityHint(Text(verbatim: descriptor.hint))
            .disabled(!descriptor.isEnabled)
    }
}

private extension View {
    func menuBarAccessibleButton(
        _ descriptor: MenuBarAccessibilityDescriptor
    ) -> some View {
        modifier(MenuBarAccessibleButtonModifier(descriptor: descriptor))
    }
}

enum MenuBarLayout {
    static let rowHorizontalPadding: CGFloat = 14
    static let headerHeight: CGFloat = 42
    static let groupRowHeight: CGFloat = 72
    static let groupControlSize: CGFloat = 44
    static let powerReadoutWidth: CGFloat = 148
    static let minimumReadoutClearance: CGFloat = 148

    static func requiresScrolling(groupCount: Int) -> Bool {
        groupCount > 5
    }
}

@MainActor
enum MenuBarAccessibilityActions {
    static func adjustPower(
        _ direction: AccessibilityAdjustmentDirection,
        controller: GodoxSessionController,
        group: GodoxGroup,
        enabled: Bool
    ) {
        guard enabled else { return }
        switch direction {
        case .increment:
            controller.adjust(group, direction: 1)
        case .decrement:
            controller.adjust(group, direction: -1)
        @unknown default:
            break
        }
    }
}

enum MenuBarPendingPolicy {
    static func canToggleRadioEnabled(
        controllerAllowsToggle: Bool,
        hasActiveMultiFlashScene: Bool
    ) -> Bool {
        controllerAllowsToggle && !hasActiveMultiFlashScene
    }

    static func canManage(
        displayedGroups: [GodoxGroup],
        pendingGroups: [GodoxGroup],
        pendingFields: [GodoxGroup: Set<PendingGroupField>],
        groupStates: [GodoxGroup: GroupDraft],
        hasPendingMultiFlashChange: Bool,
        hasPendingRestoration: Bool
    ) -> Bool {
        guard !hasPendingMultiFlashChange,
              !hasPendingRestoration,
              !pendingGroups.isEmpty else {
            return false
        }

        let visible = Set(displayedGroups)
        let manageableFields: Set<PendingGroupField> = [.power, .mode]
        return pendingGroups.allSatisfy { group in
            guard visible.contains(group),
                  let fields = pendingFields[group],
                  !fields.isEmpty,
                  fields.isSubset(of: manageableFields) else {
                return false
            }
            guard fields.contains(.mode) else { return true }
            guard let state = groupStates[group] else { return false }
            return isActivationTransition(
                from: state.baseline.operatingMode,
                to: state.draft.operatingMode
            )
        }
    }

    static func isActivationTransition(
        from baseline: GroupOperatingMode,
        to draft: GroupOperatingMode
    ) -> Bool {
        guard baseline != .multi, draft != .multi else { return false }
        return (baseline == .off) != (draft == .off)
    }
}

enum MenuBarStrings {
    static func pendingChanges(_ count: Int, language: AppLanguage) -> String {
        let key = pendingLocalizationKey(for: count)
        if key == "menubar.pendingOne" {
            return language.localized(key)
        }
        return language.localizedFormat(key, Int64(count))
    }

    static func pendingLocalizationKey(for count: Int) -> String {
        count == 1 ? "menubar.pendingOne" : "menubar.pendingMany"
    }
}
