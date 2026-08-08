import SwiftUI
import AppKit

// Every control delegates to GodoxSessionController; esta vista no construye
// payloads Bluetooth ni toca credenciales directamente.

@MainActor
struct PrototypeRootView: View {
    @ObservedObject var controller: GodoxSessionController

    @StateObject private var languageStore = AppLanguageStore()
    @State private var variant: PrototypeVariant
    @State private var selectedGroup: GodoxGroup = .b
    private let workspaceViewPreferences: WorkspaceViewPreferences

    init(controller: GodoxSessionController) {
        self.controller = controller
        let preferences = WorkspaceViewPreferences()
        workspaceViewPreferences = preferences
        _variant = State(initialValue: preferences.launchVariant(arguments: CommandLine.arguments))
    }

    private var minimumWidth: CGFloat {
        switch variant {
        case .channels: 900
        case .inspector: 900
        case .matrix: 900
        }
    }

    private var contentMaximumWidth: CGFloat? {
        switch variant {
        case .channels: nil
        case .inspector: 1080
        case .matrix: nil
        }
    }

    var body: some View {
        ZStack {
            PrototypePalette.windowBackground
                .ignoresSafeArea()

            if !controller.hasCompletedOnboarding && controller.restorationPoints.isEmpty {
                WorkspaceConfigurationFlow(controller: controller)
            } else {
                VStack(spacing: 0) {
                    PrototypeHeader(
                        controller: controller,
                        variant: $variant
                    )

                    Rectangle()
                        .fill(PrototypePalette.divider)
                        .frame(height: 1)

                    if controller.showsControlWorkspace {
                        QuickControlsBar(controller: controller)

                        Rectangle()
                            .fill(PrototypePalette.divider)
                            .frame(height: 1)

                        variantContent
                            .frame(maxWidth: contentMaximumWidth ?? .infinity)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)

                        Rectangle()
                            .fill(PrototypePalette.divider)
                            .frame(height: 1)

                        WorkspaceFooter(controller: controller)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            .background(PrototypePalette.footerSurface)
                    } else {
                        ConnectionPanel(controller: controller)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)

                        ConnectionSetupFlow(controller: controller)
                            .frame(maxWidth: 680)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.horizontal, 28)
                            .padding(.top, 12)

                        ActivityStrip(item: controller.activity.last)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .environment(\.locale, languageStore.language.locale)
        .environmentObject(languageStore)
        .environmentObject(controller)
        .frame(minWidth: minimumWidth, minHeight: 720)
        .animation(.easeInOut(duration: 0.16), value: variant)
        .onAppear(perform: keepInspectorSelectionVisible)
        .onReceive(controller.$visibleGroups) { _ in
            keepInspectorSelectionVisible()
        }
        .onChange(of: variant) { newValue in
            workspaceViewPreferences.save(newValue)
        }
    }

    @ViewBuilder
    private var variantContent: some View {
        switch variant {
        case .channels:
            ChannelsLayout(controller: controller)
        case .inspector:
            InspectorLayout(
                controller: controller,
                selectedGroup: $selectedGroup
            )
        case .matrix:
            MatrixLayout(controller: controller)
        }
    }

    private func keepInspectorSelectionVisible() {
        if let valid = LocalGroupPreferences.validSelection(
            current: selectedGroup,
            visibleGroups: controller.visibleGroups
        ), valid != selectedGroup {
            selectedGroup = valid
        }
    }
}

@MainActor
private struct WorkspaceConfigurationFlow: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore

    @State private var profileID: String
    @State private var selectedGroups: Set<GodoxGroup>
    @State private var assignedFlashModelIDs: [GodoxGroup: Set<String>]
    @State private var configuredGroup: GodoxGroup
    @State private var modelFilter = ""
    @State private var completionFailed = false
    @State private var showsGroupPicker = false
    @State private var showsSavedTransmitters = false

    init(controller: GodoxSessionController) {
        self.controller = controller
        let profile = controller.transmitterProfile
        let startsEmpty = !controller.hasStoredWorkspaceConfiguration
        let initialGroups = startsEmpty
            ? Set<GodoxGroup>()
            : Set(controller.workingGroups.filter(profile.supportedGroups.contains))

        let catalogIDs = Set(profile.flashCatalog.map(\.id))
        let assignments = Dictionary(uniqueKeysWithValues: profile.supportedGroups.map { group in
            (
                group,
                startsEmpty
                    ? Set<String>()
                    : controller.groupConfiguration(group).assignedFlashModelIDs
                        .intersection(catalogIDs)
            )
        })

        _profileID = State(initialValue: profile.id)
        _selectedGroups = State(initialValue: initialGroups)
        _assignedFlashModelIDs = State(initialValue: assignments)
        _configuredGroup = State(
            initialValue: profile.supportedGroups.first(where: initialGroups.contains)
                ?? profile.supportedGroups.first
                ?? .b
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                EstroboBrandLockup()
                Spacer()
                LanguageToggle()
                    .fixedSize(horizontal: true, vertical: false)
                AppearanceToggle()
            }
            .padding(.horizontal, 28)
            .frame(minHeight: 82)

            Rectangle()
                .fill(PrototypePalette.divider)
                .frame(height: 1)

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 7) {
                        Text(languageStore.language.localized("Configura tu espacio de trabajo"))
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(PrototypePalette.primaryText)
                        Text(languageStore.language.localized(
                            controller.isReconfiguringWorkspace
                                ? "Organiza el transmisor, los grupos y sus flashes en un solo lugar."
                                : "Antes de conectar, elige tus grupos y asigna sus flashes."
                        ))
                            .font(.callout)
                            .foregroundStyle(PrototypePalette.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    unifiedWorkspacePanel

                    if completionFailed {
                        Label(
                            languageStore.language.localized(
                                "No se pudo guardar el espacio de trabajo. Inténtalo nuevamente."
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout.weight(.medium))
                        .foregroundStyle(PrototypePalette.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isStaticText)
                    }

                }
                .frame(maxWidth: 1000)
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
            }

            Rectangle()
                .fill(PrototypePalette.divider)
                .frame(height: 1)

            configurationFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: profileID) { _ in
            reconcileProfileSelection()
        }
        .onChange(of: controller.availableTransmitterProfiles.map(\.id)) { availableIDs in
            guard !availableIDs.contains(profileID) else { return }
            profileID = availableIDs.contains(controller.transmitterProfile.id)
                ? controller.transmitterProfile.id
                : (controller.defaultTransmitterProfileID)
        }
        .sheet(isPresented: $showsGroupPicker) {
            AddWorkingGroupsSheet(
                groups: unselectedSupportedGroups,
                onAdd: addWorkingGroups
            )
        }
        .sheet(isPresented: $showsSavedTransmitters) {
            SavedTransmittersSheet(controller: controller)
        }
    }

    private var configurationFooter: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(languageStore.language.localizedFormat(
                    "%lld grupos de trabajo",
                    selectedGroups.count
                ))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PrototypePalette.primaryText)
                Text(configurationSummary)
                    .font(.caption)
                    .foregroundStyle(
                        configurationIsValid
                            ? PrototypePalette.secondaryText
                            : PrototypePalette.warning
                    )
            }

            Spacer()

            if controller.isReconfiguringWorkspace {
                Button {
                    controller.cancelWorkspaceConfiguration()
                } label: {
                    Text(languageStore.language.localized("Cancelar"))
                }
                .buttonStyle(QuietButtonStyle())
            }

            Button {
                completeConfiguration()
            } label: {
                Label(
                    languageStore.language.localized(
                        controller.isReconfiguringWorkspace
                            ? "Guardar cambios"
                            : "Guardar y continuar"
                    ),
                    systemImage: controller.isReconfiguringWorkspace
                        ? "checkmark"
                        : "arrow.right"
                )
            }
            .buttonStyle(WorkspacePrimaryButtonStyle())
            .disabled(!configurationIsValid || !controller.canConfigureWorkspace)
            .keyboardShortcut(.defaultAction)
            .help(languageStore.language.localized(configurationHelp))
        }
        .padding(.horizontal, 28)
        .frame(minHeight: 74)
        .background(PrototypePalette.footerSurface)
    }

    private var unifiedWorkspacePanel: some View {
        VStack(spacing: 0) {
            profileToolbar

            Rectangle()
                .fill(PrototypePalette.dividerStrong)
                .frame(height: 1)

            HStack(spacing: 0) {
                groupMasterPane

                Rectangle()
                    .fill(PrototypePalette.dividerStrong)
                    .frame(width: 1)

                flashDetailPane
            }
            .frame(minHeight: 420, maxHeight: 460)
        }
        .prototypePanel(padding: 0)
    }

    private var profileToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageStore.language.localized("Compatibilidad de grupos").uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(PrototypePalette.secondaryText)

            HStack(spacing: 12) {
                Picker(
                    languageStore.language.localized("Compatibilidad de grupos"),
                    selection: $profileID
                ) {
                    ForEach(controller.availableTransmitterProfiles) { profile in
                        Text(languageStore.language.localized(profile.name)).tag(profile.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(!controller.canConfigureHardwareProfile)
                .frame(maxWidth: 360, alignment: .leading)
                .help(languageStore.language.localized(
                    controller.canConfigureHardwareProfile
                        ? "Elige la compatibilidad de grupos para tu transmisor."
                        : "Desconecta para cambiar la compatibilidad de grupos."
                ))

                if profileID == controller.defaultTransmitterProfileID {
                    Label(
                        languageStore.language.localized("Predeterminado"),
                        systemImage: "star.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(PrototypePalette.surfaceRaised)
                    )
                    .accessibilityAddTraits(.isSelected)
                }

                Spacer(minLength: 12)

                Button {
                    showsSavedTransmitters = true
                } label: {
                    Label(
                        languageStore.language.localized("Transmisores guardados…"),
                        systemImage: "externaldrive.badge.wifi"
                    )
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityHint(languageStore.language.localized(
                    "Revisa los transmisores que se han guardado en este Mac."
                ))
            }
        }
        .padding(16)
    }

    private var groupMasterPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(languageStore.language.localized("Grupos de trabajo").uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("\(selectedGroups.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(PrototypePalette.surfaceRaised))

                Spacer(minLength: 4)

                Button {
                    showsGroupPicker = true
                } label: {
                    Label(
                        languageStore.language.localized("Añadir grupo"),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(unselectedSupportedGroups.isEmpty)
                .help(languageStore.language.localized(
                    unselectedSupportedGroups.isEmpty
                        ? "Todos los grupos disponibles ya están añadidos."
                        : "Añade uno o varios grupos de trabajo."
                ))
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(orderedSelectedGroups) { group in
                        groupMasterRow(group)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(PrototypePalette.surfaceRaised.opacity(0.22))
    }

    @ViewBuilder
    private var flashDetailPane: some View {
        if orderedSelectedGroups.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(PrototypePalette.muted)
                Text(languageStore.language.localized(
                    "Aún no hay grupos de trabajo"
                ))
                    .font(.headline)
                    .foregroundStyle(PrototypePalette.primaryText)
                Text(languageStore.language.localized(
                    "Estrobo no selecciona grupos por ti. Añade los que realmente utilizas y asigna sus modelos de flash."
                ))
                    .font(.callout)
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)

                Button {
                    showsGroupPicker = true
                } label: {
                    Label(
                        languageStore.language.localized("Elegir grupos"),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(WorkspacePrimaryButtonStyle())
                .disabled(unselectedSupportedGroups.isEmpty)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    GroupBadge(group: configuredGroup, size: 38, fontSize: 18)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(languageStore.language.localizedFormat(
                            "Grupo %@",
                            configuredGroup.label
                        ))
                            .font(.headline)
                            .foregroundStyle(PrototypePalette.primaryText)
                        Text(modelAssignmentSummary(
                            count: assignedFlashModelIDs[configuredGroup, default: []].count,
                            group: configuredGroup
                        ))
                            .font(.caption)
                            .foregroundStyle(PrototypePalette.secondaryText)
                    }

                    Spacer(minLength: 8)

                    Button(role: .destructive) {
                        removeWorkingGroup(configuredGroup)
                    } label: {
                        Label(
                            languageStore.language.localized("Eliminar grupo"),
                            systemImage: "trash"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PrototypePalette.error)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(languageStore.language.localized(
                        "Quita este grupo del espacio de trabajo."
                    ))
                }

                TextField(
                    languageStore.language.localized("Buscar modelo"),
                    text: $modelFilter
                )
                .textFieldStyle(.roundedBorder)

                HStack {
                    Text(languageStore.language.localized("MODELO"))
                    Spacer()
                    Text(languageStore.language.localized("MÍN. MANUAL"))
                }
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(PrototypePalette.secondaryText)

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(filteredModels) { model in
                            flashModelButton(model)
                        }
                    }
                    .padding(.vertical, 1)
                }

                safeRangeSummary
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func groupMasterRow(_ group: GodoxGroup) -> some View {
        let assignedCount = assignedFlashModelIDs[group, default: []].count
        let isSelected = configuredGroup == group
        let capability = draftCapability(for: group)

        return HStack(spacing: 0) {
            Button {
                configuredGroup = group
                completionFailed = false
            } label: {
                HStack(spacing: 10) {
                    GroupBadge(group: group, size: 38, fontSize: 17)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(languageStore.language.localizedFormat("Grupo %@", group.label))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(PrototypePalette.primaryText)
                        Text(
                            assignedCount == 0
                                ? languageStore.language.localized("Falta un modelo")
                                : languageStore.language.localizedFormat(
                                    assignedCount == 1 ? "%lld modelo" : "%lld modelos",
                                    assignedCount
                                )
                        )
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(
                                assignedCount == 0
                                    ? PrototypePalette.warning
                                    : PrototypePalette.secondaryText
                            )
                        Text(languageStore.language.localizedFormat(
                            "Rango seguro %@",
                            languageStore.language.localized(capability.safeRangeLabel)
                        ))
                            .font(.caption2)
                            .foregroundStyle(PrototypePalette.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)
                }
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageStore.language.localizedFormat("Grupo %@", group.label))
            .accessibilityValue(modelAssignmentSummary(count: assignedCount, group: group))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Menu {
                Button(role: .destructive) {
                    removeWorkingGroup(group)
                } label: {
                    Label(
                        languageStore.language.localized("Eliminar grupo"),
                        systemImage: "trash"
                    )
                }
                .disabled(selectedGroups.count <= 1)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(languageStore.language.localizedFormat(
                "Opciones del grupo %@",
                group.label
            ))
        }
        .padding(.trailing, 4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? PrototypePalette.accent.opacity(0.10)
                        : PrototypePalette.surface
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            isSelected
                                ? PrototypePalette.accent.opacity(0.78)
                                : PrototypePalette.divider,
                            lineWidth: 1
                        )
                }
        )
    }

    private func flashModelButton(_ model: FlashCapability) -> some View {
        let isAssigned = assignedFlashModelIDs[configuredGroup, default: []].contains(model.id)

        return Button {
            modelBinding(model.id).wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isAssigned ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        isAssigned ? PrototypePalette.accent : PrototypePalette.secondaryText
                    )

                Text(model.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PrototypePalette.primaryText)

                Spacer(minLength: 8)

                Text("1/\(model.minimumManualDenominator)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(PrototypePalette.secondaryText)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isAssigned
                            ? PrototypePalette.accent.opacity(0.08)
                            : PrototypePalette.surfaceRaised.opacity(0.62)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isAssigned
                                    ? PrototypePalette.accent.opacity(0.42)
                                    : PrototypePalette.divider,
                                lineWidth: 1
                            )
                    }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.name)
        .accessibilityValue(languageStore.language.localized(
            isAssigned ? "Seleccionado" : "No seleccionado"
        ))
        .accessibilityAddTraits(isAssigned ? .isSelected : [])
    }

    private var safeRangeSummary: some View {
        let capability = draftCapability(for: configuredGroup)
        let assignedCount = assignedFlashModelIDs[configuredGroup, default: []].count

        return HStack(spacing: 10) {
            Image(systemName: assignedCount > 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(
                    assignedCount > 0 ? PrototypePalette.success : PrototypePalette.warning
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(languageStore.language.localizedFormat(
                    "Grupo %@ · Rango seguro %@",
                    configuredGroup.label,
                    languageStore.language.localized(capability.safeRangeLabel)
                ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PrototypePalette.primaryText)
                Text(languageStore.language.localized(
                    assignedCount > 0
                        ? "Estrobo limitará la potencia al rango que todos los modelos seleccionados comparten."
                        : "Selecciona al menos un modelo para calcular el rango seguro."
                ))
                    .font(.caption2)
                    .foregroundStyle(PrototypePalette.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PrototypePalette.surfaceRaised)
        )
        .accessibilityElement(children: .combine)
    }

    private func draftCapability(for group: GodoxGroup) -> ResolvedGroupCapability {
        ResolvedGroupCapability.resolve(
            configuration: GroupConfiguration(
                assignedFlashModelIDs: assignedFlashModelIDs[group, default: []],
                isVisibleLocally: true,
                isEnabledOnRadio: false,
                hasCompleteBaseline: false
            ),
            profile: selectedProfile
        )
    }

    private var selectedProfile: TransmitterProfile {
        controller.availableTransmitterProfiles.first(where: { $0.id == profileID })
            ?? controller.transmitterProfile
    }

    private var orderedSelectedGroups: [GodoxGroup] {
        selectedProfile.supportedGroups.filter(selectedGroups.contains)
    }

    private var unselectedSupportedGroups: [GodoxGroup] {
        selectedProfile.supportedGroups.filter { !selectedGroups.contains($0) }
    }

    private var filteredModels: [FlashCapability] {
        guard !modelFilter.isEmpty else { return selectedProfile.flashCatalog }
        return selectedProfile.flashCatalog.filter {
            $0.name.localizedCaseInsensitiveContains(modelFilter) ||
                $0.id.localizedCaseInsensitiveContains(modelFilter)
        }
    }

    private var configurationIsValid: Bool {
        !orderedSelectedGroups.isEmpty && orderedSelectedGroups.allSatisfy {
            !assignedFlashModelIDs[$0, default: []].isEmpty
        }
    }

    private var configurationSummary: String {
        if selectedGroups.isEmpty {
            return languageStore.language.localized("Selecciona al menos un grupo.")
        }
        let missing = orderedSelectedGroups.filter {
            assignedFlashModelIDs[$0, default: []].isEmpty
        }
        guard !missing.isEmpty else {
            return languageStore.language.localized(
                "La configuración está lista para guardarse en este Mac."
            )
        }
        return languageStore.language.localizedFormat(
            "Falta asignar flashes a: %@",
            missing.map(\.label).joined(separator: ", ")
        )
    }

    private var configurationHelp: String {
        guard configurationIsValid else { return configurationSummary }
        return controller.isReconfiguringWorkspace
            ? "Guarda los grupos y modelos sin interrumpir la conexión"
            : "Guarda los grupos de trabajo y continúa a la conexión"
    }

    private func modelAssignmentSummary(count: Int, group: GodoxGroup) -> String {
        if count == 0 {
            return languageStore.language.localizedFormat(
                "El grupo %@ necesita al menos un modelo.",
                group.label
            )
        }
        if count == 1 {
            return languageStore.language.localizedFormat(
                "1 modelo asignado al grupo %@",
                group.label
            )
        }
        return languageStore.language.localizedFormat(
            "%lld modelos asignados al grupo %@",
            count,
            group.label
        )
    }

    private func modelBinding(_ modelID: String) -> Binding<Bool> {
        Binding(
            get: { assignedFlashModelIDs[configuredGroup, default: []].contains(modelID) },
            set: { isAssigned in
                if isAssigned {
                    assignedFlashModelIDs[configuredGroup, default: []].insert(modelID)
                } else {
                    assignedFlashModelIDs[configuredGroup, default: []].remove(modelID)
                }
                completionFailed = false
            }
        )
    }

    private func addWorkingGroups(_ groups: Set<GodoxGroup>) {
        let validGroups = groups.intersection(Set(selectedProfile.supportedGroups))
        guard !validGroups.isEmpty else { return }
        completionFailed = false
        selectedGroups.formUnion(validGroups)
        if let firstAdded = selectedProfile.supportedGroups.first(where: validGroups.contains) {
            configuredGroup = firstAdded
        }
        modelFilter = ""
    }

    private func removeWorkingGroup(_ group: GodoxGroup) {
        guard selectedGroups.contains(group) else { return }
        completionFailed = false
        selectedGroups.remove(group)
        if configuredGroup == group {
            configuredGroup = orderedSelectedGroups.first
                ?? selectedProfile.supportedGroups.first
                ?? .b
            modelFilter = ""
        }
    }

    private func reconcileProfileSelection() {
        completionFailed = false
        let supported = Set(selectedProfile.supportedGroups)
        selectedGroups.formIntersection(supported)

        let catalogIDs = Set(selectedProfile.flashCatalog.map(\.id))
        for group in selectedProfile.supportedGroups {
            assignedFlashModelIDs[group, default: []].formIntersection(catalogIDs)
        }
        configuredGroup = orderedSelectedGroups.first
            ?? selectedProfile.supportedGroups.first
            ?? .b
        modelFilter = ""
    }

    private func completeConfiguration() {
        guard configurationIsValid else { return }
        let didComplete = controller.completeWorkspaceConfiguration(
            profileID: profileID,
            selectedGroups: selectedGroups,
            assignedFlashModelIDs: assignedFlashModelIDs
        )
        completionFailed = !didComplete
    }
}

@MainActor
private struct AddWorkingGroupsSheet: View {
    let groups: [GodoxGroup]
    let onAdd: (Set<GodoxGroup>) -> Void

    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGroups: Set<GodoxGroup> = []
    @State private var groupFilter = ""

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 4
    )

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 5) {
                    Text(languageStore.language.localized("Añadir grupos"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(PrototypePalette.primaryText)
                    Text(languageStore.language.localized(
                        "Elige uno o varios grupos disponibles para este perfil."
                    ))
                        .font(.callout)
                        .foregroundStyle(PrototypePalette.secondaryText)
                }
                .frame(maxWidth: .infinity)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(languageStore.language.localized("Cerrar"))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider().overlay(PrototypePalette.dividerStrong)

            VStack(alignment: .leading, spacing: 14) {
                TextField(
                    languageStore.language.localized("Buscar grupo"),
                    text: $groupFilter
                )
                .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(filteredGroups) { group in
                            groupOption(group)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider().overlay(PrototypePalette.dividerStrong)

            HStack(spacing: 10) {
                Text(selectionSummary)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PrototypePalette.primaryText)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(languageStore.language.localized("Cancelar"))
                }
                .buttonStyle(QuietButtonStyle())

                Button {
                    onAdd(selectedGroups)
                    dismiss()
                } label: {
                    Label(addButtonTitle, systemImage: "plus")
                }
                .buttonStyle(WorkspacePrimaryButtonStyle())
                .disabled(selectedGroups.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 70)
            .background(PrototypePalette.footerSurface)
        }
        .frame(width: 690, height: 500)
        .background(PrototypePalette.windowBackground)
    }

    private var filteredGroups: [GodoxGroup] {
        guard !groupFilter.isEmpty else { return groups }
        return groups.filter { group in
            group.label.localizedCaseInsensitiveContains(groupFilter) ||
                languageStore.language.localizedFormat("Grupo %@", group.label)
                    .localizedCaseInsensitiveContains(groupFilter)
        }
    }

    private var addButtonTitle: String {
        if selectedGroups.count == 1 {
            return languageStore.language.localized("Añadir grupo")
        }
        return languageStore.language.localizedFormat(
            "Añadir %lld grupos",
            selectedGroups.count
        )
    }

    private var selectionSummary: String {
        if selectedGroups.count == 1 {
            return languageStore.language.localized("1 grupo seleccionado")
        }
        return languageStore.language.localizedFormat(
            "%lld grupos seleccionados",
            selectedGroups.count
        )
    }

    private func groupOption(_ group: GodoxGroup) -> some View {
        let isSelected = selectedGroups.contains(group)

        return Button {
            if isSelected {
                selectedGroups.remove(group)
            } else {
                selectedGroups.insert(group)
            }
        } label: {
            HStack(spacing: 10) {
                GroupBadge(group: group, size: 34, fontSize: 16)
                    .accessibilityHidden(true)
                Text(languageStore.language.localizedFormat("Grupo %@", group.label))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PrototypePalette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? PrototypePalette.accent.opacity(0.10)
                            : PrototypePalette.surface
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                isSelected
                                    ? PrototypePalette.accent.opacity(0.85)
                                    : PrototypePalette.divider,
                                lineWidth: 1
                            )
                    }
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PrototypePalette.accent)
                        .padding(5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageStore.language.localizedFormat("Grupo %@", group.label))
        .accessibilityValue(languageStore.language.localized(
            isSelected ? "Seleccionado" : "No seleccionado"
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

@MainActor
private struct SavedTransmittersSheet: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var radioPendingForget: SavedRadio?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(languageStore.language.localized("Transmisores guardados"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PrototypePalette.primaryText)
                    Text(languageStore.language.localized(
                        "Radios que se han conectado y guardado en este Mac."
                    ))
                        .font(.callout)
                        .foregroundStyle(PrototypePalette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(languageStore.language.localized("Cerrar"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider().overlay(PrototypePalette.dividerStrong)

            ScrollView {
                if controller.savedRadios.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(controller.savedRadios, id: \.deviceID) { radio in
                            transmitterRow(radio)
                        }
                    }
                    .padding(24)
                }
            }

            Divider().overlay(PrototypePalette.dividerStrong)

            HStack(alignment: .center, spacing: 16) {
                Text(languageStore.language.localized(
                    "Los códigos guardados permanecen en este Mac y no se muestran en esta lista."
                ))
                    .font(.caption)
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(languageStore.language.localized("Listo"))
                }
                .buttonStyle(WorkspacePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .frame(minHeight: 78)
            .background(PrototypePalette.footerSurface)
        }
        .frame(width: 720, height: 540)
        .background(PrototypePalette.windowBackground)
        .alert(
            languageStore.language.localized("¿Olvidar este transmisor?"),
            isPresented: Binding(
                get: { radioPendingForget != nil },
                set: { isPresented in
                    if !isPresented { radioPendingForget = nil }
                }
            ),
            presenting: radioPendingForget
        ) { radio in
            Button(languageStore.language.localized("Cancelar"), role: .cancel) {
                radioPendingForget = nil
            }
            Button(languageStore.language.localized("Olvidar"), role: .destructive) {
                controller.forgetSavedRadio(radio.deviceID)
                radioPendingForget = nil
            }
        } message: { _ in
            Text(languageStore.language.localized(
                "Se eliminarán el transmisor y su Código del radio guardados en este Mac."
            ))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.wifi")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(PrototypePalette.secondaryText)
                .accessibilityHidden(true)

            Text(languageStore.language.localized("Aún no hay transmisores guardados"))
                .font(.headline)
                .foregroundStyle(PrototypePalette.primaryText)

            Text(languageStore.language.localized(
                "Activa Recordar antes de conectar; se guardará sólo al completar autenticación y Sync."
            ))
                .font(.callout)
                .foregroundStyle(PrototypePalette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
        .padding(24)
        .accessibilityElement(children: .combine)
    }

    private func transmitterRow(_ radio: SavedRadio) -> some View {
        let isConnected = controller.showsControlWorkspace &&
            controller.selectedDeviceID == radio.deviceID
        let isDiscovered = controller.isSavedRadioDiscovered(radio.deviceID)
        let statusTitle: String
        let statusImage: String
        let statusColor: Color
        if isConnected {
            statusTitle = "Conectado"
            statusImage = "link.circle.fill"
            statusColor = PrototypePalette.success
        } else if isDiscovered {
            statusTitle = "Encontrado en la última búsqueda"
            statusImage = "dot.radiowaves.left.and.right"
            statusColor = PrototypePalette.accent
        } else {
            statusTitle = "Guardado en este Mac"
            statusImage = "bookmark.fill"
            statusColor = PrototypePalette.secondaryText
        }

        return HStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(PrototypePalette.primaryText)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(PrototypePalette.surfaceRaised)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(radio.name)
                    .font(.headline)
                    .foregroundStyle(PrototypePalette.primaryText)

                Text(languageStore.language.localizedFormat(
                    "Identificador …%@",
                    identifierSuffix(radio.deviceID)
                ))
                    .font(.caption.monospaced())
                    .foregroundStyle(PrototypePalette.secondaryText)

                Label(
                    languageStore.language.localized(statusTitle),
                    systemImage: statusImage
                )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: 12)

            Button(role: .destructive) {
                radioPendingForget = radio
            } label: {
                Label(
                    languageStore.language.localized("Olvidar"),
                    systemImage: "trash"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(PrototypePalette.error)
            }
            .buttonStyle(.plain)
            .disabled(!controller.canForgetSavedRadios)
            .accessibilityLabel(languageStore.language.localizedFormat(
                "Olvidar transmisor %@",
                radio.name
            ))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(PrototypePalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(PrototypePalette.divider, lineWidth: 1)
                }
        )
        .accessibilityElement(children: .contain)
    }

    private func identifierSuffix(_ deviceID: UUID) -> String {
        String(deviceID.uuidString.replacingOccurrences(of: "-", with: "").suffix(6))
    }
}

@MainActor
struct QuickControlsBar: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var globalOffsetSteps = 0
    @State private var globalPowerAnchor: [GodoxGroup: ManualPower] = [:]
    @State private var limitFeedback: GlobalPowerLimitCause?
    @State private var limitFeedbackPulses = false
    @State private var limitFeedbackGeneration = 0
    @State private var lastDragLimitDirection: Int?
    @State private var interactiveEditToken: GodoxSessionController.InteractiveEditToken?

    var body: some View {
        let canAttemptGlobalAdjustment = !controller.makeGlobalPowerAnchor().isEmpty

        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageStore.language.localized("global.title"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(PrototypePalette.primaryText)

                    if let limitFeedback {
                        limitFeedbackView(limitFeedback)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .frame(width: 154, alignment: .leading)

                GlobalStepButton(
                    systemImage: "minus",
                    accessibilityLabel: "Bajar un tercio EV en todos los grupos activos",
                    enabled: canAttemptGlobalAdjustment
                ) {
                    attemptGlobalStep(direction: -1)
                }

                VStack(spacing: 6) {
                    Text(offsetLabel)
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            globalOffsetSteps == 0
                                ? PrototypePalette.primaryText
                                : PrototypePalette.accent
                        )

                    Slider(
                        value: globalOffsetBinding,
                        in: -9...9,
                        step: 1
                    )
                    .tint(PrototypePalette.accent)
                    .disabled(!canAttemptGlobalAdjustment)
                    .background(
                        InteractivePointerEditMonitor(
                            isEnabled: canAttemptGlobalAdjustment,
                            onEditingChanged: globalSliderEditingChanged
                        )
                    )
                    .accessibilityLabel(languageStore.language.localized(
                        "global.slider.accessibility"
                    ))
                    .accessibilityValue(offsetLabel)
                    .accessibilityHint(languageStore.language.localized(
                        "global.slider.help"
                    ))
                    .frame(height: 24)

                    HStack {
                        Text("−3.0 EV")
                        Spacer()
                        Text(languageStore.language.localized("AJUSTE RELATIVO · PASOS DE 1/3 EV"))
                        Spacer()
                        Text("+3.0 EV")
                    }
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PrototypePalette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)

                GlobalStepButton(
                    systemImage: "plus",
                    accessibilityLabel: "Subir un tercio EV en todos los grupos activos",
                    enabled: canAttemptGlobalAdjustment
                ) {
                    attemptGlobalStep(direction: 1)
                }

                Rectangle()
                    .fill(PrototypePalette.divider)
                    .frame(width: 1, height: 54)

                HStack(spacing: 8) {
                    GlobalStateToggle(
                        title: "Beep",
                        systemImage: controller.globalBeepEnabled
                            ? "speaker.wave.2.fill"
                            : "speaker.slash",
                        isOn: Binding(
                            get: { controller.globalBeepEnabled },
                            set: { controller.setGlobalBeep($0) }
                        ),
                        enabled: controller.canToggleGlobalBeep
                    )
                    .help(languageStore.language.localized(
                        controller.pendingCount > 0
                            ? "Aplica o descarta los cambios antes de cambiar el beep global."
                            : "Activa o apaga el beep para todos los grupos de trabajo."
                    ))

                    MultiModeButton(
                        isActive: multiIsActive,
                        enabled: controller.canSetGlobalMultiFlashEnabled(!multiIsActive)
                    ) {
                        controller.setGlobalMultiFlashEnabled(!multiIsActive)
                    }

                    GlobalStateToggle(
                        title: "Standby",
                        systemImage: controller.isGlobalStandbyEnabled
                            ? "pause.fill"
                            : "pause",
                        isOn: Binding(
                            get: { controller.isGlobalStandbyEnabled },
                            set: { controller.setGlobalStandby($0) }
                        ),
                        enabled: controller.canToggleGlobalStandby
                    )
                    .help(languageStore.language.localized(
                        controller.isGlobalStandbyEnabled
                            ? "Reanuda todos los grupos sin perder sus ajustes."
                            : "Pone todos los grupos en espera sin perder sus ajustes."
                    ))
                }

                Button {
                    controller.sendTestFlash()
                } label: {
                    Label {
                        Text(languageStore.language.localized(
                            controller.isTestPending ? "global.test.sending" : "global.test"
                        ))
                    } icon: {
                        Image(systemName: "bolt.fill")
                    }
                        .frame(minWidth: 96)
                }
                .buttonStyle(TestButtonStyle())
                .disabled(!controller.canSendTest)
                .help(testHelp)
                .accessibilityLabel("Disparo Test global")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)

            if multiIsActive {
                Rectangle()
                    .fill(PrototypePalette.divider)
                    .frame(height: 1)

                MultiFlashConsole(controller: controller)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .transition(
                        reduceMotion
                            ? .identity
                            : .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .background(PrototypePalette.globalSurface)
        .onChange(of: canAttemptGlobalAdjustment) { isAvailable in
            if !isAvailable {
                finishGlobalInteractiveEdit()
            }
        }
        .onDisappear(perform: finishGlobalInteractiveEdit)
    }

    private var multiIsActive: Bool {
        !controller.multiFlashGroups.isEmpty
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
        return languageStore.language.localizedMessage(
            controller.testBlockReason
                ?? "Dispara todos los grupos activos del radio con los ajustes ya aplicados; Bluetooth no confirma el destello"
        )
    }

    private var globalOffsetBinding: Binding<Double> {
        Binding(
            get: { Double(globalOffsetSteps) },
            set: { rawValue in
                if globalPowerAnchor.isEmpty {
                    globalPowerAnchor = controller.makeGlobalPowerAnchor()
                }
                let requestedSteps = min(9, max(-9, Int(rawValue.rounded())))
                let outcome = controller.attemptGlobalPowerAdjustment(
                    offsetSteps: requestedSteps,
                    from: globalPowerAnchor,
                    limitedTo: 9
                )
                handleSliderOutcome(outcome, requestedSteps: requestedSteps)
            }
        )
    }

    private var offsetLabel: String {
        offsetText(for: globalOffsetSteps)
    }

    private func offsetText(for steps: Int) -> String {
        String(format: "%+.1f EV", Double(steps) / 3.0)
    }

    private func globalSliderEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if interactiveEditToken == nil {
                interactiveEditToken = controller.beginInteractiveEdit()
                globalPowerAnchor = controller.makeGlobalPowerAnchor()
            }
        } else {
            lastDragLimitDirection = nil
            globalPowerAnchor.removeAll()
            withAnimation(.easeOut(duration: 0.18)) {
                globalOffsetSteps = 0
            }
            finishGlobalInteractiveEdit()
        }
    }

    private func finishGlobalInteractiveEdit() {
        guard let token = interactiveEditToken else { return }
        interactiveEditToken = nil
        controller.endInteractiveEdit(token)
    }

    private func attemptGlobalStep(direction: Int) {
        let outcome = controller.adjustGlobalPower(direction: direction)
        if case .limited(_, let cause) = outcome {
            presentLimitFeedback(cause, direction: direction, alwaysPerformHaptic: true)
        }
    }

    private func handleSliderOutcome(
        _ outcome: GlobalPowerAdjustmentOutcome,
        requestedSteps: Int
    ) {
        switch outcome {
        case .applied(let appliedSteps):
            globalOffsetSteps = appliedSteps
            lastDragLimitDirection = nil
        case .limited(let appliedSteps, let cause):
            globalOffsetSteps = appliedSteps
            let direction = requestedSteps < appliedSteps ? -1 : 1
            presentLimitFeedback(cause, direction: direction, alwaysPerformHaptic: false)
        case .unavailable:
            globalOffsetSteps = 0
            globalPowerAnchor.removeAll()
        }
    }

    private func presentLimitFeedback(
        _ cause: GlobalPowerLimitCause,
        direction: Int,
        alwaysPerformHaptic: Bool
    ) {
        let shouldPerformHaptic = alwaysPerformHaptic || lastDragLimitDirection != direction
        lastDragLimitDirection = direction
        limitFeedbackGeneration += 1
        let generation = limitFeedbackGeneration

        withAnimation(.easeOut(duration: 0.12)) {
            limitFeedback = cause
            limitFeedbackPulses = true
        }

        if shouldPerformHaptic {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .drawCompleted
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard generation == limitFeedbackGeneration else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                limitFeedbackPulses = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            guard generation == limitFeedbackGeneration else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                limitFeedback = nil
            }
        }
    }

    @ViewBuilder
    private func limitFeedbackView(_ cause: GlobalPowerLimitCause) -> some View {
        switch cause {
        case .groups(let groups):
            HStack(spacing: 5) {
                ForEach(groups) { group in
                    GroupBadge(group: group, size: 20, fontSize: 9)
                        .scaleEffect(
                            limitFeedbackPulses && !reduceMotion ? 1.12 : 1
                        )
                }
                Text(limitText(for: groups))
                    .lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(PrototypePalette.warning)
        case .visualWindow:
            Label(
                languageStore.language.localized("Límite de ±3 EV"),
                systemImage: "exclamationmark.circle.fill"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(PrototypePalette.warning)
            .scaleEffect(limitFeedbackPulses && !reduceMotion ? 1.04 : 1)
        }
    }

    private func limitText(for groups: [GodoxGroup]) -> String {
        let labels = groups.map(\.label).joined(separator: ", ")
        switch languageStore.language {
        case .es:
            return groups.count == 1 ? "Límite: grupo \(labels)" : "Límite: grupos \(labels)"
        case .en:
            return groups.count == 1 ? "Limit: group \(labels)" : "Limit: groups \(labels)"
        }
    }
}

private struct GlobalStepButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let enabled: Bool
    let action: () -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(stepButtonSurface(enabled: enabled))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(languageStore.language.localizedMessage(accessibilityLabel))
    }
}

private struct GlobalStateToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let enabled: Bool
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(languageStore.language.localized(title))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.35)
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? PrototypePalette.brandRing : PrototypePalette.primaryText)
            .frame(width: 58, height: 46)
        }
        .toggleStyle(GlobalStateToggleStyle())
        .disabled(!enabled)
        .accessibilityLabel(languageStore.language.localized(title))
        .accessibilityValue(languageStore.language.localized(isOn ? "Activo" : "Apagado"))
    }
}

private struct MultiModeButton: View {
    let isActive: Bool
    let enabled: Bool
    let action: () -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: isActive ? "bolt.circle.fill" : "bolt.circle")
                        .font(.system(size: 15, weight: .semibold))
                }

                Text(verbatim: "MULTI")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.35)
                    .lineLimit(1)
            }
            .foregroundStyle(
                isActive ? PrototypePalette.brandRing : PrototypePalette.primaryText
            )
            .frame(width: 58, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? PrototypePalette.brandTile : PrototypePalette.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        isActive ? PrototypePalette.accent : PrototypePalette.dividerStrong,
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(languageStore.language.localized(
            isActive
                ? "Desactiva Multi y devuelve todos los grupos a Manual."
                : "Activa Multi en todos los grupos compatibles que estén activos."
        ))
        .accessibilityLabel(languageStore.language.localized(
            isActive ? "Desactivar Multi" : "Activar Multi"
        ))
        .accessibilityValue(languageStore.language.localized(
            isActive ? "Multi activo" : "Multi inactivo"
        ))
        .accessibilityHint(languageStore.language.localized(
            isActive
                ? "Todos los grupos volverán activos en modo Manual."
                : "Los grupos activos compatibles entrarán juntos a Multi."
        ))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct GlobalStateToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            configuration.isOn
                                ? PrototypePalette.brandTile
                                : PrototypePalette.surface
                        )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            configuration.isOn
                                ? PrototypePalette.accent
                                : PrototypePalette.dividerStrong,
                            lineWidth: 1
                        )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct MultiFlashConsole: View {
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        ViewThatFits(in: .horizontal) {
            desktopLayout
            compactLayout
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PrototypePalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            controller.hasPendingMultiFlashChange
                                ? PrototypePalette.warning.opacity(0.58)
                                : PrototypePalette.dividerStrong,
                            lineWidth: 1
                        )
                }
        )
        .accessibilityElement(children: .contain)
    }

    private var desktopLayout: some View {
        HStack(spacing: 10) {
            MultiConsoleIdentity(controller: controller)
                .frame(width: 100)

            sectionDivider

            MultiConsolePowerRail(controller: controller)
                .frame(minWidth: 270, idealWidth: 290)

            sectionDivider

            MultiConsoleNumericControl(
                title: "DESTELLOS",
                unit: "×",
                value: controller.multiFlashDraft.count,
                range: controller.multiFlashCountRange,
                enabled: controller.canEditMultiFlashSettings,
                setValue: controller.setMultiFlashCount,
                controller: controller
            )
            .frame(width: 145)

            sectionDivider

            MultiConsoleNumericControl(
                title: "FRECUENCIA",
                unit: "Hz",
                value: controller.multiFlashDraft.hertz,
                range: MultiFlashSettings.hertzRange,
                enabled: controller.canEditMultiFlashSettings,
                setValue: controller.setMultiFlashHertz,
                controller: controller
            )
            .frame(width: 145)

            sectionDivider

            MultiConsoleOutcome(controller: controller)
                .frame(minWidth: 210, idealWidth: 230)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var compactLayout: some View {
        VStack(spacing: 11) {
            HStack(spacing: 12) {
                MultiConsoleIdentity(controller: controller)
                    .frame(width: 112)
                sectionDivider
                MultiConsoleOutcome(controller: controller)
            }

            Rectangle()
                .fill(PrototypePalette.divider)
                .frame(height: 1)

            HStack(alignment: .top, spacing: 12) {
                MultiConsolePowerRail(controller: controller)
                    .frame(minWidth: 260)
                sectionDivider
                MultiConsoleNumericControl(
                    title: "DESTELLOS",
                    unit: "×",
                    value: controller.multiFlashDraft.count,
                    range: controller.multiFlashCountRange,
                    enabled: controller.canEditMultiFlashSettings,
                    setValue: controller.setMultiFlashCount,
                    controller: controller
                )
                .frame(minWidth: 140)
                MultiConsoleNumericControl(
                    title: "FRECUENCIA",
                    unit: "Hz",
                    value: controller.multiFlashDraft.hertz,
                    range: MultiFlashSettings.hertzRange,
                    enabled: controller.canEditMultiFlashSettings,
                    setValue: controller.setMultiFlashHertz,
                    controller: controller
                )
                .frame(minWidth: 140)
            }
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(PrototypePalette.divider)
            .frame(width: 1, height: 112)
    }
}

@MainActor
private struct MultiConsoleIdentity: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(
                    controller.multiFlashGroups.isEmpty
                        ? PrototypePalette.secondaryText
                        : PrototypePalette.primaryText
                )

            Text(verbatim: "MULTI")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(PrototypePalette.primaryText)

            Text(languageStore.language.localized("AJUSTE GLOBAL"))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(PrototypePalette.accent)

            Capsule(style: .continuous)
                .fill(
                    controller.hasPendingMultiFlashChange
                        ? PrototypePalette.warning
                        : PrototypePalette.accent.opacity(0.72)
                )
                .frame(width: 22, height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(languageStore.language.localized("Configuración Multi"))
        .accessibilityValue(languageStore.language.localized(
            controller.multiFlashGroups.isEmpty ? "Multi inactivo" : "Multi activo"
        ))
    }
}

@MainActor
private struct MultiConsolePowerRail: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(languageStore.language.localized("POTENCIA"))
                    .font(.caption2.weight(.bold))
                    .tracking(0.75)
                    .foregroundStyle(PrototypePalette.secondaryText)
                Spacer()
                Text(languageStore.language.localized("Pasos enteros · máximo 1/4"))
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundStyle(PrototypePalette.muted)
            }

            HStack(spacing: 2) {
                ForEach(controller.allowedMultiFlashPowers) { power in
                    let isSelected = power == controller.multiFlashDraft.power
                    Button {
                        controller.setMultiFlashPower(power)
                    } label: {
                        VStack(spacing: 5) {
                            Text(powerFraction(power))
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(
                                    isSelected
                                        ? PrototypePalette.primaryText
                                        : PrototypePalette.secondaryText
                                )
                                .lineLimit(1)

                            Circle()
                                .fill(
                                    isSelected
                                        ? PrototypePalette.accent
                                        : PrototypePalette.surfaceRaised
                                )
                                .frame(width: isSelected ? 13 : 9, height: isSelected ? 13 : 9)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            isSelected
                                                ? PrototypePalette.primaryText.opacity(0.72)
                                                : PrototypePalette.dividerStrong,
                                            lineWidth: 1
                                        )
                                }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!controller.canEditMultiFlashSettings)
                    .accessibilityLabel(languageStore.language.localizedFormat(
                        "Potencia Multi %@",
                        power.label
                    ))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(PrototypePalette.dividerStrong)
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .offset(y: -6)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(powerFraction(controller.multiFlashDraft.power))
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
                Text(powerOffset(controller.multiFlashDraft.power))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text("EV")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(PrototypePalette.secondaryText)
                Spacer(minLength: 0)
            }
            .monospacedDigit()
            .foregroundStyle(
                controller.canEditMultiFlashSettings
                    ? PrototypePalette.primaryText
                    : PrototypePalette.muted
            )
        }
    }

    private func powerFraction(_ power: ManualPower) -> String {
        power.label.split(separator: " ").first.map(String.init) ?? power.label
    }

    private func powerOffset(_ power: ManualPower) -> String {
        let components = power.label.split(separator: " ")
        return components.count > 1 ? String(components[1]) : "+0.0"
    }
}

@MainActor
private struct MultiConsoleNumericControl: View {
    let title: String
    let unit: String
    let value: Int
    let range: ClosedRange<Int>
    let enabled: Bool
    let setValue: (Int) -> Void
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore
    @State private var interactiveEditToken: GodoxSessionController.InteractiveEditToken?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(languageStore.language.localized(title))
                .font(.caption2.weight(.bold))
                .tracking(0.75)
                .foregroundStyle(PrototypePalette.secondaryText)

            HStack(spacing: 6) {
                stepButton(systemImage: "minus", value: max(range.lowerBound, value - 1))
                    .disabled(!enabled || value <= range.lowerBound)

                Text("\(value)\(unit == "×" ? "×" : "")")
                    .font(.system(size: 27, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(enabled ? PrototypePalette.primaryText : PrototypePalette.muted)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if unit != "×" {
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PrototypePalette.secondaryText)
                }

                stepButton(systemImage: "plus", value: min(range.upperBound, value + 1))
                    .disabled(!enabled || value >= range.upperBound)
            }

            Slider(
                value: Binding(
                    get: { Double(min(max(value, range.lowerBound), range.upperBound)) },
                    set: { setValue(Int($0.rounded())) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1,
                onEditingChanged: editingChanged
            )
            .tint(PrototypePalette.accent)
            .disabled(!enabled)
            .accessibilityLabel(languageStore.language.localized(title))
            .accessibilityValue("\(value) \(unit)")

            HStack {
                Text("\(range.lowerBound)\(unit)")
                Spacer()
                Text("\(range.upperBound)\(unit)")
            }
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .foregroundStyle(PrototypePalette.muted)
        }
        .onDisappear(perform: finishInteractiveEdit)
        .onChange(of: enabled) { isEnabled in
            if !isEnabled { finishInteractiveEdit() }
        }
    }

    private func stepButton(systemImage: String, value: Int) -> some View {
        Button {
            setValue(value)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(stepButtonSurface(enabled: enabled))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(systemImage == "plus" ? "+1" : "−1")")
    }

    private func editingChanged(_ isEditing: Bool) {
        if isEditing {
            if interactiveEditToken == nil {
                interactiveEditToken = controller.beginInteractiveEdit()
            }
        } else {
            finishInteractiveEdit()
        }
    }

    private func finishInteractiveEdit() {
        guard let token = interactiveEditToken else { return }
        interactiveEditToken = nil
        controller.endInteractiveEdit(token)
    }
}

@MainActor
private struct MultiConsoleOutcome: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .font(.caption2.weight(.semibold))
                Text(languageStore.language.localized("OBTURACIÓN MÍNIMA"))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.55)
                Spacer(minLength: 4)
                Text(String(format: "≥ %.3f s", controller.multiFlashDraft.minimumExposureSeconds))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PrototypePalette.primaryText)
            }
            .foregroundStyle(PrototypePalette.secondaryText)

            Rectangle()
                .fill(PrototypePalette.divider)
                .frame(height: 1)

            HStack(alignment: .center, spacing: 6) {
                Text(languageStore.language.localized("GRUPOS MULTI"))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.55)
                    .foregroundStyle(PrototypePalette.secondaryText)

                Spacer(minLength: 2)

                ForEach(multiWorkspaceGroups) { group in
                    MultiParticipantButton(group: group, controller: controller)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(restrictionColor)
                    .frame(width: 6, height: 6)
                Text(restrictionText)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if controller.hasPendingMultiFlashChange {
                Text(languageStore.language.localized("PENDIENTE GLOBAL"))
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .tracking(0.45)
                    .foregroundStyle(PrototypePalette.warning)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var multiWorkspaceGroups: [GodoxGroup] {
        controller.workingGroups.filter {
            controller.transmitterProfile.supportedMultiGroups.contains($0)
        }
    }

    private var restrictionColor: Color {
        controller.hasUnverifiedMultiFlashCountLimit ||
            controller.hasConservativeMultiFlashCountLimit
            ? PrototypePalette.warning
            : PrototypePalette.success
    }

    private var restrictionText: String {
        if controller.multiFlashGroups.isEmpty {
            return languageStore.language.localized(
                "Añade un grupo compatible para activar la ráfaga."
            )
        }
        if controller.hasConservativeMultiFlashCountLimit {
            return languageStore.language.localizedFormat(
                controller.hasUnverifiedMultiFlashCountLimit
                    ? "Límite conservador parcial · 51–59 Hz no publicado · máximo %lld · sin HSS"
                    : "Límite conservador · 51–59 Hz no publicado · máximo %lld · sin HSS",
                controller.multiFlashMaximumCount
            )
        }
        if controller.hasVerifiedMultiFlashCountLimit,
           controller.hasUnverifiedMultiFlashCountLimit {
            return languageStore.language.localizedFormat(
                "Límite verificado parcial · máximo %lld · sin HSS",
                controller.multiFlashMaximumCount
            )
        }
        if controller.hasVerifiedMultiFlashCountLimit {
            return languageStore.language.localizedFormat(
                "Límite verificado · máximo %lld · sin HSS",
                controller.multiFlashMaximumCount
            )
        }
        return languageStore.language.localized(
            "Límite por modelo pendiente de validar · sin HSS"
        )
    }
}

@MainActor
private struct MultiParticipantButton: View {
    let group: GodoxGroup
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore

    private var isParticipating: Bool {
        controller.groupDraft(group).draft.operatingMode == .multi
    }

    private var canToggle: Bool {
        controller.canSetMultiFlashParticipation(group, enabled: !isParticipating)
    }

    var body: some View {
        let identity = group.visualIdentity
        let fill = Color(estroboRGB: identity.fillRGB)
        let foreground = Color(estroboRGB: identity.foregroundRGB)

        Button {
            controller.setMultiFlashParticipation(group, enabled: !isParticipating)
        } label: {
            Text(group.label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isParticipating ? foreground : PrototypePalette.secondaryText)
                .frame(width: 29, height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isParticipating ? fill : PrototypePalette.surfaceRaised)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isParticipating ? fill.opacity(0.92) : PrototypePalette.dividerStrong,
                            lineWidth: 1
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if controller.groupDraft(group).hasPendingModeChange {
                        Circle()
                            .fill(PrototypePalette.warning)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
        .help(participationHelp)
        .accessibilityLabel(participationHelp)
        .accessibilityValue(languageStore.language.localized(
            isParticipating ? "Participa en Multi" : "Fuera de Multi"
        ))
        .accessibilityAddTraits(isParticipating ? .isSelected : [])
    }

    private var participationHelp: String {
        if isParticipating {
            if controller.multiFlashGroups.count == 1 {
                return languageStore.language.localized(
                    "Desactiva Multi desde el botón MULTI."
                )
            }
            return languageStore.language.localizedFormat(
                "Quitar grupo %@ de Multi",
                group.label
            )
        }
        if !controller.supportsMultiFlash(group) {
            return languageStore.language.localizedFormat(
                "El grupo %@ no admite Multi con esta configuración",
                group.label
            )
        }
        guard !controller.multiFlashGroups.isEmpty else {
            return languageStore.language.localized(
                "Activa Multi desde el botón MULTI."
            )
        }
        return languageStore.language.localizedFormat("Añadir grupo %@ a Multi", group.label)
    }
}

// MARK: - Common chrome

private enum HeaderMetrics {
    static let controlHeight: CGFloat = 32
}

@MainActor
private struct PrototypeHeader: View {
    @ObservedObject var controller: GodoxSessionController
    @Binding var variant: PrototypeVariant
    @EnvironmentObject private var languageStore: AppLanguageStore
    @State private var showsConfiguration = false
    @State private var showsPresets = false

    var body: some View {
        HStack(spacing: 12) {
            EstroboBrandLockup()
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PrototypePalette.primaryText)

                Text(languageStore.language.localizedMessage(controller.statusTitle))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PrototypePalette.primaryText)
                    .lineLimit(1)

                if controller.isSimulation {
                    Text(languageStore.language.localized("mock.badge"))
                        .prototypeBadge(
                            foreground: PrototypePalette.accent,
                            background: PrototypePalette.accent.opacity(0.12)
                        )
                } else {
                    StatusDot(phase: controller.phase)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: HeaderMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PrototypePalette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(PrototypePalette.dividerStrong, lineWidth: 1)
                    }
            )
            .accessibilityElement(children: .combine)

            if controller.showsControlWorkspace {
                Button {
                    controller.synchronizeValuesToRadio()
                } label: {
                    HStack(spacing: 7) {
                        if controller.isSynchronizingValues {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(verbatim: "Sync")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(QuietButtonStyle(height: HeaderMetrics.controlHeight))
                .disabled(!controller.canSynchronizeValues)
                .help(languageStore.language.localizedMessage(
                    controller.valueSynchronizationBlockReason
                        ?? "Envía todos los valores actuales de Estrobo al radio para los grupos de trabajo."
                ))
                .accessibilityLabel(Text(verbatim: "Sync"))
                .accessibilityHint(languageStore.language.localized(
                    "Envía los valores de Estrobo al radio; no lee ni reemplaza la configuración local."
                ))

                Button {
                    controller.disconnect()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32)
                }
                .buttonStyle(QuietButtonStyle(height: HeaderMetrics.controlHeight))
                .disabled(!controller.canDisconnect)
                .help(languageStore.language.localized("Desconectar"))
                .accessibilityLabel(languageStore.language.localized("Desconectar"))
            }

            Spacer(minLength: 4)

            if controller.hasCompletedOnboarding {
                Button {
                    showsPresets = true
                } label: {
                    Label(
                        languageStore.language.localized("Presets"),
                        systemImage: "square.stack.3d.up"
                    )
                    .lineLimit(1)
                }
                .buttonStyle(QuietButtonStyle(height: HeaderMetrics.controlHeight))
                .disabled(!controller.canManagePresets)
                .help(languageStore.language.localized(
                    controller.canManagePresets
                        ? "Guarda, carga y sincroniza configuraciones con nombre."
                        : "Espera a que termine la operación actual."
                ))
                .sheet(isPresented: $showsPresets) {
                    PresetLibrarySheet(controller: controller)
                }
            }

            AppearanceToggle()
                .frame(height: HeaderMetrics.controlHeight)

            Button {
                showsConfiguration = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32)
            }
            .buttonStyle(QuietButtonStyle(height: HeaderMetrics.controlHeight))
            .accessibilityLabel(languageStore.language.localized("Configuración"))
            .sheet(isPresented: $showsConfiguration) {
                LocalConfigurationPopover(
                    controller: controller,
                    variant: $variant
                )
            }
        }
        .padding(.horizontal, 28)
        .frame(minHeight: 82)
    }
}

@MainActor
private struct PresetLibrarySheet: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.dismiss) private var dismiss

    @State private var presetName = ""
    @State private var actionError: String?
    @State private var presetPendingDeletion: StudioPreset?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageStore.language.localized("Presets"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PrototypePalette.primaryText)
                    Text(languageStore.language.localized(
                        "Guarda los valores de tus grupos y recupéralos en otra sesión."
                    ))
                        .font(.callout)
                        .foregroundStyle(PrototypePalette.secondaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 30)
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel(languageStore.language.localized("Cerrar"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider().overlay(PrototypePalette.dividerStrong)

            VStack(alignment: .leading, spacing: 18) {
                savePresetPanel

                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(PrototypePalette.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isStaticText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(languageStore.language.localized("Presets guardados"))
                            .font(.headline)
                            .foregroundStyle(PrototypePalette.primaryText)
                        Spacer()
                        Text("\(controller.presets.count)")
                            .prototypeBadge(
                                foreground: PrototypePalette.secondaryText,
                                background: PrototypePalette.surfaceRaised
                            )
                            .accessibilityLabel(languageStore.language.localizedFormat(
                                "%lld presets guardados",
                                controller.presets.count
                            ))
                    }

                    if controller.presets.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 9) {
                                ForEach(controller.presets) { preset in
                                    presetRow(preset)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 720, height: 620)
        .background(PrototypePalette.windowBackground)
        .alert(
            languageStore.language.localized("Eliminar preset"),
            isPresented: deleteConfirmationIsPresented
        ) {
            Button(languageStore.language.localized("Cancelar"), role: .cancel) {
                presetPendingDeletion = nil
            }
            Button(languageStore.language.localized("Eliminar"), role: .destructive) {
                deletePendingPreset()
            }
        } message: {
            if let presetPendingDeletion {
                Text(languageStore.language.localizedFormat(
                    "¿Eliminar el preset “%@”? Esta acción no cambia el radio.",
                    presetPendingDeletion.name
                ))
            }
        }
    }

    private var savePresetPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(languageStore.language.localized("Guardar valores actuales"))
                .font(.headline)
                .foregroundStyle(PrototypePalette.primaryText)

            HStack(spacing: 10) {
                TextField(
                    languageStore.language.localized("Nombre del preset"),
                    text: $presetName
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit(savePreset)
                .accessibilityHint(languageStore.language.localized(
                    "Usa un nombre único para identificar esta configuración."
                ))

                Button {
                    savePreset()
                } label: {
                    Label(
                        languageStore.language.localized("Guardar"),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSavePreset)
                .keyboardShortcut(.defaultAction)
            }

            if duplicateName {
                Text(languageStore.language.localized("Ya existe un preset con ese nombre."))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PrototypePalette.warning)
            } else {
                Text(languageStore.language.localized(
                    "Se guardarán potencia, modelado, beep y estado activo de todos los grupos de trabajo."
                ))
                    .font(.caption)
                    .foregroundStyle(PrototypePalette.secondaryText)
            }
        }
        .padding(16)
        .prototypePanel(padding: 0)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(PrototypePalette.muted)
            Text(languageStore.language.localized("Aún no tienes presets"))
                .font(.headline)
                .foregroundStyle(PrototypePalette.primaryText)
            Text(languageStore.language.localized(
                "Escribe un nombre arriba para guardar los valores actuales."
            ))
                .font(.callout)
                .foregroundStyle(PrototypePalette.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .prototypePanel(padding: 18)
        .accessibilityElement(children: .combine)
    }

    private func presetRow(_ preset: StudioPreset) -> some View {
        let isActive = controller.activePresetID == preset.id
        let compatibilityIssue = controller.presetCompatibilityIssue(preset)
        let isCompatible = compatibilityIssue == nil

        return HStack(spacing: 14) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? PrototypePalette.success : PrototypePalette.secondaryText)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(preset.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(PrototypePalette.primaryText)
                    if isActive {
                        Text(languageStore.language.localized("Cargado"))
                            .prototypeBadge(
                                foreground: PrototypePalette.success,
                                background: PrototypePalette.success.opacity(0.12)
                            )
                    } else if !isCompatible {
                        Text(languageStore.language.localized("NO COMPATIBLE"))
                            .prototypeBadge(
                                foreground: PrototypePalette.warning,
                                background: PrototypePalette.warning.opacity(0.12)
                            )
                    }
                }
                Text(presetDetail(preset))
                    .font(.caption)
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                loadPreset(preset, synchronize: false)
            } label: {
                Text(languageStore.language.localized("Cargar en Estrobo"))
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(!controller.canManagePresets || !isCompatible)
            .help(languageStore.language.localizedMessage(
                compatibilityIssue
                    ?? "Carga el preset localmente sin enviar valores al radio."
            ))

            if controller.phase == .ready {
                Button {
                    loadPreset(preset, synchronize: true)
                } label: {
                    Label(
                        languageStore.language.localized("Cargar y sincronizar"),
                        systemImage: "arrow.right.circle"
                    )
                }
                .buttonStyle(ApplyButtonStyle())
                .disabled(
                    !controller.canManagePresets ||
                        !controller.canSynchronizeValues ||
                        !isCompatible
                )
                .help(languageStore.language.localizedMessage(
                    compatibilityIssue
                        ?? controller.valueSynchronizationBlockReason
                        ?? "Carga el preset en Estrobo y envía sus valores al radio."
                ))
            }

            Button(role: .destructive) {
                presetPendingDeletion = preset
            } label: {
                Image(systemName: "trash")
                    .frame(width: 18)
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(!controller.canManagePresets)
            .accessibilityLabel(languageStore.language.localizedFormat(
                "Eliminar preset %@",
                preset.name
            ))
        }
        .padding(14)
        .prototypePanel(padding: 0)
        .accessibilityElement(children: .contain)
    }

    private var trimmedName: String {
        presetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var duplicateName: Bool {
        !trimmedName.isEmpty && controller.presetNameExists(trimmedName)
    }

    private var canSavePreset: Bool {
        controller.canManagePresets && !trimmedName.isEmpty && !duplicateName
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { presetPendingDeletion != nil },
            set: { isPresented in
                if !isPresented { presetPendingDeletion = nil }
            }
        )
    }

    private func presetDetail(_ preset: StudioPreset) -> String {
        let profileName = TransmitterProfile.available
            .first(where: { $0.id == preset.profileID })?
            .name ?? preset.profileID
        let groups = preset.groups.map(\.label).joined(separator: ", ")
        let date = preset.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return languageStore.language.localizedFormat(
            "%@ · grupos %@ · %@",
            languageStore.language.localized(profileName),
            groups,
            date
        )
    }

    private func savePreset() {
        actionError = nil
        guard canSavePreset else { return }
        if controller.savePreset(named: trimmedName) {
            presetName = ""
        } else {
            actionError = languageStore.language.localized(
                "No se pudo guardar el preset en este Mac."
            )
        }
    }

    private func loadPreset(_ preset: StudioPreset, synchronize: Bool) {
        actionError = nil
        if controller.loadPreset(id: preset.id, synchronizeIfConnected: synchronize) {
            dismiss()
        } else {
            actionError = languageStore.language.localized(
                "No se pudo cargar el preset. Revisa el perfil y los grupos de trabajo."
            )
        }
    }

    private func deletePendingPreset() {
        guard let preset = presetPendingDeletion else { return }
        presetPendingDeletion = nil
        actionError = nil
        if !controller.deletePreset(id: preset.id) {
            actionError = languageStore.language.localized(
                "No se pudo eliminar el preset."
            )
        }
    }
}

private struct EstroboBrandLockup: View {
    var body: some View {
        Group {
            if let lockupImage = EstroboBrandAssets.lockupImage {
                Image(nsImage: lockupImage)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 192, height: 36)
                    .accessibilityHidden(true)
            } else {
                EstroboGeneratedBrandLockup()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("estrobo")
    }
}

private struct EstroboGeneratedBrandLockup: View {
    var body: some View {
        HStack(spacing: 11) {
            EstroboMark()
                .frame(width: 46, height: 46)

            Text("estrobo")
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .tracking(-0.9)
                .foregroundStyle(PrototypePalette.brandWordmark)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(PrototypePalette.accent)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                        .padding(.trailing, 3)
                }
        }
    }
}

private struct EstroboMark: View {
    var body: some View {
        Group {
            if let markImage = EstroboBrandAssets.markImage {
                Image(nsImage: markImage)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .accessibilityHidden(true)
            } else {
                EstroboGeneratedMark()
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: PrototypePalette.brandShadow, radius: 7, x: 0, y: 3)
    }
}

private struct EstroboGeneratedMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PrototypePalette.brandTile)

            Circle()
                .trim(from: 0.06, to: 0.82)
                .stroke(
                    PrototypePalette.brandRing,
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                )
                .rotationEffect(.degrees(38))
                .padding(8)

            Image(systemName: "bolt.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PrototypePalette.accent)
                .offset(x: -2, y: 2)

            EstroboRadioWaveShape()
                .stroke(
                    PrototypePalette.accent,
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                )
                .frame(width: 18, height: 18)
                .offset(x: 10, y: -9)
        }
    }
}

private struct EstroboRadioWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.minX, y: rect.maxY)
        for radius in [CGFloat(5), 9, 13] {
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(-82),
                endAngle: .degrees(-8),
                clockwise: false
            )
        }
        return path
    }
}

private struct AppearanceToggle: View {
    @EnvironmentObject private var appearanceStore: AppAppearanceStore
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            appearanceButton(.light, systemImage: "sun.max")
            appearanceButton(.dark, systemImage: "moon")
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(PrototypePalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(PrototypePalette.dividerStrong, lineWidth: 1)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(languageStore.language.localized("appearance.title"))
    }

    private func appearanceButton(
        _ appearance: AppAppearance,
        systemImage: String
    ) -> some View {
        Button {
            appearanceStore.select(appearance)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    isSelected(appearance)
                        ? PrototypePalette.accent
                        : PrototypePalette.secondaryText
                )
                .frame(width: 34, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isSelected(appearance)
                                ? PrototypePalette.surfaceRaised
                                : .clear
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            languageStore.language.localized(
                appearance == .light ? "appearance.switchToLight" : "appearance.switchToDark"
            )
        )
        .accessibilityAddTraits(isSelected(appearance) ? .isSelected : [])
    }

    private func isSelected(_ appearance: AppAppearance) -> Bool {
        if appearanceStore.appearance == appearance { return true }
        guard appearanceStore.appearance == .system else { return false }
        return (appearance == .light && colorScheme == .light) ||
            (appearance == .dark && colorScheme == .dark)
    }
}

private struct LanguageToggle: View {
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        HStack(spacing: 2) {
            languageButton(.es, label: "ES")
            languageButton(.en, label: "EN")
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(PrototypePalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(PrototypePalette.dividerStrong, lineWidth: 1)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Idioma")
    }

    private func languageButton(_ language: AppLanguage, label: String) -> some View {
        Button {
            languageStore.select(language)
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    languageStore.language == language
                        ? PrototypePalette.primaryText
                        : PrototypePalette.secondaryText
                )
                .frame(width: 38, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            languageStore.language == language
                                ? PrototypePalette.surfaceRaised
                                : .clear
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language == .es ? "Español" : "English")
        .accessibilityAddTraits(languageStore.language == language ? .isSelected : [])
    }
}

@MainActor
private struct LocalConfigurationPopover: View {
    @ObservedObject var controller: GodoxSessionController
    @Binding var variant: PrototypeVariant
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsSavedTransmitters = false

    private let groupColumns = [
        GridItem(.adaptive(minimum: 42, maximum: 48), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageStore.language.localized("Configuración"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PrototypePalette.primaryText)
                    Text(languageStore.language.localized("Preferencias locales para este Mac"))
                        .font(.callout)
                        .foregroundStyle(PrototypePalette.secondaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 30)
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel(languageStore.language.localized("Cerrar"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider().overlay(PrototypePalette.dividerStrong)

            ScrollView {
                VStack(spacing: 0) {
                    SettingsRow(title: "Idioma") {
                        SettingsLanguagePicker()
                    }

                    SettingsDivider()

                    SettingsRow(title: "appearance.title") {
                        VStack(alignment: .leading, spacing: 7) {
                            SettingsAppearancePicker()
                            Text(languageStore.language.localized("appearance.help"))
                                .font(.caption)
                                .foregroundStyle(PrototypePalette.secondaryText)
                        }
                    }

                    SettingsDivider()

                    SettingsRow(title: "Vista", alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            WorkspaceVariantSelector(
                                variant: $variant,
                                help: "Cambia la vista del espacio de trabajo."
                            )
                            .frame(maxWidth: 430)

                            Text(languageStore.language.localized(
                                "El cambio se aplica de inmediato y se conserva para la próxima sesión."
                            ))
                                .font(.caption)
                                .foregroundStyle(PrototypePalette.secondaryText)
                        }
                    }

                    SettingsDivider()

                    SettingsRow(title: "Envío de cambios") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(
                                languageStore.language.localized("Envío de cambios"),
                                selection: changeDeliveryModeBinding
                            ) {
                                Text(languageStore.language.localized("Automático"))
                                    .tag(ChangeDeliveryMode.automatic)
                                Text(languageStore.language.localized("Con botón"))
                                    .tag(ChangeDeliveryMode.manual)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .disabled(!controller.canChangeDeliveryMode)

                            Text(languageStore.language.localized(changeDeliveryModeDetail))
                                .font(.caption)
                                .foregroundStyle(PrototypePalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SettingsDivider()

                    SettingsRow(title: "Compatibilidad de grupos", alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(languageStore.language.localized(
                                controller.transmitterProfile.name
                            ))
                                .font(.callout.weight(.medium))
                                .foregroundStyle(PrototypePalette.primaryText)

                            Text(languageStore.language.localized(
                                "Define los grupos y funciones disponibles; no representa un transmisor guardado."
                            ))
                                .font(.caption)
                                .foregroundStyle(PrototypePalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SettingsDivider()

                    SettingsRow(title: "Transmisores guardados", alignment: .top) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(savedTransmittersSummary)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(PrototypePalette.primaryText)

                                Text(languageStore.language.localized(
                                    "Administra los radios que se han conectado y guardado en este Mac."
                                ))
                                    .font(.caption)
                                    .foregroundStyle(PrototypePalette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            Button {
                                showsSavedTransmitters = true
                            } label: {
                                Label(
                                    languageStore.language.localized("Transmisores guardados…"),
                                    systemImage: "externaldrive.badge.wifi"
                                )
                            }
                            .buttonStyle(QuietButtonStyle())
                        }
                    }

                    SettingsDivider()

                    SettingsRow(title: "Grupos de trabajo", alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                dismiss()
                                controller.beginWorkspaceConfiguration()
                            } label: {
                                Label(
                                    languageStore.language.localized(
                                        "Reconfigurar espacio de trabajo…"
                                    ),
                                    systemImage: "slider.horizontal.3"
                                )
                            }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(!controller.canConfigureWorkspace)
                            .help(languageStore.language.localized(
                                controller.canConfigureWorkspace
                                    ? "Edita los grupos y flashes sin desconectar el radio."
                                    : "Espera a que termine la operación actual."
                            ))

                            Text(languageStore.language.localized(
                                "Abrir o cancelar no envía valores. Las nuevas ediciones se sincronizan con el flujo normal."
                            ))
                                .font(.caption)
                                .foregroundStyle(PrototypePalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SettingsDivider()

                    SettingsRow(title: "Grupos visibles", alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            LazyVGrid(columns: groupColumns, spacing: 7) {
                                ForEach(controller.workingGroups) { group in
                                    let isVisible = controller.visibleGroups.contains(group)
                                    Button {
                                        controller.setGroupVisible(
                                            group,
                                            isVisible: !isVisible
                                        )
                                    } label: {
                                        GroupVisibilityTile(
                                            group: group,
                                            isVisible: isVisible
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        languageStore.language.localizedFormat(
                                            "Grupo %@",
                                            group.label
                                        )
                                    )
                                    .accessibilityValue(
                                        languageStore.language == .es
                                            ? (isVisible ? "Visible" : "Oculto")
                                            : (isVisible ? "Visible" : "Hidden")
                                    )
                                    .accessibilityAddTraits(isVisible ? .isSelected : [])
                                }
                            }
                            Text(languageStore.language.localized(
                                "Siempre debe quedar al menos uno. Esta selección se conserva en este Mac."
                            ))
                                .font(.caption)
                                .foregroundStyle(PrototypePalette.secondaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(width: 760, height: 600)
        .background(PrototypePalette.windowBackground)
        .sheet(isPresented: $showsSavedTransmitters) {
            SavedTransmittersSheet(controller: controller)
        }
    }

    private var changeDeliveryModeBinding: Binding<ChangeDeliveryMode> {
        Binding(
            get: { controller.changeDeliveryMode },
            set: { controller.setChangeDeliveryMode($0) }
        )
    }

    private var changeDeliveryModeDetail: String {
        switch controller.changeDeliveryMode {
        case .automatic:
            "Agrupa cambios durante 0.7 s y los envía uno por uno."
        case .manual:
            "Los cambios esperan hasta que pulses Aplicar."
        }
    }

    private var savedTransmittersSummary: String {
        if controller.savedRadios.count == 1 {
            return languageStore.language.localized("1 transmisor guardado")
        }
        return languageStore.language.localizedFormat(
            "%lld transmisores guardados",
            controller.savedRadios.count
        )
    }

}

private struct SettingsRow<Content: View>: View {
    let title: String
    let alignment: VerticalAlignment
    let content: Content
    @EnvironmentObject private var languageStore: AppLanguageStore

    init(
        title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 24) {
            Text(languageStore.language.localized(title))
                .font(.headline)
                .foregroundStyle(PrototypePalette.primaryText)
                .frame(width: 180, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(PrototypePalette.dividerStrong)
    }
}

struct SettingsLanguagePicker: View {
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        HStack(spacing: 0) {
            option(.en, label: "English")
            option(.es, label: "Español")
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PrototypePalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PrototypePalette.dividerStrong, lineWidth: 1)
                }
        )
    }

    private func option(_ language: AppLanguage, label: String) -> some View {
        Button {
            languageStore.select(language)
        } label: {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(PrototypePalette.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            languageStore.language == language
                                ? PrototypePalette.surfaceRaised
                                : .clear
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(languageStore.language == language ? .isSelected : [])
    }
}

private struct SettingsAppearancePicker: View {
    @EnvironmentObject private var appearanceStore: AppAppearanceStore
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        Picker(
            languageStore.language.localized("appearance.title"),
            selection: appearanceBinding
        ) {
            ForEach(AppAppearance.allCases) { appearance in
                Text(languageStore.language.localized(appearance.localizationKey))
                    .tag(appearance)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { appearanceStore.appearance },
            set: { appearanceStore.select($0) }
        )
    }
}

@MainActor
private struct ConnectionPanel: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore

    private var isSessionSurfaceCompact: Bool {
        switch controller.phase {
        case .ready, .applying, .disconnecting:
            true
        default:
            false
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(phase: controller.phase)

            VStack(alignment: .leading, spacing: 1) {
                Text(languageStore.language.localizedMessage(controller.statusTitle))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PrototypePalette.primaryText)
                    .lineLimit(1)
                Text(languageStore.language.localizedMessage(statusDetail))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if controller.canCancelConnectionAttempt {
                Button {
                    controller.cancelConnectionAttempt()
                } label: {
                    Text(languageStore.language.localized("Cancelar"))
                }
                .buttonStyle(QuietButtonStyle())
            } else if controller.phase == .disconnecting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(languageStore.language.localized(
                        "Liberando enlace Bluetooth"
                    ))
            } else if isSessionSurfaceCompact {
                Button {
                    controller.disconnect()
                } label: {
                    Text(languageStore.language.localized("Desconectar"))
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(!controller.canDisconnect)
            } else {
                Text(languageStore.language.localized("PASO 1 · CONECTAR RADIO"))
                    .prototypeBadge(
                        foreground: PrototypePalette.warning,
                        background: PrototypePalette.warning.opacity(0.12)
                    )
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PrototypePalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(PrototypePalette.divider, lineWidth: 1)
                }
        )
    }

    private var statusDetail: String {
        switch controller.phase {
        case .ready:
            return controller.readyConnectionDetail
        case .applying:
            return "Escrituras serializadas en curso"
        case .scanning:
            return "Buscando transmisores GD o Ami cercanos"
        case .authenticating:
            return "Autenticando directamente con el radio"
        case .synchronizing:
            return controller.isSynchronizingValues
                ? "Enviando valores de Estrobo al radio"
                : "Autenticando directamente con el radio"
        case .disconnecting:
            return controller.connectionRecoveryMessage ?? "Liberando el enlace Bluetooth"
        case .failed(let message), .unavailable(let message):
            return message
        default:
            return "Selecciona un radio e introduce su código"
        }
    }
}

@MainActor
private struct ConnectionSetupFlow: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore
    @State private var showsSavedTransmitters = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(languageStore.language.localized("Busca y conecta tu radio"))
                    .font(.system(size: 20, weight: .semibold))
                Text(languageStore.language.localized(
                    "Completa este paso para habilitar los controles del flash"
                ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if controller.hasCompletedOnboarding {
                workingGroupsSummary
            }

            if controller.isSynchronizingValues {
                valueSynchronizationProgress
            }

            if !controller.savedRadios.isEmpty {
                savedTransmittersCard
            }

            HStack(spacing: 8) {
                Button {
                    controller.startScanning()
                } label: {
                    Text(languageStore.language.localized(searchButtonTitle))
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(connectionLocked || controller.phase == .scanning)

                if controller.phase == .scanning {
                    ProgressView()
                        .controlSize(.small)
                }

                if controller.canCancelConnectionAttempt {
                    Button {
                        controller.cancelConnectionAttempt()
                    } label: {
                        Text(languageStore.language.localized("Cancelar"))
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }

            Picker("Radio", selection: deviceSelection) {
                Text(languageStore.language.localized(devicePlaceholder))
                    .tag(Optional<UUID>.none)
                ForEach(controller.devices) { device in
                    Text("\(device.name) · \(device.rssi) dBm · …\(controller.deviceIdentifierSuffix(device))")
                        .tag(Optional(device.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(controller.devices.isEmpty || connectionLocked)

            if controller.hasDuplicateDeviceNames {
                Label {
                    Text(languageStore.language.localized(
                        "Hay radios con el mismo nombre. Elige usando RSSI y el sufijo UUID; estos datos ayudan a distinguirlos, pero no autentican el transmisor."
                    ))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PrototypePalette.warning)
                .fixedSize(horizontal: false, vertical: true)
            }

            SecureField(
                languageStore.language.localized("Código del radio · 6 dígitos"),
                text: $controller.radioCode
            )
                .textFieldStyle(.roundedBorder)
                .privacySensitive()
                .disabled(connectionLocked)
                .onSubmit(connectIfPossible)

            Toggle(isOn: $controller.rememberSelectedRadio) {
                Text(languageStore.language.localized(
                    "Recordar este radio y su código en este Mac"
                ))
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 11, weight: .medium))
            .disabled(connectionLocked)

            Button {
                controller.connectSelectedDevice()
            } label: {
                Text(languageStore.language.localized(connectionButtonTitle))
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(!canConnect)

            Text(languageStore.language.localized(
                "Si activas Recordar, el código se guarda localmente y sin cifrar en este Mac. Nunca se envía a Internet. No reutilices un PIN personal."
            ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(languageStore.language.localized(
                "El radio admite una sola conexión Bluetooth a la vez. Cierra antes cualquier otra app conectada al transmisor."
            ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: 440)
        .prototypePanel(padding: 0)
        .sheet(isPresented: $showsSavedTransmitters) {
            SavedTransmittersSheet(controller: controller)
        }
    }

    private var devicePlaceholder: String {
        controller.devices.isEmpty ? "Ningún radio encontrado" : "Selecciona un radio"
    }

    private var deviceSelection: Binding<UUID?> {
        Binding(
            get: { controller.selectedDeviceID },
            set: { controller.selectDevice($0) }
        )
    }

    private var searchButtonTitle: String {
        if controller.phase == .scanning { return "Escaneando…" }
        return "Buscar radios"
    }

    private var savedTransmittersCard: some View {
        HStack(spacing: 10) {
            Image(systemName: discoveredSavedTransmitterCount > 0
                ? "dot.radiowaves.left.and.right"
                : "externaldrive.badge.wifi")
                .foregroundStyle(
                    discoveredSavedTransmitterCount > 0
                        ? PrototypePalette.success
                        : PrototypePalette.secondaryText
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(savedTransmittersSummary)
                    .font(.system(size: 12, weight: .semibold))
                Text(savedTransmittersDiscoverySummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                showsSavedTransmitters = true
            } label: {
                Text(languageStore.language.localized("Ver transmisores…"))
            }
            .buttonStyle(QuietButtonStyle())
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var discoveredSavedTransmitterCount: Int {
        controller.savedRadios.filter {
            controller.isSavedRadioDiscovered($0.deviceID)
        }.count
    }

    private var savedTransmittersSummary: String {
        if controller.savedRadios.count == 1 {
            return languageStore.language.localized("1 transmisor guardado")
        }
        return languageStore.language.localizedFormat(
            "%lld transmisores guardados",
            controller.savedRadios.count
        )
    }

    private var savedTransmittersDiscoverySummary: String {
        if discoveredSavedTransmitterCount == 0 {
            return languageStore.language.localized(
                "Pulsa Buscar para encontrarlos."
            )
        }
        if discoveredSavedTransmitterCount == 1 {
            return languageStore.language.localized(
                "1 encontrado en la última búsqueda"
            )
        }
        return languageStore.language.localizedFormat(
            "%lld encontrados en la última búsqueda",
            discoveredSavedTransmitterCount
        )
    }

    private var connectionButtonTitle: String {
        switch controller.phase {
        case .connecting, .discovering, .authenticating, .synchronizing:
            controller.phase.title
        default:
            controller.hasCompletedOnboarding ? "Conectar y sincronizar" : "Conectar"
        }
    }

    private var workingGroupsSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PrototypePalette.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(languageStore.language.localizedFormat(
                    "Al conectar, Estrobo enviará sus valores al radio: %@.",
                    controller.workingGroups.map(\.label).joined(separator: ", ")
                ))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PrototypePalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(workingGroupStateSummary)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.25)
                    .foregroundStyle(PrototypePalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if !offWorkingGroups.isEmpty {
                    Text(offWorkingGroupsMessage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PrototypePalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(languageStore.language.localized(
                    "La dirección es Estrobo → radio; la app no lee el estado completo del transmisor."
                ))
                    .font(.system(size: 10))
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PrototypePalette.accent.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PrototypePalette.accent.opacity(0.22), lineWidth: 1)
                }
        )
        .accessibilityElement(children: .combine)
    }

    private var offWorkingGroups: [GodoxGroup] {
        controller.workingGroups.filter {
            !controller.groupDraft($0).draft.isEnabledOnRadio
        }
    }

    private var workingGroupStateSummary: String {
        controller.workingGroups.map { group in
            let state = controller.groupDraft(group).draft.isEnabledOnRadio
                ? languageStore.language.localized("Activo")
                : languageStore.language.localized("Apagado")
            return "\(group.label) · \(state.uppercased())"
        }
        .joined(separator: "    ")
    }

    private var offWorkingGroupsMessage: String {
        let labels = offWorkingGroups.map(\.label).joined(separator: ", ")
        if offWorkingGroups.count == 1 {
            return languageStore.language.localizedFormat(
                "El grupo %@ se sincronizará apagado. Podrás activarlo después de conectar.",
                labels
            )
        }
        return languageStore.language.localizedFormat(
            "Los grupos %@ se sincronizarán apagados. Podrás activarlos después de conectar.",
            labels
        )
    }

    @ViewBuilder
    private var valueSynchronizationProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = controller.applySequenceStatus {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(languageStore.language.localizedFormat(
                        "Sincronizando %lld de %lld · Grupo %@",
                        status.currentPosition,
                        status.totalCount,
                        status.activeGroup.label
                    ))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(PrototypePalette.primaryText)
                }
                ProgressView(
                    value: Double(status.completedCount),
                    total: Double(max(status.totalCount, 1))
                )
                .tint(PrototypePalette.accent)
                .accessibilityLabel(languageStore.language.localized("Progreso de sincronización"))
                .accessibilityValue(languageStore.language.localizedFormat(
                    "%lld de %lld grupos completados",
                    status.completedCount,
                    status.totalCount
                ))
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(languageStore.language.localized("Preparando los valores de Estrobo…"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(PrototypePalette.primaryText)
                }
            }
            Text(languageStore.language.localized(
                "No cierres Estrobo ni apagues el radio durante esta operación."
            ))
                .font(.caption)
                .foregroundStyle(PrototypePalette.secondaryText)
        }
        .padding(12)
        .prototypePanel(padding: 0)
        .accessibilityElement(children: .contain)
    }

    private var connectionLocked: Bool {
        switch controller.phase {
        case .connecting, .discovering, .authenticating, .synchronizing,
             .applying, .disconnecting:
            true
        default:
            false
        }
    }

    private var canConnect: Bool {
        controller.selectedDeviceID != nil && controller.isRadioCodeValid && !connectionLocked
    }

    private func connectIfPossible() {
        guard canConnect else { return }
        controller.connectSelectedDevice()
    }
}

private struct StatusDot: View {
    let phase: SessionPhase

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay {
                Circle()
                    .stroke(color.opacity(0.32), lineWidth: 5)
            }
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch phase {
        case .ready:
            PrototypePalette.success
        case .scanning, .connecting, .discovering, .authenticating,
             .synchronizing, .applying, .disconnecting:
            PrototypePalette.warning
        case .failed, .unavailable:
            PrototypePalette.error
        case .idle:
            PrototypePalette.muted
        }
    }
}

private struct ActivityStrip: View {
    let item: ActivityItem?
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(activityColor)
                .frame(width: 6, height: 6)
            Text(localizedMessage)
                .font(.caption)
                .foregroundStyle(PrototypePalette.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            languageStore.language == .es
                ? "Actividad: \(localizedMessage)"
                : "Activity: \(localizedMessage)"
        )
    }

    private var activityColor: Color {
        guard let item else { return PrototypePalette.muted }
        return switch item.level {
        case .info: PrototypePalette.muted
        case .success: PrototypePalette.success
        case .warning: PrototypePalette.warning
        case .error: PrototypePalette.error
        }
    }

    private var localizedMessage: String {
        languageStore.language.localizedMessage(item?.message ?? "Sin actividad todavía")
    }
}

@MainActor
private struct WorkspaceFooter: View {
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        HStack(spacing: 18) {
            ActivityStrip(item: controller.activity.last)
                .frame(maxWidth: .infinity, alignment: .leading)

            FooterApplyControls(controller: controller)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 54)
    }
}

@MainActor
private struct FooterApplyControls: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        HStack(spacing: 8) {
            if let status = controller.applySequenceStatus {
                ProgressView()
                    .controlSize(.small)
                    .tint(PrototypePalette.accent)
                    .accessibilityLabel(languageStore.language.localizedFormat(
                        "Enviando %lld de %lld · %@",
                        status.currentPosition,
                        status.totalCount,
                        status.activeGroup.label
                    ))
            }

            if controller.isInteractiveEditActive {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(languageStore.language == .es ? "Ajustando…" : "Adjusting…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PrototypePalette.warning)
                    Text(
                        languageStore.language == .es
                            ? "Suelta para iniciar el envío automático"
                            : "Release to start automatic delivery"
                    )
                    .font(.caption2)
                    .foregroundStyle(PrototypePalette.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }

            Text(deliveryModeBadge)
                .prototypeBadge(
                    foreground: controller.changeDeliveryMode == .automatic
                        ? PrototypePalette.accent
                        : PrototypePalette.secondaryText,
                    background: controller.changeDeliveryMode == .automatic
                        ? PrototypePalette.accent.opacity(0.12)
                        : PrototypePalette.surfaceRaised
                )

            if let restorationGroup, controller.applySequenceStatus == nil {
                Button {
                    controller.prepareBaselineRestoration(for: restorationGroup)
                } label: {
                    Text(languageStore.language.localized("Recuperar"))
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(controller.phase == .applying)
                .help(languageStore.language.localized("Recuperar ajuste anterior"))
            } else if controller.changeDeliveryMode == .manual {
                discardButton
            } else if controller.isAutomaticApplyScheduled && controller.pendingCount > 0 {
                discardButton
            }

            Button {
                controller.applyPendingChanges()
            } label: {
                Label(
                    languageStore.language.localized(applyTitle),
                    systemImage: "checkmark.circle"
                )
                .lineLimit(1)
            }
            .buttonStyle(ApplyButtonStyle())
            .disabled(!controller.canApply)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .help(languageStore.language.localized(applyHelp))
    }

    private var deliveryModeBadge: String {
        languageStore.language.localized(
            controller.changeDeliveryMode == .automatic ? "AUTOMÁTICO" : "CON BOTÓN"
        )
    }

    private var applyTitle: String {
        if controller.isInteractiveEditActive {
            return "Ajustando…"
        }
        if controller.applySequenceStatus != nil {
            return "Enviando…"
        }
        if restorationGroup != nil {
            return "Aplicar recuperación"
        }
        if controller.changeDeliveryMode == .automatic {
            return "Enviar ahora"
        }
        if controller.hasPendingMultiFlashChange, controller.pendingGroups.isEmpty {
            return "Aplicar Multi"
        }
        if controller.pendingCount > 1 {
            return languageStore.language.localizedFormat(
                "Aplicar %lld cambios",
                controller.pendingCount
            )
        }
        if let group = controller.pendingGroups.first {
            return languageStore.language.localizedFormat("Aplicar %@", group.label)
        }
        return "Aplicar"
    }

    private var discardTitle: String {
        controller.pendingCount > 1 ? "Descartar todo" : "Descartar"
    }

    private var discardButton: some View {
        Button {
            controller.discardPendingChanges()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .frame(width: 18)
        }
        .buttonStyle(QuietButtonStyle())
        .disabled(
            !controller.canDiscardPendingChanges || controller.phase == .applying ||
                controller.applySequenceStatus != nil || controller.isInteractiveEditActive
        )
        .help(languageStore.language.localized(discardTitle))
        .accessibilityLabel(languageStore.language.localized(discardTitle))
    }

    private var applyHelp: String {
        if let reason = controller.applyBlockReason { return reason }
        if controller.changeDeliveryMode == .automatic {
            return "Los cambios se envían juntos después de una breve pausa"
        }
        return controller.hasPendingMultiFlashChange
            ? "Aplica primero el ajuste global Multi y después los grupos pendientes"
            : "Aplica en orden todos los grupos pendientes"
    }

    private var restorationGroup: GodoxGroup? {
        controller.restorationPoints.keys.sorted { $0.rawValue < $1.rawValue }.first
    }
}

private struct WorkspaceVariantSelector: View {
    @Binding var variant: PrototypeVariant
    let help: String
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PrototypeVariant.allCases) { option in
                Button {
                    variant = option
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: symbol(for: option))
                            .font(.system(size: 13, weight: .semibold))
                        Text(languageStore.language.localized(option.rawValue).uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.35)
                    }
                    .foregroundStyle(
                        variant == option
                            ? PrototypePalette.brandRing
                            : PrototypePalette.primaryText
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                variant == option
                                    ? PrototypePalette.brandTile
                                    : Color.clear
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(variant == option ? .isSelected : [])

                if option != PrototypeVariant.allCases.last {
                    Rectangle()
                        .fill(PrototypePalette.divider)
                        .frame(width: 1, height: 38)
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PrototypePalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(PrototypePalette.dividerStrong, lineWidth: 1)
                }
        )
        .help(languageStore.language.localized(help))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(languageStore.language.localized("Vista"))
    }

    private func symbol(for option: PrototypeVariant) -> String {
        switch option {
        case .channels:
            "square.grid.2x2"
        case .inspector:
            "slider.horizontal.3"
        case .matrix:
            "square.grid.3x3"
        }
    }
}

@MainActor
private struct ApplyBar: View {
    @ObservedObject var controller: GodoxSessionController
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: applyStatusSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(detailColor)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .stroke(detailColor.opacity(0.55), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(languageStore.language.localized(pendingTitle))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(
                            controller.pendingCount == 0 && controller.applySequenceStatus == nil
                                ? PrototypePalette.secondaryText
                                : PrototypePalette.primaryText
                        )

                    Text(languageStore.language.localized(detailText))
                        .font(.caption)
                        .foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(deliveryModeBadge)
                    .prototypeBadge(
                        foreground: controller.changeDeliveryMode == .automatic
                            ? PrototypePalette.accent
                            : PrototypePalette.secondaryText,
                        background: controller.changeDeliveryMode == .automatic
                            ? PrototypePalette.accent.opacity(0.12)
                            : PrototypePalette.surfaceRaised
                    )

                if let restorationGroup, controller.applySequenceStatus == nil {
                    Button {
                        controller.prepareBaselineRestoration(for: restorationGroup)
                    } label: {
                        Text(languageStore.language.localized("Recuperar ajuste anterior"))
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(controller.phase == .applying)
                    .help("Carga el ajuste anterior guardado para poder enviarlo al radio original")
                }

                if controller.changeDeliveryMode == .manual {
                    Rectangle()
                        .fill(PrototypePalette.divider)
                        .frame(width: 1, height: 28)

                    Button(discardTitle) {
                        controller.discardPendingChanges()
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(
                        !controller.canDiscardPendingChanges || controller.phase == .applying ||
                            restorationGroup != nil || controller.applySequenceStatus != nil ||
                            controller.isInteractiveEditActive
                    )
                } else if controller.isAutomaticApplyScheduled && controller.pendingCount > 0 {
                    Rectangle()
                        .fill(PrototypePalette.divider)
                        .frame(width: 1, height: 28)

                    Button(discardTitle) {
                        controller.discardPendingChanges()
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(
                        !controller.canDiscardPendingChanges ||
                            controller.isInteractiveEditActive
                    )
                }

                Button(applyTitle) {
                    controller.applyPendingChanges()
                }
                .buttonStyle(ApplyButtonStyle())
                .disabled(!controller.canApply)
            }

            if let status = controller.applySequenceStatus {
                ProgressView(
                    value: Double(status.currentPosition),
                    total: Double(max(status.totalCount, 1))
                )
                .controlSize(.small)
                .tint(PrototypePalette.accent)
                .accessibilityLabel(
                    "Enviando grupo \(status.activeGroup.label), \(status.currentPosition) de \(status.totalCount)"
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var applyStatusSymbol: String {
        if controller.applySequenceStatus != nil { return "arrow.triangle.2.circlepath" }
        if controller.pendingCount > 0 { return "clock" }
        return "checkmark"
    }

    private var deliveryModeBadge: String {
        languageStore.language.localized(
            controller.changeDeliveryMode == .automatic ? "AUTOMÁTICO" : "CON BOTÓN"
        )
    }

    private var pendingTitle: String {
        if controller.isInteractiveEditActive {
            return languageStore.language == .es ? "Ajustando…" : "Adjusting…"
        }
        if let status = controller.applySequenceStatus {
            return languageStore.language.localizedFormat(
                "Enviando %lld de %lld · %@",
                status.currentPosition,
                status.totalCount,
                status.activeGroup.label
            )
        }
        if let restorationGroup {
            return languageStore.language.localizedFormat(
                "Recuperación pendiente · grupo %@",
                restorationGroup.label
            )
        }

        if controller.changeDeliveryMode == .automatic {
            if controller.pendingCount == 0 {
                return languageStore.language.localized("Envío automático listo")
            }
            if controller.isAutomaticApplyScheduled {
                return controller.pendingCount == 1
                    ? languageStore.language.localized("1 grupo listo")
                    : languageStore.language.localizedFormat(
                        "%lld grupos listos",
                        controller.pendingCount
                    )
            }
        }

        return pendingGroupTitle
    }

    private var pendingGroupTitle: String {
        switch controller.pendingCount {
        case 0:
            languageStore.language.localized("Sin cambios pendientes")
        case 1:
            languageStore.language.localized("1 grupo pendiente")
        default:
            languageStore.language.localizedFormat(
                "%lld grupos pendientes",
                controller.pendingCount
            )
        }
    }

    private var detailText: String {
        if controller.isInteractiveEditActive {
            return languageStore.language == .es
                ? "Suelta para iniciar el envío automático"
                : "Release to start automatic delivery"
        }
        if let status = controller.applySequenceStatus {
            guard !status.remainingGroups.isEmpty else {
                return languageStore.language.localized("Último grupo de la secuencia")
            }
            return languageStore.language.localizedFormat(
                "Después: %@",
                groupList(status.remainingGroups)
            )
        }

        if let restorationGroup {
            if controller.changeDeliveryMode == .automatic {
                return languageStore.language.localizedFormat(
                    "El envío automático está pausado hasta recuperar %@",
                    restorationGroup.label
                )
            }
            return languageStore.language.localized(
                "Prepara el ajuste anterior y envíalo al radio original"
            )
        }

        if let blockReason = controller.applyBlockReason {
            return languageStore.language.localizedMessage(blockReason)
        }

        if controller.changeDeliveryMode == .automatic {
            guard controller.pendingCount > 0 else {
                return languageStore.language.localized(
                    "Los cambios se enviarán juntos después de una breve pausa"
                )
            }
            if languageStore.language == .es {
                let verb = controller.pendingCount == 1 ? "Se enviará" : "Se enviarán"
                let timing = controller.isAutomaticApplyScheduled
                    ? "automáticamente en breve"
                    : "cuando el radio esté disponible"
                return "\(verb) \(timing) · \(groupList(controller.pendingGroups))"
            }
            let verb = controller.pendingCount == 1 ? "Will be sent" : "Will be sent"
            let timing = controller.isAutomaticApplyScheduled
                ? "automatically shortly"
                : "when the trigger is available"
            return "\(verb) \(timing) · \(groupList(controller.pendingGroups))"
        }

        guard controller.pendingCount > 0 else {
            return languageStore.language.localized("Nada se envía hasta pulsar Aplicar")
        }
        if languageStore.language == .es {
            let verb = controller.pendingCount == 1 ? "Se enviará" : "Se enviarán"
            return "\(verb) uno por uno · \(groupList(controller.pendingGroups))"
        }
        return "Will be sent one at a time · \(groupList(controller.pendingGroups))"
    }

    private var detailColor: Color {
        if controller.applySequenceStatus != nil {
            return PrototypePalette.accent
        }
        if controller.isInteractiveEditActive || restorationGroup != nil || controller.applyBlockReason != nil ||
            controller.isAutomaticApplyScheduled || controller.pendingCount > 0 {
            return PrototypePalette.warning
        }
        return PrototypePalette.secondaryText
    }

    private var applyTitle: String {
        if controller.isInteractiveEditActive {
            return languageStore.language == .es ? "Ajustando…" : "Adjusting…"
        }
        if let status = controller.applySequenceStatus {
            return languageStore.language.localizedFormat(
                "Enviando %@…",
                status.activeGroup.label
            )
        }
        if let restorationGroup {
            return languageStore.language.localizedFormat(
                "Aplicar recuperación %@",
                restorationGroup.label
            )
        }
        if controller.changeDeliveryMode == .automatic {
            return languageStore.language.localized("Enviar ahora")
        }
        if controller.pendingCount > 1 {
            return languageStore.language.localizedFormat(
                "Aplicar %lld grupos",
                controller.pendingCount
            )
        }
        guard let group = controller.pendingGroups.first else {
            return languageStore.language.localized("Aplicar")
        }
        return languageStore.language.localizedFormat("Aplicar %@", group.label)
    }

    private var discardTitle: String {
        languageStore.language.localized(
            controller.pendingCount > 1 ? "Descartar todo" : "Descartar"
        )
    }

    private var restorationGroup: GodoxGroup? {
        controller.restorationPoints.keys.sorted { $0.rawValue < $1.rawValue }.first
    }

    private func groupList(_ groups: [GodoxGroup]) -> String {
        let labels = groups.map(\.label)
        switch labels.count {
        case 0:
            return ""
        case 1:
            return labels[0]
        case 2:
            return labels.joined(separator: languageStore.language == .es ? " y " : " and ")
        default:
            let conjunction = languageStore.language == .es ? " y " : ", and "
            return "\(labels.dropLast().joined(separator: ", "))\(conjunction)\(labels.last!)"
        }
    }
}

// MARK: - Variant A: Channels

@MainActor
private struct ChannelsLayout: View {
    @ObservedObject var controller: GodoxSessionController

    var body: some View {
        GeometryReader { geometry in
            let visibleCount = max(controller.visibleGroups.count, 1)
            let fittedCount = min(visibleCount, 4)
            let channelWidth = max(
                360,
                (geometry.size.width - CGFloat(fittedCount - 1)) / CGFloat(fittedCount)
            )
            let requiredWidth =
                (CGFloat(visibleCount) * channelWidth) + CGFloat(max(0, visibleCount - 1))

            if requiredWidth <= geometry.size.width {
                ScrollView(.vertical) {
                    channelStrips(width: channelWidth, minHeight: geometry.size.height)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    channelStrips(width: channelWidth, minHeight: geometry.size.height)
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private func channelStrips(width: CGFloat, minHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(controller.visibleGroups) { group in
                StudioChannelStrip(
                    group: group,
                    state: controller.groupDraft(group),
                    canEdit: controller.canEdit(group),
                    allowedPowers: controller.allowedPowers(for: group),
                    allowedModeling: controller.allowedModelingLights(for: group),
                    capability: controller.resolvedCapability(for: group),
                    canToggleMode: controller.canToggleRadioEnabled(group),
                    canChangeOperatingMode: controller.canChangeOperatingMode(group),
                    setPower: { controller.setDraftPower(group, power: $0) },
                    setModeling: { controller.setDraftModeling(group, modeling: $0) },
                    setOperatingMode: { controller.setDraftOperatingMode(group, mode: $0) },
                    setRadioEnabled: { controller.setDraftRadioEnabled(group, enabled: $0) }
                )
                .frame(width: width)

                if group != controller.visibleGroups.last {
                    Rectangle()
                        .fill(PrototypePalette.divider)
                        .frame(width: 1)
                        .padding(.vertical, 8)
                }
            }
        }
        .frame(minHeight: minHeight)
    }
}

private struct StudioChannelStrip: View {
    let group: GodoxGroup
    let state: GroupDraft
    let canEdit: Bool
    let allowedPowers: [ManualPower]
    let allowedModeling: [ModelingLight]
    let capability: ResolvedGroupCapability
    let canToggleMode: Bool
    let canChangeOperatingMode: Bool
    let setPower: (ManualPower) -> Void
    let setModeling: (ModelingLight) -> Void
    let setOperatingMode: (GroupOperatingMode) -> Void
    let setRadioEnabled: (Bool) -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var controller: GodoxSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                GroupBadge(
                    group: group,
                    isPending: hasVisiblePendingChange,
                    size: 44,
                    fontSize: 27
                )

                Text(state.draft.operatingMode.label.uppercased())
                    .prototypeBadge(
                        foreground: hasVisiblePendingChange
                            ? PrototypePalette.accent
                            : PrototypePalette.secondaryText,
                        background: hasVisiblePendingChange
                            ? PrototypePalette.accent.opacity(0.12)
                            : PrototypePalette.surfaceRaised
                    )

                Spacer()

                DraftChangeDot(changed: hasVisiblePendingChange)
            }

            GroupStateControls(
                group: group,
                state: state,
                canToggleMode: canToggleMode,
                canChangeOperatingMode: canChangeOperatingMode,
                hasAssignedModel: !capability.flashModels.isEmpty,
                compact: true,
                setOperatingMode: setOperatingMode,
                setRadioEnabled: setRadioEnabled
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(languageStore.language.localized(
                    isMulti ? "Potencia Multi" : "Potencia"
                ).uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(PrototypePalette.secondaryText)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(powerFraction)
                        .font(.system(size: 38, weight: .medium, design: .monospaced))
                        .minimumScaleFactor(0.75)

                    VStack(alignment: .trailing, spacing: 0) {
                        Text(powerOffset)
                            .font(.system(size: 17, weight: .medium, design: .monospaced))
                        Text("EV")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .monospacedDigit()
                .foregroundStyle(
                    canInteractWithDisplayedPower
                        ? PrototypePalette.primaryText
                        : PrototypePalette.muted
                )
                .lineLimit(1)
            }

            if isMulti {
                MultiModeSummary(compact: false)
                    .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VerticalDiscretePowerControl(
                        group: group,
                        value: state.draft.power,
                        allowed: allowedPowers,
                        enabled: canEdit,
                        onChange: setPower
                    )
                    .frame(width: 112, height: 250)

                    VStack(alignment: .leading, spacing: 16) {
                        ModelingEditor(
                            group: group,
                            value: state.draft.modeling,
                            baseline: state.baseline.modeling,
                            allowed: allowedModeling,
                            enabled: canEdit,
                            compact: true,
                            onChange: setModeling
                        )

                        Rectangle()
                            .fill(PrototypePalette.divider)
                            .frame(height: 1)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(languageStore.language.localized("ESTADO"))
                                .font(.caption2.weight(.bold))
                                .tracking(0.7)
                                .foregroundStyle(PrototypePalette.secondaryText)

                            HStack(spacing: 7) {
                                Circle()
                                    .fill(
                                        state.hasPendingChange
                                            ? PrototypePalette.accent
                                            : confirmationColor(state.confirmation)
                                    )
                                    .frame(width: 7, height: 7)
                                Text(statusLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        state.hasPendingChange
                                            ? PrototypePalette.accent
                                            : PrototypePalette.secondaryText
                                    )
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 250, alignment: .topLeading)
                }
            }

            if !isMulti && !capability.powerScale.isEmpty &&
                (capability.hasMixedPowerCapabilities ||
                    !capability.powerScale.contains(state.draft.power)) {
                PowerRangeSummary(
                    capability: capability,
                    currentPower: state.draft.power,
                    compact: true
                )
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            hasVisiblePendingChange
                ? PrototypePalette.accent.opacity(0.045)
                : Color.clear
        )
        .overlay(alignment: .leading) {
            if hasVisiblePendingChange {
                Rectangle()
                    .fill(PrototypePalette.accent)
                    .frame(width: 2)
                    .padding(.vertical, 8)
            }
        }
        .opacity(
            canEdit || isMulti || canChangeOperatingMode || state.draft.operatingMode == .off
                ? 1
                : 0.7
        )
        .help(groupInteractionHelp(
            group: group,
            state: state,
            canEdit: canEdit,
            canToggleMode: canToggleMode,
            canChangeOperatingMode: canChangeOperatingMode,
            hasAssignedModel: !capability.flashModels.isEmpty,
            multiIsActive: !controller.multiFlashGroups.isEmpty,
            language: languageStore.language
        ))
        .multiExcludedGroupOverlay(
            group: group,
            state: state,
            controller: controller,
            compact: false
        )
    }

    private var statusLabel: String {
        languageStore.language.localized(
            state.hasPendingChange
                ? "PENDIENTE"
                : confirmationLabel(state.confirmation)
        )
    }

    private var powerFraction: String {
        displayedPower.label.split(separator: " ").first.map(String.init)
            ?? displayedPower.label
    }

    private var powerOffset: String {
        let components = displayedPower.label.split(separator: " ")
        return components.count > 1 ? String(components[1]) : "+0.0"
    }

    private var isMulti: Bool {
        state.draft.operatingMode == .multi
    }

    private var displayedPower: ManualPower {
        isMulti ? controller.multiFlashDraft.power : state.draft.power
    }

    private var canInteractWithDisplayedPower: Bool {
        isMulti ? controller.canEditMultiFlashSettings : canEdit
    }

    private var hasVisiblePendingChange: Bool {
        state.hasPendingChange || (isMulti && controller.hasPendingMultiFlashChange)
    }
}

private struct ChannelRow: View {
    let group: GodoxGroup
    let state: GroupDraft
    let canEdit: Bool
    let allowedPowers: [ManualPower]
    let allowedModeling: [ModelingLight]
    let capability: ResolvedGroupCapability
    let canToggleMode: Bool
    let canChangeOperatingMode: Bool
    let decrement: () -> Void
    let increment: () -> Void
    let setPower: (ManualPower) -> Void
    let setModeling: (ModelingLight) -> Void
    let setOperatingMode: (GroupOperatingMode) -> Void
    let setRadioEnabled: (Bool) -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 9) {
                GroupBadge(group: group, isPending: state.hasPendingChange)

                Text(state.draft.operatingMode.label)
                    .prototypeBadge(
                        foreground: PrototypePalette.secondaryText,
                        background: PrototypePalette.surfaceRaised
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(modelSummary)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(PrototypePalette.primaryText)
                        .lineLimit(1)

                    Text(localizedConfirmationText)
                    .font(.caption2.weight(.bold))
                    .tracking(0.55)
                    .foregroundStyle(
                        state.hasPendingChange
                            ? PrototypePalette.accent
                            : confirmationColor(state.confirmation)
                    )
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DraftChangeDot(changed: state.baseline.power != state.draft.power)

                Text(state.draft.power.label)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(canEdit ? PrototypePalette.primaryText : PrototypePalette.muted)
                    .frame(width: 132, alignment: .trailing)
                    .monospacedDigit()
            }

            HStack(spacing: 7) {
                StepButton(
                    title: "−",
                    accessibilityLabel: "Bajar potencia del grupo \(group.label)",
                    enabled: canEdit,
                    action: decrement
                )

                DiscretePowerSlider(
                    group: group,
                    value: state.draft.power,
                    allowed: allowedPowers,
                    enabled: canEdit,
                    onChange: setPower
                )

                StepButton(
                    title: "+",
                    accessibilityLabel: "Subir potencia del grupo \(group.label)",
                    enabled: canEdit,
                    action: increment
                )
            }

            PowerRangeSummary(
                capability: capability,
                currentPower: state.draft.power,
                compact: true
            )

            HStack(alignment: .top, spacing: 16) {
                ModelingEditor(
                    group: group,
                    value: state.draft.modeling,
                    baseline: state.baseline.modeling,
                    allowed: allowedModeling,
                    enabled: canEdit,
                    compact: true,
                    onChange: setModeling
                )
                .frame(maxWidth: 560)

                Rectangle()
                    .fill(PrototypePalette.divider)
                    .frame(width: 1, height: 36)

                GroupStateControls(
                    group: group,
                    state: state,
                    canToggleMode: canToggleMode,
                    canChangeOperatingMode: canChangeOperatingMode,
                    hasAssignedModel: !capability.flashModels.isEmpty,
                    compact: true,
                    setOperatingMode: setOperatingMode,
                    setRadioEnabled: setRadioEnabled
                )
                .frame(maxWidth: 280)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(groupSurface(isPending: state.hasPendingChange))
        .opacity(canEdit || canChangeOperatingMode ? 1 : 0.72)
        .help(languageStore.language.localized(
            canEdit
                ? "Ajusta el grupo; la barra inferior muestra cuándo se envía"
                : "Conecta el radio para editar este grupo"
        ))
    }

    private var modelSummary: String {
        let names = capability.flashModels.map(\.name)
        guard !names.isEmpty else {
            return languageStore.language == .es ? "Sin modelo asignado" : "No model assigned"
        }
        if names.count <= 2 { return names.joined(separator: " + ") }
        return "\(names[0]) +\(names.count - 1)"
    }

    private var localizedConfirmationText: String {
        let source = state.hasPendingChange
            ? "PENDIENTE"
            : confirmationLabel(state.confirmation)
        return languageStore.language.localized(source).uppercased()
    }
}

// MARK: - Variant B: Inspector

@MainActor
private struct InspectorLayout: View {
    @ObservedObject var controller: GodoxSessionController
    @Binding var selectedGroup: GodoxGroup

    var body: some View {
        HStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(controller.visibleGroups) { group in
                        let state = controller.groupDraft(group)
                        InspectorRailButton(
                            group: group,
                            state: state,
                            isSelected: selectedGroup == group,
                            select: { selectedGroup = group }
                        )
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(width: 112)

            InspectorEditor(
                group: selectedGroup,
                state: controller.groupDraft(selectedGroup),
                canEdit: controller.canEdit(selectedGroup),
                allowedPowers: controller.allowedPowers(for: selectedGroup),
                allowedModeling: controller.allowedModelingLights(for: selectedGroup),
                capability: controller.resolvedCapability(for: selectedGroup),
                canToggleMode: controller.canToggleRadioEnabled(selectedGroup),
                canChangeOperatingMode: controller.canChangeOperatingMode(selectedGroup),
                decrement: { controller.adjust(selectedGroup, direction: -1) },
                increment: { controller.adjust(selectedGroup, direction: 1) },
                setPower: { controller.setDraftPower(selectedGroup, power: $0) },
                setModeling: { controller.setDraftModeling(selectedGroup, modeling: $0) },
                setOperatingMode: {
                    controller.setDraftOperatingMode(selectedGroup, mode: $0)
                },
                setRadioEnabled: { controller.setDraftRadioEnabled(selectedGroup, enabled: $0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct InspectorRailButton: View {
    let group: GodoxGroup
    let state: GroupDraft
    let isSelected: Bool
    let select: () -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var controller: GodoxSessionController

    var body: some View {
        let identity = group.visualIdentity
        let groupFill = Color(estroboRGB: identity.fillRGB)
        let groupForeground = Color(estroboRGB: identity.foregroundRGB)
        let isMulti = state.draft.operatingMode == .multi
        let isExcludedFromMulti = !controller.multiFlashGroups.isEmpty &&
            state.draft.operatingMode == .off
        let effectivePending = state.hasPendingChange ||
            (isMulti && controller.hasPendingMultiFlashChange)
        let detail = isExcludedFromMulti
            ? "Desactivado"
            : isMulti
            ? "\(controller.multiFlashDraft.count)× · \(controller.multiFlashDraft.hertz) Hz"
            : state.draft.operatingMode == .off
                ? "Apagado"
                : state.hasPendingChange
                    ? "PENDIENTE"
                    : state.draft.modeling.label
        let displayedPower = isMulti
            ? controller.multiFlashDraft.power
            : state.draft.power

        Button(action: select) {
            HStack(spacing: 7) {
                if isSelected {
                    Text(group.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(groupForeground)
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(groupForeground.opacity(0.30), lineWidth: 1)
                        )
                } else {
                    GroupBadge(
                        group: group,
                        isPending: effectivePending,
                        size: 24,
                        fontSize: 12
                    )
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayedPower.label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                    Text(languageStore.language.localized(detail).uppercased())
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .tracking(0.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(
                    isSelected
                        ? groupForeground
                        : PrototypePalette.secondaryText
                )

                Spacer(minLength: 0)

                if isExcludedFromMulti {
                    Image(systemName: "bolt.slash.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? groupForeground : PrototypePalette.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 41)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? groupFill
                            : effectivePending
                                ? PrototypePalette.warning.opacity(0.11)
                                : PrototypePalette.surface
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isSelected
                                    ? groupForeground.opacity(0.34)
                                    : effectivePending
                                        ? PrototypePalette.warning.opacity(0.42)
                                        : PrototypePalette.divider,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(languageStore.language.localized(
            isExcludedFromMulti ? "Desactivado en Multi" : detail
        ))
        .opacity(isExcludedFromMulti && !isSelected ? 0.58 : 1)
        .animation(.easeInOut(duration: 0.14), value: isSelected)
    }
}

private struct InspectorEditor: View {
    let group: GodoxGroup
    let state: GroupDraft
    let canEdit: Bool
    let allowedPowers: [ManualPower]
    let allowedModeling: [ModelingLight]
    let capability: ResolvedGroupCapability
    let canToggleMode: Bool
    let canChangeOperatingMode: Bool
    let decrement: () -> Void
    let increment: () -> Void
    let setPower: (ManualPower) -> Void
    let setModeling: (ModelingLight) -> Void
    let setOperatingMode: (GroupOperatingMode) -> Void
    let setRadioEnabled: (Bool) -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var controller: GodoxSessionController

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 10) {
                GroupBadge(
                    group: group,
                    isPending: hasEffectivePendingChange,
                    size: 36,
                    fontSize: 18
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(languageStore.language.localizedFormat("GRUPO %@", group.label))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(PrototypePalette.secondaryText)
                    Text(languageStore.language.localized(modeDescription))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PrototypePalette.primaryText)
                }
                Spacer()
                Text(state.draft.operatingMode.label)
                    .prototypeBadge(
                        foreground: PrototypePalette.primaryText,
                        background: PrototypePalette.surfaceRaised
                    )
            }

            GroupStateControls(
                group: group,
                state: state,
                canToggleMode: canToggleMode,
                canChangeOperatingMode: canChangeOperatingMode,
                hasAssignedModel: !capability.flashModels.isEmpty,
                compact: false,
                setOperatingMode: setOperatingMode,
                setRadioEnabled: setRadioEnabled
            )

            if isMulti {
                MultiModeSummary(compact: false)
            } else {
                Text(state.draft.power.label)
                    .font(.system(size: 29, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(canEdit ? PrototypePalette.primaryText : PrototypePalette.muted)

                HStack(spacing: 12) {
                    LargeStepButton(
                        title: "−",
                        accessibilityLabel: "Bajar potencia del grupo \(group.label)",
                        enabled: canEdit,
                        action: decrement
                    )

                    DiscretePowerSlider(
                        group: group,
                        value: state.draft.power,
                        allowed: allowedPowers,
                        enabled: canEdit,
                        onChange: setPower
                    )

                    LargeStepButton(
                        title: "+",
                        accessibilityLabel: "Subir potencia del grupo \(group.label)",
                        enabled: canEdit,
                        action: increment
                    )
                }

                HStack {
                    Text(allowedPowers.first?.label ?? "—")
                    Spacer()
                    Text(languageStore.language.localized(
                        state.hasPendingChange
                            ? "PASOS DE 1/3 EV · CAMBIO PENDIENTE"
                            : "PASOS DE 1/3 EV · SIN CAMBIOS"
                    ))
                    Spacer()
                    Text(allowedPowers.last?.label ?? "—")
                }
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(PrototypePalette.muted)

                PowerRangeSummary(
                    capability: capability,
                    currentPower: state.draft.power,
                    compact: false
                )

                Divider()
                    .overlay(PrototypePalette.divider)

                ModelingEditor(
                    group: group,
                    value: state.draft.modeling,
                    baseline: state.baseline.modeling,
                    allowed: allowedModeling,
                    enabled: canEdit,
                    compact: false,
                    onChange: setModeling
                )
            }

            VStack(spacing: 6) {
                HStack {
                    Text(languageStore.language.localized("REFERENCIA DE LA APP"))
                    Spacer()
                    Text(baselineReference)
                        .fontDesign(.monospaced)
                }
                HStack {
                    Text(languageStore.language.localized("BORRADOR"))
                    Spacer()
                    Text(draftReference)
                        .fontDesign(.monospaced)
                        .foregroundStyle(
                            hasEffectivePendingChange
                                ? PrototypePalette.warning
                                : PrototypePalette.primaryText
                        )
                }
                HStack {
                    Text(languageStore.language.localized("CONFIRMACIÓN"))
                    Spacer()
                    Text(
                        languageStore.language
                            .localized(confirmationLabel(state.confirmation))
                            .uppercased()
                    )
                        .foregroundStyle(confirmationColor(state.confirmation))
                }
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.35)
            .foregroundStyle(PrototypePalette.secondaryText)

            if !canEdit {
                Text(groupInteractionHelp(
                    group: group,
                    state: state,
                    canEdit: canEdit,
                    canToggleMode: canToggleMode,
                    canChangeOperatingMode: canChangeOperatingMode,
                    hasAssignedModel: !capability.flashModels.isEmpty,
                    multiIsActive: !controller.multiFlashGroups.isEmpty,
                    language: languageStore.language
                ).uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.3)
                    .foregroundStyle(PrototypePalette.muted)
            }
        }
        .padding(14)
        .background(groupSurface(isPending: hasEffectivePendingChange))
        .multiExcludedGroupOverlay(
            group: group,
            state: state,
            controller: controller,
            compact: false
        )
    }

    private var isMulti: Bool {
        state.draft.operatingMode == .multi
    }

    private var hasEffectivePendingChange: Bool {
        state.hasPendingChange || (isMulti && controller.hasPendingMultiFlashChange)
    }

    private var modeDescription: String {
        switch state.draft.operatingMode {
        case .autoTTL:
            return "Exposición automática TTL"
        case .multi:
            return "Destellos múltiples"
        case .manual, .off:
            return "Potencia manual"
        }
    }

    private var baselineReference: String {
        if isMulti {
            return multiReference(controller.multiFlashBaseline)
        }
        return "\(state.baseline.power.label) · " +
            languageStore.language.localized(state.baseline.modeling.label)
    }

    private var draftReference: String {
        if isMulti {
            return multiReference(controller.multiFlashDraft)
        }
        return "\(state.draft.power.label) · " +
            languageStore.language.localized(state.draft.modeling.label)
    }

    private func multiReference(_ settings: MultiFlashSettings) -> String {
        "\(settings.power.label) · \(settings.count)× · \(settings.hertz) Hz"
    }
}

// MARK: - Variant C: Matrix

@MainActor
private struct MatrixLayout: View {
    @ObservedObject var controller: GodoxSessionController

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(controller.visibleGroups) { group in
                    let state = controller.groupDraft(group)
                    MatrixGroupCard(
                        group: group,
                        state: state,
                        canEdit: controller.canEdit(group),
                        allowedPowers: controller.allowedPowers(for: group),
                        allowedModeling: controller.allowedModelingLights(for: group),
                        capability: controller.resolvedCapability(for: group),
                        canToggleMode: controller.canToggleRadioEnabled(group),
                        canChangeOperatingMode: controller.canChangeOperatingMode(group),
                        decrement: { controller.adjust(group, direction: -1) },
                        increment: { controller.adjust(group, direction: 1) },
                        setPower: { controller.setDraftPower(group, power: $0) },
                        setModeling: { controller.setDraftModeling(group, modeling: $0) },
                        setOperatingMode: {
                            controller.setDraftOperatingMode(group, mode: $0)
                        },
                        setRadioEnabled: { controller.setDraftRadioEnabled(group, enabled: $0) }
                    )
                }
            }
            .padding(.trailing, 2)
        }
        .scrollIndicators(.never)
    }
}

private struct MatrixGroupCard: View {
    let group: GodoxGroup
    let state: GroupDraft
    let canEdit: Bool
    let allowedPowers: [ManualPower]
    let allowedModeling: [ModelingLight]
    let capability: ResolvedGroupCapability
    let canToggleMode: Bool
    let canChangeOperatingMode: Bool
    let decrement: () -> Void
    let increment: () -> Void
    let setPower: (ManualPower) -> Void
    let setModeling: (ModelingLight) -> Void
    let setOperatingMode: (GroupOperatingMode) -> Void
    let setRadioEnabled: (Bool) -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var controller: GodoxSessionController

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                GroupBadge(group: group, isPending: hasEffectivePendingChange)
                Text(state.draft.operatingMode.label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(PrototypePalette.secondaryText)
                Spacer()
                Text(languageStore.language.localized(
                    hasEffectivePendingChange
                        ? "PENDIENTE"
                        : compactConfirmationLabel(state.confirmation)
                ))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.35)
                    .foregroundStyle(
                        hasEffectivePendingChange
                            ? PrototypePalette.warning
                            : PrototypePalette.muted
                    )
            }

            GroupStateControls(
                group: group,
                state: state,
                canToggleMode: canToggleMode,
                canChangeOperatingMode: canChangeOperatingMode,
                hasAssignedModel: !capability.flashModels.isEmpty,
                compact: true,
                setOperatingMode: setOperatingMode,
                setRadioEnabled: setRadioEnabled
            )

            if isMulti {
                MultiModeSummary(compact: true)
            } else {
                Text(state.draft.power.label)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(canEdit ? PrototypePalette.primaryText : PrototypePalette.muted)

                HStack(spacing: 7) {
                    StepButton(
                        title: "−",
                        accessibilityLabel: "Bajar potencia del grupo \(group.label)",
                        enabled: canEdit,
                        action: decrement
                    )

                    DiscretePowerSlider(
                        group: group,
                        value: state.draft.power,
                        allowed: allowedPowers,
                        enabled: canEdit,
                        onChange: setPower
                    )

                    StepButton(
                        title: "+",
                        accessibilityLabel: "Subir potencia del grupo \(group.label)",
                        enabled: canEdit,
                        action: increment
                    )
                }

                PowerRangeSummary(
                    capability: capability,
                    currentPower: state.draft.power,
                    compact: true
                )

                ModelingEditor(
                    group: group,
                    value: state.draft.modeling,
                    baseline: state.baseline.modeling,
                    allowed: allowedModeling,
                    enabled: canEdit,
                    compact: true,
                    onChange: setModeling
                )
            }

        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 238)
        .background(groupSurface(isPending: hasEffectivePendingChange))
        .opacity(
            canEdit || isMulti || canChangeOperatingMode || state.draft.operatingMode == .off
                ? 1
                : 0.62
        )
        .help(groupInteractionHelp(
            group: group,
            state: state,
            canEdit: canEdit,
            canToggleMode: canToggleMode,
            canChangeOperatingMode: canChangeOperatingMode,
            hasAssignedModel: !capability.flashModels.isEmpty,
            multiIsActive: !controller.multiFlashGroups.isEmpty,
            language: languageStore.language
        ))
        .multiExcludedGroupOverlay(
            group: group,
            state: state,
            controller: controller,
            compact: true
        )
    }

    private var isMulti: Bool {
        state.draft.operatingMode == .multi
    }

    private var hasEffectivePendingChange: Bool {
        state.hasPendingChange || (isMulti && controller.hasPendingMultiFlashChange)
    }
}

private extension View {
    @MainActor
    func multiExcludedGroupOverlay(
        group: GodoxGroup,
        state: GroupDraft,
        controller: GodoxSessionController,
        compact: Bool
    ) -> some View {
        modifier(MultiExcludedGroupModifier(
            group: group,
            state: state,
            controller: controller,
            compact: compact
        ))
    }
}

@MainActor
private struct MultiExcludedGroupModifier: ViewModifier {
    let group: GodoxGroup
    let state: GroupDraft
    @ObservedObject var controller: GodoxSessionController
    let compact: Bool

    private var isExcluded: Bool {
        !controller.multiFlashGroups.isEmpty && state.draft.operatingMode == .off
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isExcluded ? 0.16 : 1)
                .allowsHitTesting(!isExcluded)
                .accessibilityHidden(isExcluded)

            if isExcluded {
                MultiExcludedGroupOverlay(
                    group: group,
                    controller: controller,
                    compact: compact
                )
                .padding(compact ? 10 : 18)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isExcluded)
    }
}

@MainActor
private struct MultiExcludedGroupOverlay: View {
    let group: GodoxGroup
    @ObservedObject var controller: GodoxSessionController
    let compact: Bool
    @EnvironmentObject private var languageStore: AppLanguageStore

    private var supportsMulti: Bool {
        controller.supportsMultiFlash(group)
    }

    private var canActivate: Bool {
        controller.canSetMultiFlashParticipation(group, enabled: true)
    }

    var body: some View {
        VStack(spacing: compact ? 7 : 10) {
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: compact ? 18 : 23, weight: .semibold))
                .foregroundStyle(PrototypePalette.muted)

            VStack(spacing: 3) {
                Text(languageStore.language.localizedFormat(
                    "GRUPO %@ DESACTIVADO",
                    group.label
                ))
                    .font(.system(size: compact ? 9 : 11, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(PrototypePalette.primaryText)

                Text(languageStore.language.localized(
                    supportsMulti
                        ? "Este grupo está fuera de la secuencia Multi."
                        : "Este grupo no admite Multi con su configuración actual."
                ))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if supportsMulti {
                Button {
                    controller.setMultiFlashParticipation(group, enabled: true)
                } label: {
                    Label(
                        languageStore.language.localized("Activar en Multi"),
                        systemImage: "plus.circle.fill"
                    )
                }
                .buttonStyle(WorkspacePrimaryButtonStyle())
                .disabled(!canActivate)
                .accessibilityLabel(languageStore.language.localizedFormat(
                    "Activar grupo %@ en Multi",
                    group.label
                ))
            }
        }
        .padding(.horizontal, compact ? 14 : 20)
        .padding(.vertical, compact ? 12 : 16)
        .frame(maxWidth: compact ? 230 : 280)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PrototypePalette.surface.opacity(0.97))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PrototypePalette.dividerStrong, lineWidth: 1)
        }
        .shadow(color: PrototypePalette.brandShadow, radius: 14, y: 5)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Reusable controls and styling

@MainActor
private struct MultiModeSummary: View {
    let compact: Bool
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(PrototypePalette.success)
            Text(languageStore.language.localized("INCLUIDO EN MULTI"))
                .tracking(0.55)
            if !compact {
                Text(languageStore.language.localized("AJUSTE EN CONSOLA GLOBAL"))
                    .foregroundStyle(PrototypePalette.muted)
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(PrototypePalette.secondaryText)
        .accessibilityElement(children: .combine)
    }
}

private struct PowerRangeSummary: View {
    let capability: ResolvedGroupCapability
    let currentPower: ManualPower
    let compact: Bool
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        HStack(spacing: 6) {
            Text(languageStore.language.localized(capability.powerScale.first?.label ?? "SIN MODELO"))
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.bold))
            Text(capability.powerScale.last?.label ?? "—")
            Spacer(minLength: 4)
            if let commonPower = capability.powerScale.first,
               !capability.powerScale.contains(currentPower) {
                Label {
                    Text(languageStore.language.localizedFormat(
                        "PRÓXIMO CAMBIO · %@",
                        commonPower.label
                    ))
                } icon: {
                    Image(systemName: "arrow.down.to.line")
                }
                    .foregroundStyle(PrototypePalette.warning)
                    .help("La referencia actual queda fuera del rango común; la primera edición usará \(commonPower.label)")
            } else if capability.hasMixedPowerCapabilities,
               let common = capability.minimumManualDenominator {
                Label {
                    Text(languageStore.language.localizedFormat(
                        "MIXTO · común 1/%lld",
                        common
                    ))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                    .foregroundStyle(PrototypePalette.warning)
                    .help("Se usa el límite que todos comparten; 1/256 + 1/512 = 1/256")
            } else {
                Text(languageStore.language.localized("RANGO DEL PERFIL"))
                    .foregroundStyle(PrototypePalette.muted)
            }
        }
        .font(.caption2.weight(.semibold))
        .tracking(0.4)
        .foregroundStyle(PrototypePalette.secondaryText)
        .lineLimit(1)
    }
}

private struct GroupStateControls: View {
    let group: GodoxGroup
    let state: GroupDraft
    let canToggleMode: Bool
    let canChangeOperatingMode: Bool
    let hasAssignedModel: Bool
    let compact: Bool
    let setOperatingMode: (GroupOperatingMode) -> Void
    let setRadioEnabled: (Bool) -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var controller: GodoxSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if compact {
                VStack(alignment: .leading, spacing: 6) {
                    exposureModePicker
                    activationToggle
                }
            } else {
                HStack(spacing: 16) {
                    exposureModePicker
                    activationToggle
                    Spacer(minLength: 0)
                }
            }

            if showsActivationExplanation {
                Text(activationExplanation)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(
                        activationIsEnabled
                            ? PrototypePalette.secondaryText
                            : PrototypePalette.warning
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .toggleStyle(.switch)
        .tint(PrototypePalette.accent)
        .controlSize(.small)
        .font(.caption.weight(.semibold))
        .foregroundStyle(PrototypePalette.secondaryText)
    }

    @ViewBuilder
    private var exposureModePicker: some View {
        HStack(spacing: 7) {
            Text(languageStore.language.localized("Modo").uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.45)
                .foregroundStyle(PrototypePalette.secondaryText)

            if state.draft.operatingMode == .multi {
                Label {
                    Text(languageStore.language.localized("MULTI · GLOBAL"))
                        .font(.caption2.weight(.bold))
                        .tracking(0.45)
                } icon: {
                    Image(systemName: "bolt.circle.fill")
                }
                .foregroundStyle(PrototypePalette.accent)
                .frame(width: compact ? 132 : 154, height: 24)
                .background(
                    Capsule(style: .continuous)
                        .fill(PrototypePalette.brandTile)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(PrototypePalette.accent.opacity(0.7), lineWidth: 1)
                }
                .accessibilityLabel(languageStore.language.localizedFormat(
                    "Modo de exposición del grupo %@",
                    group.label
                ))
                .accessibilityValue(languageStore.language.localized("Multi global"))
            } else {
                Picker(
                    languageStore.language.localizedFormat(
                        "Modo de exposición del grupo %@",
                        group.label
                    ),
                    selection: Binding(
                        get: { displayedOperatingMode },
                        set: setOperatingMode
                    )
                ) {
                    ForEach(selectableOperatingModes, id: \.self) { mode in
                        Text(verbatim: mode == .autoTTL ? "AUTO · TTL" : mode.label)
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: compact ? 132 : 154)
                .disabled(!canChangeOperatingMode || !controller.multiFlashGroups.isEmpty)
                .help(languageStore.language.localized(
                    controller.multiFlashGroups.isEmpty
                        ? "M usa la potencia manual guardada; Auto usa TTL neutro."
                        : "El modo de cada grupo se controla desde el panel global Multi."
                ))
                .accessibilityValue(languageStore.language.localized(modeAccessibilityValue))
            }
        }
    }

    private var selectableOperatingModes: [GroupOperatingMode] {
        controller.availableOperatingModes(for: group).filter {
            $0 == .manual || $0 == .autoTTL
        }
    }

    private var displayedOperatingMode: GroupOperatingMode {
        switch state.draft.operatingMode {
        case .manual, .autoTTL, .multi:
            return state.draft.operatingMode
        case .off:
            if state.lastKnownActiveMode == .autoTTL { return .autoTTL }
            return .manual
        }
    }

    private var modeAccessibilityValue: String {
        switch displayedOperatingMode {
        case .manual: "Manual"
        case .autoTTL: "Auto · TTL"
        case .multi: "Multi"
        case .off: "Off"
        }
    }

    private var activationToggle: some View {
        Toggle(isOn: Binding(
            get: { state.draft.isEnabledOnRadio },
            set: setRadioEnabled
        )) {
            Text(activationTitle)
                .lineLimit(1)
        }
        .disabled(!activationIsEnabled)
        .help(activationExplanation)
        .accessibilityLabel(activationTitle)
        .accessibilityValue(languageStore.language.localized(
            state.draft.isEnabledOnRadio
                ? "Activo"
                : controller.multiFlashGroups.isEmpty
                    ? "Apagado"
                    : "Desactivado en Multi"
        ))
        .accessibilityHint(activationExplanation)
    }

    private var activationIsEnabled: Bool {
        canToggleMode && hasAssignedModel
    }

    private var activationTitle: String {
        if state.draft.operatingMode == .off,
           !controller.multiFlashGroups.isEmpty,
           controller.supportsMultiFlash(group) {
            return languageStore.language.localizedFormat(
                "Añadir grupo %@ a Multi",
                group.label
            )
        }
        return languageStore.language.localizedFormat(
            state.draft.isEnabledOnRadio ? "Grupo %@ activo" : "Activar grupo %@",
            group.label
        )
    }

    private var showsActivationExplanation: Bool {
        !activationIsEnabled || state.draft.operatingMode == .off
    }

    private var activationExplanation: String {
        if !hasAssignedModel {
            return languageStore.language.localizedFormat(
                "Asigna un modelo en Configuración para activar el grupo %@.",
                group.label
            )
        }

        if state.draft.operatingMode == .multi,
           controller.multiFlashGroups.count == 1 {
            return languageStore.language.localized(
                "Desactiva Multi desde el botón MULTI."
            )
        }

        switch state.draft.operatingMode {
        case .off where activationIsEnabled && !controller.multiFlashGroups.isEmpty:
            return languageStore.language.localizedFormat(
                "El grupo %@ está fuera de Multi. Actívalo para añadirlo a la ráfaga global.",
                group.label
            )
        case .off where activationIsEnabled:
            return languageStore.language.localizedFormat(
                "El grupo %@ está apagado. Actívalo para editar potencia y modelado.",
                group.label
            )
        case .manual where activationIsEnabled,
             .autoTTL where activationIsEnabled,
             .multi where activationIsEnabled:
            return languageStore.language.localizedFormat(
                "Desactiva el grupo %@ para dejar de dispararlo; el cambio queda pendiente de envío.",
                group.label
            )
        case .manual, .autoTTL, .multi, .off:
            return languageStore.language.localized(
                "Espera a que termine la operación actual."
            )
        }
    }
}

private func groupInteractionHelp(
    group: GodoxGroup,
    state: GroupDraft,
    canEdit: Bool,
    canToggleMode: Bool,
    canChangeOperatingMode: Bool,
    hasAssignedModel: Bool,
    multiIsActive: Bool,
    language: AppLanguage
) -> String {
    if !hasAssignedModel {
        return language.localizedFormat(
            "Asigna un modelo en Configuración para activar el grupo %@.",
            group.label
        )
    }

    switch state.draft.operatingMode {
    case .off where canToggleMode && multiIsActive:
        return language.localizedFormat(
            "Añade el grupo %@ a la ráfaga Multi global.",
            group.label
        )
    case .off where canToggleMode:
        return language.localizedFormat(
            "Activa el grupo %@ para editar potencia y modelado.",
            group.label
        )
    case .off:
        return language.localized("Espera a que termine la operación actual.")
    case .manual where canEdit:
        return language.localized(
            "Ajusta el grupo; la barra inferior muestra cuándo se envía"
        )
    case .manual:
        return language.localized("Espera a que termine la operación actual.")
    case .autoTTL where canChangeOperatingMode:
        return language.localized(
            "Auto/TTL activo; cambia a M para editar la potencia manual guardada."
        )
    case .autoTTL:
        return language.localized("Espera a que termine la operación actual.")
    case .multi where canChangeOperatingMode:
        return language.localized(
            "Multi activo; ajusta potencia, destellos y Hz en el control global Multi."
        )
    case .multi:
        return language.localized("Espera a que termine la operación actual.")
    }
}

struct VerticalDiscretePowerControl: View {
    let group: GodoxGroup
    let value: ManualPower
    let allowed: [ManualPower]
    let enabled: Bool
    let onChange: (ManualPower) -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var controller: GodoxSessionController
    @State private var interactiveEditToken: GodoxSessionController.InteractiveEditToken?

    private let railX: CGFloat = 88
    private let railInset: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let thumbY = yPosition(for: currentIndex, height: geometry.size.height)
            let fillHeight = allowed.isEmpty
                ? 0
                : max(0, geometry.size.height - railInset - thumbY)

            ZStack(alignment: .topLeading) {
                Capsule(style: .continuous)
                    .fill(PrototypePalette.surfaceRaised)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(PrototypePalette.dividerStrong, lineWidth: 1)
                    }
                    .frame(width: 8, height: max(1, geometry.size.height - (railInset * 2)))
                    .position(x: railX, y: geometry.size.height / 2)

                Capsule(style: .continuous)
                    .fill(PrototypePalette.primaryText.opacity(enabled ? 0.82 : 0.28))
                    .frame(width: 8, height: fillHeight)
                    .position(x: railX, y: thumbY + (fillHeight / 2))

                ForEach(allowed.indices, id: \.self) { index in
                    let power = allowed[index]
                    let fullStop = power.decimalValue.isMultiple(of: 10)
                    let tickWidth: CGFloat = fullStop ? 14 : 7
                    let y = yPosition(for: index, height: geometry.size.height)

                    Rectangle()
                        .fill(
                            index == currentIndex
                                ? PrototypePalette.accent
                                : PrototypePalette.secondaryText.opacity(fullStop ? 0.85 : 0.48)
                        )
                        .frame(width: tickWidth, height: 1)
                        .position(x: 72 - (tickWidth / 2), y: y)

                    if fullStop {
                        Text(fullStopLabel(for: power))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(
                                index == currentIndex
                                    ? PrototypePalette.primaryText
                                    : PrototypePalette.secondaryText
                            )
                            .frame(width: 50, alignment: .trailing)
                            .position(x: 25, y: y)
                    }
                }

                Circle()
                    .fill(PrototypePalette.surface)
                    .frame(width: 25, height: 25)
                    .overlay {
                        Circle()
                            .stroke(PrototypePalette.primaryText.opacity(0.78), lineWidth: 2)
                    }
                    .overlay {
                        Circle()
                            .fill(PrototypePalette.accent)
                            .frame(width: 13, height: 13)
                    }
                    .shadow(color: PrototypePalette.brandShadow, radius: 3, x: 0, y: 1)
                    .position(x: railX, y: thumbY)
                    .opacity(allowed.isEmpty ? 0 : 1)

                if allowed.isEmpty {
                    Text(languageStore.language.localized("SIN MODELO"))
                        .font(.caption2.weight(.bold))
                        .tracking(0.45)
                        .foregroundStyle(PrototypePalette.muted)
                        .frame(width: 62)
                        .position(x: 32, y: geometry.size.height / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updatePower(at: gesture.location.y, height: geometry.size.height)
                    }
                    .onEnded { _ in
                        finishInteractiveEdit()
                    }
            )
        }
        .opacity(enabled ? 1 : 0.48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(languageStore.language.localizedFormat(
            "Potencia del grupo %@",
            group.label
        ))
        .accessibilityValue(value.label)
        .accessibilityHint(languageStore.language.localized(
            "Arrastra verticalmente o pulsa una marca; cada paso equivale a un tercio EV"
        ))
        .accessibilityAdjustableAction { direction in
            applyAccessibilityAdjustment(direction)
        }
        .help("Arrastra o pulsa la escala vertical · pasos discretos de 1/3 EV")
        .background(
            InteractivePointerEditMonitor(
                isEnabled: enabled && allowed.count > 1,
                onEditingChanged: interactiveEditingChanged
            )
        )
        .onChange(of: enabled) { isEnabled in
            if !isEnabled { finishInteractiveEdit() }
        }
        .onChange(of: allowed.count) { count in
            if count < 2 { finishInteractiveEdit() }
        }
        .onDisappear(perform: finishInteractiveEdit)
    }

    private var currentIndex: Int {
        if let exact = allowed.firstIndex(of: value) { return exact }
        return allowed.indices.min {
            abs(allowed[$0].decimalValue - value.decimalValue) <
                abs(allowed[$1].decimalValue - value.decimalValue)
        } ?? 0
    }

    private func yPosition(for index: Int, height: CGFloat) -> CGFloat {
        guard allowed.count > 1 else { return height / 2 }
        let progress = CGFloat(index) / CGFloat(allowed.count - 1)
        return railInset + ((1 - progress) * max(0, height - (railInset * 2)))
    }

    private func updatePower(at y: CGFloat, height: CGFloat) {
        guard enabled, allowed.count > 1 else { return }
        let usableHeight = max(1, height - (railInset * 2))
        let clampedY = min(height - railInset, max(railInset, y))
        let progress = 1 - ((clampedY - railInset) / usableHeight)
        let index = Int((progress * CGFloat(allowed.count - 1)).rounded())
        setPower(at: index)
    }

    private func beginInteractiveEditIfNeeded() -> Bool {
        guard enabled, allowed.count > 1 else { return false }
        if interactiveEditToken == nil {
            interactiveEditToken = controller.beginInteractiveEdit()
        }
        return true
    }

    private func interactiveEditingChanged(_ isEditing: Bool) {
        if isEditing {
            _ = beginInteractiveEditIfNeeded()
        } else {
            finishInteractiveEdit()
        }
    }

    private func finishInteractiveEdit() {
        guard let token = interactiveEditToken else { return }
        interactiveEditToken = nil
        controller.endInteractiveEdit(token)
    }

    private func setPower(at index: Int) {
        guard enabled, allowed.indices.contains(index), allowed[index] != value else { return }
        onChange(allowed[index])
    }

    func applyAccessibilityAdjustment(_ direction: AccessibilityAdjustmentDirection) {
        guard enabled else { return }
        switch direction {
        case .increment:
            setPower(at: currentIndex + 1)
        case .decrement:
            setPower(at: currentIndex - 1)
        @unknown default:
            break
        }
    }

    private func fullStopLabel(for power: ManualPower) -> String {
        power.label.split(separator: " ").first.map(String.init) ?? power.label
    }
}

struct DiscretePowerSlider: View {
    let group: GodoxGroup
    let value: ManualPower
    let allowed: [ManualPower]
    let enabled: Bool
    let onChange: (ManualPower) -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var controller: GodoxSessionController
    @State private var interactiveEditToken: GodoxSessionController.InteractiveEditToken?

    var body: some View {
        Slider(
            value: Binding(
                get: { Double(currentIndex) },
                set: applyDiscreteInput
            ),
            in: 0...Double(max(allowed.count - 1, 1)),
            step: 1
        )
        .controlSize(.small)
        .tint(PrototypePalette.accent)
        .disabled(!enabled || allowed.count < 2)
        .background(
            InteractivePointerEditMonitor(
                isEnabled: enabled && allowed.count > 1,
                onEditingChanged: interactiveEditingChanged
            )
        )
        .accessibilityLabel(languageStore.language.localizedFormat(
            "Potencia del grupo %@",
            group.label
        ))
        .accessibilityValue(value.label)
        .help("Pasos de 1/3 EV; la barra inferior muestra cuándo se envía")
        .onChange(of: enabled) { isEnabled in
            if !isEnabled { finishInteractiveEdit() }
        }
        .onChange(of: allowed.count) { count in
            if count < 2 { finishInteractiveEdit() }
        }
        .onDisappear(perform: finishInteractiveEdit)
    }

    private var currentIndex: Int {
        allowed.firstIndex(of: value) ?? 0
    }

    func applyDiscreteInput(_ rawIndex: Double) {
        let index = Int(rawIndex.rounded())
        guard enabled, allowed.indices.contains(index) else { return }
        onChange(allowed[index])
    }

    private func interactiveEditingChanged(_ isEditing: Bool) {
        if isEditing, enabled, allowed.count > 1 {
            if interactiveEditToken == nil {
                interactiveEditToken = controller.beginInteractiveEdit()
            }
        } else {
            finishInteractiveEdit()
        }
    }

    private func finishInteractiveEdit() {
        guard let token = interactiveEditToken else { return }
        interactiveEditToken = nil
        controller.endInteractiveEdit(token)
    }
}

private enum ModelingModeChoice: String, CaseIterable, Identifiable {
    case off
    case proportional
    case fixed

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .off:
            "lightbulb.slash"
        case .proportional:
            "lightbulb.max"
        case .fixed:
            "lightbulb"
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .off:
            language.localized("Apagada")
        case .proportional:
            language.localized("Proporcional")
        case .fixed:
            language == .es ? "Fija" : "Fixed"
        }
    }

    init(_ modeling: ModelingLight) {
        switch modeling {
        case .off:
            self = .off
        case .proportional:
            self = .proportional
        case .fixed:
            self = .fixed
        }
    }
}

/// Coordinates the custom modeling dropdowns across Channels, Inspector, and
/// Matrix so only one group menu can remain open at a time.
private final class ModelingMenuCoordinator: ObservableObject {
    static let shared = ModelingMenuCoordinator()

    @Published private(set) var openMenuID: UUID?

    private var localMouseMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?

    private init() {
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.close()
        }
    }

    deinit {
        stopMonitoringClicks()
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
    }

    func toggle(_ menuID: UUID) {
        if openMenuID == menuID {
            close(menuID)
        } else {
            openMenuID = menuID
            startMonitoringClicks()
        }
    }

    func close(_ menuID: UUID? = nil) {
        guard menuID == nil || openMenuID == menuID else { return }
        openMenuID = nil
        stopMonitoringClicks()
    }

    private func startMonitoringClicks() {
        guard localMouseMonitor == nil else { return }
        // SwiftUI menu-row buttons commit on mouse-up. Monitoring mouse-down
        // can remove the row before its action fires during a normal held click.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            guard let self, let menuIDAtMouseDown = self.openMenuID else {
                return event
            }

            // The clicked control handles the event first. If it opens another
            // group, the new ID protects that menu from this deferred close.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.openMenuID == menuIDAtMouseDown else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    self.close(menuIDAtMouseDown)
                }
            }
            return event
        }
    }

    private func stopMonitoringClicks() {
        guard let localMouseMonitor else { return }
        NSEvent.removeMonitor(localMouseMonitor)
        self.localMouseMonitor = nil
    }
}

private struct ModelingEditor: View {
    let group: GodoxGroup
    let value: ModelingLight
    let baseline: ModelingLight
    let allowed: [ModelingLight]
    let enabled: Bool
    let compact: Bool
    let onChange: (ModelingLight) -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore
    @ObservedObject private var menuCoordinator = ModelingMenuCoordinator.shared
    @State private var menuID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 12) {
            modelingModeSelector

            if case .fixed(let percent) = value, !isModeMenuExpanded {
                VerticalFixedIntensityControl(
                    group: group,
                    percent: percent,
                    allowedPercents: fixedPercents,
                    enabled: enabled,
                    compact: compact,
                    onChange: { onChange(.fixed(percent: $0)) }
                )
            }
        }
        .zIndex(isModeMenuExpanded ? 20 : 0)
        .onChange(of: enabled) { isEnabled in
            if !isEnabled {
                menuCoordinator.close(menuID)
            }
        }
        .onDisappear {
            menuCoordinator.close(menuID)
        }
    }

    @ViewBuilder
    private var modelingModeSelector: some View {
        let controlWidth: CGFloat = compact ? 112 : 160
        let menuWidth: CGFloat = compact ? 170 : 190
        let buttonOffset = (controlWidth - 36) / 2

        ZStack(alignment: .topLeading) {
            Button {
                guard enabled, allowedModes.count > 1 else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    menuCoordinator.toggle(menuID)
                }
            } label: {
                Image(systemName: currentMode.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(enabled ? PrototypePalette.primaryText : PrototypePalette.muted)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(PrototypePalette.surfaceRaised)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                enabled ? PrototypePalette.modeling : PrototypePalette.divider,
                                lineWidth: enabled ? 1.25 : 1
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        if baseline != value {
                            Circle()
                                .fill(PrototypePalette.warning)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled || allowedModes.count < 2)
            .offset(x: buttonOffset)
            .accessibilityLabel(languageStore.language.localizedFormat(
                "Luz de modelado del grupo %@",
                group.label
            ))
            .accessibilityValue(currentMode.title(in: languageStore.language))
            .accessibilityHint(
                languageStore.language == .es
                    ? "Abre las opciones Apagada, Proporcional y Fija"
                    : "Opens Off, Proportional, and Fixed options"
            )

            if isModeMenuExpanded {
                modelingModeMenu(width: menuWidth)
                    .offset(x: (controlWidth - menuWidth) / 2, y: 43)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .zIndex(1)
            }
        }
        .frame(
            width: controlWidth,
            height: isModeMenuExpanded ? 179 : 36,
            alignment: .topLeading
        )
        .onExitCommand {
            menuCoordinator.close(menuID)
        }
    }

    private func modelingModeMenu(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(ModelingModeChoice.allCases.enumerated()), id: \.element.id) { index, mode in
                Button {
                    guard enabled, allowedModes.contains(mode) else { return }
                    modeBinding.wrappedValue = mode
                    withAnimation(.easeOut(duration: 0.1)) {
                        menuCoordinator.close(menuID)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 22)

                        Text(mode.title(in: languageStore.language).uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(0.25)

                        Spacer(minLength: 8)

                        if mode == currentMode {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(PrototypePalette.modeling)
                        }
                    }
                    .foregroundStyle(
                        allowedModes.contains(mode)
                            ? PrototypePalette.primaryText
                            : PrototypePalette.muted
                    )
                    .padding(.horizontal, 12)
                    .frame(width: width, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled || !allowedModes.contains(mode))
                .accessibilityLabel(mode.title(in: languageStore.language))
                .accessibilityAddTraits(mode == currentMode ? .isSelected : [])

                if index < ModelingModeChoice.allCases.count - 1 {
                    Rectangle()
                        .fill(PrototypePalette.divider)
                        .frame(height: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PrototypePalette.surface)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PrototypePalette.dividerStrong, lineWidth: 1)
        }
    }

    private var modeBinding: Binding<ModelingModeChoice> {
        Binding(
            get: { ModelingModeChoice(value) },
            set: { mode in
                switch mode {
                case .off:
                    onChange(.off)
                case .proportional:
                    onChange(.proportional)
                case .fixed:
                    let preferred = currentFixedPercent.flatMap { fixedPercents.contains($0) ? $0 : nil }
                        ?? (fixedPercents.contains(25) ? 25 : fixedPercents.first)
                    if let preferred {
                        onChange(.fixed(percent: preferred))
                    }
                }
            }
        )
    }

    private var allowedModes: Set<ModelingModeChoice> {
        Set(allowed.map(ModelingModeChoice.init))
    }

    private var fixedPercents: [Int] {
        Array(Set(allowed.compactMap {
            if case .fixed(let percent) = $0 { return percent }
            return nil
        })).sorted()
    }

    private var currentFixedPercent: Int? {
        if case .fixed(let percent) = value { return percent }
        return nil
    }

    private var currentMode: ModelingModeChoice {
        ModelingModeChoice(value)
    }

    private var isModeMenuExpanded: Bool {
        menuCoordinator.openMenuID == menuID
    }
}

struct VerticalFixedIntensityControl: View {
    let group: GodoxGroup
    let percent: Int
    let allowedPercents: [Int]
    let enabled: Bool
    let compact: Bool
    let onChange: (Int) -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var controller: GodoxSessionController
    @State private var interactiveEditToken: GodoxSessionController.InteractiveEditToken?

    private let railInset: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(languageStore.language.localized("INTENSIDAD"))
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(PrototypePalette.secondaryText)

            GeometryReader { geometry in
                let height = geometry.size.height

                ZStack(alignment: .topLeading) {
                    ForEach(Array(stride(from: 100, through: 10, by: -10)), id: \.self) { mark in
                        let y = position(for: mark, height: height)

                        Text("\(mark)%")
                            .font(.system(size: compact ? 7.5 : 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PrototypePalette.secondaryText)
                            .frame(width: 34, alignment: .trailing)
                            .position(x: 17, y: y)

                        Capsule(style: .continuous)
                            .fill(PrototypePalette.secondaryText.opacity(0.72))
                            .frame(width: mark.isMultiple(of: 20) ? 9 : 6, height: 1)
                            .position(x: 43, y: y)
                    }

                    Capsule(style: .continuous)
                        .fill(PrototypePalette.surfaceRaised)
                        .frame(width: 8, height: max(1, height - (railInset * 2)))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(PrototypePalette.dividerStrong, lineWidth: 1)
                        }
                        .position(x: 58, y: height / 2)

                    ZStack {
                        Circle()
                            .fill(PrototypePalette.surface)
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle()
                                    .stroke(PrototypePalette.primaryText, lineWidth: 1.5)
                            }
                        Circle()
                            .fill(PrototypePalette.modeling)
                            .frame(width: 11, height: 11)
                    }
                    .position(x: 58, y: position(for: percent, height: height))

                    Text("\(percent)%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(PrototypePalette.modeling)
                        .frame(width: 42, alignment: .leading)
                        .position(x: 91, y: position(for: percent, height: height))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            updatePercent(at: gesture.location.y, height: height)
                        }
                        .onEnded { _ in
                            finishInteractiveEdit()
                        }
                )
            }
            .frame(width: 112, height: compact ? 122 : 138)
        }
        .opacity(enabled && !allowedPercents.isEmpty ? 1 : 0.48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(languageStore.language.localizedFormat(
            "Intensidad de modelado del grupo %@",
            group.label
        ))
        .accessibilityValue(
            languageStore.language == .es
                ? "\(percent) por ciento"
                : "\(percent) percent"
        )
        .accessibilityHint(languageStore.language.localized(
            "Porcentaje fijo; la barra inferior muestra cuándo se envía"
        ))
        .accessibilityAdjustableAction { direction in
            applyAccessibilityAdjustment(direction)
        }
        .help(languageStore.language.localized(
            allowedPercents.count > 1
                ? "Porcentaje fijo; la barra inferior muestra cuándo se envía"
                : "Este flash utiliza un único valor de intensidad"
        ))
        .background(
            InteractivePointerEditMonitor(
                isEnabled: enabled && allowedPercents.count > 1,
                onEditingChanged: interactiveEditingChanged
            )
        )
        .onChange(of: enabled) { isEnabled in
            if !isEnabled { finishInteractiveEdit() }
        }
        .onChange(of: allowedPercents.count) { count in
            if count < 2 { finishInteractiveEdit() }
        }
        .onDisappear(perform: finishInteractiveEdit)
    }

    private func position(for rawPercent: Int, height: CGFloat) -> CGFloat {
        let clamped = min(100, max(10, rawPercent))
        let progress = CGFloat(100 - clamped) / 90
        return railInset + (progress * max(0, height - (railInset * 2)))
    }

    private func updatePercent(at y: CGFloat, height: CGFloat) {
        guard enabled, allowedPercents.count > 1 else { return }
        let usableHeight = max(1, height - (railInset * 2))
        let clampedY = min(height - railInset, max(railInset, y))
        let estimated = 100 - Int((((clampedY - railInset) / usableHeight) * 90).rounded())
        guard let nearest = allowedPercents.min(by: {
            abs($0 - estimated) < abs($1 - estimated)
        }), nearest != percent else {
            return
        }
        onChange(nearest)
    }

    private func beginInteractiveEditIfNeeded() -> Bool {
        guard enabled, allowedPercents.count > 1 else { return false }
        if interactiveEditToken == nil {
            interactiveEditToken = controller.beginInteractiveEdit()
        }
        return true
    }

    private func interactiveEditingChanged(_ isEditing: Bool) {
        if isEditing {
            _ = beginInteractiveEditIfNeeded()
        } else {
            finishInteractiveEdit()
        }
    }

    private func finishInteractiveEdit() {
        guard let token = interactiveEditToken else { return }
        interactiveEditToken = nil
        controller.endInteractiveEdit(token)
    }

    func applyAccessibilityAdjustment(_ direction: AccessibilityAdjustmentDirection) {
        guard enabled, !allowedPercents.isEmpty else { return }
        let index = allowedPercents.firstIndex(of: percent)
            ?? allowedPercents.enumerated().min(by: {
                abs($0.element - percent) < abs($1.element - percent)
            })?.offset
            ?? 0
        let nextIndex: Int
        switch direction {
        case .increment:
            nextIndex = min(allowedPercents.count - 1, index + 1)
        case .decrement:
            nextIndex = max(0, index - 1)
        @unknown default:
            return
        }
        guard allowedPercents[nextIndex] != percent else { return }
        onChange(allowedPercents[nextIndex])
    }
}

private struct DraftChangeDot: View {
    let changed: Bool

    var body: some View {
        Circle()
            .fill(changed ? PrototypePalette.warning : PrototypePalette.muted.opacity(0.25))
            .frame(width: 5, height: 5)
            .accessibilityHidden(true)
    }
}

private struct GroupVisibilityTile: View {
    let group: GodoxGroup
    let isVisible: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    var body: some View {
        let identity = group.visualIdentity
        let fill = Color(estroboRGB: identity.fillRGB)
        let foreground = Color(estroboRGB: identity.foregroundRGB)
        let tintOpacity = colorScheme == .dark ? 0.20 : 0.14
        let borderOpacity = accessibilityContrast == .increased
            ? 0.82
            : (colorScheme == .dark ? 0.56 : 0.42)

        Text(group.label)
            .font(.callout.weight(.bold))
            .foregroundStyle(isVisible ? foreground : PrototypePalette.primaryText)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isVisible ? fill : PrototypePalette.surfaceRaised)
                    .overlay {
                        if !isVisible {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(fill.opacity(tintOpacity))
                        }
                    }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isVisible
                            ? foreground.opacity(accessibilityContrast == .increased ? 0.58 : 0.28)
                            : fill.opacity(borderOpacity),
                        lineWidth: accessibilityContrast == .increased ? 1.5 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isVisible {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(foreground)
                        .frame(width: 13, height: 13)
                        .background(Circle().fill(foreground.opacity(0.13)))
                        .padding(3)
                } else {
                    Circle()
                        .fill(fill)
                        .frame(width: 6, height: 6)
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(.easeInOut(duration: 0.14), value: isVisible)
    }
}

private struct GroupBadge: View {
    let group: GodoxGroup
    var isPending = false
    var size: CGFloat = 34
    var fontSize: CGFloat = 17
    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    var body: some View {
        let identity = group.visualIdentity

        Text(group.label)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(Color(estroboRGB: identity.foregroundRGB))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: max(6, size * 0.21), style: .continuous)
                    .fill(Color(estroboRGB: identity.fillRGB))
            )
            .overlay {
                RoundedRectangle(cornerRadius: max(6, size * 0.21), style: .continuous)
                    .stroke(
                        PrototypePalette.primaryText.opacity(
                            accessibilityContrast == .increased ? 0.42 : 0.16
                        ),
                        lineWidth: accessibilityContrast == .increased ? 1.5 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isPending {
                    Circle()
                        .fill(PrototypePalette.warning)
                        .overlay {
                            Circle()
                                .stroke(PrototypePalette.windowBackground, lineWidth: 2)
                        }
                        .frame(width: 9, height: 9)
                        .offset(x: 3, y: -3)
                }
            }
            .accessibilityLabel(group.label)
    }
}

private struct StepButton: View {
    let title: String
    let accessibilityLabel: String
    let enabled: Bool
    let action: () -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(width: 38, height: 34)
                .background(stepButtonSurface(enabled: enabled))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(languageStore.language.localizedMessage(accessibilityLabel))
    }
}

private struct LargeStepButton: View {
    let title: String
    let accessibilityLabel: String
    let enabled: Bool
    let action: () -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .frame(width: 76, height: 40)
                .background(stepButtonSurface(enabled: enabled))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(languageStore.language.localizedMessage(accessibilityLabel))
    }
}

private struct WideStepButton: View {
    let title: String
    let accessibilityLabel: String
    let enabled: Bool
    let action: () -> Void
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(stepButtonSurface(enabled: enabled))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(languageStore.language.localizedMessage(accessibilityLabel))
    }
}

private struct QuietButtonStyle: ButtonStyle {
    let height: CGFloat

    init(height: CGFloat = 32) {
        self.height = height
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(PrototypePalette.primaryText)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? PrototypePalette.surfaceRaised : PrototypePalette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(PrototypePalette.divider, lineWidth: 1)
                    }
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(
                isEnabled ? PrototypePalette.accentText : PrototypePalette.muted
            )
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isEnabled
                            ? PrototypePalette.accent.opacity(configuration.isPressed ? 0.74 : 1)
                            : PrototypePalette.surfaceRaised
                    )
            )
    }
}

private struct WorkspacePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(
                isEnabled ? PrototypePalette.brandRing : PrototypePalette.muted
            )
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isEnabled
                            ? PrototypePalette.brandTile.opacity(configuration.isPressed ? 0.78 : 1)
                            : PrototypePalette.surfaceRaised
                    )
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

private struct ApplyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(
                isEnabled
                    ? PrototypePalette.accentText
                    : PrototypePalette.muted
            )
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isEnabled
                            ? PrototypePalette.accent.opacity(configuration.isPressed ? 0.72 : 1)
                            : PrototypePalette.surfaceRaised
                    )
            )
    }
}

private struct TestButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(
                isEnabled
                    ? PrototypePalette.accentText
                    : PrototypePalette.muted
            )
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isEnabled
                            ? PrototypePalette.accent.opacity(configuration.isPressed ? 0.72 : 1)
                            : PrototypePalette.surfaceRaised
                    )
            )
    }
}

private struct PrototypePanelModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PrototypePalette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(PrototypePalette.divider, lineWidth: 1)
                    }
            )
    }
}

private struct PrototypeBadgeModifier: ViewModifier {
    let foreground: Color
    let background: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.35)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
    }
}

private extension View {
    func prototypePanel(padding: CGFloat) -> some View {
        modifier(PrototypePanelModifier(padding: padding))
    }

    func prototypeBadge(foreground: Color, background: Color) -> some View {
        modifier(
            PrototypeBadgeModifier(
                foreground: foreground,
                background: background
            )
        )
    }
}

@ViewBuilder
private func groupSurface(isPending: Bool) -> some View {
    RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(isPending ? PrototypePalette.accent.opacity(0.065) : PrototypePalette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isPending
                        ? PrototypePalette.accent.opacity(0.44)
                        : PrototypePalette.dividerStrong,
                    lineWidth: 1
                )
        }
}

@ViewBuilder
private func stepButtonSurface(enabled: Bool) -> some View {
    RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(enabled ? PrototypePalette.surfaceRaised : PrototypePalette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(PrototypePalette.divider, lineWidth: 1)
        }
}

private func confirmationColor(_ confirmation: GroupConfirmation) -> Color {
    switch confirmation {
    case .unread: PrototypePalette.muted
    case .gattAccepted: PrototypePalette.warning
    case .radioResponded: PrototypePalette.success
    case .failed: PrototypePalette.error
    }
}

private func confirmationLabel(_ confirmation: GroupConfirmation) -> String {
    switch confirmation {
    case .unread: "SIN LEER"
    default: confirmation.label
    }
}

private func compactConfirmationLabel(_ confirmation: GroupConfirmation) -> String {
    switch confirmation {
    case .unread: "SIN LEER"
    case .gattAccepted: "WRITE OK"
    case .radioResponded: "FEC8"
    case .failed: "ERROR"
    }
}

private enum PrototypePalette {
    static let windowBackground = adaptive(light: 0xF7F4EE, dark: 0x18191B)
    static let surface = adaptive(light: 0xFFFEFA, dark: 0x1D1F22)
    static let surfaceRaised = adaptive(light: 0xEAEDEF, dark: 0x292C31)
    static let globalSurface = adaptive(light: 0xFAF8F3, dark: 0x202226)
    static let footerSurface = adaptive(light: 0xF2EFE8, dark: 0x17181A)
    static let divider = adaptive(light: 0xD8DCDE, dark: 0x35383D)
    static let dividerStrong = adaptive(light: 0xC3CACE, dark: 0x4A4E55)
    static let primaryText = adaptive(light: 0x09223F, dark: 0xF7F4ED)
    static let secondaryText = adaptive(light: 0x607083, dark: 0xB5B7BB)
    static let muted = adaptive(light: 0x8B959E, dark: 0x7D8086)
    static let accent = Color(red: 1.0, green: 0.67, blue: 0.09)
    static let accentText = adaptive(light: 0x081A2E, dark: 0x151515)
    static let success = adaptive(light: 0x16845C, dark: 0x5BD49A)
    static let warning = adaptive(light: 0xB87308, dark: 0xF0AD42)
    static let error = adaptive(light: 0xC3433E, dark: 0xFF746D)
    static let modeling = Color(red: 1.0, green: 0.67, blue: 0.09)
    static let brandTile = Color(red: 0.025, green: 0.105, blue: 0.205)
    static let brandRing = adaptive(light: 0xF7F4EA, dark: 0xFFFDF7)
    static let brandWordmark = adaptive(light: 0x08213F, dark: 0xFFFDF7)
    static let brandShadow = adaptive(light: 0x183B5E, dark: 0x000000).opacity(0.22)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return nsColor(match == .darkAqua ? dark : light)
        })
    }

    private static func nsColor(_ value: UInt32) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
