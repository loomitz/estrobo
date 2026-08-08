import Foundation
import Combine

@MainActor
final class GodoxSessionController: NSObject, ObservableObject, BluetoothClientDelegate {
    struct InteractiveEditToken: Hashable {
        fileprivate let id = UUID()
    }

    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var devices: [BluetoothClient.Device] = []
    @Published var selectedDeviceID: UUID?
    @Published var radioCode = ""
    @Published var rememberSelectedRadio = false
    @Published private(set) var savedRadios: [SavedRadio]
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var groups: [GodoxGroup: GroupDraft]
    @Published private(set) var transmitterProfile: TransmitterProfile
    @Published private(set) var availableTransmitterProfiles: [TransmitterProfile]
    @Published private(set) var defaultTransmitterProfileID: String
    @Published private(set) var groupConfigurations: [GodoxGroup: GroupConfiguration]
    @Published private(set) var hasCompletedOnboarding = false
    /// Distingue una instalación nueva de una configuración guardada que se
    /// está editando o reanudando. `hasCompletedOnboarding` no basta porque se
    /// vuelve temporalmente falso mientras se abre la reconfiguración.
    private(set) var hasStoredWorkspaceConfiguration = false
    @Published private(set) var isReconfiguringWorkspace = false
    @Published private(set) var workingGroups: [GodoxGroup]
    @Published private(set) var visibleGroups: [GodoxGroup]
    @Published private(set) var physicalSafetyState = PhysicalOperationSafetyState()
    @Published private(set) var recoveryBlockReason: String?
    @Published private(set) var activity: [ActivityItem] = []
    @Published private(set) var lastRadioResponseAt: Date?
    @Published private(set) var changeDeliveryMode: ChangeDeliveryMode
    @Published private(set) var isAutomaticApplyScheduled = false
    @Published private(set) var applySequenceStatus: ApplySequenceStatus?
    @Published private(set) var isTestPending = false
    @Published private(set) var isSynchronizingValues = false
    @Published private(set) var lastValueSynchronizationAt: Date?
    @Published private(set) var presets: [StudioPreset] = []
    @Published private(set) var activePresetID: UUID?
    @Published private(set) var globalBeepEnabled = false
    @Published private(set) var multiFlashBaseline = MultiFlashSettings.default
    @Published private(set) var multiFlashDraft = MultiFlashSettings.default
    @Published private(set) var isGlobalStandbyEnabled = false
    @Published private(set) var isGlobalControlPending = false
    @Published private(set) var activeInteractiveEditCount = 0

    private enum ApplySequencePurpose: Equatable {
        case pendingChanges
        case connectionSynchronization
        case manualSynchronization
        case presetSynchronization(UUID)

        var synchronizesValues: Bool {
            self != .pendingChanges
        }

        var keepsConnectionFlowVisible: Bool {
            self == .connectionSynchronization
        }
    }

    private enum ApplySequenceJournalKind {
        case none
        case forward
        case restoration
    }

    private enum GlobalControlPurpose {
        case valueSynchronization(ApplySequencePurpose)
        case pendingChanges
        case beep
        case standby

        var keepsConnectionFlowVisible: Bool {
            if case .valueSynchronization(let purpose) = self {
                return purpose.keepsConnectionFlowVisible
            }
            return false
        }
    }

    private struct GlobalControlFollowup {
        let groups: [GodoxGroup]
        let purpose: ApplySequencePurpose
        let forceWrite: Bool
        let restorationGlobalSnapshot: GlobalRadioSnapshot
    }

    private struct QueuedGroupChange {
        let group: GodoxGroup
        let snapshot: ManualGroupSnapshot
        let frame: Data
        let forceWrite: Bool
        let restorationSnapshot: ManualGroupSnapshot
        let restorationGlobalSnapshot: GlobalRadioSnapshot?
        let restorationUnderlyingMultiMode: GroupOperatingMode?
        let restorationRestoresAfterMulti: Bool
    }

    private struct GlobalPowerPosition {
        let group: GodoxGroup
        let allowed: [ManualPower]
        let anchorIndex: Int
    }

    private struct InitialMultiScenePlan {
        let groups: [GodoxGroup: GroupDraft]
        let settings: MultiFlashSettings
        let activatedGroups: [GodoxGroup]
        let disabledGroups: [GodoxGroup]
    }

    private struct ManualMultiScenePlan {
        let groups: [GodoxGroup: GroupDraft]
        let normalizedPowers: [(group: GodoxGroup, power: ManualPower)]
    }

    private enum ControlIntent {
        case global(
            intentID: UUID,
            deviceID: UUID,
            sessionID: UUID,
            snapshot: GlobalRadioSnapshot,
            previousSnapshot: GlobalRadioSnapshot,
            purpose: GlobalControlPurpose,
            followup: GlobalControlFollowup?
        )
        case group(
            intentID: UUID,
            deviceID: UUID,
            sessionID: UUID,
            group: GodoxGroup,
            snapshot: ManualGroupSnapshot
        )
        case heartbeat(deviceID: UUID, sessionID: UUID, intentID: UUID)

        var id: UUID {
            switch self {
            case .global(let intentID, _, _, _, _, _, _),
                 .group(let intentID, _, _, _, _),
                 .heartbeat(_, _, let intentID):
                intentID
            }
        }
    }

    private enum DisconnectResolution {
        case idle
        case failure(String)
    }

    private var client: (any GodoxSessionTransport)!
    private let deadlineScheduler: any SessionDeadlineScheduling
    private var authenticationAttempt: UUID?
    private var scanDeadline: SessionDeadlineToken?
    private var connectionSetupDeadline: SessionDeadlineToken?
    private var disconnectRecoveryDeadline: SessionDeadlineToken?
    private var automaticApplyDeadline: SessionDeadlineToken?
    private var valueSynchronizationSettleDeadline: SessionDeadlineToken?
    private var testDeliveryDeadline: SessionDeadlineToken?
    private var pendingDisconnectResolution: DisconnectResolution?
    private var authenticationTimeout: SessionDeadlineToken?
    private var synchronizationDelay: Task<Void, Never>?
    private var synchronizationTimeout: Task<Void, Never>?
    private var controlTimeout: Task<Void, Never>?
    private var heartbeatTimeouts: [UUID: SessionDeadlineToken] = [:]
    private var radioResponseTimeouts: [GodoxGroup: Task<Void, Never>] = [:]
    private var controlIntents: [ControlIntent] = []
    private var submittingControlIntentID: UUID?
    private var awaitingRadioResponses: [GodoxGroup] = []
    private var snapshotsAwaitingRadioResponse: [GodoxGroup: ManualGroupSnapshot] = [:]
    private var controlWriteHasStarted = false
    private var sessionIsInvalidating = false
    private var shouldSaveRadioAfterAuthentication = false
    private var selectedDeviceWasChosenExplicitly = false
    private var sessionDeviceID: UUID?
    private var sessionID: UUID?
    private var queuedGroupChanges: [QueuedGroupChange] = []
    private var activeGroupChange: QueuedGroupChange?
    private var applySequenceCompletedCount = 0
    private var applySequenceTotalCount = 0
    private var applySequencePurpose: ApplySequencePurpose = .pendingChanges
    private var applySequenceJournalKind: ApplySequenceJournalKind = .none
    private var automaticApplySuppressedForLocalPreset = false
    private var interactiveEditTokens: Set<InteractiveEditToken> = []
    private var globalRadioSnapshot = GlobalRadioSnapshot(
        apkDefaultsWithBeepEnabled: false,
        modelingLightEnabled: false,
        standbyEnabled: false
    )
    private var hasConfirmedGlobalSnapshot = false
    private let visibilityPreferences: LocalGroupPreferences
    private let restorationStore: PendingRestorationStore
    private let savedRadioStore: SavedRadioStore
    private let changeDeliveryPreferences: ChangeDeliveryPreferences
    private let transmitterProfilePreferences: TransmitterProfilePreferences
    private let studioLibraryStore: StudioLibraryStore

    var restorationPoints: [GodoxGroup: GroupRestorationPoint] {
        physicalSafetyState.restorationPoints
    }

    var preparedRestorations: Set<GodoxGroup> {
        physicalSafetyState.preparedRestorations
    }

    override convenience init() {
        self.init(
            transport: nil,
            deadlineScheduler: LiveSessionDeadlineScheduler(),
            visibilityPreferences: LocalGroupPreferences(),
            restorationStore: PendingRestorationStore(),
            savedRadioStore: SavedRadioStore(),
            changeDeliveryPreferences: ChangeDeliveryPreferences(),
            transmitterProfilePreferences: TransmitterProfilePreferences(),
            studioLibraryStore: StudioLibraryStore()
        )
    }

    init(
        transport: (any GodoxSessionTransport)?,
        deadlineScheduler: any SessionDeadlineScheduling,
        visibilityPreferences initialVisibilityPreferences: LocalGroupPreferences,
        restorationStore initialRestorationStore: PendingRestorationStore,
        savedRadioStore initialSavedRadioStore: SavedRadioStore = SavedRadioStore(),
        changeDeliveryPreferences initialChangeDeliveryPreferences: ChangeDeliveryPreferences = ChangeDeliveryPreferences(),
        transmitterProfilePreferences initialTransmitterProfilePreferences: TransmitterProfilePreferences = TransmitterProfilePreferences(),
        studioLibraryStore initialStudioLibraryStore: StudioLibraryStore = StudioLibraryStore()
    ) {
        self.deadlineScheduler = deadlineScheduler
        let loadedLibrary: StudioLibrary?
        let studioLibraryLoadWasInvalid: Bool
        switch initialStudioLibraryStore.load() {
        case .none:
            loadedLibrary = nil
            studioLibraryLoadWasInvalid = false
        case .record(let library):
            loadedLibrary = library
            studioLibraryLoadWasInvalid = false
        case .invalid:
            loadedLibrary = nil
            studioLibraryLoadWasInvalid = true
        }
        let builtInProfiles = TransmitterProfile.available
        let builtInProfileIDs = builtInProfiles.map(\.id)
        let profilePreferenceState = initialTransmitterProfilePreferences.load(
            builtInProfileIDs: builtInProfileIDs,
            fallbackDefaultProfileID: TransmitterProfile.observedGDBH.id
        )
        let availableProfileIDs = Set(profilePreferenceState.availableProfileIDs)
        let initialAvailableProfiles = builtInProfiles.filter {
            availableProfileIDs.contains($0.id)
        }
        let storedProfile = loadedLibrary.flatMap { library in
            initialAvailableProfiles.first {
                $0.id == library.workspace.profileID
            }
        }
        let defaultProfile = initialAvailableProfiles.first {
            $0.id == profilePreferenceState.defaultProfileID
        }
        let initialProfile = storedProfile ?? defaultProfile ?? initialAvailableProfiles[0]
        let restoredWorkspace: StudioWorkspace?
        if let workspace = loadedLibrary?.workspace,
           Self.isCompatible(workspace: workspace, with: initialProfile) {
            restoredWorkspace = workspace
        } else {
            restoredWorkspace = nil
        }
        transmitterProfile = initialProfile
        availableTransmitterProfiles = initialAvailableProfiles
        defaultTransmitterProfileID = profilePreferenceState.defaultProfileID
        visibilityPreferences = initialVisibilityPreferences
        restorationStore = initialRestorationStore
        savedRadioStore = initialSavedRadioStore
        changeDeliveryPreferences = initialChangeDeliveryPreferences
        transmitterProfilePreferences = initialTransmitterProfilePreferences
        studioLibraryStore = initialStudioLibraryStore
        presets = loadedLibrary?.presets ?? []
        changeDeliveryMode = initialChangeDeliveryPreferences.load()
        let savedRadioLoadWasInvalid: Bool
        switch initialSavedRadioStore.load() {
        case .none:
            savedRadios = []
            savedRadioLoadWasInvalid = false
        case .records(let radios):
            savedRadios = radios
            savedRadioLoadWasInvalid = false
        case .invalid:
            savedRadios = []
            savedRadioLoadWasInvalid = true
        }

        let hiddenBaseline = ManualGroupSnapshot(
            power: ManualPower.value(decimal: 30)!,
            modeling: .proportional,
            operatingMode: .off
        )
        var initialGroups = Dictionary(uniqueKeysWithValues: GodoxGroup.allCases.map {
            ($0, GroupDraft(baseline: hiddenBaseline, draft: hiddenBaseline))
        })
        let groupBBaseline = ManualGroupSnapshot(
            power: ManualPower.value(decimal: 10)!,
            modeling: .off
        )
        initialGroups[.b] = GroupDraft(baseline: groupBBaseline, draft: groupBBaseline)

        let groupCBaseline = ManualGroupSnapshot(
            power: ManualPower.value(decimal: 27)!,
            modeling: .proportional
        )
        initialGroups[.c] = GroupDraft(baseline: groupCBaseline, draft: groupCBaseline)
        if let restoredWorkspace {
            for group in restoredWorkspace.workingGroups {
                guard let stored = restoredWorkspace.groupConfigurations[group] else { continue }
                initialGroups[group] = GroupDraft(
                    baseline: stored.snapshot,
                    draft: stored.snapshot,
                    lastKnownActiveMode: stored.lastKnownActiveMode,
                    restoresAfterMulti: stored.restoresAfterMulti
                )
            }
        }
        var recoveredRestorationGroups: [GodoxGroup] = []
        var initialPhysicalSafetyState = PhysicalOperationSafetyState()
        switch initialRestorationStore.load() {
        case .none:
            break
        case .record(let group, let point):
            let points = [group: point]
            if initialPhysicalSafetyState.begin(points: points) {
                recoveredRestorationGroups = [group]
                initialGroups[group] = GroupDraft(
                    baseline: point.snapshot,
                    draft: point.snapshot,
                    confirmation: .failed("Recuperación pendiente de una sesión anterior"),
                    lastKnownActiveMode: point.multiUnderlyingMode,
                    restoresAfterMulti: point.restoresAfterMulti
                )
            } else {
                recoveryBlockReason = "El registro local de restauración no forma una operación segura"
            }
        case .batch(let points):
            if initialPhysicalSafetyState.begin(points: points) {
                recoveredRestorationGroups = GodoxGroup.allCases.filter {
                    points[$0] != nil
                }
                for group in recoveredRestorationGroups {
                    guard let point = points[group] else { continue }
                    initialGroups[group] = GroupDraft(
                        baseline: point.snapshot,
                        draft: point.snapshot,
                        confirmation: .failed("Recuperación pendiente de una sesión anterior"),
                        lastKnownActiveMode: point.multiUnderlyingMode,
                        restoresAfterMulti: point.restoresAfterMulti
                    )
                }
            } else {
                recoveryBlockReason = "El lote local de restauración no forma una operación segura"
            }
        case .invalid:
            recoveryBlockReason = "El registro local de restauración es ilegible; las escrituras físicas están bloqueadas"
        }
        groups = initialGroups
        physicalSafetyState = initialPhysicalSafetyState
        let initialMultiFlashSettings = restoredWorkspace?.multiFlashSettings ?? .default
        multiFlashBaseline = initialMultiFlashSettings
        multiFlashDraft = initialMultiFlashSettings

        var initialConfigurations = Dictionary(uniqueKeysWithValues: GodoxGroup.allCases.map {
            ($0, GroupConfiguration(
                assignedFlashModelIDs: [],
                isVisibleLocally: false,
                isEnabledOnRadio: false,
                hasCompleteBaseline: true
            ))
        })
        initialConfigurations[.a] = GroupConfiguration(
            assignedFlashModelIDs: ["ad600pro-ii"],
            isVisibleLocally: false,
            isEnabledOnRadio: false,
            hasCompleteBaseline: true
        )
        initialConfigurations[.b] = GroupConfiguration(
            assignedFlashModelIDs: ["ad600", "ad600pro-ii"],
            isVisibleLocally: true,
            isEnabledOnRadio: true,
            hasCompleteBaseline: true
        )
        initialConfigurations[.c] = GroupConfiguration(
            assignedFlashModelIDs: ["ad400pro"],
            isVisibleLocally: true,
            isEnabledOnRadio: true,
            hasCompleteBaseline: true
        )
        let defaultVisible: [GodoxGroup] = [.b, .c]
        if let restoredWorkspace {
            for group in restoredWorkspace.workingGroups {
                guard let stored = restoredWorkspace.groupConfigurations[group],
                      let snapshot = initialGroups[group]?.draft else { continue }
                initialConfigurations[group] = GroupConfiguration(
                    assignedFlashModelIDs: stored.assignedFlashModelIDs,
                    isVisibleLocally: restoredWorkspace.visibleGroups.contains(group),
                    isEnabledOnRadio: snapshot.isEnabledOnRadio,
                    hasCompleteBaseline: true
                )
            }
        }
        var initialWorkingGroups = restoredWorkspace?.workingGroups
            ?? initialProfile.supportedGroups.filter { defaultVisible.contains($0) }
        var initialVisibleGroups = restoredWorkspace?.visibleGroups
            ?? initialVisibilityPreferences.loadVisibleGroups(
                supportedGroups: initialWorkingGroups,
                defaultVisibleGroups: defaultVisible
            )
        if !recoveredRestorationGroups.isEmpty {
            initialWorkingGroups = initialProfile.supportedGroups.filter {
                initialWorkingGroups.contains($0) || recoveredRestorationGroups.contains($0)
            }
            initialVisibleGroups = initialWorkingGroups.filter {
                initialVisibleGroups.contains($0) || recoveredRestorationGroups.contains($0)
            }
        }
        for group in GodoxGroup.allCases {
            initialConfigurations[group]?.isVisibleLocally = initialVisibleGroups.contains(group)
        }
        groupConfigurations = initialConfigurations
        workingGroups = initialWorkingGroups
        visibleGroups = initialVisibleGroups
        let initialGlobalBeep = initialWorkingGroups.contains {
            initialGroups[$0]?.draft.beepEnabled == true
        }
        let initialGlobalModeling = initialWorkingGroups.contains {
            initialGroups[$0]?.draft.modeling != .off
        }
        globalBeepEnabled = initialGlobalBeep
        var initialGlobalSnapshot = GlobalRadioSnapshot(
            apkDefaultsWithBeepEnabled: initialGlobalBeep,
            modelingLightEnabled: initialGlobalModeling,
            standbyEnabled: false
        )
        initialGlobalSnapshot.multiEnabled = initialWorkingGroups.contains {
            initialGroups[$0]?.draft.operatingMode == .multi
        }
        initialGlobalSnapshot.multiCount = initialMultiFlashSettings.countByte
        initialGlobalSnapshot.multiHertz = initialMultiFlashSettings.hertzByte
        initialGlobalSnapshot.multiPowerByte = initialMultiFlashSettings.powerByte
        globalRadioSnapshot = initialGlobalSnapshot
        hasStoredWorkspaceConfiguration = restoredWorkspace != nil
        hasCompletedOnboarding = restoredWorkspace?.onboardingCompleted ?? false
        super.init()

        let restoredMultiFlashSettingsBeforeMigration = multiFlashDraft
        var didMigrateStoredMultiFlashSettings = false
        if recoveredRestorationGroups.isEmpty,
           normalizeMultiFlashDraftForCurrentGroups() {
            // Treat a newly introduced manufacturer limit as a local data
            // migration, not as an unsent user edit on launch.
            didMigrateStoredMultiFlashSettings =
                multiFlashDraft != restoredMultiFlashSettingsBeforeMigration
            multiFlashBaseline = multiFlashDraft
            globalRadioSnapshot.multiCount = multiFlashDraft.countByte
            globalRadioSnapshot.multiHertz = multiFlashDraft.hertzByte
            globalRadioSnapshot.multiPowerByte = multiFlashDraft.powerByte
        }

        client = transport ?? BluetoothClient()
        client.delegate = self
        if didMigrateStoredMultiFlashSettings, hasCompletedOnboarding,
           !persistStudioLibrary() {
            addActivity(
                .warning,
                "Multi se ajustó a un límite seguro, pero no pudo actualizarse en la configuración guardada"
            )
        }
        if studioLibraryLoadWasInvalid {
            addActivity(
                .warning,
                "La configuración local no pudo cargarse; vuelve a preparar tu espacio de trabajo"
            )
        } else if loadedLibrary != nil && restoredWorkspace == nil {
            addActivity(
                .warning,
                "La configuración guardada ya no es compatible; vuelve a revisar grupos y modelos"
            )
        }
        if savedRadioLoadWasInvalid {
            addActivity(
                .warning,
                "El radio guardado no pudo cargarse; busca el transmisor e introduce su código nuevamente"
            )
        }
        if !recoveredRestorationGroups.isEmpty {
            let labels = recoveredRestorationGroups.map(\.label).joined(separator: ", ")
            addActivity(
                .error,
                "Hay una escena anterior por recuperar (\(labels)); conecta el radio original antes de continuar"
            )
        } else if let recoveryBlockReason {
            addActivity(.error, recoveryBlockReason)
        } else if !studioLibraryLoadWasInvalid,
                  !(loadedLibrary != nil && restoredWorkspace == nil),
                  !savedRadioLoadWasInvalid {
            addActivity(.info, "Listo para buscar un radio")
        }
    }

    var selectedDevice: BluetoothClient.Device? {
        devices.first { $0.id == selectedDeviceID }
    }

    func isSavedRadioDiscovered(_ deviceID: UUID) -> Bool {
        devices.contains { $0.id == deviceID }
    }

    var isSelectedDeviceSaved: Bool {
        guard let selectedDeviceID else { return false }
        return savedRadio(for: selectedDeviceID) != nil
    }

    func savedRadio(for deviceID: UUID) -> SavedRadio? {
        savedRadios.first { $0.deviceID == deviceID }
    }

    var isRadioCodeValid: Bool {
        SavedRadio.isValidRadioCode(radioCode)
    }

    var hasDuplicateDeviceNames: Bool {
        !duplicateDeviceNameKeys.isEmpty
    }

    func isDeviceNameDuplicated(_ device: BluetoothClient.Device) -> Bool {
        duplicateDeviceNameKeys.contains(Self.normalizedDeviceName(device.name))
    }

    func deviceIdentifierSuffix(_ device: BluetoothClient.Device) -> String {
        String(device.id.uuidString.replacingOccurrences(of: "-", with: "").suffix(6))
    }

    var isSessionReady: Bool { phase == .ready }
    var isSimulation: Bool { client.isSimulation }

    /// La configuración de conexión ocupa el espacio principal hasta que el
    /// handshake y Sync terminan. Durante un write se conserva el workspace,
    /// pero sus controles permanecen bloqueados por `canEdit`.
    var showsControlWorkspace: Bool {
        phase == .ready || phase == .applying
    }

    /// Grupos y modelos son configuración local y pueden revisarse con el
    /// radio desconectado o ya listo. Ninguna reconfiguración puede competir
    /// con un write, Test o recuperación física pendiente.
    var canConfigureWorkspace: Bool {
        guard recoveryBlockReason == nil,
              !isInteractiveEditActive,
              !isGlobalStandbyEnabled,
              restorationPoints.isEmpty,
              !isTestPending,
              pendingDisconnectResolution == nil,
              !sessionIsInvalidating,
              controlIntents.isEmpty,
              awaitingRadioResponses.isEmpty,
              snapshotsAwaitingRadioResponse.isEmpty,
              activeGroupChange == nil,
              queuedGroupChanges.isEmpty else {
            return false
        }
        return phase == .idle || phase == .ready
    }

    /// El perfil determina la superficie de protocolo disponible, por lo que
    /// sólo puede cambiar cuando no existe una sesión con un radio.
    var canConfigureHardwareProfile: Bool {
        canConfigureWorkspace && phase == .idle
    }

    /// Borrar identidad/código local no puede competir con un handshake,
    /// escaneo, write, Test ni recuperación en curso.
    var canForgetSavedRadios: Bool {
        canConfigureWorkspace
    }

    @discardableResult
    func setDefaultTransmitterProfile(_ profileID: String) -> Bool {
        let normalizedProfileID = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard availableTransmitterProfiles.contains(where: { $0.id == normalizedProfileID }) else {
            return false
        }
        guard normalizedProfileID != defaultTransmitterProfileID else { return true }

        let state = TransmitterProfilePreferences.State(
            availableProfileIDs: availableTransmitterProfiles.map(\.id),
            defaultProfileID: normalizedProfileID
        )
        guard saveTransmitterProfilePreferences(state) else { return false }
        defaultTransmitterProfileID = normalizedProfileID
        return true
    }

    @discardableResult
    func removeTransmitterProfile(_ profileID: String) -> Bool {
        let normalizedProfileID = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedProfileID != transmitterProfile.id,
              availableTransmitterProfiles.count > 1,
              availableTransmitterProfiles.contains(where: { $0.id == normalizedProfileID }) else {
            return false
        }

        let remainingProfiles = availableTransmitterProfiles.filter {
            $0.id != normalizedProfileID
        }
        let nextDefaultProfileID = remainingProfiles.contains(where: {
            $0.id == defaultTransmitterProfileID
        }) ? defaultTransmitterProfileID : transmitterProfile.id
        let state = TransmitterProfilePreferences.State(
            availableProfileIDs: remainingProfiles.map(\.id),
            defaultProfileID: nextDefaultProfileID
        )
        guard saveTransmitterProfilePreferences(state) else { return false }

        availableTransmitterProfiles = remainingProfiles
        defaultTransmitterProfileID = nextDefaultProfileID
        return true
    }

    func restoreTransmitterProfiles() {
        let builtInProfiles = TransmitterProfile.available
        let nextDefaultProfileID = builtInProfiles.contains(where: {
            $0.id == defaultTransmitterProfileID
        }) ? defaultTransmitterProfileID : transmitterProfile.id
        let state = TransmitterProfilePreferences.State(
            availableProfileIDs: builtInProfiles.map(\.id),
            defaultProfileID: nextDefaultProfileID
        )
        guard saveTransmitterProfilePreferences(state) else { return }

        availableTransmitterProfiles = builtInProfiles
        defaultTransmitterProfileID = nextDefaultProfileID
    }

    var statusTitle: String {
        if phase == .ready, let connectedDeviceName {
            return "Conectado · \(connectedDeviceName)"
        }
        return phase.title
    }

    var pendingGroups: [GodoxGroup] {
        managedGroups.filter {
            groups[$0]?.hasPendingChange == true || preparedRestorations.contains($0)
        }
    }

    var hasPendingMultiFlashChange: Bool {
        if multiFlashBaseline != multiFlashDraft { return true }
        guard hasConfirmedGlobalSnapshot else { return false }
        return globalRadioSnapshot.multiEnabled != !multiFlashGroups.isEmpty ||
            globalRadioSnapshot.multiCount != multiFlashDraft.countByte ||
            globalRadioSnapshot.multiHertz != multiFlashDraft.hertzByte ||
            globalRadioSnapshot.multiPowerByte != multiFlashDraft.powerByte
    }

    var pendingCount: Int {
        pendingGroups.count + (hasPendingMultiFlashChange ? 1 : 0)
    }

    /// Un cambio derivado sólo de quitar el último grupo Multi del workspace
    /// no tiene un borrador que pueda descartarse sin deshacer el workspace.
    var canDiscardPendingChanges: Bool {
        if !pendingGroups.isEmpty { return true }
        return multiFlashBaseline != multiFlashDraft &&
            isValidMultiFlashSettings(multiFlashBaseline)
    }

    var multiFlashGroups: [GodoxGroup] {
        workingGroups.filter { groups[$0]?.draft.operatingMode == .multi }
    }

    var isInteractiveEditActive: Bool {
        activeInteractiveEditCount > 0
    }

    /// Starts a pointer-driven continuous edit. Tokens intentionally model
    /// overlapping gestures from multiple windows; no gesture can release a
    /// different gesture's delivery gate.
    func beginInteractiveEdit() -> InteractiveEditToken {
        let token = InteractiveEditToken()
        interactiveEditTokens.insert(token)
        activeInteractiveEditCount = interactiveEditTokens.count
        cancelAutomaticApply()
        return token
    }

    /// Ends one continuous edit. Repeated or stale endings are harmless, and
    /// only releasing the final live token may arm the 700 ms debounce.
    func endInteractiveEdit(_ token: InteractiveEditToken) {
        guard interactiveEditTokens.remove(token) != nil else { return }
        activeInteractiveEditCount = interactiveEditTokens.count
        guard interactiveEditTokens.isEmpty else { return }
        scheduleAutomaticApplyIfNeeded()
    }

    private var groupsEligibleForApply: [GodoxGroup] {
        guard !restorationPoints.isEmpty else { return pendingGroups }
        return transmitterProfile.supportedGroups.filter {
            preparedRestorations.contains($0)
        }
    }

    private var managedGroups: [GodoxGroup] {
        hasCompletedOnboarding ? workingGroups : transmitterProfile.supportedGroups
    }

    var canApply: Bool {
        let eligibleGroups = groupsEligibleForApply
        let canApplyMultiFlashOnly = restorationPoints.isEmpty && hasPendingMultiFlashChange
        guard recoveryBlockReason == nil, isSessionReady, !isReconfiguringWorkspace,
              !isInteractiveEditActive,
              !isGlobalStandbyEnabled,
              !eligibleGroups.isEmpty || canApplyMultiFlashOnly,
              !isTestPending,
              controlIntents.isEmpty, awaitingRadioResponses.isEmpty,
              activeGroupChange == nil, queuedGroupChanges.isEmpty else {
            return false
        }
        if !restorationPoints.isEmpty,
           Set(eligibleGroups) != Set(restorationPoints.keys) {
            return false
        }
        if restorationPoints.isEmpty, !isMultiFlashDraftValid { return false }
        return eligibleGroups.allSatisfy {
            canTransmit($0, snapshot: groupDraft($0).draft)
        }
    }

    var applyBlockReason: String? {
        guard pendingCount > 0, !canApply else { return nil }
        if isInteractiveEditActive { return "Suelta el control antes de enviar" }
        if let recoveryBlockReason { return recoveryBlockReason }
        if !isSessionReady { return "Conecta y sincroniza el radio antes de aplicar" }
        return physicalApplyBlockReason
    }

    var canSynchronizeValues: Bool {
        recoveryBlockReason == nil && phase == .ready && !isReconfiguringWorkspace &&
            !isInteractiveEditActive &&
            !isGlobalStandbyEnabled &&
            !isTestPending &&
            !workingGroups.isEmpty && workingConfigurationIssue == nil &&
            controlIntents.isEmpty && awaitingRadioResponses.isEmpty &&
            activeGroupChange == nil && queuedGroupChanges.isEmpty &&
            restorationPoints.isEmpty
    }

    var valueSynchronizationBlockReason: String? {
        guard !canSynchronizeValues else { return nil }
        if isInteractiveEditActive { return "Suelta el control antes de sincronizar" }
        if isSynchronizingValues { return "La sincronización de valores está en curso" }
        if let recoveryBlockReason { return recoveryBlockReason }
        if !restorationPoints.isEmpty {
            return "Recupera el ajuste seguro pendiente antes de sincronizar"
        }
        if phase != .ready { return "Conecta el radio antes de sincronizar valores" }
        if let workingConfigurationIssue { return workingConfigurationIssue }
        return "Espera a que termine la operación actual"
    }

    var workingConfigurationIssue: String? {
        guard !workingGroups.isEmpty else { return "Selecciona al menos un grupo de trabajo" }
        guard isMultiFlashDraftValid else {
            return "Revisa la potencia, los destellos y la frecuencia de Multi"
        }
        let activeModes = workingGroups.compactMap { groups[$0]?.draft.operatingMode }
        if activeModes.contains(.multi),
           activeModes.contains(where: { $0 == .manual || $0 == .autoTTL }) {
            return "Multi es global: los grupos activos deben estar en Multi o apagados"
        }
        for group in workingGroups {
            let configuration = groupConfiguration(group)
            let snapshot = groupDraft(group).draft
            guard configuration.hasCompleteBaseline else {
                return "El grupo \(group.label) no tiene un ajuste completo"
            }
            guard !configuration.assignedFlashModelIDs.isEmpty else {
                return "Asigna al menos un modelo de flash a \(group.label)"
            }
            guard isValidForTransmission(group, snapshot: snapshot) else {
                return "Revisa los valores del grupo \(group.label) antes de sincronizar"
            }
        }
        return nil
    }

    var canDisconnect: Bool {
        switch phase {
        case .ready, .failed, .unavailable, .idle:
            return !isTestPending && controlIntents.isEmpty && awaitingRadioResponses.isEmpty &&
                restorationPoints.isEmpty
        default:
            return false
        }
    }

    var canCancelConnectionAttempt: Bool {
        guard pendingDisconnectResolution == nil else { return false }
        switch phase {
        case .scanning, .connecting, .discovering, .authenticating, .synchronizing:
            return true
        default:
            return false
        }
    }

    var connectionRecoveryMessage: String? {
        guard let pendingDisconnectResolution else { return nil }
        switch pendingDisconnectResolution {
        case .idle:
            return "Cerrando el intento local de forma segura"
        case .failure(let message):
            return message
        }
    }

    var readyConnectionDetail: String {
        if lastValueSynchronizationAt != nil {
            return "Radio conectado · valores de Estrobo sincronizados"
        }
        return "Radio conectado y listo para recibir cambios"
    }

    var canChangeDeliveryMode: Bool {
        !isInteractiveEditActive && phase != .applying && !isGlobalStandbyEnabled && !isTestPending &&
            restorationPoints.isEmpty
    }

    var canToggleGlobalStandby: Bool {
        recoveryBlockReason == nil && phase == .ready && !isReconfiguringWorkspace &&
            !isInteractiveEditActive && !isTestPending && physicalSafetyState.allowsNewEdits &&
            controlIntents.isEmpty && awaitingRadioResponses.isEmpty &&
            activeGroupChange == nil && queuedGroupChanges.isEmpty &&
            sessionDeviceID != nil && sessionID != nil
    }

    var canToggleGlobalBeep: Bool {
        canToggleGlobalStandby && !isGlobalStandbyEnabled && pendingCount == 0 &&
            !workingGroups.isEmpty &&
            workingGroups.allSatisfy { group in
                groupConfiguration(group).hasCompleteBaseline &&
                    resolvedCapability(for: group).supportsBeepDraft
            }
    }

    var canEditMultiFlashSettings: Bool {
        recoveryBlockReason == nil && phase == .ready && !isReconfiguringWorkspace &&
            !isGlobalStandbyEnabled && !isTestPending &&
            physicalSafetyState.allowsNewEdits && controlIntents.isEmpty &&
            awaitingRadioResponses.isEmpty && activeGroupChange == nil &&
            queuedGroupChanges.isEmpty && !allowedMultiFlashPowers.isEmpty
    }

    /// Multi se enciende y apaga exclusivamente como una decisión global. Al
    /// encenderlo debe existir al menos un grupo activo compatible; al apagarlo
    /// toda la escena de trabajo debe poder quedar en Manual de forma válida.
    func canSetGlobalMultiFlashEnabled(_ enabled: Bool) -> Bool {
        guard canEditMultiFlashSettings,
              enabled != !multiFlashGroups.isEmpty else {
            return false
        }
        return enabled
            ? initialMultiScenePlan() != nil
            : manualMultiScenePlan() != nil
    }

    func supportsMultiFlash(_ group: GodoxGroup) -> Bool {
        transmitterProfile.supportedMultiGroups.contains(group) &&
            managedGroups.contains(group) &&
            !resolvedCapability(for: group).multiPowerScale.isEmpty
    }

    var allowedMultiFlashPowers: [ManualPower] {
        let selected = multiFlashGroups
        return selected.isEmpty
            ? MultiFlashSettings.supportedPowers
            : multiPowerScale(for: selected)
    }

    var multiFlashCountRange: ClosedRange<Int> {
        MultiFlashSettings.countRange.lowerBound...multiFlashMaximumCount
    }

    var multiFlashMaximumCount: Int {
        maximumMultiFlashCount(
            power: multiFlashDraft.power,
            hertz: multiFlashDraft.hertz,
            groups: multiFlashGroups
        )
    }

    var hasVerifiedMultiFlashCountLimit: Bool {
        multiFlashGroups.contains {
            resolvedCapability(for: $0).multiLimitProfiles.contains {
                $0.hasManufacturerPublishedLimit(
                    power: multiFlashDraft.power,
                    hertz: multiFlashDraft.hertz
                )
            }
        }
    }

    var hasConservativeMultiFlashCountLimit: Bool {
        multiFlashGroups.contains {
            resolvedCapability(for: $0).multiLimitProfiles.contains {
                $0.maximumFlashCount(
                    power: multiFlashDraft.power,
                    hertz: multiFlashDraft.hertz
                ) != nil && !$0.hasManufacturerPublishedLimit(
                    power: multiFlashDraft.power,
                    hertz: multiFlashDraft.hertz
                )
            }
        }
    }

    var hasUnverifiedMultiFlashCountLimit: Bool {
        multiFlashGroups.contains {
            resolvedCapability(for: $0).hasUnverifiedMultiLimits
        }
    }

    private var isMultiFlashDraftValid: Bool {
        isValidMultiFlashSettings(multiFlashDraft)
    }

    private func isValidMultiFlashSettings(_ settings: MultiFlashSettings) -> Bool {
        let scale = multiFlashGroups.isEmpty
            ? MultiFlashSettings.supportedPowers
            : multiPowerScale(for: multiFlashGroups)
        let maximumCount = maximumMultiFlashCount(
            power: settings.power,
            hertz: settings.hertz,
            groups: multiFlashGroups
        )
        return scale.contains(settings.power) &&
            (MultiFlashSettings.countRange.lowerBound...maximumCount).contains(settings.count)
    }

    private func multiPowerScale(for groups: [GodoxGroup]) -> [ManualPower] {
        guard !groups.isEmpty,
              groups.allSatisfy(supportsMultiFlash),
              let commonMinimumDenominator = groups.compactMap({
                  resolvedCapability(for: $0).minimumManualDenominator
              }).min() else {
            return []
        }
        return ManualPower.scale(minimumDenominator: commonMinimumDenominator).filter {
            $0.decimalValue <= 80 && $0.decimalValue.isMultiple(of: 10)
        }
    }

    private func maximumMultiFlashCount(
        power: ManualPower,
        hertz: Int,
        groups: [GodoxGroup]
    ) -> Int {
        let verifiedLimits = groups.flatMap { group in
            resolvedCapability(for: group).multiLimitProfiles.compactMap {
                $0.maximumFlashCount(power: power, hertz: hertz)
            }
        }
        return min(
            MultiFlashSettings.countRange.upperBound,
            verifiedLimits.min() ?? MultiFlashSettings.countRange.upperBound
        )
    }

    func setChangeDeliveryMode(_ mode: ChangeDeliveryMode) {
        guard canChangeDeliveryMode, mode != changeDeliveryMode else { return }
        cancelAutomaticApply()
        automaticApplySuppressedForLocalPreset = false
        changeDeliveryMode = mode
        changeDeliveryPreferences.save(mode)
        if mode == .automatic {
            addActivity(.info, "Envío automático activado · pausa de 0.7 s")
            scheduleAutomaticApplyIfNeeded()
        } else {
            addActivity(.info, "Envío con botón activado")
        }
    }

    func groupDraft(_ group: GodoxGroup) -> GroupDraft {
        groups[group]!
    }

    func groupConfiguration(_ group: GodoxGroup) -> GroupConfiguration {
        groupConfigurations[group]!
    }

    func resolvedCapability(for group: GodoxGroup) -> ResolvedGroupCapability {
        ResolvedGroupCapability.resolve(
            configuration: groupConfiguration(group),
            profile: transmitterProfile
        )
    }

    func canEdit(_ group: GodoxGroup) -> Bool {
        guard phase == .ready,
              !isGlobalStandbyEnabled,
              !isReconfiguringWorkspace,
              !isTestPending,
              managedGroups.contains(group),
              physicalSafetyState.allowsNewEdits,
              groupConfiguration(group).hasCompleteBaseline,
              !resolvedCapability(for: group).powerScale.isEmpty else {
            return false
        }
        return groupDraft(group).draft.operatingMode == .manual
    }

    func availableOperatingModes(for group: GodoxGroup) -> [GroupOperatingMode] {
        var modes: [GroupOperatingMode] = [.manual, .autoTTL]
        if supportsMultiFlash(group) { modes.append(.multi) }
        return modes
    }

    func canChangeOperatingMode(_ group: GodoxGroup) -> Bool {
        guard phase == .ready,
              !isGlobalStandbyEnabled,
              !isReconfiguringWorkspace,
              !isTestPending,
              managedGroups.contains(group),
              physicalSafetyState.allowsNewEdits,
              groupConfiguration(group).hasCompleteBaseline,
              !resolvedCapability(for: group).powerScale.isEmpty else {
            return false
        }
        let snapshot = groupDraft(group).draft
        let modes = availableOperatingModes(for: group)
        guard modes.contains(snapshot.operatingMode) else {
            return false
        }
        return modes.contains { mode in
            guard mode != snapshot.operatingMode else { return false }
            var alternate = snapshot
            alternate.operatingMode = mode
            if mode == .autoTTL || mode == .multi {
                alternate.compensationByte = 0
            }
            return isValidForTransmission(group, snapshot: alternate)
        }
    }

    func allowedPowers(for group: GodoxGroup) -> [ManualPower] {
        resolvedCapability(for: group).powerScale
    }

    func allowedModelingLights(for group: GodoxGroup) -> [ModelingLight] {
        guard canEdit(group) else { return [] }
        return resolvedCapability(for: group).modeling.editableValues
    }

    func allowedModeling(for group: GodoxGroup) -> [ModelingLight] {
        allowedModelingLights(for: group)
    }

    func canEditBeep(_ group: GodoxGroup) -> Bool {
        canEdit(group) && resolvedCapability(for: group).supportsBeepDraft
    }

    func canToggleRadioEnabled(_ group: GodoxGroup) -> Bool {
        guard phase == .ready,
              !isGlobalStandbyEnabled,
              !isReconfiguringWorkspace,
              !isTestPending,
              managedGroups.contains(group),
              physicalSafetyState.allowsNewEdits,
              groupConfiguration(group).hasCompleteBaseline else {
            return false
        }
        let state = groupDraft(group)
        return snapshotAfterTogglingRadioEnabled(
            group,
            state: state,
            enabled: !state.draft.isEnabledOnRadio
        ) != nil
    }

    /// Todos los grupos manuales configurados en el radio, incluso si están
    /// ocultos localmente. Ocultar un grupo sólo cambia la presentación.
    var globalPowerGroups: [GodoxGroup] {
        workingGroups.filter { group in
            guard let state = groups[group],
                  let configuration = groupConfigurations[group],
                  configuration.hasCompleteBaseline,
                  !resolvedCapability(for: group).powerScale.isEmpty else {
                return false
            }
            return state.draft.operatingMode == .manual
        }
    }

    /// Captura la potencia de cada grupo manual que participa en el control
    /// global. La visibilidad es deliberadamente irrelevante: ocultar una
    /// tarjeta no debe cambiar el resultado de un ajuste relativo.
    ///
    /// Un diccionario vacío indica que las compuertas de seguridad no permiten
    /// comenzar el gesto. El llamador debe conservar esta instantánea durante
    /// todo el arrastre para que cada offset se calcule desde el mismo origen.
    func makeGlobalPowerAnchor() -> [GodoxGroup: ManualPower] {
        guard permitsGlobalPowerAdjustment else { return [:] }
        let participants = globalPowerGroups
        guard !participants.isEmpty else { return [:] }

        var anchor: [GodoxGroup: ManualPower] = [:]
        for group in participants {
            guard let power = groups[group]?.draft.power,
                  allowedPowers(for: group).contains(power) else {
                // Un valor histórico fuera de la escala no puede participar sin
                // romper la relación de potencia. Se normaliza de forma individual.
                return [:]
            }
            anchor[group] = power
        }
        return anchor
    }

    /// Devuelve la intersección de offsets que todos los grupos capturados
    /// pueden recorrer. El primer grupo que llega a un límite detiene al resto.
    func globalPowerOffsetBounds(
        from anchor: [GodoxGroup: ManualPower],
        limitedTo limit: Int = 9
    ) -> ClosedRange<Int> {
        globalPowerConstraint(from: anchor, limitedTo: limit)?.allowedOffsets ?? 0...0
    }

    /// Separa el dominio visual fijo del control global de los límites físicos
    /// de los flashes y conserva qué grupo detuvo cada dirección.
    func globalPowerConstraint(
        from anchor: [GodoxGroup: ManualPower],
        limitedTo limit: Int = 9
    ) -> GlobalPowerConstraint? {
        guard permitsGlobalPowerAdjustment, limit > 0,
              let positions = globalPowerPositions(from: anchor),
              let commonBounds = commonGlobalPowerOffsetBounds(for: positions) else {
            return nil
        }

        let allowedOffsets = max(-limit, commonBounds.lowerBound)...min(
            limit,
            commonBounds.upperBound
        )
        let lowerBoundary: GlobalPowerLimitCause
        if commonBounds.lowerBound < -limit {
            lowerBoundary = .visualWindow
        } else {
            lowerBoundary = .groups(positions.compactMap { position in
                position.allowed.startIndex - position.anchorIndex == commonBounds.lowerBound
                    ? position.group
                    : nil
            })
        }

        let upperBoundary: GlobalPowerLimitCause
        if commonBounds.upperBound > limit {
            upperBoundary = .visualWindow
        } else {
            upperBoundary = .groups(positions.compactMap { position in
                position.allowed.index(before: position.allowed.endIndex) - position.anchorIndex ==
                    commonBounds.upperBound
                    ? position.group
                    : nil
            })
        }

        return GlobalPowerConstraint(
            allowedOffsets: allowedOffsets,
            lowerBoundary: lowerBoundary,
            upperBoundary: upperBoundary
        )
    }

    func canAdjustGlobalPower(direction: Int) -> Bool {
        guard direction == -1 || direction == 1,
              let bounds = commonGlobalPowerOffsetBounds(
                  from: makeGlobalPowerAnchor()
              ) else {
            return false
        }
        return bounds.contains(direction)
    }

    var canSendTest: Bool {
        recoveryBlockReason == nil && phase == .ready && !isReconfiguringWorkspace &&
            !isInteractiveEditActive &&
            !isGlobalStandbyEnabled &&
            !isTestPending &&
            isMultiFlashDraftValid &&
            pendingCount == 0 && restorationPoints.isEmpty &&
            controlIntents.isEmpty && awaitingRadioResponses.isEmpty &&
            activeGroupChange == nil && queuedGroupChanges.isEmpty
    }

    var testBlockReason: String? {
        guard !canSendTest else { return nil }
        if isInteractiveEditActive { return "Suelta el control antes de probar" }
        if isTestPending { return "La orden Test se está entregando al radio" }
        if let recoveryBlockReason { return recoveryBlockReason }
        if !restorationPoints.isEmpty { return "Recupera el ajuste anterior antes de disparar" }
        if phase != .ready { return "Conecta y sincroniza el radio antes de disparar" }
        if !isMultiFlashDraftValid { return "Revisa la configuración Multi antes de disparar" }
        if pendingCount > 0 { return "Aplica o descarta los cambios antes de probar" }
        return "Espera a que termine la operación actual"
    }

    func powerIndex(for group: GodoxGroup) -> Int {
        guard let power = groups[group]?.draft.power else { return 0 }
        guard let minimum = resolvedCapability(for: group).minimumManualDenominator else {
            return 0
        }
        return power.sliderIndex(minimumDenominator: minimum) ?? 0
    }

    func setDraftPower(_ group: GodoxGroup, power: ManualPower) {
        guard canEdit(group), var state = groups[group],
              let canonicalPower = allowedPowers(for: group).first(where: {
                  $0.decimalValue == power.decimalValue
              }) else {
            return
        }
        guard state.draft.power != canonicalPower else { return }
        state.draft.power = canonicalPower
        groups[group] = state
        draftDidChange()
    }

    func setDraftPower(_ group: GodoxGroup, index: Int) {
        guard let minimum = resolvedCapability(for: group).minimumManualDenominator,
              let power = ManualPower.value(
                  atSliderIndex: index,
                  minimumDenominator: minimum
              ) else {
            return
        }
        setDraftPower(group, power: power)
    }

    func setDraftPowerIndex(_ index: Int, for group: GodoxGroup) {
        setDraftPower(group, index: index)
    }

    func setDraftModeling(_ group: GodoxGroup, modeling: ModelingLight) {
        guard var state = groups[group],
              allowedModelingLights(for: group).contains(modeling),
              state.draft.modeling != modeling else {
            return
        }
        let normalizedPower = normalizeDraftPowerToCommonRange(&state, for: group)
        state.draft.modeling = modeling
        groups[group] = state
        noteCommonRangeNormalization(normalizedPower, for: group)
        draftDidChange()
    }

    /// Compatibilidad temporal para las llamadas históricas por grupo. El beep
    /// oficial tiene un maestro A0 y Estrobo lo presenta como una sola decisión.
    func setDraftBeep(_ group: GodoxGroup, enabled: Bool) {
        guard managedGroups.contains(group) else { return }
        setGlobalBeep(enabled)
    }

    func setGlobalBeep(_ enabled: Bool) {
        guard canToggleGlobalBeep, globalBeepEnabled != enabled else { return }
        cancelAutomaticApply()
        automaticApplySuppressedForLocalPreset = false

        for group in workingGroups {
            guard var state = groups[group] else { continue }
            let normalizedPower = normalizeDraftPowerToCommonRange(&state, for: group)
            state.draft.beepEnabled = enabled
            groups[group] = state
            noteCommonRangeNormalization(normalizedPower, for: group)
        }
        activePresetID = nil
        globalBeepEnabled = enabled
        if hasCompletedOnboarding, !persistStudioLibrary() {
            addActivity(.warning, "El beep cambió, pero no pudo guardarse para la próxima sesión")
        }

        // Beep no debe arrastrar el gate de modelado de un borrador A1. Parte
        // siempre del último A0 conocido y cambia únicamente su master audible.
        var snapshot = globalRadioSnapshot
        snapshot.beepEnabled = enabled
        let followup = GlobalControlFollowup(
            groups: workingGroups,
            purpose: .pendingChanges,
            forceWrite: true,
            restorationGlobalSnapshot: globalRadioSnapshot
        )
        if !submitGlobalControl(snapshot, purpose: .beep, followup: followup) {
            addActivity(.error, "No se pudo preparar el cambio global de beep")
        }
    }

    func setGlobalStandby(_ enabled: Bool) {
        guard canToggleGlobalStandby, isGlobalStandbyEnabled != enabled else { return }
        cancelAutomaticApply()
        automaticApplySuppressedForLocalPreset = false

        // Standby es A0-only: conserva exactamente el resto del estado global
        // confirmado, aunque existan cambios A1 pendientes en modo con botón.
        var snapshot = globalRadioSnapshot
        snapshot.standbyEnabled = enabled
        isGlobalStandbyEnabled = enabled
        if !submitGlobalControl(snapshot, purpose: .standby, followup: nil) {
            isGlobalStandbyEnabled.toggle()
            addActivity(.error, "No se pudo preparar el standby general")
        }
    }

    func setMultiFlashPower(_ power: ManualPower) {
        guard canEditMultiFlashSettings,
              allowedMultiFlashPowers.contains(power) else {
            return
        }
        let maximumCount = maximumMultiFlashCount(
            power: power,
            hertz: multiFlashDraft.hertz,
            groups: multiFlashGroups
        )
        guard
              let candidate = MultiFlashSettings(
                  power: power,
                  count: min(multiFlashDraft.count, maximumCount),
                  hertz: multiFlashDraft.hertz
              ), candidate != multiFlashDraft else {
            return
        }
        noteMultiFlashCountNormalization(from: multiFlashDraft, to: candidate)
        updateMultiFlashDraft(candidate)
    }

    func setMultiFlashCount(_ count: Int) {
        guard canEditMultiFlashSettings,
              multiFlashCountRange.contains(count),
              let candidate = MultiFlashSettings(
                  power: multiFlashDraft.power,
                  count: count,
                  hertz: multiFlashDraft.hertz
              ), candidate != multiFlashDraft else {
            return
        }
        updateMultiFlashDraft(candidate)
    }

    func setMultiFlashHertz(_ hertz: Int) {
        guard canEditMultiFlashSettings else { return }
        let maximumCount = maximumMultiFlashCount(
            power: multiFlashDraft.power,
            hertz: hertz,
            groups: multiFlashGroups
        )
        guard
              let candidate = MultiFlashSettings(
                  power: multiFlashDraft.power,
                  count: min(multiFlashDraft.count, maximumCount),
                  hertz: hertz
              ), candidate != multiFlashDraft else {
            return
        }
        noteMultiFlashCountNormalization(from: multiFlashDraft, to: candidate)
        updateMultiFlashDraft(candidate)
    }

    /// La participación por grupo sólo modifica una sesión Multi ya activa. El
    /// último participante no puede quitarse desde aquí porque eso apagaría la
    /// decisión global; el cierre pertenece al botón Multi superior.
    func canSetMultiFlashParticipation(_ group: GodoxGroup, enabled: Bool) -> Bool {
        guard !multiFlashGroups.isEmpty,
              workingGroups.contains(group), supportsMultiFlash(group),
              groupConfiguration(group).hasCompleteBaseline else {
            return false
        }

        let mode = groupDraft(group).draft.operatingMode
        if enabled {
            switch mode {
            case .multi:
                return true
            case .off:
                return canToggleRadioEnabled(group)
            case .manual, .autoTTL:
                return false
            }
        }
        return mode == .multi && multiFlashGroups.count > 1 &&
            canToggleRadioEnabled(group)
    }

    func setMultiFlashParticipation(_ group: GodoxGroup, enabled: Bool) {
        guard canSetMultiFlashParticipation(group, enabled: enabled) else { return }

        let mode = groupDraft(group).draft.operatingMode
        if enabled {
            if mode == .off {
                setDraftRadioEnabled(group, enabled: true)
            }
        } else if mode == .multi {
            setDraftRadioEnabled(group, enabled: false)
        }
    }

    func setGlobalMultiFlashEnabled(_ enabled: Bool) {
        guard canSetGlobalMultiFlashEnabled(enabled) else { return }
        if enabled {
            _ = beginMultiFlashScene()
        } else {
            _ = endMultiFlashSceneInManual()
        }
    }

    /// Builds the initial global Multi scene in one atomic draft. Every active
    /// compatible working group joins Multi so the group cards match the global
    /// state immediately. Groups that were already Off stay Off; unsupported
    /// active groups move to Off because Godox only documents Multi on A-E.
    private func initialMultiScenePlan() -> InitialMultiScenePlan? {
        guard multiFlashGroups.isEmpty else { return nil }

        var nextGroups = groups
        var activatedGroups: [GodoxGroup] = []
        var disabledGroups: [GodoxGroup] = []

        for workingGroup in workingGroups {
            guard groupConfiguration(workingGroup).hasCompleteBaseline,
                  var state = nextGroups[workingGroup] else {
                return nil
            }

            switch state.draft.operatingMode {
            case .manual, .autoTTL:
                state.lastKnownActiveMode = state.draft.operatingMode
                state.draftRestoresAfterMulti = true
                if supportsMultiFlash(workingGroup) {
                    state.draft.operatingMode = .multi
                    state.draft.compensationByte = 0
                    activatedGroups.append(workingGroup)
                } else {
                    state.draft.operatingMode = .off
                    disabledGroups.append(workingGroup)
                }
            case .off:
                state.draftRestoresAfterMulti = false
            case .multi:
                return nil
            }

            guard isValidForTransmission(workingGroup, snapshot: state.draft) else {
                return nil
            }
            nextGroups[workingGroup] = state
        }

        let sharedPowerScale = multiPowerScale(for: activatedGroups)
        guard !activatedGroups.isEmpty, let safePower = sharedPowerScale.first else {
            return nil
        }
        let nextPower = sharedPowerScale.contains(multiFlashDraft.power)
            ? multiFlashDraft.power
            : safePower
        let nextMaximumCount = maximumMultiFlashCount(
            power: nextPower,
            hertz: multiFlashDraft.hertz,
            groups: activatedGroups
        )
        guard let settings = MultiFlashSettings(
            power: nextPower,
            count: min(multiFlashDraft.count, nextMaximumCount),
            hertz: multiFlashDraft.hertz
        ) else {
            return nil
        }

        return InitialMultiScenePlan(
            groups: nextGroups,
            settings: settings,
            activatedGroups: activatedGroups,
            disabledGroups: disabledGroups
        )
    }

    @discardableResult
    private func beginMultiFlashScene() -> Bool {
        guard let plan = initialMultiScenePlan() else { return false }

        if plan.settings.power != multiFlashDraft.power {
            addActivity(
                .info,
                "Multi se ajustó a \(plan.settings.power.label), el mínimo común de sus flashes"
            )
        }
        noteMultiFlashCountNormalization(from: multiFlashDraft, to: plan.settings)
        multiFlashDraft = plan.settings
        groups = plan.groups
        for workingGroup in workingGroups {
            groupConfigurations[workingGroup]?.isEnabledOnRadio =
                plan.groups[workingGroup]?.draft.isEnabledOnRadio == true
        }

        addActivity(
            .info,
            "Multi global se activó en los grupos \(plan.activatedGroups.map(\.label).joined(separator: ", "))"
        )
        if !plan.disabledGroups.isEmpty {
            addActivity(
                .info,
                "Multi es global; se apagaron los grupos \(plan.disabledGroups.map(\.label).joined(separator: ", "))"
            )
        }
        draftDidChange()
        return true
    }

    /// Construye el único destino válido al apagar Multi: todos los grupos de
    /// trabajo activos en Manual, con compensación neutra y sin restauraciones
    /// diferidas. Conserva cada potencia si sigue siendo válida para el grupo.
    private func manualMultiScenePlan() -> ManualMultiScenePlan? {
        guard !multiFlashGroups.isEmpty else { return nil }

        var nextGroups = groups
        var normalizedPowers: [(group: GodoxGroup, power: ManualPower)] = []
        for workingGroup in workingGroups {
            guard groupConfiguration(workingGroup).hasCompleteBaseline,
                  var state = nextGroups[workingGroup] else {
                return nil
            }
            let scale = resolvedCapability(for: workingGroup).powerScale
            guard let safePower = scale.contains(state.draft.power)
                ? state.draft.power
                : scale.first else {
                return nil
            }
            if safePower != state.draft.power {
                normalizedPowers.append((workingGroup, safePower))
            }
            state.draft.power = safePower
            state.draft.operatingMode = .manual
            state.draft.compensationByte = 0
            state.lastKnownActiveMode = .manual
            state.draftRestoresAfterMulti = false
            guard isValidForTransmission(workingGroup, snapshot: state.draft) else {
                return nil
            }
            nextGroups[workingGroup] = state
        }
        return ManualMultiScenePlan(
            groups: nextGroups,
            normalizedPowers: normalizedPowers
        )
    }

    @discardableResult
    private func endMultiFlashSceneInManual() -> Bool {
        guard let plan = manualMultiScenePlan() else { return false }

        groups = plan.groups
        for workingGroup in workingGroups {
            groupConfigurations[workingGroup]?.isEnabledOnRadio = true
        }
        for normalization in plan.normalizedPowers {
            noteCommonRangeNormalization(
                normalization.power,
                for: normalization.group
            )
        }
        addActivity(.info, "Multi global se desactivó; todos los grupos volvieron a Manual")
        draftDidChange()
        return true
    }

    private func updateMultiFlashDraft(_ candidate: MultiFlashSettings) {
        multiFlashDraft = candidate
        draftDidChange()
    }

    private func noteMultiFlashCountNormalization(
        from previous: MultiFlashSettings,
        to candidate: MultiFlashSettings
    ) {
        guard candidate.count < previous.count else { return }
        addActivity(
            .info,
            "Multi limitó la secuencia a \(candidate.count) destellos para la potencia, Hz y modelos participantes"
        )
    }

    @discardableResult
    private func normalizeMultiFlashDraftForCurrentGroups() -> Bool {
        guard !multiFlashGroups.isEmpty else { return true }
        let scale = allowedMultiFlashPowers
        guard let safePower = scale.first else { return false }
        let nextPower = scale.contains(multiFlashDraft.power)
            ? multiFlashDraft.power
            : safePower
        let maximumCount = maximumMultiFlashCount(
            power: nextPower,
            hertz: multiFlashDraft.hertz,
            groups: multiFlashGroups
        )
        guard let normalized = MultiFlashSettings(
            power: nextPower,
            count: min(multiFlashDraft.count, maximumCount),
            hertz: multiFlashDraft.hertz
        ) else { return false }
        guard normalized != multiFlashDraft else { return true }

        if normalized.power != multiFlashDraft.power {
            addActivity(
                .info,
                "Multi se ajustó a \(safePower.label), el mínimo común de sus flashes"
            )
        }
        noteMultiFlashCountNormalization(from: multiFlashDraft, to: normalized)
        multiFlashDraft = normalized
        return true
    }

    /// M y Auto siguen siendo modos editables por grupo. Multi queda fuera de
    /// esta ruta: su entrada y salida pertenecen exclusivamente al control
    /// global y la participación se cambia con setMultiFlashParticipation.
    func setDraftOperatingMode(_ group: GodoxGroup, mode: GroupOperatingMode) {
        guard canChangeOperatingMode(group),
              availableOperatingModes(for: group).contains(mode),
              var state = groups[group],
              state.draft.operatingMode != mode else {
            return
        }

        guard mode != .multi, state.draft.operatingMode != .multi else { return }

        var candidate = state.draft
        candidate.operatingMode = mode
        if mode == .autoTTL {
            candidate.compensationByte = 0
        }

        guard isValidForTransmission(group, snapshot: candidate) else { return }
        state.draft = candidate
        state.lastKnownActiveMode = mode
        state.draftRestoresAfterMulti = false
        groups[group] = state
        groupConfigurations[group]?.isEnabledOnRadio = true
        draftDidChange()
    }

    func setDraftRadioEnabled(_ group: GodoxGroup, enabled: Bool) {
        guard canToggleRadioEnabled(group), var state = groups[group],
              let nextSnapshot = snapshotAfterTogglingRadioEnabled(
                  group,
                  state: state,
                  enabled: enabled
              ) else {
            return
        }
        let normalizedPower = nextSnapshot.power == state.draft.power
            ? nil
            : nextSnapshot.power
        let wasMulti = state.draft.operatingMode == .multi
        if enabled, nextSnapshot.operatingMode == .multi {
            if state.lastKnownActiveMode == nil {
                state.lastKnownActiveMode = .manual
            }
        } else if enabled {
            state.lastKnownActiveMode = nextSnapshot.operatingMode
            state.draftRestoresAfterMulti = false
        } else if !wasMulti {
            state.lastKnownActiveMode = state.draft.operatingMode
            state.draftRestoresAfterMulti = false
        }
        state.draft = nextSnapshot
        groups[group] = state
        groupConfigurations[group]?.isEnabledOnRadio = enabled
        noteCommonRangeNormalization(normalizedPower, for: group)
        if enabled, nextSnapshot.operatingMode == .multi,
           let safePower = allowedMultiFlashPowers.first {
            let nextPower = allowedMultiFlashPowers.contains(multiFlashDraft.power)
                ? multiFlashDraft.power
                : safePower
            let maximumCount = maximumMultiFlashCount(
                power: nextPower,
                hertz: multiFlashDraft.hertz,
                groups: multiFlashGroups
            )
            if let normalized = MultiFlashSettings(
                power: nextPower,
                count: min(multiFlashDraft.count, maximumCount),
                hertz: multiFlashDraft.hertz
            ), normalized != multiFlashDraft {
                if normalized.power != multiFlashDraft.power {
                    addActivity(
                        .info,
                        "Multi se ajustó a \(safePower.label), el mínimo común de sus flashes"
                    )
                }
                noteMultiFlashCountNormalization(from: multiFlashDraft, to: normalized)
                multiFlashDraft = normalized
            }
        }
        draftDidChange()
    }

    private func snapshotAfterTogglingRadioEnabled(
        _ group: GodoxGroup,
        state: GroupDraft,
        enabled: Bool
    ) -> ManualGroupSnapshot? {
        var candidate = state.draft
        if enabled {
            guard candidate.operatingMode == .off else { return nil }
            let restoredMode: GroupOperatingMode
            if !multiFlashGroups.isEmpty {
                guard supportsMultiFlash(group) else { return nil }
                restoredMode = .multi
            } else if state.lastKnownActiveMode == .autoTTL {
                restoredMode = .autoTTL
            } else {
                restoredMode = .manual
            }
            guard availableOperatingModes(for: group).contains(restoredMode) else { return nil }
            candidate.operatingMode = restoredMode
            if restoredMode == .autoTTL || restoredMode == .multi {
                candidate.compensationByte = 0
            }
        } else {
            guard availableOperatingModes(for: group).contains(candidate.operatingMode) else {
                return nil
            }
            if candidate.operatingMode == .multi, multiFlashGroups.count <= 1 {
                return nil
            }
            candidate.operatingMode = .off
        }

        let scale = resolvedCapability(for: group).powerScale
        guard let safeMinimum = scale.first else { return nil }
        if !scale.contains(candidate.power) {
            candidate.power = safeMinimum
        }
        return isValidForTransmission(group, snapshot: candidate) ? candidate : nil
    }

    func setGroupVisible(_ group: GodoxGroup, isVisible: Bool) {
        let result = LocalGroupPreferences.visibilityAfterToggling(
            group,
            isVisible: isVisible,
            currentVisibleGroups: visibleGroups,
            supportedGroups: workingGroups
        )
        visibleGroups = result.visibleGroups
        for supportedGroup in workingGroups {
            groupConfigurations[supportedGroup]?.isVisibleLocally = visibleGroups.contains(supportedGroup)
        }
        if result.wasAccepted {
            visibleGroups = visibilityPreferences.saveVisibleGroups(
                visibleGroups,
                supportedGroups: workingGroups
            )
            if hasCompletedOnboarding, !persistStudioLibrary() {
                addActivity(.warning, "No se pudo guardar la visibilidad de los grupos")
            }
        } else {
            addActivity(.warning, "Debe quedar al menos un grupo visible")
        }
    }

    func beginWorkspaceConfiguration() {
        guard canConfigureWorkspace, hasCompletedOnboarding else {
            addActivity(
                .warning,
                "Espera a que termine la operación actual antes de configurar los grupos"
            )
            return
        }
        hasCompletedOnboarding = false
        if !persistStudioLibrary() {
            hasCompletedOnboarding = true
            addActivity(.error, "No se pudo abrir la configuración del primer inicio")
            return
        }
        cancelAutomaticApply()
        isReconfiguringWorkspace = true
    }

    func cancelWorkspaceConfiguration() {
        guard isReconfiguringWorkspace, canConfigureWorkspace else { return }
        hasCompletedOnboarding = true
        guard persistStudioLibrary() else {
            hasCompletedOnboarding = false
            addActivity(.error, "No se pudo restaurar la configuración anterior")
            return
        }
        isReconfiguringWorkspace = false
        addActivity(.info, "Se conservó la configuración anterior")
    }

    @discardableResult
    func completeWorkspaceConfiguration(
        profileID: String,
        selectedGroups: Set<GodoxGroup>,
        assignedFlashModelIDs: [GodoxGroup: Set<String>]
    ) -> Bool {
        guard canConfigureWorkspace,
              let profile = availableTransmitterProfiles.first(where: { $0.id == profileID }) else {
            addActivity(.warning, "Espera a que termine la operación actual antes de guardar")
            return false
        }
        if phase == .ready {
            guard isReconfiguringWorkspace else {
                addActivity(.warning, "Abre la configuración antes de cambiar grupos conectados")
                return false
            }
            guard profile.id == transmitterProfile.id else {
                addActivity(.warning, "Desconecta el radio antes de cambiar el perfil")
                return false
            }
        }

        let orderedGroups = profile.supportedGroups.filter(selectedGroups.contains)
        guard !orderedGroups.isEmpty else {
            addActivity(.warning, "Selecciona al menos un grupo de trabajo")
            return false
        }

        let catalogIDs = Set(profile.flashCatalog.map(\.id))
        for group in orderedGroups {
            let validModels = assignedFlashModelIDs[group, default: []]
                .intersection(catalogIDs)
            guard !validModels.isEmpty else {
                addActivity(
                    .warning,
                    "Asigna al menos un modelo de flash a \(group.label)"
                )
                return false
            }
        }

        let previousProfile = transmitterProfile
        let previousWorkingGroups = workingGroups
        let previousVisibleGroups = visibleGroups
        let previousConfigurations = groupConfigurations
        let previousGroups = groups
        let previousOnboardingState = hasCompletedOnboarding
        let previousStoredWorkspaceState = hasStoredWorkspaceConfiguration
        let previousReconfigurationState = isReconfiguringWorkspace
        let previousActivePresetID = activePresetID
        let previousAutomaticSuppression = automaticApplySuppressedForLocalPreset
        let previousMultiFlashDraft = multiFlashDraft
        let requestedVisibleGroups = previousReconfigurationState
            ? orderedGroups.filter {
                !previousWorkingGroups.contains($0) || previousVisibleGroups.contains($0)
            }
            : orderedGroups
        let nextVisibleGroups = LocalGroupPreferences.normalizedVisibleGroups(
            requestedVisibleGroups,
            supportedGroups: orderedGroups
        )

        var nextConfigurations = groupConfigurations
        for group in GodoxGroup.allCases {
            guard var configuration = nextConfigurations[group] else {
                addActivity(.error, "Falta la configuración local de \(group.label)")
                return false
            }
            if orderedGroups.contains(group) {
                configuration.assignedFlashModelIDs =
                    assignedFlashModelIDs[group, default: []].intersection(catalogIDs)
            }
            configuration.isVisibleLocally = nextVisibleGroups.contains(group)
            nextConfigurations[group] = configuration
        }

        var nextGroups = groups
        for group in orderedGroups {
            guard var state = nextGroups[group],
                  var configuration = nextConfigurations[group] else {
                addActivity(.error, "Falta el estado local de \(group.label)")
                return false
            }
            let capability = ResolvedGroupCapability.resolve(
                configuration: configuration,
                profile: profile
            )
            guard let safeMinimum = capability.powerScale.first else {
                addActivity(.warning, "El grupo \(group.label) no tiene un rango manual válido")
                return false
            }

            if previousWorkingGroups.contains(group) {
                if !capability.powerScale.contains(state.draft.power) {
                    state.draft.power = safeMinimum
                }
            } else {
                var safeSnapshot = state.draft
                safeSnapshot.operatingMode = .off
                if !capability.powerScale.contains(safeSnapshot.power) {
                    safeSnapshot.power = safeMinimum
                }
                if safeSnapshot.beepEnabled && !capability.supportsBeepDraft {
                    safeSnapshot.beepEnabled = false
                }
                state = GroupDraft(baseline: safeSnapshot, draft: safeSnapshot)
                configuration.isEnabledOnRadio = false
                nextConfigurations[group] = configuration
            }

            guard let minimumDenominator = capability.minimumManualDenominator,
                  ManualPower.isSupported(
                      state.draft.power,
                      minimumDenominator: minimumDenominator
                  ),
                  state.draft.modelingState.isValidForWrite,
                  state.draft.operatingMode == .manual ||
                    state.draft.operatingMode == .autoTTL ||
                    state.draft.operatingMode == .multi ||
                    state.draft.operatingMode == .off,
                  !state.draft.beepEnabled || capability.supportsBeepDraft else {
                addActivity(.warning, "Los valores actuales de \(group.label) no son compatibles")
                return false
            }
            if state.draft.operatingMode == .multi,
               (!profile.supportedMultiGroups.contains(group) || capability.multiPowerScale.isEmpty) {
                addActivity(.warning, "El grupo \(group.label) no admite Multi en este perfil")
                return false
            }
            nextGroups[group] = state
        }

        var restoredSceneForWorkspaceChange = false
        let retainedMultiGroups = orderedGroups.filter {
            nextGroups[$0]?.draft.operatingMode == .multi
        }
        if retainedMultiGroups.isEmpty {
            for group in orderedGroups {
                guard var state = nextGroups[group],
                      let configuration = nextConfigurations[group] else { return false }
                if state.draftRestoresAfterMulti {
                    state.draft.operatingMode = state.lastKnownActiveMode == .autoTTL
                        ? .autoTTL
                        : .manual
                    if state.draft.operatingMode == .autoTTL {
                        state.draft.compensationByte = 0
                    }
                    restoredSceneForWorkspaceChange = true
                }
                state.draftRestoresAfterMulti = false
                let capability = ResolvedGroupCapability.resolve(
                    configuration: configuration,
                    profile: profile
                )
                guard let minimum = capability.minimumManualDenominator,
                      ManualPower.isSupported(
                          state.draft.power,
                          minimumDenominator: minimum
                      ),
                      state.draft.modelingState.isValidForWrite,
                      state.draft.operatingMode == .manual ||
                        state.draft.operatingMode == .autoTTL ||
                        state.draft.operatingMode == .off,
                      !state.draft.beepEnabled || capability.supportsBeepDraft else {
                    addActivity(.warning, "No se pudo restaurar la escena previa de \(group.label)")
                    return false
                }
                nextGroups[group] = state
                nextConfigurations[group]?.isEnabledOnRadio =
                    state.draft.isEnabledOnRadio
            }
        }

        transmitterProfile = profile
        workingGroups = orderedGroups
        visibleGroups = nextVisibleGroups
        groupConfigurations = nextConfigurations
        groups = nextGroups
        guard normalizeMultiFlashDraftForCurrentGroups() else { return false }

        hasStoredWorkspaceConfiguration = true
        hasCompletedOnboarding = true
        isReconfiguringWorkspace = false
        activePresetID = nil
        automaticApplySuppressedForLocalPreset = false
        guard persistStudioLibrary() else {
            transmitterProfile = previousProfile
            workingGroups = previousWorkingGroups
            visibleGroups = previousVisibleGroups
            groupConfigurations = previousConfigurations
            groups = previousGroups
            multiFlashDraft = previousMultiFlashDraft
            hasCompletedOnboarding = previousOnboardingState
            hasStoredWorkspaceConfiguration = previousStoredWorkspaceState
            isReconfiguringWorkspace = previousReconfigurationState
            activePresetID = previousActivePresetID
            automaticApplySuppressedForLocalPreset = previousAutomaticSuppression
            addActivity(
                .error,
                "No se pudo guardar el espacio de trabajo; la configuración anterior se conservó"
            )
            return false
        }
        visibleGroups = visibilityPreferences.saveVisibleGroups(
            nextVisibleGroups,
            supportedGroups: orderedGroups
        )
        addActivity(
            .success,
            "Espacio de trabajo listo · \(orderedGroups.map(\.label).joined(separator: ", "))"
        )
        if restoredSceneForWorkspaceChange {
            addActivity(.info, "Multi global se desactivó y se restauró la escena previa")
        }
        scheduleAutomaticApplyIfNeeded()
        return true
    }

    var canManagePresets: Bool {
        hasCompletedOnboarding && workingConfigurationIssue == nil &&
            restorationPoints.isEmpty && (phase == .idle || phase == .ready) &&
            !isInteractiveEditActive && !isSynchronizingValues && !isTestPending
    }

    func presetNameExists(_ name: String) -> Bool {
        let candidate = canonicalPresetName(name)
        guard !candidate.isEmpty else { return false }
        return presets.contains { canonicalPresetName($0.name) == candidate }
    }

    func presetCompatibilityIssue(_ preset: StudioPreset) -> String? {
        guard preset.profileID == transmitterProfile.id,
              preset.groups == workingGroups else {
            return "Este preset no coincide con el perfil y los grupos de trabajo actuales"
        }
        let presetGlobalBeep = preset.groups.contains {
            preset.states[$0]?.beepEnabled == true
        }
        let presetMultiGroups = preset.groups.filter {
            preset.states[$0]?.operatingMode == .multi
        }
        if !presetMultiGroups.isEmpty,
           preset.groups.contains(where: {
               let mode = preset.states[$0]?.operatingMode
               return mode == .manual || mode == .autoTTL
           }) {
            return "Multi es global; el preset mezcla grupos Multi con M/TTL"
        }
        if !presetMultiGroups.isEmpty,
           !multiPowerScale(for: presetMultiGroups).contains(preset.multiFlashSettings.power) {
            return "La potencia Multi del preset no coincide con los flashes configurados"
        }
        if !presetMultiGroups.isEmpty,
           preset.multiFlashSettings.count > maximumMultiFlashCount(
               power: preset.multiFlashSettings.power,
               hertz: preset.multiFlashSettings.hertz,
               groups: presetMultiGroups
           ) {
            return "Los destellos Multi del preset superan el límite seguro de sus flashes"
        }
        for group in preset.groups {
            guard var snapshot = preset.states[group] else {
                return "El preset no es compatible con el rango del grupo \(group.label)"
            }
            snapshot.beepEnabled = presetGlobalBeep
            guard isValidForTransmission(group, snapshot: snapshot) else {
                return "El preset no es compatible con el rango del grupo \(group.label)"
            }
        }
        return nil
    }

    @discardableResult
    func savePreset(named name: String) -> Bool {
        guard canManagePresets else {
            addActivity(.warning, "Completa la configuración antes de guardar presets")
            return false
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            addActivity(.warning, "Escribe un nombre para el preset")
            return false
        }
        guard !presetNameExists(trimmed) else {
            addActivity(.warning, "Ya existe un preset con ese nombre")
            return false
        }
        let states = Dictionary(uniqueKeysWithValues: workingGroups.map { group in
            var snapshot = groupDraft(group).draft
            snapshot.beepEnabled = globalBeepEnabled
            return (group, snapshot)
        })
        let lastKnownActiveModes = Dictionary(uniqueKeysWithValues: workingGroups.compactMap {
            group -> (GodoxGroup, GroupOperatingMode)? in
            guard let mode = groupDraft(group).lastKnownActiveMode,
                  mode == .manual || mode == .autoTTL else { return nil }
            return (group, mode)
        })
        let groupsRestoredAfterMulti = Set(workingGroups.filter {
            groupDraft($0).draftRestoresAfterMulti
        })
        guard let preset = StudioPreset(
            name: trimmed,
            profileID: transmitterProfile.id,
            groups: workingGroups,
            states: states,
            lastKnownActiveModes: lastKnownActiveModes,
            groupsRestoredAfterMulti: groupsRestoredAfterMulti,
            multiFlashSettings: multiFlashDraft
        ) else {
            addActivity(.error, "No se pudo preparar el preset")
            return false
        }
        let previousPresets = presets
        presets.insert(preset, at: 0)
        guard persistStudioLibrary() else {
            presets = previousPresets
            addActivity(.error, "No se pudo guardar el preset en este Mac")
            return false
        }
        activePresetID = preset.id
        addActivity(.success, "Preset “\(preset.name)” guardado")
        return true
    }

    @discardableResult
    func deletePreset(id: UUID) -> Bool {
        guard let index = presets.firstIndex(where: { $0.id == id }),
              canManagePresets else { return false }
        let previousPresets = presets
        let removed = presets.remove(at: index)
        guard persistStudioLibrary() else {
            presets = previousPresets
            addActivity(.error, "No se pudo eliminar el preset")
            return false
        }
        if activePresetID == id { activePresetID = nil }
        addActivity(.info, "Preset “\(removed.name)” eliminado")
        return true
    }

    @discardableResult
    func loadPreset(id: UUID, synchronizeIfConnected: Bool) -> Bool {
        guard let preset = presets.first(where: { $0.id == id }),
              canManagePresets else {
            addActivity(.warning, "Espera a que termine la operación actual")
            return false
        }
        if synchronizeIfConnected, phase == .ready, !canSynchronizeValues {
            addActivity(
                .warning,
                valueSynchronizationBlockReason ?? "Espera a que termine la operación actual"
            )
            return false
        }
        if let compatibilityIssue = presetCompatibilityIssue(preset) {
            addActivity(.warning, compatibilityIssue)
            return false
        }

        cancelAutomaticApply()
        let previousGroups = groups
        let previousActivePresetID = activePresetID
        let previousAutomaticSuppression = automaticApplySuppressedForLocalPreset
        let previousGlobalBeepEnabled = globalBeepEnabled
        let previousMultiFlashBaseline = multiFlashBaseline
        let previousMultiFlashDraft = multiFlashDraft
        let presetGlobalBeep = preset.groups.contains {
            preset.states[$0]?.beepEnabled == true
        }
        for group in preset.groups {
            guard var snapshot = preset.states[group], var state = groups[group] else { continue }
            snapshot.beepEnabled = presetGlobalBeep
            state.draft = snapshot
            if let storedMode = preset.lastKnownActiveModes[group] {
                state.lastKnownActiveMode = storedMode
            } else if snapshot.operatingMode == .manual || snapshot.operatingMode == .autoTTL {
                state.lastKnownActiveMode = snapshot.operatingMode
            }
            state.draftRestoresAfterMulti =
                preset.groupsRestoredAfterMulti.contains(group)
            if phase == .idle {
                state.baseline = snapshot
                state.baselineLastKnownActiveMode = state.lastKnownActiveMode
                state.baselineRestoresAfterMulti = state.draftRestoresAfterMulti
                state.confirmation = .unread
            }
            groups[group] = state
            groupConfigurations[group]?.isEnabledOnRadio = snapshot.isEnabledOnRadio
        }
        globalBeepEnabled = presetGlobalBeep
        multiFlashDraft = preset.multiFlashSettings
        if phase == .idle {
            multiFlashBaseline = preset.multiFlashSettings
        }
        activePresetID = preset.id
        guard persistStudioLibrary() else {
            groups = previousGroups
            globalBeepEnabled = previousGlobalBeepEnabled
            multiFlashBaseline = previousMultiFlashBaseline
            multiFlashDraft = previousMultiFlashDraft
            activePresetID = previousActivePresetID
            automaticApplySuppressedForLocalPreset = previousAutomaticSuppression
            addActivity(.error, "No se pudo cargar el preset en el espacio de trabajo")
            return false
        }

        if synchronizeIfConnected && phase == .ready {
            automaticApplySuppressedForLocalPreset = false
            startValueSynchronization(purpose: .presetSynchronization(preset.id))
        } else {
            automaticApplySuppressedForLocalPreset = phase == .ready && pendingCount > 0
            addActivity(
                .success,
                phase == .ready
                    ? "Preset “\(preset.name)” cargado · aún no enviado al radio"
                    : "Preset “\(preset.name)” cargado · se enviará al conectar"
            )
        }
        return true
    }

    func setFlashModel(_ modelID: String, assigned: Bool, to group: GodoxGroup) {
        guard transmitterProfile.supportedGroups.contains(group),
              canConfigureWorkspace,
              !isReconfiguringWorkspace,
              transmitterProfile.flashCatalog.contains(where: { $0.id == modelID }),
              var configuration = groupConfigurations[group] else {
            return
        }
        cancelAutomaticApply()
        let previousConfiguration = configuration
        let previousState = groups[group]
        let previousActivePresetID = activePresetID
        let previousMultiFlashDraft = multiFlashDraft
        if assigned {
            configuration.assignedFlashModelIDs.insert(modelID)
        } else {
            if hasCompletedOnboarding,
               workingGroups.contains(group),
               configuration.assignedFlashModelIDs.count == 1,
               configuration.assignedFlashModelIDs.contains(modelID) {
                addActivity(
                    .warning,
                    "Cada grupo de trabajo debe conservar al menos un modelo de flash"
                )
                return
            }
            configuration.assignedFlashModelIDs.remove(modelID)
        }

        let capability = ResolvedGroupCapability.resolve(
            configuration: configuration,
            profile: transmitterProfile
        )
        if hasCompletedOnboarding, workingGroups.contains(group),
           let state = groups[group],
           (capability.powerScale.isEmpty ||
            (state.draft.operatingMode == .multi && capability.multiPowerScale.isEmpty) ||
            (state.draft.beepEnabled && !capability.supportsBeepDraft)) {
            addActivity(.warning, "Los valores actuales de \(group.label) no admiten ese modelo")
            scheduleAutomaticApplyIfNeeded()
            return
        }

        groupConfigurations[group] = configuration
        let scale = capability.powerScale
        if let first = scale.first, var state = groups[group], !scale.contains(state.draft.power) {
            state.draft.power = first
            groups[group] = state
            addActivity(.warning, "El borrador de \(group.label) se ajustó al rango común \(first.label)")
        }
        if groups[group]?.draft.operatingMode == .multi,
           !normalizeMultiFlashDraftForCurrentGroups() {
            groupConfigurations[group] = previousConfiguration
            if let previousState { groups[group] = previousState }
            multiFlashDraft = previousMultiFlashDraft
            addActivity(.warning, "No se pudo conservar un ajuste Multi seguro")
            scheduleAutomaticApplyIfNeeded()
            return
        }
        activePresetID = nil
        if hasCompletedOnboarding, !persistStudioLibrary() {
            groupConfigurations[group] = previousConfiguration
            if let previousState { groups[group] = previousState }
            multiFlashDraft = previousMultiFlashDraft
            activePresetID = previousActivePresetID
            addActivity(.warning, "La configuración cambió, pero no pudo guardarse")
            scheduleAutomaticApplyIfNeeded()
            return
        }
        addActivity(.info, "La configuración de \(group.label) actualizó su rango de potencia")
        scheduleAutomaticApplyIfNeeded()
    }

    func prepareBaselineRestoration(for group: GodoxGroup) {
        guard !isInteractiveEditActive else {
            addActivity(.warning, "Suelta el control antes de preparar una recuperación")
            return
        }
        cancelAutomaticApply()
        guard restorationPoints[group] != nil,
              physicalSafetyState.prepareRestoration(for: group) != nil else { return }

        let orderedGroups = GodoxGroup.allCases.filter { restorationPoints[$0] != nil }
        for restorationGroup in orderedGroups {
            guard let point = restorationPoints[restorationGroup],
                  var state = groups[restorationGroup] else { continue }
            let restoration = point.snapshot
            state.draft = restoration
            if let underlyingMode = point.multiUnderlyingMode {
                state.lastKnownActiveMode = underlyingMode
            } else if restoration.operatingMode == .manual ||
                        restoration.operatingMode == .autoTTL {
                state.lastKnownActiveMode = restoration.operatingMode
            }
            state.draftRestoresAfterMulti = point.restoresAfterMulti
            groups[restorationGroup] = state
        }

        if let globalSnapshot = restorationPoints.values.first?.globalSnapshot,
           let settings = MultiFlashSettings(
               countByte: globalSnapshot.multiCount,
               hertzByte: globalSnapshot.multiHertz,
               powerByte: globalSnapshot.multiPowerByte
           ) {
            globalBeepEnabled = globalSnapshot.beepEnabled
            multiFlashDraft = settings
            isGlobalStandbyEnabled = globalSnapshot.standbyEnabled
        }
        let labels = orderedGroups.map(\.label).joined(separator: ", ")
        addActivity(
            .warning,
            "Escena segura preparada para recuperar \(labels); falta pulsar Aplicar"
        )
    }

    /// Disparo global explícito. El protocolo Test viaja por FFF1 sin
    /// respuesta, por lo que sólo se informa que CoreBluetooth recibió la
    /// orden; nunca se presenta como confirmación óptica del flash.
    func sendTestFlash() {
        guard canSendTest else {
            if let testBlockReason { addActivity(.warning, testBlockReason) }
            return
        }
        isTestPending = true
        testDeliveryDeadline?.cancel()
        testDeliveryDeadline = deadlineScheduler.schedule(.testDelivery) { [weak self] in
            guard let self, self.isTestPending else { return }
            self.testDeliveryDeadline = nil
            self.isTestPending = false
            self.invalidateSession("La orden Test no fue entregada a CoreBluetooth en 3 segundos")
        }
        addActivity(
            .warning,
            multiFlashGroups.isEmpty
                ? "Enviando disparo Test global"
                : "Enviando prueba de secuencia Multi global"
        )
        client.sendTest(SafeGodoxProtocol.testPayload(now: Date()))
    }

    func startScanning() {
        if let recoveryBlockReason {
            addActivity(.error, recoveryBlockReason)
            return
        }
        guard pendingDisconnectResolution == nil else {
            addActivity(.warning, "Espera a que termine la recuperación del enlace")
            return
        }
        resetTransientSessionState()
        devices.removeAll()
        selectDeviceAutomatically(nil)
        phase = .scanning
        scanDeadline = deadlineScheduler.schedule(.scan) { [weak self] in
            guard let self, self.phase == .scanning else { return }
            self.scanDeadline = nil
            self.client.stopScanning()
            if self.phase == .scanning {
                self.phase = .idle
            }
            self.addActivity(.info, "Búsqueda finalizada; puedes volver a intentar")
        }
        client.startScanning()
    }

    func connectSelectedDevice() {
        guard pendingDisconnectResolution == nil else {
            addActivity(.warning, "Espera a que termine la recuperación del enlace")
            return
        }
        guard let selectedDevice else {
            failLocally("Selecciona un radio antes de conectar")
            return
        }
        guard isRadioCodeValid else {
            failLocally("El código local del radio debe tener seis dígitos")
            return
        }
        if !physicalSafetyState.permitsConnection(to: selectedDevice.id) {
            failLocally("La restauración pendiente pertenece a otro radio; selecciona el transmisor original")
            return
        }
        resetTransientSessionState()
        lastValueSynchronizationAt = nil
        shouldSaveRadioAfterAuthentication = rememberSelectedRadio
        sessionDeviceID = selectedDevice.id
        let attemptID = UUID()
        sessionID = attemptID
        phase = .connecting
        connectedDeviceName = selectedDevice.name
        addActivity(.info, "Conectando con \(selectedDevice.name)")
        connectionSetupDeadline = deadlineScheduler.schedule(.connectionSetup) { [weak self] in
            guard let self, self.sessionID == attemptID else { return }
            switch self.phase {
            case .connecting, .discovering:
                self.connectionSetupDeadline = nil
                self.invalidateSession("El radio no completó el enlace Bluetooth a tiempo")
            default:
                break
            }
        }
        client.connect(to: selectedDevice)
    }

    func disconnect() {
        guard canDisconnect else {
            addActivity(.warning, "Espera a que termine la operación pendiente")
            return
        }
        beginDisconnectRecovery(.idle)
    }

    func cancelConnectionAttempt() {
        guard canCancelConnectionAttempt else { return }
        if phase == .scanning {
            scanDeadline?.cancel()
            scanDeadline = nil
            client.stopScanning()
            resetTransientSessionState()
            phase = .idle
            addActivity(.info, "Búsqueda cancelada")
            return
        }
        addActivity(.info, "Intento de conexión cancelado")
        beginDisconnectRecovery(.idle)
    }

    func selectDevice(_ deviceID: UUID?) {
        setSelectedDevice(deviceID, explicitly: deviceID != nil)
    }

    private func selectDeviceAutomatically(_ deviceID: UUID?) {
        setSelectedDevice(deviceID, explicitly: false)
    }

    private func setSelectedDevice(_ deviceID: UUID?, explicitly: Bool) {
        guard selectedDeviceID != deviceID else {
            if explicitly { selectedDeviceWasChosenExplicitly = true }
            return
        }
        selectedDeviceID = deviceID
        selectedDeviceWasChosenExplicitly = explicitly
        if let deviceID, let savedRadio = savedRadio(for: deviceID) {
            radioCode = savedRadio.radioCode
        } else {
            radioCode = ""
        }
    }

    func forgetSavedRadio(_ deviceID: UUID) {
        guard canForgetSavedRadios else { return }
        guard savedRadio(for: deviceID) != nil else { return }
        guard savedRadioStore.remove(deviceID: deviceID) else {
            addActivity(.error, "No se pudo eliminar el radio guardado")
            return
        }
        savedRadios.removeAll { $0.deviceID == deviceID }
        if selectedDeviceID == deviceID {
            rememberSelectedRadio = false
            radioCode = ""
        }
        addActivity(.info, "Radio guardado eliminado de este Mac")
    }

    func noteTerminationBlockedForRestoration() {
        addActivity(
            .error,
            "No se puede cerrar: recupera el ajuste anterior antes de salir"
        )
    }

    func adjust(_ group: GodoxGroup, direction: Int) {
        guard canEdit(group), direction == -1 || direction == 1,
              let state = groups[group] else {
            return
        }

        let allowed = allowedPowers(for: group)
        guard let nextPower = adjustedPower(
            from: state.draft.power,
            allowed: allowed,
            direction: direction
        ) else { return }
        setDraftPower(group, power: nextPower)
    }

    @discardableResult
    func adjustGlobalPower(direction: Int) -> GlobalPowerAdjustmentOutcome {
        guard direction == -1 || direction == 1 else { return .unavailable }
        let anchor = makeGlobalPowerAnchor()
        let outcome = attemptGlobalPowerAdjustment(
            offsetSteps: direction,
            from: anchor,
            limitedTo: 9
        )
        guard case .applied = outcome else { return outcome }
        let step = direction > 0 ? "+1/3 EV" : "−1/3 EV"
        addActivity(
            .info,
            "Potencia global \(step) · \(anchor.keys.sorted { $0.rawValue < $1.rawValue }.map(\.label).joined(separator: ", "))"
        )
        return outcome
    }

    /// Aplica un offset discreto de 1/3 EV desde una instantánea estable.
    /// El offset se limita una sola vez contra la intersección común y luego
    /// se aplica por igual a todos los grupos del ancla. El cálculo nunca parte
    /// del borrador producido por una llamada anterior, evitando histéresis.
    @discardableResult
    func adjustGlobalPower(
        offsetSteps: Int,
        from anchor: [GodoxGroup: ManualPower]
    ) -> GlobalPowerAdjustmentOutcome {
        guard permitsGlobalPowerAdjustment,
              let positions = globalPowerPositions(from: anchor),
              let bounds = commonGlobalPowerOffsetBounds(for: positions) else {
            return .unavailable
        }
        let commonOffset = min(bounds.upperBound, max(bounds.lowerBound, offsetSteps))

        applyGlobalPowerOffset(commonOffset, positions: positions)
        if commonOffset < offsetSteps {
            return .limited(
                offsetSteps: commonOffset,
                cause: .groups(positions.compactMap { position in
                    position.allowed.index(before: position.allowed.endIndex) - position.anchorIndex ==
                        bounds.upperBound
                        ? position.group
                        : nil
                })
            )
        }
        if commonOffset > offsetSteps {
            return .limited(
                offsetSteps: commonOffset,
                cause: .groups(positions.compactMap { position in
                    position.allowed.startIndex - position.anchorIndex == bounds.lowerBound
                        ? position.group
                        : nil
                })
            )
        }
        return .applied(offsetSteps: commonOffset)
    }

    /// Intenta un offset dentro de una ventana visual. Si el usuario arrastra
    /// más allá, aplica el último valor seguro y devuelve la causa del límite.
    @discardableResult
    func attemptGlobalPowerAdjustment(
        offsetSteps: Int,
        from anchor: [GodoxGroup: ManualPower],
        limitedTo limit: Int = 9
    ) -> GlobalPowerAdjustmentOutcome {
        guard let constraint = globalPowerConstraint(from: anchor, limitedTo: limit),
              let positions = globalPowerPositions(from: anchor) else {
            return .unavailable
        }

        let commonOffset = min(
            constraint.allowedOffsets.upperBound,
            max(constraint.allowedOffsets.lowerBound, offsetSteps)
        )
        applyGlobalPowerOffset(commonOffset, positions: positions)

        if offsetSteps < constraint.allowedOffsets.lowerBound {
            return .limited(offsetSteps: commonOffset, cause: constraint.lowerBoundary)
        }
        if offsetSteps > constraint.allowedOffsets.upperBound {
            return .limited(offsetSteps: commonOffset, cause: constraint.upperBoundary)
        }
        return .applied(offsetSteps: commonOffset)
    }

    private func applyGlobalPowerOffset(
        _ commonOffset: Int,
        positions: [GlobalPowerPosition]
    ) {

        var updatedGroups = groups
        var changed = false
        for position in positions {
            guard var state = updatedGroups[position.group],
                  position.allowed.indices.contains(position.anchorIndex + commonOffset) else {
                return
            }
            let target = position.allowed[position.anchorIndex + commonOffset]
            guard target != state.draft.power else { continue }
            state.draft.power = target
            updatedGroups[position.group] = state
            changed = true
        }

        guard changed else { return }
        groups = updatedGroups
        draftDidChange()
    }

    private var permitsGlobalPowerAdjustment: Bool {
        recoveryBlockReason == nil && phase == .ready && !isGlobalStandbyEnabled &&
            !isTestPending &&
            physicalSafetyState.allowsNewEdits
    }

    private func globalPowerPositions(
        from anchor: [GodoxGroup: ManualPower]
    ) -> [GlobalPowerPosition]? {
        guard !anchor.isEmpty else { return nil }
        let orderedGroups = transmitterProfile.supportedGroups.filter { anchor[$0] != nil }
        guard orderedGroups.count == anchor.count else { return nil }

        var positions: [GlobalPowerPosition] = []
        for group in orderedGroups {
            guard groups[group] != nil,
                  let power = anchor[group] else {
                return nil
            }
            let allowed = allowedPowers(for: group)
            guard let anchorIndex = allowed.firstIndex(of: power) else {
                return nil
            }
            positions.append(GlobalPowerPosition(
                group: group,
                allowed: allowed,
                anchorIndex: anchorIndex
            ))
        }
        return positions
    }

    private func commonGlobalPowerOffsetBounds(
        from anchor: [GodoxGroup: ManualPower]
    ) -> ClosedRange<Int>? {
        guard permitsGlobalPowerAdjustment,
              let positions = globalPowerPositions(from: anchor) else {
            return nil
        }
        return commonGlobalPowerOffsetBounds(for: positions)
    }

    private func commonGlobalPowerOffsetBounds(
        for positions: [GlobalPowerPosition]
    ) -> ClosedRange<Int>? {
        guard let first = positions.first else { return nil }
        var lowerBound = first.allowed.startIndex - first.anchorIndex
        var upperBound = first.allowed.index(before: first.allowed.endIndex) - first.anchorIndex

        for position in positions.dropFirst() {
            lowerBound = max(
                lowerBound,
                position.allowed.startIndex - position.anchorIndex
            )
            upperBound = min(
                upperBound,
                position.allowed.index(before: position.allowed.endIndex) - position.anchorIndex
            )
        }
        return lowerBound...upperBound
    }

    private func adjustedPower(
        from current: ManualPower,
        allowed: [ManualPower],
        direction: Int
    ) -> ManualPower? {
        guard direction == -1 || direction == 1, !allowed.isEmpty else { return nil }
        if let index = allowed.firstIndex(of: current) {
            let targetIndex = max(
                allowed.startIndex,
                min(allowed.index(before: allowed.endIndex), index + direction)
            )
            let target = allowed[targetIndex]
            return target == current ? nil : target
        }

        // Un valor histórico puede quedar fuera de la intersección actual. No
        // se permite que "bajar" termine subiendo potencia para normalizarlo.
        if direction < 0 {
            return allowed.last { $0.decimalValue < current.decimalValue }
        }
        return allowed.first { $0.decimalValue > current.decimalValue }
    }

    /// Todo write nuevo usa la intersección de capacidades del grupo. El
    /// ajuste anterior puede quedar fuera de ese rango como verdad de
    /// recuperación, pero el primer cambio del usuario lo lleva al mínimo
    /// compartido antes de construir A1.
    @discardableResult
    private func normalizeDraftPowerToCommonRange(
        _ state: inout GroupDraft,
        for group: GodoxGroup
    ) -> ManualPower? {
        let scale = resolvedCapability(for: group).powerScale
        guard !scale.contains(state.draft.power), let commonMinimum = scale.first else {
            return nil
        }
        state.draft.power = commonMinimum
        return commonMinimum
    }

    private func noteCommonRangeNormalization(
        _ power: ManualPower?,
        for group: GodoxGroup
    ) {
        guard let power else { return }
        addActivity(
            .info,
            "\(group.label) se ajustó a \(power.label), el mínimo común de sus flashes"
        )
    }

    private func draftDidChange() {
        activePresetID = nil
        automaticApplySuppressedForLocalPreset = false
        if hasCompletedOnboarding, !persistStudioLibrary() {
            addActivity(.warning, "El valor cambió, pero no pudo guardarse para la próxima sesión")
        }
        scheduleAutomaticApplyIfNeeded()
    }

    private func scheduleAutomaticApplyIfNeeded() {
        cancelAutomaticApply()
        guard changeDeliveryMode == .automatic,
              !isInteractiveEditActive,
              !automaticApplySuppressedForLocalPreset,
              restorationPoints.isEmpty,
              canApply else {
            return
        }
        isAutomaticApplyScheduled = true
        automaticApplyDeadline = deadlineScheduler.schedule(.automaticApply) { [weak self] in
            guard let self, !self.isInteractiveEditActive else { return }
            self.automaticApplyDeadline = nil
            self.isAutomaticApplyScheduled = false
            self.applyPendingChanges()
        }
    }

    private func cancelAutomaticApply() {
        automaticApplyDeadline?.cancel()
        automaticApplyDeadline = nil
        isAutomaticApplyScheduled = false
    }

    private func updateApplySequenceStatus() {
        guard let activeGroupChange else {
            applySequenceStatus = nil
            return
        }
        applySequenceStatus = ApplySequenceStatus(
            activeGroup: activeGroupChange.group,
            remainingGroups: queuedGroupChanges.map(\.group),
            completedCount: applySequenceCompletedCount,
            totalCount: applySequenceTotalCount
        )
    }

    private func finishApplySequence() {
        let completedPurpose = applySequencePurpose
        let completedCount = applySequenceTotalCount
        if !restorationPoints.isEmpty {
            guard let sessionDeviceID else {
                failApplySequence("No se pudo identificar el radio para cerrar la operación segura")
                return
            }
            let previousSafetyState = physicalSafetyState
            let didComplete: Bool
            switch applySequenceJournalKind {
            case .forward:
                didComplete = physicalSafetyState.completeSuccessfulOperation(
                    deviceID: sessionDeviceID
                )
            case .restoration:
                didComplete = physicalSafetyState.completeRestoration(
                    deviceID: sessionDeviceID
                )
            case .none:
                didComplete = false
            }
            guard didComplete else {
                failApplySequence("No se pudo cerrar el lote de recuperación de la escena")
                return
            }
            guard restorationStore.clear() else {
                physicalSafetyState = previousSafetyState
                failApplySequence(
                    "El radio confirmó la escena, pero no se pudo cerrar su recuperación local"
                )
                return
            }
        }
        queuedGroupChanges.removeAll()
        activeGroupChange = nil
        applySequenceCompletedCount = 0
        applySequenceTotalCount = 0
        applySequenceStatus = nil
        applySequencePurpose = .pendingChanges
        applySequenceJournalKind = .none
        isSynchronizingValues = false
        phase = .ready
        if completedPurpose.synchronizesValues {
            lastValueSynchronizationAt = Date()
            addActivity(
                .success,
                "Valores sincronizados · \(completedCount) de \(completedCount) grupos confirmados"
            )
        }
        scheduleAutomaticApplyIfNeeded()
    }

    private func cancelApplySequence() {
        queuedGroupChanges.removeAll()
        activeGroupChange = nil
        applySequenceCompletedCount = 0
        applySequenceTotalCount = 0
        applySequenceStatus = nil
        applySequencePurpose = .pendingChanges
        applySequenceJournalKind = .none
        isSynchronizingValues = false
    }

    private func failApplySequence(_ message: String) {
        let failedPurpose = applySequencePurpose
        if failedPurpose.keepsConnectionFlowVisible {
            invalidateSession(message)
        } else {
            cancelApplySequence()
            phase = .ready
            addActivity(.error, message)
        }
    }

    func discardPendingChanges() {
        guard !isInteractiveEditActive else {
            addActivity(.warning, "Suelta el control antes de descartar")
            return
        }
        guard restorationPoints.isEmpty, phase != .applying else {
            addActivity(.warning, "Hay una recuperación pendiente; no se descartó el ajuste preparado")
            return
        }
        guard canDiscardPendingChanges else {
            addActivity(
                .warning,
                "El cambio global proviene del workspace y debe aplicarse al radio"
            )
            return
        }
        cancelAutomaticApply()
        automaticApplySuppressedForLocalPreset = false
        for group in transmitterProfile.supportedGroups {
            guard var state = groups[group] else { continue }
            state.discard()
            groups[group] = state
            groupConfigurations[group]?.isEnabledOnRadio = state.draft.isEnabledOnRadio
        }
        let safeMultiBeforeDiscard = multiFlashDraft
        multiFlashDraft = multiFlashBaseline
        if !normalizeMultiFlashDraftForCurrentGroups() {
            multiFlashDraft = safeMultiBeforeDiscard
            addActivity(
                .warning,
                "Los cambios de grupo se descartaron, pero Multi conservó su ajuste seguro pendiente"
            )
        }
        globalBeepEnabled = workingGroups.contains {
            groups[$0]?.draft.beepEnabled == true
        }
        activePresetID = nil
        if hasCompletedOnboarding, !persistStudioLibrary() {
            addActivity(.warning, "Los cambios se descartaron, pero el estado local no pudo guardarse")
        }
        addActivity(
            multiFlashDraft == multiFlashBaseline ? .info : .warning,
            multiFlashDraft == multiFlashBaseline
                ? "Cambios descartados"
                : "Multi conservó un ajuste seguro pendiente para los flashes configurados"
        )
    }

    func applyPendingChanges() {
        cancelAutomaticApply()
        automaticApplySuppressedForLocalPreset = false
        guard canApply else {
            if pendingCount > 0 {
                addActivity(.warning, applyBlockReason ?? physicalApplyBlockReason)
            }
            return
        }

        let targetGroups = groupsEligibleForApply
        let desiredGlobal = desiredGlobalSnapshot()
        if !restorationPoints.isEmpty {
            let requiredGroups = Set(restorationPoints.keys)
            guard !targetGroups.isEmpty,
                  Set(targetGroups) == requiredGroups,
                  let firstGroup = targetGroups.first,
                  let point = restorationPoints[firstGroup] else {
                addActivity(
                    .error,
                    "La recuperación no pudo reconstruir todos los grupos de la escena"
                )
                return
            }
            let recoveryGlobal = point.globalSnapshot ?? desiredGlobal
            if point.globalSnapshot == nil {
                addActivity(
                    .warning,
                    "El registro anterior no incluía A0; se reconstruyó un estado global conservador"
                )
            }
            let followup = GlobalControlFollowup(
                groups: targetGroups,
                purpose: .pendingChanges,
                forceWrite: false,
                restorationGlobalSnapshot: recoveryGlobal
            )
            if !submitGlobalControl(
                recoveryGlobal,
                purpose: .pendingChanges,
                followup: followup
            ) {
                addActivity(.error, "No se pudo preparar A0 para la recuperación segura")
            }
        } else if desiredGlobal != globalRadioSnapshot ||
                    (!hasConfirmedGlobalSnapshot && hasCompletedOnboarding) {
            let restorationGlobal = hasConfirmedGlobalSnapshot
                ? globalRadioSnapshot
                : desiredGlobal
            let followup = targetGroups.isEmpty ? nil : GlobalControlFollowup(
                groups: targetGroups,
                purpose: .pendingChanges,
                forceWrite: false,
                restorationGlobalSnapshot: restorationGlobal
            )
            if !submitGlobalControl(
                desiredGlobal,
                purpose: .pendingChanges,
                followup: followup
            ) {
                addActivity(.error, "No se pudo preparar el estado global previo a los cambios")
            }
        } else if !targetGroups.isEmpty {
            startApplySequence(
                groups: targetGroups,
                purpose: .pendingChanges,
                forceWrite: false,
                restorationGlobalSnapshot: hasConfirmedGlobalSnapshot
                    ? globalRadioSnapshot
                    : nil
            )
        }
    }

    func synchronizeValuesToRadio() {
        cancelAutomaticApply()
        automaticApplySuppressedForLocalPreset = false
        guard canSynchronizeValues else {
            if let valueSynchronizationBlockReason {
                addActivity(.warning, valueSynchronizationBlockReason)
            }
            return
        }
        startValueSynchronization(purpose: .manualSynchronization)
    }

    private func startValueSynchronization(purpose: ApplySequencePurpose) {
        automaticApplySuppressedForLocalPreset = false
        guard purpose.synchronizesValues, workingConfigurationIssue == nil else {
            if let workingConfigurationIssue {
                addActivity(.error, workingConfigurationIssue)
            }
            if purpose.keepsConnectionFlowVisible {
                invalidateSession("No se pudo iniciar la sincronización de valores")
            }
            return
        }
        harmonizeWorkingGroupBeepDrafts()
        isSynchronizingValues = true
        let desiredGlobal = desiredGlobalSnapshot()
        let followup = GlobalControlFollowup(
            groups: workingGroups,
            purpose: purpose,
            forceWrite: true,
            restorationGlobalSnapshot: desiredGlobal
        )
        guard submitGlobalControl(
            desiredGlobal,
            purpose: .valueSynchronization(purpose),
            followup: followup
        ) else {
            isSynchronizingValues = false
            if purpose.keepsConnectionFlowVisible {
                invalidateSession("No se pudo preparar la sincronización global inicial")
            } else {
                phase = .ready
                addActivity(.error, "No se pudo preparar la sincronización global")
            }
            return
        }
    }

    private func desiredGlobalSnapshot() -> GlobalRadioSnapshot {
        var snapshot = globalRadioSnapshot
        snapshot.beepEnabled = globalBeepEnabled
        snapshot.modelingLightEnabled = workingGroups.contains { group in
            groups[group]?.draft.modeling != .off
        }
        snapshot.multiEnabled = !multiFlashGroups.isEmpty
        snapshot.multiCount = multiFlashDraft.countByte
        snapshot.multiHertz = multiFlashDraft.hertzByte
        snapshot.multiPowerByte = multiFlashDraft.powerByte
        snapshot.standbyEnabled = isGlobalStandbyEnabled
        return snapshot
    }

    private func harmonizeWorkingGroupBeepDrafts() {
        var changed = false
        for group in workingGroups {
            guard var state = groups[group],
                  state.draft.beepEnabled != globalBeepEnabled else { continue }
            state.draft.beepEnabled = globalBeepEnabled
            groups[group] = state
            changed = true
        }
        guard changed, hasCompletedOnboarding, !persistStudioLibrary() else { return }
        addActivity(.warning, "El beep global se unificó, pero no pudo guardarse localmente")
    }

    @discardableResult
    private func submitGlobalControl(
        _ snapshot: GlobalRadioSnapshot,
        purpose: GlobalControlPurpose,
        followup: GlobalControlFollowup?
    ) -> Bool {
        guard recoveryBlockReason == nil,
              let sessionDeviceID,
              let sessionID,
              controlIntents.isEmpty,
              awaitingRadioResponses.isEmpty,
              activeGroupChange == nil,
              queuedGroupChanges.isEmpty else {
            return false
        }

        do {
            let frame = try SafeGodoxProtocol.globalFrame(snapshot: snapshot)
            if let followup,
               restorationPoints.isEmpty || applySequenceJournalKind == .forward {
                let preflightChanges = try makeQueuedGroupChanges(
                    groups: followup.groups,
                    forceWrite: followup.forceWrite,
                    restorationGlobalSnapshot: followup.restorationGlobalSnapshot,
                    isExactRestoration: false
                )
                guard prepareForwardJournal(for: preflightChanges) else {
                    addActivity(
                        .error,
                        "No se pudo guardar la escena anterior completa; no se transmitió A0"
                    )
                    return false
                }
            }
            let previousSnapshot = globalRadioSnapshot
            let intentID = UUID()
            globalRadioSnapshot = snapshot
            globalBeepEnabled = snapshot.beepEnabled
            isGlobalStandbyEnabled = snapshot.standbyEnabled
            isGlobalControlPending = true
            phase = purpose.keepsConnectionFlowVisible ? .synchronizing : .applying
            controlIntents.append(.global(
                intentID: intentID,
                deviceID: sessionDeviceID,
                sessionID: sessionID,
                snapshot: snapshot,
                previousSnapshot: previousSnapshot,
                purpose: purpose,
                followup: followup
            ))
            scheduleGlobalControlTimeout(for: intentID)
            switch purpose {
            case .valueSynchronization:
                addActivity(.info, "Sincronizando beep, modelado, Multi y standby globales")
            case .pendingChanges:
                addActivity(.info, "Actualizando el estado global y Multi antes de los grupos")
            case .beep:
                addActivity(.info, "Enviando beep global \(snapshot.beepEnabled ? "on" : "off")")
            case .standby:
                addActivity(.info, snapshot.standbyEnabled
                    ? "Activando standby general"
                    : "Reanudando todos los grupos")
            }
            submitControl(frame, intentID: intentID)
            return true
        } catch {
            addActivity(.error, "No se pudo construir A0: \(error.localizedDescription)")
            return false
        }
    }

    private func startApplySequence(
        groups targetGroups: [GodoxGroup],
        purpose: ApplySequencePurpose,
        forceWrite: Bool,
        restorationGlobalSnapshot: GlobalRadioSnapshot?
    ) {
        do {
            let isExactRestoration = !restorationPoints.isEmpty &&
                applySequenceJournalKind != .forward
            let changes = try makeQueuedGroupChanges(
                groups: targetGroups,
                forceWrite: forceWrite,
                restorationGlobalSnapshot: restorationGlobalSnapshot,
                isExactRestoration: isExactRestoration
            )
            guard !changes.isEmpty else { return }
            if isExactRestoration {
                applySequenceJournalKind = .restoration
            } else if !prepareForwardJournal(for: changes) {
                failApplySequence(
                    "No se pudo guardar la escena anterior completa; no se transmitió A1"
                )
                return
            }
            queuedGroupChanges = changes
            activeGroupChange = nil
            applySequenceCompletedCount = 0
            applySequenceTotalCount = changes.count
            applySequencePurpose = purpose
            isSynchronizingValues = purpose.synchronizesValues
            if purpose.synchronizesValues {
                addActivity(.info, "Sincronizando valores de \(changes.count) grupos")
            }
            sendNextQueuedGroupChange()
        } catch {
            let failedPurpose = purpose
            cancelApplySequence()
            addActivity(.error, "No se pudo preparar la secuencia: \(error.localizedDescription)")
            if failedPurpose.keepsConnectionFlowVisible {
                invalidateSession("No se pudo preparar la sincronización inicial de valores")
            }
        }
    }

    private func makeQueuedGroupChanges(
        groups targetGroups: [GodoxGroup],
        forceWrite: Bool,
        restorationGlobalSnapshot: GlobalRadioSnapshot?,
        isExactRestoration: Bool
    ) throws -> [QueuedGroupChange] {
        try targetGroups.map { group -> QueuedGroupChange in
            let state = groupDraft(group)
            let snapshot = state.draft
            if isExactRestoration {
                guard let sessionDeviceID,
                      physicalSafetyState.permitsOnlyExactRestoration(
                          group: group,
                          deviceID: sessionDeviceID,
                          snapshot: snapshot
                      ) else {
                    throw SafeGodoxProtocolError.invalidGroupSnapshot
                }
            }
            let capabilityMinimum = resolvedCapability(for: group)
                .minimumManualDenominator ?? 0
            let frame = try SafeGodoxProtocol.manualGroupFrame(
                group: group,
                snapshot: snapshot,
                minimumManualDenominator: isExactRestoration
                    ? 512
                    : capabilityMinimum,
                underlyingMultiMode: isExactRestoration
                    ? restorationPoints[group]?.multiUnderlyingMode
                    : state.lastKnownActiveMode
            )
            let restorationSnapshot = isExactRestoration
                ? snapshot
                : state.baseline
            let restorationRestoresAfterMulti = isExactRestoration
                ? (restorationPoints[group]?.restoresAfterMulti ?? false)
                : state.baselineRestoresAfterMulti
            let restorationUnderlyingMultiMode: GroupOperatingMode?
            if restorationSnapshot.operatingMode == .multi ||
                restorationSnapshot.operatingMode == .off ||
                restorationRestoresAfterMulti {
                restorationUnderlyingMultiMode = isExactRestoration
                    ? restorationPoints[group]?.multiUnderlyingMode
                    : state.baselineLastKnownActiveMode
            } else {
                restorationUnderlyingMultiMode = nil
            }
            return QueuedGroupChange(
                group: group,
                snapshot: snapshot,
                frame: frame,
                forceWrite: forceWrite,
                restorationSnapshot: restorationSnapshot,
                restorationGlobalSnapshot: restorationGlobalSnapshot,
                restorationUnderlyingMultiMode: restorationUnderlyingMultiMode,
                restorationRestoresAfterMulti: restorationRestoresAfterMulti
            )
        }
    }

    private func prepareForwardJournal(for changes: [QueuedGroupChange]) -> Bool {
        guard let sessionDeviceID, !changes.isEmpty else { return false }
        var points: [GodoxGroup: GroupRestorationPoint] = [:]
        for change in changes {
            guard points[change.group] == nil else { return false }
            points[change.group] = GroupRestorationPoint(
                deviceID: sessionDeviceID,
                snapshot: change.restorationSnapshot,
                globalSnapshot: change.restorationGlobalSnapshot,
                multiUnderlyingMode: change.restorationUnderlyingMultiMode,
                restoresAfterMulti: change.restorationRestoresAfterMulti
            )
        }

        if applySequenceJournalKind == .forward {
            return restorationPoints == points
        }
        guard applySequenceJournalKind == .none,
              restorationPoints.isEmpty,
              physicalSafetyState.begin(points: points) else {
            return false
        }
        guard restorationStore.save(points: points) else {
            _ = physicalSafetyState.cancelUnsentOperation(points: points)
            return false
        }
        applySequenceJournalKind = .forward
        return true
    }

    private func sendNextQueuedGroupChange() {
        guard activeGroupChange == nil,
              controlIntents.isEmpty,
              awaitingRadioResponses.isEmpty else {
            return
        }
        guard !queuedGroupChanges.isEmpty else {
            finishApplySequence()
            return
        }

        let change = queuedGroupChanges.removeFirst()
        guard groups[change.group] != nil,
              canTransmit(
                  change.group,
                  snapshot: change.snapshot,
                  forceWrite: change.forceWrite,
                  permitsJournaledForwardWrite: applySequenceJournalKind == .forward
              ),
              let sessionDeviceID,
              let sessionID else {
            let failedPurpose = applySequencePurpose
            cancelApplySequence()
            if failedPurpose.keepsConnectionFlowVisible {
                invalidateSession(
                    workingConfigurationIssue
                        ?? "La sincronización inicial no pudo preparar el siguiente grupo"
                )
            } else {
                phase = .ready
                addActivity(
                    .warning,
                    failedPurpose.synchronizesValues
                        ? (workingConfigurationIssue
                            ?? "No se pudo sincronizar el siguiente grupo")
                        : physicalApplyBlockReason
                )
            }
            return
        }

        activeGroupChange = change
        phase = applySequencePurpose.keepsConnectionFlowVisible ? .synchronizing : .applying
        updateApplySequenceStatus()
        let intentID = UUID()
        controlIntents.append(.group(
            intentID: intentID,
            deviceID: sessionDeviceID,
            sessionID: sessionID,
            group: change.group,
            snapshot: change.snapshot
        ))
        scheduleControlTimeout(for: change.group)
        addActivity(
            .info,
            "Enviando \(change.group.label) · \(change.snapshot.operatingMode.label) · \(change.snapshot.power.label) · modelado \(change.snapshot.modeling.label) · beep \(change.snapshot.beepEnabled ? "on" : "off")"
        )
        submitControl(change.frame, intentID: intentID)
    }

    private func canTransmit(
        _ group: GodoxGroup,
        snapshot: ManualGroupSnapshot,
        forceWrite: Bool = false,
        permitsJournaledForwardWrite: Bool = false
    ) -> Bool {
        guard recoveryBlockReason == nil,
              let sessionDeviceID, let state = groups[group] else { return false }
        if !restorationPoints.isEmpty {
            if !permitsJournaledForwardWrite {
                return physicalSafetyState.permitsOnlyExactRestoration(
                    group: group,
                    deviceID: sessionDeviceID,
                    snapshot: snapshot
                )
            }
            guard restorationPoints[group]?.deviceID == sessionDeviceID else {
                return false
            }
        }

        guard isValidForTransmission(group, snapshot: snapshot) else { return false }
        return forceWrite || snapshot != state.baseline
    }

    private func isValidForTransmission(
        _ group: GodoxGroup,
        snapshot: ManualGroupSnapshot
    ) -> Bool {
        guard transmitterProfile.supportedGroups.contains(group),
              let configuration = groupConfigurations[group],
              configuration.hasCompleteBaseline else { return false }
        let capability = resolvedCapability(for: group)
        guard let minimumDenominator = capability.minimumManualDenominator else { return false }
        guard ManualPower.isSupported(
            snapshot.power,
            minimumDenominator: minimumDenominator
        ),
              snapshot.modelingState.isValidForWrite,
              snapshot.operatingMode == .autoTTL ||
                snapshot.operatingMode == .manual ||
                snapshot.operatingMode == .multi ||
                snapshot.operatingMode == .off else {
            return false
        }
        if snapshot.operatingMode == .multi {
            let nextMultiGroups = multiFlashGroups.filter { $0 != group } + [group]
            guard supportsMultiFlash(group), !multiPowerScale(for: nextMultiGroups).isEmpty else {
                return false
            }
        }
        if snapshot.beepEnabled && !capability.supportsBeepDraft { return false }
        return true
    }

    private var physicalApplyBlockReason: String {
        guard !pendingGroups.isEmpty else {
            return hasPendingMultiFlashChange
                ? "Revisa la configuración Multi antes de enviarla"
                : "No hay cambios pendientes"
        }
        if !restorationPoints.isEmpty {
            return "Hay una recuperación pendiente; prepara y aplica el ajuste anterior al radio original"
        }
        guard let group = pendingGroups.first(where: {
            !canTransmit($0, snapshot: groupDraft($0).draft)
        }) else {
            return "La secuencia de cambios aún está ocupada"
        }
        let configuration = groupConfiguration(group)
        let capability = resolvedCapability(for: group)
        if !configuration.hasCompleteBaseline {
            return "\(group.label) no tiene un ajuste completo para construir el comando"
        }
        if capability.flashModels.isEmpty {
            return "Asigna al menos un modelo de flash a \(group.label)"
        }
        if let minimum = capability.minimumManualDenominator,
           !ManualPower.isSupported(
               groupDraft(group).draft.power,
               minimumDenominator: minimum
           ) {
            let safeMinimum = capability.powerScale.first?.label ?? "1/\(minimum)"
            return "La potencia elegida para \(group.label) está fuera de su rango; usa \(safeMinimum) o más"
        }
        return "El cambio de \(group.label) no forma un comando válido"
    }

    func bluetoothClient(didReceive event: BluetoothClient.Event) {
        switch event {
        case .stateChanged(let clientState):
            handleClientState(clientState)

        case .discoveryReset:
            devices.removeAll()

        case .discovered(let device):
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                devices[index] = device
            } else {
                devices.append(device)
            }
            devices.sort { $0.rssi > $1.rssi }
            if let preferredSavedRadio = savedRadios.first(where: { saved in
                devices.contains { $0.id == saved.deviceID }
            }), !selectedDeviceWasChosenExplicitly {
                // El orden persistido decide entre varios radios recordados que
                // estén visibles; una elección explícita del usuario siempre gana.
                selectDeviceAutomatically(preferredSavedRadio.deviceID)
            } else if let selectedDevice,
                      savedRadio(for: selectedDevice.id) == nil,
                      !selectedDeviceWasChosenExplicitly,
                      isDeviceNameDuplicated(selectedDevice) {
                // Scanning revealed that a previously unique display name was
                // ambiguous. Require the user to choose using RSSI + UUID.
                selectDeviceAutomatically(nil)
            } else if selectedDeviceID == nil, devices.count == 1 {
                selectDeviceAutomatically(device.id)
            }

        case .log(let level, let message):
            let activityLevel: ActivityLevel
            switch level {
            case .debug, .info:
                activityLevel = .info
            case .warning:
                activityLevel = .warning
            case .error:
                activityLevel = .error
            }
            addActivity(activityLevel, message)

        case .readyForAuthentication:
            beginAuthentication()

        case .notification(.authentication, let data):
            handleAuthenticationResponse(data)

        case .notification(.control, let data):
            handleControlNotification(data)

        case .commandSent(let kind):
            handleCommandSent(kind)

        case .controlWriteStarted:
            handleControlWriteStarted()

        case .controlWriteCompleted:
            handleControlWriteCompleted()

        case .commandFailed(let kind, let error):
            handleCommandFailure(kind, message: error.localizedDescription)

        case .failed(let error):
            authenticationAttempt = nil
            cancelSessionTasks()
            cancelApplySequence()
            sessionIsInvalidating = true
            radioCode = ""
            pendingDisconnectResolution = nil
            phase = .failed(error.localizedDescription)
            addActivity(.error, error.localizedDescription)
        }
    }

    private func handleClientState(_ state: BluetoothClient.State) {
        switch state {
        case .idle:
            if pendingDisconnectResolution != nil {
                completeDisconnectRecovery()
                return
            }
            let scanWasActive = phase == .scanning
            resetTransientSessionState()
            if !scanWasActive {
                radioCode = ""
                phase = .idle
                connectedDeviceName = nil
            }
        case .waitingForBluetooth:
            phase = .scanning
        case .bluetoothUnavailable(let reason):
            pendingDisconnectResolution = nil
            resetTransientSessionState()
            radioCode = ""
            phase = .unavailable(reason)
            connectedDeviceName = nil
        case .scanning:
            phase = .scanning
        case .connecting(let device):
            sessionIsInvalidating = false
            sessionDeviceID = device.id
            if sessionID == nil { sessionID = UUID() }
            phase = .connecting
            connectedDeviceName = device.name
        case .discovering:
            phase = .discovering
        case .subscribing:
            phase = .discovering
        case .ready:
            // GATT está listo, pero la UI aún no habilita controles.
            phase = .authenticating
        case .disconnecting:
            phase = .disconnecting
        case .failed(let message):
            cancelSessionTasks()
            cancelApplySequence()
            phase = .failed(message)
        }
    }

    private func beginAuthentication() {
        connectionSetupDeadline?.cancel()
        connectionSetupDeadline = nil
        guard isRadioCodeValid else {
            invalidateSession("El código local del radio ya no está disponible")
            return
        }

        do {
            let request = try SafeGodoxProtocol.authenticationRequest(
                radioCode: radioCode,
                unixMilliseconds: unixMilliseconds(),
                randomValue: Int.random(in: 1...98)
            )
            let attempt = UUID()
            authenticationAttempt = attempt
            phase = .authenticating
            client.sendAuthentication(request)
            addActivity(.info, "Reto local enviado; contenido oculto")

            authenticationTimeout?.cancel()
            authenticationTimeout = deadlineScheduler.schedule(.authentication) { [weak self] in
                guard let self, self.authenticationAttempt == attempt else { return }
                self.authenticationAttempt = nil
                self.invalidateSession("El radio no respondió al handshake")
            }
        } catch {
            radioCode = ""
            phase = .failed(error.localizedDescription)
            addActivity(.error, error.localizedDescription)
        }
    }

    private func handleAuthenticationResponse(_ data: Data) {
        guard phase == .authenticating else { return }
        guard SafeGodoxProtocol.isValidAuthenticationResponse(
            data,
            unixMilliseconds: unixMilliseconds()
        ) else {
            authenticationAttempt = nil
            authenticationTimeout?.cancel()
            invalidateSession("El radio rechazó la autenticación local")
            return
        }

        authenticationAttempt = nil
        authenticationTimeout?.cancel()
        phase = .synchronizing
        addActivity(.success, "Handshake PWOK validado localmente")

        synchronizationDelay?.cancel()
        synchronizationDelay = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard let self, self.phase == .synchronizing else { return }
            self.synchronizationTimeout?.cancel()
            self.synchronizationTimeout = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
                guard let self, self.phase == .synchronizing else { return }
                self.invalidateSession("Sync no fue entregado a CoreBluetooth")
            }
            self.client.sendSync(SafeGodoxProtocol.synchronizationPayload(now: Date()))
        }
    }

    private func handleCommandSent(_ kind: BluetoothClient.CommandKind) {
        switch kind {
        case .authentication:
            break
        case .sync:
            guard phase == .synchronizing else { return }
            synchronizationDelay?.cancel()
            synchronizationDelay = nil
            synchronizationTimeout?.cancel()
            synchronizationTimeout = nil
            saveAuthenticatedRadioIfRequested()
            radioCode = ""
            if hasCompletedOnboarding && restorationPoints.isEmpty {
                guard workingConfigurationIssue == nil else {
                    invalidateSession(
                        workingConfigurationIssue
                            ?? "La configuración de grupos de trabajo no es válida"
                    )
                    return
                }
                isSynchronizingValues = true
                addActivity(
                    .info,
                    "Sesión preparada · enviando después los valores de Estrobo al radio"
                )
                let expectedSessionID = sessionID
                valueSynchronizationSettleDeadline?.cancel()
                valueSynchronizationSettleDeadline = deadlineScheduler.schedule(
                    .valueSynchronizationSettle
                ) { [weak self] in
                    guard let self,
                          self.phase == .synchronizing,
                          self.sessionID == expectedSessionID else { return }
                    self.valueSynchronizationSettleDeadline = nil
                    self.startValueSynchronization(purpose: .connectionSynchronization)
                }
            } else {
                phase = .ready
                addActivity(
                    restorationPoints.isEmpty ? .success : .warning,
                    restorationPoints.isEmpty
                        ? "Radio autenticado y sincronizado"
                        : "Radio autenticado · recupera el valor seguro antes de sincronizar"
                )
                scheduleAutomaticApplyIfNeeded()
            }
        case .test:
            guard !sessionIsInvalidating, isTestPending else { return }
            testDeliveryDeadline?.cancel()
            testDeliveryDeadline = nil
            isTestPending = false
            addActivity(
                .success,
                client.isSimulation
                    ? "Orden Test simulada · no se envió ningún comando físico"
                    : multiFlashGroups.isEmpty
                        ? "Orden Test entregada a CoreBluetooth · confirma el destello visualmente"
                        : "Orden Test entregada a CoreBluetooth · confirma visualmente la secuencia Multi"
            )
        case .control:
            break
        }
    }

    private func handleControlWriteStarted() {
        guard !controlIntents.isEmpty else {
            addActivity(.warning, "Comenzó un write de control sin intención correlacionada")
            return
        }
        controlWriteHasStarted = true
    }

    private func handleControlNotification(_ data: Data) {
        guard !sessionIsInvalidating else {
            addActivity(.warning, "Notificación de control tardía ignorada durante la desconexión")
            return
        }

        if let response = SafeGodoxProtocol.heartbeatResponse(for: data) {
            guard let sessionDeviceID, let sessionID else {
                addActivity(.warning, "Heartbeat ignorado fuera de una sesión identificada")
                return
            }
            let intentID = UUID()
            controlIntents.append(.heartbeat(
                deviceID: sessionDeviceID,
                sessionID: sessionID,
                intentID: intentID
            ))
            scheduleHeartbeatTimeout(for: intentID)
            submitControl(response, intentID: intentID)
            return
        }

        if SafeGodoxProtocol.isGlobalAcknowledgement(data) {
            lastRadioResponseAt = Date()
            addActivity(
                .info,
                "Eco A0 recibido · el estado global se confirma por el acuse GATT"
            )
            return
        }

        guard SafeGodoxProtocol.isGroupAcknowledgement(data) else {
            addActivity(.warning, "Notificación FEC8 ajena a A0/A1 ignorada")
            return
        }

        lastRadioResponseAt = Date()
        if let group = awaitingRadioResponses.first {
            awaitingRadioResponses.removeFirst()
            radioResponseTimeouts[group]?.cancel()
            radioResponseTimeouts[group] = nil
            guard let snapshot = snapshotsAwaitingRadioResponse.removeValue(forKey: group) else {
                addActivity(.warning, "FEC8 no tenía una instantánea correlacionada para \(group.label)")
                return
            }
            commitRadioResponse(group: group, snapshot: snapshot)
        } else if controlWriteHasStarted,
                  let firstIntent = controlIntents.first,
                  case .group(_, _, _, let group, _) = firstIntent {
            addActivity(
                .warning,
                "FEC8 de \(group.label) llegó antes del acuse GATT y se ignoró por seguridad"
            )
        } else {
            addActivity(.info, "Notificación de control recibida")
        }
    }

    private func handleControlWriteCompleted() {
        guard !controlIntents.isEmpty else {
            addActivity(.warning, "Llegó un acuse sin orden correlacionada")
            return
        }

        let intent = controlIntents.removeFirst()
        controlWriteHasStarted = false
        if sessionIsInvalidating {
            addActivity(.warning, "Acuse tardío ignorado durante la desconexión")
            return
        }
        switch intent {
        case .global(
            _,
            let deviceID,
            let intentSessionID,
            let snapshot,
            _,
            let purpose,
            let followup
        ):
            guard deviceID == sessionDeviceID, intentSessionID == sessionID else {
                addActivity(.warning, "Acuse global de una sesión anterior ignorado")
                return
            }
            controlTimeout?.cancel()
            controlTimeout = nil
            isGlobalControlPending = false
            hasConfirmedGlobalSnapshot = true
            globalRadioSnapshot = snapshot
            globalBeepEnabled = snapshot.beepEnabled
            isGlobalStandbyEnabled = snapshot.standbyEnabled
            if let confirmedMulti = MultiFlashSettings(
                countByte: snapshot.multiCount,
                hertzByte: snapshot.multiHertz,
                powerByte: snapshot.multiPowerByte
            ) {
                multiFlashBaseline = confirmedMulti
            }
            switch purpose {
            case .valueSynchronization:
                addActivity(.success, "Estado global GATT aceptado")
            case .pendingChanges:
                addActivity(.success, "Estado global actualizado")
            case .beep:
                addActivity(.success, "Beep global \(snapshot.beepEnabled ? "activo" : "apagado")")
            case .standby:
                addActivity(
                    .success,
                    snapshot.standbyEnabled
                        ? "Standby general activo"
                        : "Todos los grupos reanudados"
                )
            }

            if let followup {
                startApplySequence(
                    groups: followup.groups,
                    purpose: followup.purpose,
                    forceWrite: followup.forceWrite,
                    restorationGlobalSnapshot: followup.restorationGlobalSnapshot
                )
            } else {
                phase = .ready
                scheduleAutomaticApplyIfNeeded()
            }
        case .heartbeat(let deviceID, let intentSessionID, let intentID):
            heartbeatTimeouts[intentID]?.cancel()
            heartbeatTimeouts[intentID] = nil
            guard deviceID == sessionDeviceID, intentSessionID == sessionID else {
                addActivity(.warning, "Acuse de heartbeat de una sesión anterior ignorado")
                return
            }
            addActivity(.info, "Heartbeat respondido")
            if activeGroupChange == nil {
                if queuedGroupChanges.isEmpty {
                    scheduleAutomaticApplyIfNeeded()
                } else {
                    sendNextQueuedGroupChange()
                }
            }
        case .group(_, let deviceID, let intentSessionID, let group, let snapshot):
            guard deviceID == sessionDeviceID, intentSessionID == sessionID else {
                addActivity(.warning, "Acuse de control de una sesión anterior ignorado")
                return
            }
            controlTimeout?.cancel()
            controlTimeout = nil
            guard var state = groups[group] else { return }
            state.confirmation = .gattAccepted(Date())
            awaitingRadioResponses.append(group)
            snapshotsAwaitingRadioResponse[group] = snapshot
            scheduleRadioResponseTimeout(for: group)
            groups[group] = state
            addActivity(
                .success,
                "Write GATT aceptado para \(group.label) · esperando FEC8"
            )
        }
    }

    private func commitRadioResponse(group: GodoxGroup, snapshot: ManualGroupSnapshot) {
        guard let activeGroupChange,
              activeGroupChange.group == group,
              activeGroupChange.snapshot == snapshot,
              var state = groups[group] else {
            failApplySequence("La respuesta del radio no coincidió con la secuencia activa")
            return
        }
        state.baseline = snapshot
        state.draft = snapshot
        if snapshot.operatingMode == .manual || snapshot.operatingMode == .autoTTL {
            state.lastKnownActiveMode = snapshot.operatingMode
        }
        state.baselineLastKnownActiveMode = state.lastKnownActiveMode
        state.baselineRestoresAfterMulti = state.draftRestoresAfterMulti
        state.confirmation = .radioResponded(Date())
        groups[group] = state
        groupConfigurations[group]?.isEnabledOnRadio = snapshot.isEnabledOnRadio
        if hasCompletedOnboarding, !persistStudioLibrary() {
            addActivity(
                .warning,
                "El radio confirmó \(group.label), pero el valor no pudo guardarse localmente"
            )
        }

        addActivity(.success, "Cambio aplicado y confirmado por el radio para \(group.label)")
        self.activeGroupChange = nil
        applySequenceCompletedCount += 1
        if queuedGroupChanges.isEmpty {
            finishApplySequence()
        } else {
            sendNextQueuedGroupChange()
        }
    }

    private func handleCommandFailure(_ kind: BluetoothClient.CommandKind, message: String) {
        switch kind {
        case .authentication, .sync:
            invalidateSession(message)
        case .test:
            guard isTestPending else { return }
            testDeliveryDeadline?.cancel()
            testDeliveryDeadline = nil
            isTestPending = false
            if !sessionIsInvalidating {
                addActivity(.error, "Test no enviado: \(message)")
            }
        case .control:
            if sessionIsInvalidating { return }
            guard !controlIntents.isEmpty else {
                phase = .failed(message)
                addActivity(.error, message)
                return
            }
            let failedIndex = submittingControlIntentID.flatMap { intentID in
                controlIntents.firstIndex { $0.id == intentID }
            } ?? controlIntents.startIndex
            let failedWasNextInFlight = failedIndex == controlIntents.startIndex
            let intent = controlIntents.remove(at: failedIndex)
            if failedWasNextInFlight {
                controlWriteHasStarted = false
            }
            switch intent {
            case .global(
                _,
                _,
                _,
                let snapshot,
                let previousSnapshot,
                let purpose,
                _
            ):
                controlTimeout?.cancel()
                controlTimeout = nil
                failGlobalControl(
                    snapshot: snapshot,
                    previousSnapshot: previousSnapshot,
                    purpose: purpose,
                    message: message
                )
            case .group(_, _, _, let group, _):
                controlTimeout?.cancel()
                controlTimeout = nil
                cancelApplySequence()
                markFailed(group, message: message)
                invalidateSession(
                    "El resultado del write de \(group.label) es incierto; reconecta el mismo radio y recupera el ajuste anterior"
                )
            case .heartbeat(_, _, let intentID):
                heartbeatTimeouts[intentID]?.cancel()
                heartbeatTimeouts[intentID] = nil
                addActivity(.warning, "No se pudo responder el heartbeat")
                if activeGroupChange == nil {
                    if queuedGroupChanges.isEmpty {
                        scheduleAutomaticApplyIfNeeded()
                    } else {
                        sendNextQueuedGroupChange()
                    }
                }
            }
        }
    }

    private func submitControl(_ payload: Data, intentID: UUID) {
        let previousIntentID = submittingControlIntentID
        submittingControlIntentID = intentID
        client.sendControl(payload)
        submittingControlIntentID = previousIntentID
    }

    private func scheduleHeartbeatTimeout(for intentID: UUID) {
        heartbeatTimeouts[intentID]?.cancel()
        heartbeatTimeouts[intentID] = deadlineScheduler.schedule(.heartbeat) { [weak self] in
            guard let self,
                  self.controlIntents.contains(where: {
                      if case .heartbeat(_, _, let candidateID) = $0 {
                          return candidateID == intentID
                      }
                      return false
                  }) else {
                return
            }
            self.heartbeatTimeouts[intentID] = nil
            self.invalidateSession("El heartbeat del radio no confirmó en 5 segundos")
        }
    }

    private func markFailed(_ group: GodoxGroup, message: String) {
        if var state = groups[group] {
            state.confirmation = .failed(message)
            groups[group] = state
        }
        phase = .ready
        addActivity(.error, "No se aplicó el grupo \(group.label): \(message)")
    }

    private func failGlobalControl(
        snapshot: GlobalRadioSnapshot,
        previousSnapshot: GlobalRadioSnapshot,
        purpose: GlobalControlPurpose,
        message: String
    ) {
        cancelApplySequence()
        isGlobalControlPending = false
        isSynchronizingValues = false
        if case .standby = purpose {
            globalRadioSnapshot = previousSnapshot
            globalBeepEnabled = previousSnapshot.beepEnabled
            isGlobalStandbyEnabled = previousSnapshot.standbyEnabled
        } else {
            // Beep y modelado son estado deseado local: se conservan para que la
            // siguiente sincronización completa vuelva a intentar A0 antes de A1.
            globalRadioSnapshot = snapshot
            globalBeepEnabled = snapshot.beepEnabled
            isGlobalStandbyEnabled = false
        }
        invalidateSession(
            "El estado global no confirmó por GATT (\(message)); reconecta para sincronizarlo de nuevo"
        )
    }

    private func scheduleGlobalControlTimeout(for intentID: UUID) {
        controlTimeout?.cancel()
        controlTimeout = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self,
                  let index = self.controlIntents.firstIndex(where: {
                      if case .global(let candidateID, _, _, _, _, _, _) = $0 {
                          return candidateID == intentID
                      }
                      return false
                  }) else { return }
            guard case .global(
                _,
                _,
                _,
                let snapshot,
                let previousSnapshot,
                let purpose,
                _
            ) = self.controlIntents.remove(at: index) else { return }
            self.controlWriteHasStarted = false
            self.controlTimeout = nil
            self.failGlobalControl(
                snapshot: snapshot,
                previousSnapshot: previousSnapshot,
                purpose: purpose,
                message: "timeout de 5 segundos"
            )
        }
    }

    private func scheduleControlTimeout(for group: GodoxGroup) {
        controlTimeout?.cancel()
        controlTimeout = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self,
                  self.controlIntents.contains(where: {
                      if case .group(_, _, _, let candidate, _) = $0 { return candidate == group }
                      return false
                  }) else { return }
            self.invalidateSession("El write GATT de \(group.label) no confirmó en 5 segundos")
        }
    }

    private func scheduleRadioResponseTimeout(for group: GodoxGroup) {
        radioResponseTimeouts[group]?.cancel()
        radioResponseTimeouts[group] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard let self,
                  let index = self.awaitingRadioResponses.firstIndex(of: group) else { return }
            self.awaitingRadioResponses.remove(at: index)
            self.snapshotsAwaitingRadioResponse[group] = nil
            self.radioResponseTimeouts[group] = nil
            self.markFailed(
                group,
                message: "Write aceptado para \(group.label), sin FEC8; ajuste anterior pendiente de recuperación"
            )
            self.invalidateSession(
                "FEC8 de \(group.label) expiró; reconecta el mismo radio antes de restaurar"
            )
        }
    }

    private func failLocally(_ message: String) {
        addActivity(.warning, message)
    }

    private func saveAuthenticatedRadioIfRequested() {
        guard shouldSaveRadioAfterAuthentication,
              let deviceID = sessionDeviceID,
              let name = connectedDeviceName,
              let radio = SavedRadio(
                  deviceID: deviceID,
                  name: name,
                  radioCode: radioCode
              ) else {
            return
        }
        if savedRadioStore.upsert(radio) {
            if let index = savedRadios.firstIndex(where: { $0.deviceID == radio.deviceID }) {
                savedRadios[index] = radio
            } else {
                savedRadios.append(radio)
            }
            addActivity(.success, "Radio y código guardados localmente en este Mac")
        } else {
            addActivity(.warning, "El radio conectó, pero no se pudo guardar para la próxima vez")
        }
    }

    private func invalidateSession(_ message: String) {
        guard pendingDisconnectResolution == nil else { return }
        addActivity(.error, message)
        beginDisconnectRecovery(.failure(message))
    }

    private func beginDisconnectRecovery(_ resolution: DisconnectResolution) {
        guard pendingDisconnectResolution == nil else { return }
        sessionIsInvalidating = true
        authenticationAttempt = nil
        cancelSessionTasks()
        cancelApplySequence()
        radioCode = ""
        pendingDisconnectResolution = resolution
        phase = .disconnecting
        disconnectRecoveryDeadline = deadlineScheduler.schedule(.disconnectRecovery) { [weak self] in
            guard let self, self.pendingDisconnectResolution != nil else { return }
            self.disconnectRecoveryDeadline = nil
            self.addActivity(.warning, "CoreBluetooth no confirmó la desconexión; se liberó el intento local")
            self.client.forceResetConnection()
            if self.pendingDisconnectResolution != nil {
                self.completeDisconnectRecovery()
            }
        }
        client.disconnect()
    }

    private func completeDisconnectRecovery() {
        guard let resolution = pendingDisconnectResolution else { return }
        disconnectRecoveryDeadline?.cancel()
        disconnectRecoveryDeadline = nil
        pendingDisconnectResolution = nil
        resetTransientSessionState()
        connectedDeviceName = nil
        switch resolution {
        case .idle:
            phase = .idle
        case .failure(let message):
            phase = .failed(message)
        }
    }

    private func cancelSessionTasks() {
        cancelAutomaticApply()
        cancelInteractiveEdits()
        testDeliveryDeadline?.cancel()
        testDeliveryDeadline = nil
        isTestPending = false
        scanDeadline?.cancel()
        scanDeadline = nil
        connectionSetupDeadline?.cancel()
        connectionSetupDeadline = nil
        authenticationTimeout?.cancel()
        authenticationTimeout = nil
        synchronizationDelay?.cancel()
        synchronizationDelay = nil
        synchronizationTimeout?.cancel()
        synchronizationTimeout = nil
        valueSynchronizationSettleDeadline?.cancel()
        valueSynchronizationSettleDeadline = nil
        controlTimeout?.cancel()
        controlTimeout = nil
        heartbeatTimeouts.values.forEach { $0.cancel() }
        heartbeatTimeouts.removeAll()
        radioResponseTimeouts.values.forEach { $0.cancel() }
        radioResponseTimeouts.removeAll()
    }

    private func cancelInteractiveEdits() {
        guard !interactiveEditTokens.isEmpty else { return }
        interactiveEditTokens.removeAll()
        activeInteractiveEditCount = 0
    }

    private func resetTransientSessionState() {
        cancelSessionTasks()
        cancelApplySequence()
        isGlobalControlPending = false
        isGlobalStandbyEnabled = false
        globalRadioSnapshot.standbyEnabled = false
        hasConfirmedGlobalSnapshot = false
        authenticationAttempt = nil
        controlIntents.removeAll()
        awaitingRadioResponses.removeAll()
        snapshotsAwaitingRadioResponse.removeAll()
        submittingControlIntentID = nil
        controlWriteHasStarted = false
        sessionIsInvalidating = false
        shouldSaveRadioAfterAuthentication = false
        sessionDeviceID = nil
        sessionID = nil
    }

    private func addActivity(_ level: ActivityLevel, _ message: String) {
        activity.append(ActivityItem(level: level, message: message))
        activity = Array(activity.suffix(30))
    }

    private var duplicateDeviceNameKeys: Set<String> {
        let counts = Dictionary(grouping: devices) {
            Self.normalizedDeviceName($0.name)
        }.mapValues(\.count)
        return Set(counts.compactMap { key, count in count > 1 ? key : nil })
    }

    private static func normalizedDeviceName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func isCompatible(
        workspace: StudioWorkspace,
        with profile: TransmitterProfile
    ) -> Bool {
        guard workspace.profileID == profile.id,
              workspace.workingGroups.allSatisfy(profile.supportedGroups.contains),
              workspace.visibleGroups.allSatisfy(workspace.workingGroups.contains)
        else {
            return false
        }

        let catalogIDs = Set(profile.flashCatalog.map(\.id))
        var multiMinimumDenominators: [Int] = []
        for group in workspace.workingGroups {
            guard let stored = workspace.groupConfigurations[group],
                  stored.assignedFlashModelIDs.isSubset(of: catalogIDs) else {
                return false
            }
            if !workspace.onboardingCompleted { continue }
            guard !stored.assignedFlashModelIDs.isEmpty else { return false }
            let configuration = GroupConfiguration(
                assignedFlashModelIDs: stored.assignedFlashModelIDs,
                isVisibleLocally: workspace.visibleGroups.contains(group),
                isEnabledOnRadio: stored.snapshot.isEnabledOnRadio,
                hasCompleteBaseline: true
            )
            let capability = ResolvedGroupCapability.resolve(
                configuration: configuration,
                profile: profile
            )
            guard let minimum = capability.minimumManualDenominator,
                  ManualPower.isSupported(
                      stored.snapshot.power,
                      minimumDenominator: minimum
                  ),
                  stored.snapshot.modelingState.isValidForWrite,
                  stored.snapshot.operatingMode == .autoTTL ||
                    stored.snapshot.operatingMode == .manual ||
                    stored.snapshot.operatingMode == .multi ||
                    stored.snapshot.operatingMode == .off,
                  !stored.snapshot.beepEnabled || capability.supportsBeepDraft else {
                return false
            }
            if stored.snapshot.operatingMode == .multi {
                guard profile.supportedMultiGroups.contains(group),
                      !capability.multiPowerScale.isEmpty,
                      let denominator = capability.minimumManualDenominator else {
                    return false
                }
                multiMinimumDenominators.append(denominator)
            }
        }
        let activeModes = workspace.workingGroups.compactMap {
            workspace.groupConfigurations[$0]?.snapshot.operatingMode
        }
        if activeModes.contains(.multi),
           activeModes.contains(where: { $0 == .manual || $0 == .autoTTL }) {
            return false
        }
        if let commonMinimum = multiMinimumDenominators.min() {
            let commonScale = ManualPower.scale(minimumDenominator: commonMinimum).filter {
                $0.decimalValue <= 80 && $0.decimalValue.isMultiple(of: 10)
            }
            guard commonScale.contains(workspace.multiFlashSettings.power) else { return false }
        }
        return true
    }

    private func saveTransmitterProfilePreferences(
        _ state: TransmitterProfilePreferences.State
    ) -> Bool {
        transmitterProfilePreferences.save(
            state,
            builtInProfileIDs: TransmitterProfile.available.map(\.id),
            fallbackDefaultProfileID: TransmitterProfile.observedGDBH.id
        )
    }

    private func currentStudioWorkspace() -> StudioWorkspace? {
        var storedGroups: [GodoxGroup: StudioWorkspaceGroup] = [:]
        for group in workingGroups {
            guard let state = groups[group],
                  let configuration = groupConfigurations[group],
                  let stored = StudioWorkspaceGroup(
                      snapshot: state.draft,
                      assignedFlashModelIDs: configuration.assignedFlashModelIDs,
                      lastKnownActiveMode: state.lastKnownActiveMode,
                      restoresAfterMulti: state.draftRestoresAfterMulti
                  ) else {
                return nil
            }
            storedGroups[group] = stored
        }
        let locallyVisible = workingGroups.filter(visibleGroups.contains)
        return StudioWorkspace(
            onboardingCompleted: hasCompletedOnboarding,
            profileID: transmitterProfile.id,
            workingGroups: workingGroups,
            visibleGroups: locallyVisible,
            groupConfigurations: storedGroups,
            multiFlashSettings: multiFlashDraft
        )
    }

    @discardableResult
    private func persistStudioLibrary() -> Bool {
        guard let workspace = currentStudioWorkspace(),
              let library = StudioLibrary(workspace: workspace, presets: presets) else {
            return false
        }
        return studioLibraryStore.save(library)
    }

    private func canonicalPresetName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func unixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }
}
