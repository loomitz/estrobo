import SwiftUI
import EstroboCore

struct PresetsLibraryView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    @State private var presetName = ""
    @State private var presetPendingDeletion: StudioPreset?
    @State private var operationStatus: String?
    @FocusState private var presetNameFocused: Bool

    var body: some View {
        List {
            Section {
                TextField(
                    coordinator.text("presets.name.placeholder"),
                    text: $presetName
                )
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($presetNameFocused)
                .onSubmit(savePreset)
                .accessibilityIdentifier(EstroboAccessibilityID.presetName)

                Button(action: savePreset) {
                    Label(
                        coordinator.text("presets.save"),
                        systemImage: "plus.circle.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .accessibilityIdentifier(EstroboAccessibilityID.presetSave)

                if let operationStatus {
                    Text(operationStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(coordinator.text("presets.new"))
                    .accessibilityIdentifier(EstroboAccessibilityID.presetsScreen)
            } footer: {
                Text(coordinator.text("presets.detail"))
            }

            Section {
                if controller.presets.isEmpty {
                    Label(
                        coordinator.text("presets.empty"),
                        systemImage: "bookmark"
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(EstroboAccessibilityID.presetEmpty)
                } else {
                    ForEach(controller.presets) { preset in
                        presetRow(preset)
                    }
                }
            } header: {
                Text(coordinator.text("presets.saved"))
            }
        }
        .estroboScreenBackground()
        .navigationTitle(coordinator.text("tab.presets"))
        .sessionToolbar(coordinator: coordinator, controller: controller)
        .sheet(item: $presetPendingDeletion) { preset in
            PresetDeleteConfirmationView(
                coordinator: coordinator,
                preset: preset,
                onCancel: { presetPendingDeletion = nil },
                onConfirm: {
                    let removed = controller.deletePreset(id: preset.id)
                    operationStatus = removed
                        ? coordinator.text("presets.deleted")
                        : coordinator.text("presets.operation-failed")
                    presetPendingDeletion = nil
                }
            )
        }
    }

    private var trimmedPresetName: String {
        presetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        controller.canManagePresets
            && !trimmedPresetName.isEmpty
            && !controller.presetNameExists(trimmedPresetName)
    }

    private func savePreset() {
        guard canSave else { return }
        let saved = controller.savePreset(named: trimmedPresetName)
        operationStatus = saved
            ? coordinator.text("presets.saved-status")
            : coordinator.text("presets.operation-failed")
        if saved {
            presetName = ""
            presetNameFocused = false
        }
    }

    private func presetRow(_ preset: StudioPreset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(.headline)
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.preset(preset.id)
                        )
                    Text(presetSummary(preset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.activePresetID == preset.id {
                    Label(
                        coordinator.text("presets.active"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                presetButtons(preset)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func presetButtons(_ preset: StudioPreset) -> some View {
        Button {
            load(preset, synchronize: false)
        } label: {
            Label(
                coordinator.text("presets.load-local"),
                systemImage: "square.and.arrow.down"
            )
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(!canLoad(preset))
        .accessibilityIdentifier(EstroboAccessibilityID.presetLoadLocal(preset.id))

        Button {
            load(preset, synchronize: true)
        } label: {
            Label(
                coordinator.text("presets.load-sync"),
                systemImage: "arrow.triangle.2.circlepath"
            )
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSynchronize(preset))
        .accessibilityIdentifier(EstroboAccessibilityID.presetSync(preset.id))

        Button(role: .destructive) {
            presetPendingDeletion = preset
        } label: {
            Label(
                coordinator.text("action.delete"),
                systemImage: "trash"
            )
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(!controller.canManagePresets)
        .accessibilityIdentifier(EstroboAccessibilityID.presetDelete(preset.id))
    }

    private func canLoad(_ preset: StudioPreset) -> Bool {
        controller.canManagePresets
            && controller.presetCompatibilityIssue(preset) == nil
    }

    private func canSynchronize(_ preset: StudioPreset) -> Bool {
        canLoad(preset)
            && controller.phase == .ready
            && controller.canSynchronizeValues
    }

    private func load(_ preset: StudioPreset, synchronize: Bool) {
        let loaded = controller.loadPreset(
            id: preset.id,
            synchronizeIfConnected: synchronize
        )
        operationStatus = loaded
            ? coordinator.text(
                synchronize
                    ? "presets.sync-started"
                    : "presets.loaded-local"
            )
            : coordinator.text("presets.operation-failed")
    }

    private func presetSummary(_ preset: StudioPreset) -> String {
        let groups = preset.groups.map(\.label).joined(separator: ", ")
        return String(
            format: coordinator.text("presets.summary"),
            locale: coordinator.locale,
            arguments: [groups]
        )
    }
}

private struct PresetDeleteConfirmationView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    let preset: StudioPreset
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        coordinator.text("presets.delete.title"),
                        systemImage: "trash"
                    )
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.presetDeleteConfirmation
                    )
                    Text(preset.name)
                        .font(.headline)
                    Text(coordinator.text("presets.delete.detail"))
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(coordinator.text("action.cancel"), action: onCancel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.presetDeleteCancel
                        )
                    Button(
                        coordinator.text("action.delete"),
                        role: .destructive,
                        action: onConfirm
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.presetDeleteConfirm
                    )
                }
            }
            .navigationTitle(coordinator.text("presets.delete.title"))
        }
        .presentationDetents([.large])
    }
}

struct SavedRadiosView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    @ObservedObject var controller: GodoxSessionController

    @State private var radioPendingForget: SavedRadio?

    var body: some View {
        List {
            Section {
                if controller.savedRadios.isEmpty {
                    Label(
                        coordinator.text("saved.empty"),
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(EstroboAccessibilityID.savedRadioEmpty)
                } else {
                    ForEach(controller.savedRadios) { radio in
                        savedRadioRow(radio)
                    }
                }
            } header: {
                Text(coordinator.text("saved.title"))
                    .accessibilityIdentifier(EstroboAccessibilityID.savedRadios)
            } footer: {
                Text(coordinator.text("saved.detail"))
            }
        }
        .estroboScreenBackground()
        .navigationTitle(coordinator.text("saved.title"))
        .sessionToolbar(coordinator: coordinator, controller: controller)
        .sheet(item: $radioPendingForget) { radio in
            SavedRadioForgetConfirmationView(
                coordinator: coordinator,
                radio: radio,
                onCancel: { radioPendingForget = nil },
                onConfirm: {
                    controller.forgetSavedRadio(radio.deviceID)
                    radioPendingForget = nil
                }
            )
        }
    }

    private func savedRadioRow(_ radio: SavedRadio) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(radio.name)
                        .font(.headline)
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.savedRadio(radio.deviceID)
                        )
                    Text(String(radio.deviceID.uuidString.suffix(8)))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if controller.lastConnectedRadioID == radio.deviceID {
                        Text(coordinator.text("saved.last-connected"))
                            .font(.caption.bold())
                            .foregroundStyle(EstroboTheme.interactiveAccent)
                    }
                }
                Spacer()
                Label(
                    controller.isSavedRadioDiscovered(radio.deviceID)
                        ? coordinator.text("saved.discovered")
                        : coordinator.text("saved.not-discovered"),
                    systemImage: controller.isSavedRadioDiscovered(radio.deviceID)
                        ? "antenna.radiowaves.left.and.right"
                        : "antenna.radiowaves.left.and.right.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Toggle(
                isOn: Binding(
                    get: {
                        controller.isAutomaticConnectionEnabled(
                            for: radio.deviceID
                        )
                    },
                    set: { enabled in
                        controller.setAutomaticConnectionEnabled(
                            enabled,
                            for: radio.deviceID
                        )
                    }
                )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(coordinator.text("saved.auto-connect"))
                    Text(coordinator.text("saved.auto-connect.detail"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier(
                EstroboAccessibilityID.savedRadioAutoConnect(radio.deviceID)
            )

            Button(role: .destructive) {
                radioPendingForget = radio
            } label: {
                Label(
                    coordinator.text("saved.forget"),
                    systemImage: "trash"
                )
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!controller.canForgetSavedRadios)
            .accessibilityIdentifier(
                EstroboAccessibilityID.savedRadioForget(radio.deviceID)
            )
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

private struct SavedRadioForgetConfirmationView: View {
    @ObservedObject var coordinator: AppSessionCoordinator
    let radio: SavedRadio
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        coordinator.text("saved.forget.title"),
                        systemImage: "trash"
                    )
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.savedRadioForgetConfirmation
                    )
                    Text(radio.name)
                        .font(.headline)
                    Text(coordinator.text("saved.forget.detail"))
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(coordinator.text("action.cancel"), action: onCancel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier(
                            EstroboAccessibilityID.savedRadioForgetCancel
                        )
                    Button(
                        coordinator.text("saved.forget"),
                        role: .destructive,
                        action: onConfirm
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier(
                        EstroboAccessibilityID.savedRadioForgetConfirm
                    )
                }
            }
            .navigationTitle(coordinator.text("saved.forget.title"))
        }
        .presentationDetents([.large])
    }
}
