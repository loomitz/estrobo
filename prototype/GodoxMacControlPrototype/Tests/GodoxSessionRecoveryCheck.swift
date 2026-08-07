import Foundation

@MainActor
private final class ManualSessionDeadlineScheduler: SessionDeadlineScheduling {
    private struct Entry {
        let token: SessionDeadlineToken
        let action: @MainActor () -> Void
    }

    private var entries: [SessionDeadlineKind: [Entry]] = [:]

    func schedule(
        _ kind: SessionDeadlineKind,
        action: @escaping @MainActor () -> Void
    ) -> SessionDeadlineToken {
        let token = SessionDeadlineToken()
        entries[kind, default: []].append(Entry(token: token, action: action))
        return token
    }

    func activeCount(_ kind: SessionDeadlineKind) -> Int {
        entries[kind, default: []].filter { !$0.token.isCancelled }.count
    }

    /// Consume exactamente el deadline más antiguo. A diferencia de `fire`, no
    /// salta entradas canceladas: permite demostrar que un debounce anterior no
    /// ejecutaría su acción antes del nuevo plazo.
    @discardableResult
    func fireNext(_ kind: SessionDeadlineKind) -> Bool {
        guard var pending = entries[kind], !pending.isEmpty else { return false }
        let entry = pending.removeFirst()
        entries[kind] = pending
        guard !entry.token.isCancelled else { return false }
        entry.action()
        return true
    }

    func fire(_ kind: SessionDeadlineKind) {
        guard var pending = entries[kind] else {
            preconditionFailure("No existe un deadline \(kind) pendiente")
        }
        while !pending.isEmpty {
            let entry = pending.removeFirst()
            entries[kind] = pending
            if !entry.token.isCancelled {
                entry.action()
                return
            }
        }
        preconditionFailure("Todos los deadlines \(kind) estaban cancelados")
    }
}

@MainActor
private final class FakeGodoxSessionTransport: GodoxSessionTransport {
    weak var delegate: (any BluetoothClientDelegate)?

    private(set) var scanCount = 0
    private(set) var stopScanCount = 0
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var forceResetCount = 0
    private(set) var authenticationWriteCount = 0
    private(set) var syncWriteCount = 0
    private(set) var testWriteCount = 0
    private(set) var testPayloads: [Data] = []
    private(set) var controlWriteCount = 0
    private(set) var controlPayloads: [Data] = []
    var onSendTest: ((Data) -> Void)?
    var onSendControl: ((Data) -> Void)?

    func startScanning() {
        scanCount += 1
        emit(.stateChanged(.scanning))
    }

    func stopScanning() {
        stopScanCount += 1
        emit(.stateChanged(.idle))
    }

    func connect(to device: BluetoothClient.Device) {
        connectCount += 1
        emit(.stateChanged(.connecting(device)))
    }

    func disconnect() {
        disconnectCount += 1
        // Reproduce el callback perdido: comienza a desconectar pero nunca
        // entrega `.idle` por sí mismo.
        emit(.stateChanged(.disconnecting(testDevice)))
    }

    func forceResetConnection() {
        forceResetCount += 1
        emit(.discoveryReset)
        emit(.stateChanged(.idle))
    }

    func sendAuthentication(_ payload: Data) {
        // Deliberadamente no se conserva ni inspecciona el payload.
        authenticationWriteCount += 1
        emit(.commandSent(.authentication))
    }

    func sendSync(_ payload: Data) {
        syncWriteCount += 1
        emit(.commandSent(.sync))
    }

    func sendTest(_ payload: Data) {
        testWriteCount += 1
        testPayloads.append(payload)
        onSendTest?(payload)
    }

    func sendControl(_ payload: Data) {
        onSendControl?(payload)
        controlWriteCount += 1
        controlPayloads.append(payload)
    }

    func emit(_ event: BluetoothClient.Event) {
        delegate?.bluetoothClient(didReceive: event)
    }
}

private let testDevice = BluetoothClient.Device(
    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
    name: "GDBH-TEST",
    rssi: -42
)

private let otherTestDevice = BluetoothClient.Device(
    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
    name: "Ami-OTHER",
    rssi: -20
)

private final class MemorySavedRadioStorage {
    var object: Any?
    var acceptsWrites = true
    var acceptsRemoval = true

    func makeStore() -> SavedRadioStore {
        SavedRadioStore(
            storageKey: "session-recovery-test-saved-radio",
            readObject: { [weak self] _ in self?.object },
            writeData: { [weak self] data, _ in
                guard let self, self.acceptsWrites else { return false }
                self.object = data
                return true
            },
            removeValue: { [weak self] _ in
                guard let self, self.acceptsRemoval else { return false }
                self.object = nil
                return true
            }
        )
    }
}

private final class MemoryRestorationStorage {
    var object: Any?
    var acceptsWrites = true

    func makeStore() -> PendingRestorationStore {
        PendingRestorationStore(
            storageKey: "session-recovery-test-restoration",
            readObject: { [weak self] _ in self?.object },
            writeData: { [weak self] data, _ in
                guard let self, self.acceptsWrites else { return false }
                self.object = data
                return true
            },
            removeValue: { [weak self] _ in
                self?.object = nil
                return self != nil
            }
        )
    }
}

private final class MemoryChangeDeliveryStorage {
    var value: String?

    func makePreferences() -> ChangeDeliveryPreferences {
        ChangeDeliveryPreferences(
            storageKey: "session-recovery-test-change-delivery",
            readString: { [weak self] _ in self?.value },
            writeString: { [weak self] value, _ in
                self?.value = value
            }
        )
    }
}

private final class MemoryStudioLibraryStorage {
    var object: Any?
    var acceptsWrites = true

    func makeStore() -> StudioLibraryStore {
        StudioLibraryStore(
            storageKey: "session-recovery-memory-studio-library",
            readObject: { [weak self] _ in self?.object },
            writeData: { [weak self] data, _ in
                guard let self, self.acceptsWrites else { return false }
                self.object = data
                return true
            }
        )
    }
}

private final class MemoryTransmitterProfilePreferencesStorage {
    var object: Any?
    var acceptsWrites = true

    func makePreferences() -> TransmitterProfilePreferences {
        TransmitterProfilePreferences(
            storageKey: "session-recovery-transmitter-profiles",
            readObject: { [weak self] _ in self?.object },
            writeData: { [weak self] data, _ in
                guard let self, self.acceptsWrites else { return false }
                self.object = data
                return true
            }
        )
    }
}

@main
@MainActor
enum GodoxSessionRecoveryCheck {
    static func main() async {
        checkControlsRequireReadySession()
        checkSavedRadioReconnectFlow()
        checkDuplicateRadioNamesRequireExplicitSelection()
        checkSilentConnectionRecovers()
        checkRejectedPasswordRecoversWithoutCallback()
        checkSilentAuthenticationRecoversWithoutCallback()
        checkDiscoverySilenceRecovers()
        checkScanCanExpireAndBeCancelled()
        checkConnectionAndManualValueSynchronization()
        checkNewWorkingGroupsCanBeActivated()
        checkInitialSynchronizationRequiresRestorationJournal()
        checkPresetLoadAndSynchronization()
        checkLocalPresetLoadNeverSchedulesAutomaticDelivery()
        checkPresetCompatibilityFollowsCurrentModels()
        checkWorkspaceAndPresetsSurviveControllerRestart()
        checkTransmitterProfileAvailabilityAndDefault()
        checkWorkingGroupsKeepAtLeastOneFlashModel()
        checkWorkspaceReconfigurationCanBeCancelled()
        checkWorkspaceReconfigurationPreservesVisibility()
        checkWorkspaceGroupsCanBeReconfiguredWhileReady()
        checkTestRequiresReadyAndNoPendingChanges()
        checkTestDeliverySuccessFailureAndTimeout()
        checkManualAndAutoTTLModeTransitions()
        checkMultiFlashGlobalAndGroupSequencing()
        checkMultiFlashUnderlyingModeAndGlobalSelection()
        checkMultiFlashGlobalExitForcesManualScene()
        checkMultiFlashBatchRecoveryRestoresWholeScene()
        checkMultiFlashUnsupportedGroups()
        checkVerifiedMultiFlashCountLimit()
        checkMultiFlashModelChangeKeepsSafePendingDraft()
        checkStoredMultiFlashLimitMigrationPersists()
        checkBeepIncludesGlobalA0Gate()
        checkGlobalStandbyPreservesGroups()
        checkGlobalControlsDoNotApplyPendingGroupChanges()
        checkPresetPreservesGlobalBeep()
        checkAutomaticGlobalPowerAdjustmentIsAtomicAndSerialized()
        checkGlobalPowerStopsAllGroupsAtSharedBoundary()
        checkGlobalPowerCanReachBoundaryBeforeBlocking()
        checkHistoricalOffScalePowerBlocksGlobalAdjustment()
        checkAnchoredGlobalPowerUsesCommonBoundsAndNoHysteresis()
        checkGlobalPowerConstraintReportsLimitingGroups()
        checkAnchoredGlobalPowerUsesCapturedGroups()
        checkAnchoredGlobalPowerAdjustmentIsAtomic()
        checkAnchoredGlobalPowerAdjustmentHonorsSafetyGates()
        checkAutomaticDebounceCancelsAndRearms()
        checkManualModeCancelsAutomaticSend()
        checkAutomaticSerializesTwoGroups()
        checkSynchronousHeartbeatFailuresPreserveAutomaticBatch()
        checkHeartbeatTimeoutStopsAutomaticBatch()
        checkControlFailureStopsAutomaticBatch()
        checkLateControlNotificationsAreIgnoredDuringInvalidation()
        await checkFEC8TimeoutStopsAutomaticBatch()
        checkRestorationPersistenceFailurePreventsAutomaticBatch()
        checkAutomaticSchedulingResumesAfterRestoration()
        checkReadySessionAppliesNormalChanges()
        checkUncertainWriteRequiresPersistedRecovery()
        print("Conexión, debounce, cola de cambios y recuperación incierta verificadas sin Bluetooth")
    }

    private static func checkManualAndAutoTTLModeTransitions() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(fixture)

        let originalPower = fixture.controller.groupDraft(.c).draft.power
        expect(fixture.controller.canChangeOperatingMode(.c))

        fixture.controller.setDraftOperatingMode(.c, mode: .autoTTL)
        var state = fixture.controller.groupDraft(.c)
        expect(state.draft.operatingMode == .autoTTL)
        expect(state.draft.power == originalPower, "Entrar a Auto debe conservar la potencia M")
        expect(state.draft.compensationByte == 0, "Auto debe comenzar con compensación TTL neutra")
        expect(state.pendingFields == [.mode])
        expect(!fixture.controller.canEdit(.c), "La potencia manual debe bloquearse mientras Auto está activo")

        guard let otherPower = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta una potencia alternativa para probar Auto")
        }
        fixture.controller.setDraftPower(.c, power: otherPower)
        expect(fixture.controller.groupDraft(.c).draft.power == originalPower)

        fixture.controller.applyPendingChanges()
        guard let autoFrame = fixture.transport.controlPayloads.last,
              let autoSnapshot = SafeGodoxProtocol.groupSnapshot(from: autoFrame)?.1 else {
            preconditionFailure("Auto no generó una trama A1 válida")
        }
        expect(autoSnapshot.operatingMode == .autoTTL)
        expect(
            autoSnapshot.power == ManualPower.value(decimal: 50),
            "Auto debe usar el byte de potencia fijo 0x32 de Godox Flash"
        )
        expect(autoSnapshot.compensationByte == 0)
        expect(fixture.controller.groupDraft(.c).draft.power == originalPower)
        expect(fixture.transport.testWriteCount == 0, "Cambiar modo nunca debe disparar Test")
        confirmCurrentGroup(fixture)

        fixture.controller.setDraftRadioEnabled(.c, enabled: false)
        state = fixture.controller.groupDraft(.c)
        expect(state.draft.operatingMode == .off)
        expect(state.lastKnownActiveMode == .autoTTL)
        fixture.controller.applyPendingChanges()
        confirmCurrentGroup(fixture)

        fixture.controller.setDraftRadioEnabled(.c, enabled: true)
        state = fixture.controller.groupDraft(.c)
        expect(state.draft.operatingMode == .autoTTL, "Reactivar debe restaurar Auto, no forzar M")
        expect(state.draft.power == originalPower)
        fixture.controller.applyPendingChanges()
        confirmCurrentGroup(fixture)

        fixture.controller.setDraftOperatingMode(.c, mode: .manual)
        state = fixture.controller.groupDraft(.c)
        expect(state.draft.operatingMode == .manual)
        expect(state.draft.power == originalPower, "Volver a M debe recuperar la potencia guardada")
        fixture.controller.applyPendingChanges()
        guard let manualFrame = fixture.transport.controlPayloads.last,
              let manualSnapshot = SafeGodoxProtocol.groupSnapshot(from: manualFrame)?.1 else {
            preconditionFailure("Volver a M no generó una trama A1 válida")
        }
        expect(manualSnapshot.operatingMode == .manual)
        expect(manualSnapshot.power == originalPower)
        expect(fixture.transport.testWriteCount == 0)
        confirmCurrentGroup(fixture)
    }

    private static func checkMultiFlashGlobalAndGroupSequencing() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        completeDefaultWorkspace(fixture)
        prepareConfiguredReadyConnection(fixture)

        guard let power = ManualPower.value(decimal: 40),
              let configuredMulti = MultiFlashSettings(
                  power: power,
                  count: 7,
                  hertz: 11
              ) else {
            preconditionFailure("Falta una configuración Multi válida para la regresión")
        }

        expect(fixture.controller.supportsMultiFlash(.c))
        expect(fixture.controller.availableOperatingModes(for: .c).contains(.multi))
        expect(fixture.controller.groupDraft(.c).draft.operatingMode == .manual)

        expect(!fixture.controller.canSetMultiFlashParticipation(.c, enabled: true))
        fixture.controller.setMultiFlashParticipation(.c, enabled: true)
        expect(fixture.controller.multiFlashGroups.isEmpty)
        fixture.controller.setDraftOperatingMode(.c, mode: .multi)
        expect(
            fixture.controller.multiFlashGroups.isEmpty,
            "Ni participación ni modo de grupo deben iniciar Multi"
        )
        expect(fixture.controller.canSetGlobalMultiFlashEnabled(true))
        fixture.controller.setGlobalMultiFlashEnabled(true)
        fixture.controller.setMultiFlashPower(configuredMulti.power)
        fixture.controller.setMultiFlashCount(configuredMulti.count)
        fixture.controller.setMultiFlashHertz(configuredMulti.hertz)

        expect(fixture.controller.groupDraft(.c).draft.operatingMode == .multi)
        expect(
            fixture.controller.groupDraft(.b).draft.operatingMode == .multi,
            "Entrar a MULTI debe incluir todos los grupos activos compatibles"
        )
        expect(fixture.controller.groupDraft(.b).lastKnownActiveMode == .manual)
        expect(fixture.controller.groupDraft(.b).draftRestoresAfterMulti)
        expect(fixture.controller.groupDraft(.c).draftRestoresAfterMulti)
        expect(fixture.controller.multiFlashGroups == [.b, .c])
        expect(fixture.controller.multiFlashDraft == configuredMulti)
        expect(fixture.controller.hasPendingMultiFlashChange)

        let multiStart = fixture.transport.controlWriteCount
        fixture.controller.applyPendingChanges()
        expect(
            fixture.transport.controlWriteCount == multiStart + 1,
            "Entrar a MULTI debe esperar el A0 antes de entregar A1"
        )
        guard let multiGlobal = SafeGodoxProtocol.globalSnapshot(
            from: fixture.transport.controlPayloads[multiStart]
        ) else {
            preconditionFailure("Entrar a MULTI no comenzó con una trama A0 válida")
        }
        let expectedMultiGlobal = GlobalRadioSnapshot(
            beepEnabled: false,
            modelingLightEnabled: true,
            relativeAdjustmentByte: 0,
            multiEnabled: true,
            multiCount: configuredMulti.countByte,
            multiHertz: configuredMulti.hertzByte,
            multiPowerByte: configuredMulti.powerByte,
            standbyEnabled: false,
            adjustmentCounter: 0
        )
        expect(
            multiGlobal == expectedMultiGlobal,
            "A0 debe conservar los campos globales y codificar exactamente la ráfaga MULTI"
        )
        expect(fixture.controller.isGlobalControlPending)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)

        expect(fixture.controller.multiFlashBaseline == configuredMulti)
        expect(!fixture.controller.hasPendingMultiFlashChange)
        expect(
            fixture.transport.controlWriteCount == multiStart + 2,
            "El A1 de MULTI sólo debe comenzar después del acuse GATT de A0"
        )
        let workingScene: [(GodoxGroup, GroupOperatingMode)] = [
            (.b, .multi), (.c, .multi),
        ]
        for (index, expected) in workingScene.enumerated() {
            guard let written = SafeGodoxProtocol.groupSnapshot(
                from: fixture.transport.controlPayloads[multiStart + 1 + index]
            ) else {
                preconditionFailure("La escena Multi del workspace no produjo A1 válido")
            }
            expect(written.0 == expected.0)
            expect(written.1.operatingMode == expected.1)
            fixture.transport.emit(.controlWriteStarted)
            fixture.transport.emit(.controlWriteCompleted)
            if expected.0 == .b {
                expect(
                    fixture.controller.groupDraft(.b).baseline.operatingMode == .manual,
                    "El acuse GATT de A1 no debe confirmar Multi sin FEC8"
                )
            }
            fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        }
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.groupDraft(.b).baseline.operatingMode == .multi)
        expect(fixture.controller.groupDraft(.c).baseline.operatingMode == .multi)
        expect(fixture.controller.pendingCount == 0)

        let hertzOnly = 19
        fixture.controller.setMultiFlashHertz(hertzOnly)
        expect(fixture.controller.groupDraft(.c).pendingFields.isEmpty)
        expect(fixture.controller.hasPendingMultiFlashChange)

        let hertzStart = fixture.transport.controlWriteCount
        fixture.controller.applyPendingChanges()
        expect(
            fixture.transport.controlWriteCount == hertzStart + 1,
            "Cambiar sólo Hz debe producir una única trama A0"
        )
        guard let hertzGlobal = SafeGodoxProtocol.globalSnapshot(
            from: fixture.transport.controlPayloads[hertzStart]
        ) else {
            preconditionFailure("El cambio de Hz no produjo A0")
        }
        expect(hertzGlobal.multiEnabled)
        expect(hertzGlobal.multiCount == configuredMulti.countByte)
        expect(hertzGlobal.multiHertz == UInt8(hertzOnly))
        expect(hertzGlobal.multiPowerByte == configuredMulti.powerByte)
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(fixture.transport.controlWriteCount == hertzStart + 1)
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.multiFlashBaseline.hertz == hertzOnly)
        expect(fixture.controller.pendingCount == 0)

        fixture.controller.setMultiFlashParticipation(.b, enabled: false)
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .off)
        expect(fixture.controller.groupDraft(.b).draftRestoresAfterMulti)
        expect(fixture.controller.groupDraft(.c).draft.operatingMode == .multi)

        expect(!fixture.controller.canSetMultiFlashParticipation(.c, enabled: false))
        fixture.controller.setMultiFlashParticipation(.c, enabled: false)
        expect(fixture.controller.groupDraft(.c).draft.operatingMode == .multi)
        expect(fixture.controller.multiFlashGroups == [.c])
        expect(fixture.controller.canSetGlobalMultiFlashEnabled(false))
        fixture.controller.setGlobalMultiFlashEnabled(false)
        var state = fixture.controller.groupDraft(.c)
        expect(
            state.draft.operatingMode == .manual,
            "El botón global debe cerrar Multi con el grupo en Manual"
        )
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .manual)
        expect(!fixture.controller.groupDraft(.b).draftRestoresAfterMulti)
        expect(!state.draftRestoresAfterMulti)
        expect(state.lastKnownActiveMode == .manual)
        expect(fixture.controller.multiFlashGroups.isEmpty)
        expect(fixture.controller.groupConfiguration(.b).isEnabledOnRadio)
        expect(fixture.controller.groupConfiguration(.c).isEnabledOnRadio)

        let offStart = fixture.transport.controlWriteCount
        fixture.controller.applyPendingChanges()
        expect(fixture.transport.controlWriteCount == offStart + 1)
        guard let disabledGlobal = SafeGodoxProtocol.globalSnapshot(
            from: fixture.transport.controlPayloads[offStart]
        ) else {
            preconditionFailure("Salir del último grupo MULTI no produjo A0")
        }
        expect(!disabledGlobal.multiEnabled, "El último grupo fuera de MULTI debe apagar el gate A0")
        expect(disabledGlobal.multiCount == configuredMulti.countByte)
        expect(disabledGlobal.multiHertz == UInt8(hertzOnly))
        expect(disabledGlobal.multiPowerByte == configuredMulti.powerByte)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(fixture.transport.controlWriteCount == offStart + 2)
        let restoredWorkingScene: [(GodoxGroup, GroupOperatingMode)] = [
            (.b, .manual), (.c, .manual),
        ]
        for (index, expected) in restoredWorkingScene.enumerated() {
            guard let restoredGroup = SafeGodoxProtocol.groupSnapshot(
                from: fixture.transport.controlPayloads[offStart + 1 + index]
            ) else {
                preconditionFailure("Salir de Multi no restauró el workspace")
            }
            expect(restoredGroup.0 == expected.0)
            expect(restoredGroup.1.operatingMode == expected.1)
            confirmCurrentGroup(fixture)
        }
        state = fixture.controller.groupDraft(.c)
        expect(state.baseline.operatingMode == .manual)
        expect(state.lastKnownActiveMode == .manual)

        guard let belowGroupRange = ManualPower.value(decimal: 10),
              let safeGroupMinimum = ManualPower.value(decimal: 20) else {
            preconditionFailure("Faltan potencias Multi para probar la normalización")
        }
        fixture.controller.setMultiFlashPower(belowGroupRange)
        let disabledSettingsStart = fixture.transport.controlWriteCount
        fixture.controller.applyPendingChanges()
        expect(fixture.transport.controlWriteCount == disabledSettingsStart + 1)
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(fixture.controller.multiFlashBaseline.power == belowGroupRange)

        fixture.controller.setGlobalMultiFlashEnabled(true)
        state = fixture.controller.groupDraft(.c)
        expect(state.draft.operatingMode == .multi)
        expect(state.lastKnownActiveMode == .manual)
        expect(fixture.controller.multiFlashGroups == [.b, .c])
        expect(
            fixture.controller.multiFlashDraft.power == safeGroupMinimum,
            "Reactivar MULTI debe normalizar la potencia global al rango común"
        )

        let restoreStart = fixture.transport.controlWriteCount
        fixture.controller.applyPendingChanges()
        guard let restoredGlobal = SafeGodoxProtocol.globalSnapshot(
            from: fixture.transport.controlPayloads[restoreStart]
        ) else {
            preconditionFailure("Restaurar MULTI no volvió a habilitar A0")
        }
        expect(restoredGlobal.multiEnabled)
        expect(restoredGlobal.multiPowerByte == safeGroupMinimum.encodedByte)
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        for (index, expected) in workingScene.enumerated() {
            guard let restoredGroup = SafeGodoxProtocol.groupSnapshot(
                from: fixture.transport.controlPayloads[restoreStart + 1 + index]
            ) else {
                preconditionFailure("Restaurar MULTI no produjo la escena del workspace")
            }
            expect(restoredGroup.0 == expected.0)
            expect(restoredGroup.1.operatingMode == expected.1)
            confirmCurrentGroup(fixture)
        }
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.groupDraft(.b).baseline.operatingMode == .multi)
        expect(fixture.controller.groupDraft(.c).baseline.operatingMode == .multi)
        expect(fixture.controller.pendingCount == 0)

        fixture.controller.setMultiFlashParticipation(.b, enabled: false)
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .off)
        expect(fixture.controller.groupDraft(.b).draftRestoresAfterMulti)
        expect(fixture.controller.multiFlashGroups == [.c])

        fixture.controller.beginWorkspaceConfiguration()
        expect(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b],
            assignedFlashModelIDs: [.b: ["ad600pro-ii"]]
        ))
        expect(fixture.controller.multiFlashGroups.isEmpty)
        expect(
            fixture.controller.hasPendingMultiFlashChange,
            "Quitar el último grupo MULTI debe dejar pendiente el gate global A0"
        )
        expect(fixture.controller.pendingGroups == [.b])
        expect(fixture.controller.pendingCount == 2)
        expect(
            fixture.controller.canDiscardPendingChanges,
            "Restaurar un grupo retenido sí debe producir un borrador descartable"
        )

        let removedStart = fixture.transport.controlWriteCount
        fixture.controller.applyPendingChanges()
        expect(fixture.transport.controlWriteCount == removedStart + 1)
        guard let removedGlobal = SafeGodoxProtocol.globalSnapshot(
            from: fixture.transport.controlPayloads[removedStart]
        ) else {
            preconditionFailure("Quitar el último grupo MULTI no produjo A0")
        }
        expect(!removedGlobal.multiEnabled)
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        guard let restoredRetainedGroup = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[removedStart + 1]
        ) else {
            preconditionFailure("Quitar el último grupo Multi no restauró el grupo retenido")
        }
        expect(restoredRetainedGroup.0 == .b)
        expect(restoredRetainedGroup.1.operatingMode == .manual)
        confirmCurrentGroup(fixture)
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.pendingCount == 0)
    }

    private static func checkMultiFlashUnderlyingModeAndGlobalSelection() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        completeDefaultWorkspace(fixture)
        prepareConfiguredReadyConnection(fixture)

        fixture.controller.setDraftRadioEnabled(.b, enabled: false)
        fixture.controller.setDraftOperatingMode(.c, mode: .autoTTL)
        fixture.controller.applyPendingChanges()
        confirmCurrentGroup(fixture)
        confirmCurrentGroup(fixture)
        expect(fixture.controller.groupDraft(.b).baseline.operatingMode == .off)
        expect(fixture.controller.groupDraft(.c).baseline.operatingMode == .autoTTL)

        let enterStart = fixture.transport.controlWriteCount
        expect(!fixture.controller.canSetMultiFlashParticipation(.c, enabled: true))
        expect(fixture.controller.canSetGlobalMultiFlashEnabled(true))
        fixture.controller.setGlobalMultiFlashEnabled(true)
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .off)
        expect(!fixture.controller.groupConfiguration(.b).isEnabledOnRadio)
        expect(fixture.controller.groupDraft(.c).lastKnownActiveMode == .autoTTL)
        fixture.controller.applyPendingChanges()
        expect(
            SafeGodoxProtocol.globalSnapshot(
                from: fixture.transport.controlPayloads[enterStart]
            )?.multiEnabled == true
        )
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        let ttlOriginFrame = fixture.transport.controlPayloads[enterStart + 1]
        expect(ttlOriginFrame[4] == GroupOperatingMode.multi.rawValue)
        expect(
            ttlOriginFrame[5] == 0x32,
            "MULTI originado en TTL debe conservar el sentinel A1 0x32"
        )
        confirmCurrentGroup(fixture)

        expect(fixture.controller.canSetMultiFlashParticipation(.b, enabled: true))
        fixture.controller.setMultiFlashParticipation(.b, enabled: true)
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .multi)
        expect(
            !fixture.controller.groupDraft(.b).draftRestoresAfterMulti,
            "Un grupo originalmente Off debe volver a Off al cerrar Multi"
        )
        expect(
            fixture.controller.workingGroups.allSatisfy {
                let mode = fixture.controller.groupDraft($0).draft.operatingMode
                return mode == .multi || mode == .off
            },
            "Con A0 Multi activo sólo deben existir grupos Multi/Off"
        )
        fixture.controller.applyPendingChanges()
        confirmCurrentGroup(fixture)
        expect(Set(fixture.controller.multiFlashGroups) == Set([.b, .c]))

        expect(fixture.controller.canSetMultiFlashParticipation(.b, enabled: false))
        fixture.controller.setMultiFlashParticipation(.b, enabled: false)
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .off)
        expect(fixture.controller.groupDraft(.c).draft.operatingMode == .multi)
        expect(fixture.controller.multiFlashGroups == [.c])

        fixture.controller.setMultiFlashParticipation(.b, enabled: true)
        expect(Set(fixture.controller.multiFlashGroups) == Set([.b, .c]))

        fixture.controller.setMultiFlashParticipation(.b, enabled: false)
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .off)
        expect(fixture.controller.groupDraft(.c).draft.operatingMode == .multi)

        expect(!fixture.controller.canSetMultiFlashParticipation(.c, enabled: false))
        fixture.controller.setMultiFlashParticipation(.c, enabled: false)
        expect(fixture.controller.groupDraft(.c).draft.operatingMode == .multi)
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .off)
        expect(fixture.controller.multiFlashGroups == [.c])

        fixture.controller.setDraftOperatingMode(.c, mode: .manual)
        expect(
            fixture.controller.groupDraft(.c).draft.operatingMode == .multi,
            "El selector de grupo tampoco debe cerrar Multi"
        )
        fixture.controller.setGlobalMultiFlashEnabled(false)
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .manual)
        expect(fixture.controller.groupDraft(.c).draft.operatingMode == .manual)
        expect(fixture.controller.groupDraft(.b).draft.compensationByte == 0)
        expect(fixture.controller.groupDraft(.c).draft.compensationByte == 0)
        expect(!fixture.controller.groupDraft(.c).draftRestoresAfterMulti)
        expect(!fixture.controller.groupDraft(.b).draftRestoresAfterMulti)
        expect(fixture.controller.groupConfiguration(.b).isEnabledOnRadio)
        expect(fixture.controller.groupConfiguration(.c).isEnabledOnRadio)
        expect(fixture.controller.multiFlashGroups.isEmpty)
    }

    private static func checkMultiFlashGlobalExitForcesManualScene() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        completeDefaultWorkspace(fixture)
        prepareConfiguredReadyConnection(fixture)

        fixture.controller.setDraftOperatingMode(.c, mode: .autoTTL)
        fixture.controller.applyPendingChanges()
        confirmCurrentGroup(fixture)
        expect(fixture.controller.groupDraft(.c).baseline.operatingMode == .autoTTL)
        let retainedBPower = fixture.controller.groupDraft(.b).draft.power
        let retainedCPower = fixture.controller.groupDraft(.c).draft.power

        fixture.controller.setGlobalMultiFlashEnabled(true)
        fixture.controller.applyPendingChanges()
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        confirmCurrentGroup(fixture)
        confirmCurrentGroup(fixture)
        expect(fixture.controller.groupDraft(.b).baseline.operatingMode == .multi)
        expect(fixture.controller.groupDraft(.c).baseline.operatingMode == .multi)

        fixture.controller.setMultiFlashParticipation(.b, enabled: false)
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .off)
        expect(fixture.controller.groupDraft(.b).draftRestoresAfterMulti)
        expect(fixture.controller.groupDraft(.c).draft.operatingMode == .multi)

        fixture.controller.setGlobalMultiFlashEnabled(false)
        expect(
            fixture.controller.groupDraft(.b).draft.operatingMode == .manual,
            "Cerrar Multi global debe activar en Manual hasta un participante retirado"
        )
        expect(
            fixture.controller.groupDraft(.c).draft.operatingMode == .manual,
            "Cerrar Multi global debe convertir también un origen TTL a Manual"
        )
        expect(fixture.controller.groupDraft(.b).draft.power == retainedBPower)
        expect(fixture.controller.groupDraft(.c).draft.power == retainedCPower)
        expect(fixture.controller.groupDraft(.b).draft.compensationByte == 0)
        expect(fixture.controller.groupDraft(.c).draft.compensationByte == 0)
        expect(fixture.controller.multiFlashGroups.isEmpty)
        expect(!fixture.controller.groupDraft(.b).draftRestoresAfterMulti)
        expect(!fixture.controller.groupDraft(.c).draftRestoresAfterMulti)
        expect(fixture.controller.groupConfiguration(.b).isEnabledOnRadio)
        expect(fixture.controller.groupConfiguration(.c).isEnabledOnRadio)
    }

    private static func checkMultiFlashBatchRecoveryRestoresWholeScene() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let restorationMemory = MemoryRestorationStorage()
        let restorationStore = restorationMemory.makeStore()
        let studioMemory = MemoryStudioLibraryStorage()
        let fixture = makeFixture(
            changeDeliveryPreferences: preferences,
            restorationStore: restorationStore,
            studioLibraryStore: studioMemory.makeStore()
        )
        completeDefaultWorkspace(fixture)
        prepareConfiguredReadyConnection(fixture)

        fixture.controller.setDraftOperatingMode(.c, mode: .autoTTL)
        fixture.controller.applyPendingChanges()
        confirmCurrentGroup(fixture)
        let originalB = fixture.controller.groupDraft(.b).baseline
        let originalC = fixture.controller.groupDraft(.c).baseline
        expect(originalB.operatingMode == .manual)
        expect(originalC.operatingMode == .autoTTL)
        guard let originalGlobal = fixture.transport.controlPayloads.compactMap({
            SafeGodoxProtocol.globalSnapshot(from: $0)
        }).last else {
            preconditionFailure("La sincronización inicial no confirmó un A0 para recuperar")
        }
        expect(!originalGlobal.multiEnabled)
        let expectedBatch: [GodoxGroup: GroupRestorationPoint] = [
            .b: GroupRestorationPoint(
                deviceID: testDevice.id,
                snapshot: originalB,
                globalSnapshot: originalGlobal
            ),
            .c: GroupRestorationPoint(
                deviceID: testDevice.id,
                snapshot: originalC,
                globalSnapshot: originalGlobal
            ),
        ]

        var persistedWholeBatchBeforeA0 = false
        fixture.transport.onSendControl = { payload in
            guard SafeGodoxProtocol.globalSnapshot(from: payload)?.multiEnabled == true else {
                return
            }
            persistedWholeBatchBeforeA0 = restorationStore.load() == .batch(
                points: expectedBatch
            )
        }
        let enterStart = fixture.transport.controlWriteCount
        fixture.controller.setGlobalMultiFlashEnabled(true)
        fixture.controller.applyPendingChanges()
        fixture.transport.onSendControl = nil
        expect(
            persistedWholeBatchBeforeA0,
            "La escena B/C completa debe persistirse antes del primer write A0"
        )
        expect(fixture.transport.controlWriteCount == enterStart + 1)
        guard let enabledGlobal = SafeGodoxProtocol.globalSnapshot(
            from: fixture.transport.controlPayloads[enterStart]
        ) else {
            preconditionFailure("Entrar a Multi no produjo el A0 inicial")
        }
        expect(enabledGlobal.multiEnabled)
        expect(fixture.controller.restorationPoints == expectedBatch)
        expect(restorationStore.load() == .batch(points: expectedBatch))

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(fixture.transport.controlWriteCount == enterStart + 2)
        let multiBFrame = fixture.transport.controlPayloads[enterStart + 1]
        guard let multiB = SafeGodoxProtocol.groupSnapshot(from: multiBFrame) else {
            preconditionFailure("A0 Multi no liberó el A1 de B")
        }
        expect(multiB.0 == .b)
        expect(multiB.1.operatingMode == .multi)
        expect(
            multiBFrame[5] == originalB.power.encodedByte,
            "B Multi originado en manual debe conservar la potencia manual, no el sentinel TTL"
        )
        expect(multiBFrame[5] != 0x32)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(fixture.transport.controlWriteCount == enterStart + 3)
        let multiCFrame = fixture.transport.controlPayloads[enterStart + 2]
        guard let multiC = SafeGodoxProtocol.groupSnapshot(from: multiCFrame) else {
            preconditionFailure("Confirmar B no liberó el A1 Multi de C")
        }
        expect(multiC.0 == .c)
        expect(multiC.1.operatingMode == .multi)
        expect(
            multiCFrame[5] == 0x32,
            "C Multi originado en TTL debe usar el sentinel de potencia 0x32"
        )
        expect(
            fixture.controller.restorationPoints == expectedBatch,
            "Confirmar B no debe recortar el journal de la tanda"
        )
        expect(restorationStore.load() == .batch(points: expectedBatch))

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.commandFailed(
            .control,
            .writeFailed(command: .control, message: "fallo sintético del segundo A1 Multi")
        ))
        fixture.scheduler.fire(.disconnectRecovery)
        expectFailure(fixture.controller.phase, containing: "incierto")
        expect(fixture.controller.restorationPoints == expectedBatch)
        expect(restorationStore.load() == .batch(points: expectedBatch))

        let recovered = makeFixture(
            changeDeliveryPreferences: preferences,
            restorationStore: restorationStore,
            studioLibraryStore: studioMemory.makeStore()
        )
        expect(recovered.controller.restorationPoints == expectedBatch)
        expect(!recovered.controller.canEdit(.b))
        expect(!recovered.controller.canEdit(.c))
        prepareReadyConnection(recovered)
        recovered.controller.prepareBaselineRestoration(for: .b)
        expect(recovered.controller.preparedRestorations == Set([.b, .c]))
        expect(recovered.controller.pendingGroups == [.b, .c])
        expect(recovered.controller.canApply)

        let recoveryStart = recovered.transport.controlWriteCount
        recovered.controller.applyPendingChanges()
        expect(recovered.transport.controlWriteCount == recoveryStart + 1)
        guard let restoredGlobal = SafeGodoxProtocol.globalSnapshot(
            from: recovered.transport.controlPayloads[recoveryStart]
        ) else {
            preconditionFailure("La recuperación por lote no comenzó por A0")
        }
        expect(
            restoredGlobal == originalGlobal,
            "La recuperación debe restablecer exactamente el A0 común anterior"
        )
        expect(restorationStore.load() == .batch(points: expectedBatch))

        recovered.transport.emit(.controlWriteStarted)
        recovered.transport.emit(.controlWriteCompleted)
        guard let restoredB = SafeGodoxProtocol.groupSnapshot(
            from: recovered.transport.controlPayloads[recoveryStart + 1]
        ) else {
            preconditionFailure("A0 de recuperación no liberó el A1 original de B")
        }
        expect(restoredB.0 == .b)
        expect(restoredB.1 == originalB)
        expect(recovered.transport.controlPayloads[recoveryStart + 1][5] != 0x32)
        confirmCurrentGroup(recovered)
        expect(recovered.controller.restorationPoints == expectedBatch)
        expect(restorationStore.load() == .batch(points: expectedBatch))

        guard let restoredC = SafeGodoxProtocol.groupSnapshot(
            from: recovered.transport.controlPayloads[recoveryStart + 2]
        ) else {
            preconditionFailure("Confirmar B no liberó el A1 original de C")
        }
        expect(restoredC.0 == .c)
        expect(restoredC.1.operatingMode == originalC.operatingMode)
        expect(restoredC.1.modeling == originalC.modeling)
        expect(restoredC.1.beepEnabled == originalC.beepEnabled)
        expect(restoredC.1.compensationByte == originalC.compensationByte)
        expect(
            recovered.transport.controlPayloads[recoveryStart + 2][5] == 0x32,
            "El A1 TTL no serializa su potencia manual retenida; debe usar el sentinel 0x32"
        )
        confirmCurrentGroup(recovered)
        expect(recovered.controller.phase == .ready)
        expect(recovered.controller.groupDraft(.b).baseline == originalB)
        expect(recovered.controller.groupDraft(.c).baseline == originalC)
        expect(recovered.controller.multiFlashGroups.isEmpty)
        expect(recovered.controller.pendingCount == 0)
        expect(recovered.controller.restorationPoints.isEmpty)
        expect(restorationStore.load() == .none)
    }

    private static func checkMultiFlashUnsupportedGroups() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        let unsupportedGroups: [GodoxGroup] = [
            .f, .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine,
        ]
        var assignedModels = Dictionary(uniqueKeysWithValues: unsupportedGroups.map {
            ($0, Set(["ad600pro-ii"]))
        })
        assignedModels[.b] = ["ad600pro-ii"]
        expect(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: Set(unsupportedGroups + [.b]),
            assignedFlashModelIDs: assignedModels
        ))
        prepareConfiguredReadyConnection(fixture)

        let writesBeforeAttempts = fixture.transport.controlWriteCount
        for group in unsupportedGroups {
            expect(!fixture.controller.supportsMultiFlash(group))
            expect(!fixture.controller.availableOperatingModes(for: group).contains(.multi))

            fixture.controller.setDraftRadioEnabled(group, enabled: true)
            expect(fixture.controller.groupDraft(group).draft.operatingMode == .manual)
            expect(fixture.controller.canChangeOperatingMode(group))

            fixture.controller.setDraftOperatingMode(group, mode: .multi)
            expect(
                fixture.controller.groupDraft(group).draft.operatingMode == .manual,
                "El grupo \(group.label) no debe poder seleccionar MULTI"
            )
        }
        expect(
            fixture.transport.controlWriteCount == writesBeforeAttempts,
            "Rechazar MULTI en F/0–9 no debe escribir al radio"
        )
        expect(fixture.controller.multiFlashGroups.isEmpty)

        expect(!fixture.controller.canSetMultiFlashParticipation(.b, enabled: true))
        expect(fixture.controller.canSetGlobalMultiFlashEnabled(true))
        fixture.controller.setGlobalMultiFlashEnabled(true)
        expect(fixture.controller.multiFlashGroups == [.b])
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .multi)
        for group in unsupportedGroups {
            let state = fixture.controller.groupDraft(group)
            expect(
                state.draft.operatingMode == .off,
                "Un grupo activo incompatible debe quedar Off mientras Multi está activo"
            )
            expect(state.lastKnownActiveMode == .manual)
            expect(
                state.draftRestoresAfterMulti,
                "Un grupo incompatible apagado por Multi debe conservar su restauración"
            )
        }

        expect(!fixture.controller.canSetMultiFlashParticipation(.b, enabled: false))
        fixture.controller.setGlobalMultiFlashEnabled(false)
        expect(fixture.controller.multiFlashGroups.isEmpty)
        expect(fixture.controller.groupDraft(.b).draft.operatingMode == .manual)
        expect(fixture.controller.groupConfiguration(.b).isEnabledOnRadio)
        for group in unsupportedGroups {
            let state = fixture.controller.groupDraft(group)
            expect(
                state.draft.operatingMode == .manual,
                "Apagar Multi global debe dejar Manual los grupos incompatibles"
            )
            expect(state.draft.compensationByte == 0)
            expect(!state.draftRestoresAfterMulti)
            expect(fixture.controller.groupConfiguration(group).isEnabledOnRadio)
        }

        fixture.controller.setDraftRadioEnabled(.b, enabled: false)
        expect(
            !fixture.controller.canSetGlobalMultiFlashEnabled(true),
            "Sin ningún grupo activo compatible el botón global debe quedar indisponible"
        )
        fixture.controller.setGlobalMultiFlashEnabled(true)
        expect(fixture.controller.multiFlashGroups.isEmpty)
    }

    private static func checkVerifiedMultiFlashCountLimit() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)

        fixture.controller.beginWorkspaceConfiguration()
        expect(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b],
            assignedFlashModelIDs: [.b: ["ad400pro-ii"]]
        ))
        prepareConfiguredReadyConnection(fixture)

        fixture.controller.setGlobalMultiFlashEnabled(true)
        expect(fixture.controller.hasVerifiedMultiFlashCountLimit)
        expect(!fixture.controller.hasUnverifiedMultiFlashCountLimit)

        guard let oneOver512 = ManualPower.value(decimal: 10),
              let oneOver4 = ManualPower.value(decimal: 80) else {
            preconditionFailure("Faltan potencias enteras para probar los límites Multi")
        }

        fixture.controller.setMultiFlashHertz(1)
        fixture.controller.setMultiFlashPower(oneOver512)
        expect(fixture.controller.multiFlashMaximumCount == 100)
        fixture.controller.setMultiFlashCount(100)
        expect(fixture.controller.multiFlashDraft.count == 100)

        fixture.controller.setMultiFlashPower(oneOver4)
        expect(fixture.controller.multiFlashMaximumCount == 7)
        expect(
            fixture.controller.multiFlashDraft.count == 7,
            "Cambiar a 1/4 debe normalizar el conteo a la tabla oficial del AD400Pro II"
        )

        fixture.controller.setMultiFlashHertz(100)
        expect(fixture.controller.multiFlashMaximumCount == 2)
        expect(fixture.controller.multiFlashCountRange == 1...2)
        expect(fixture.controller.multiFlashDraft.count == 2)

        fixture.controller.setMultiFlashCount(3)
        expect(
            fixture.controller.multiFlashDraft.count == 2,
            "Un conteo por encima del límite verificado debe rechazarse"
        )

        fixture.controller.setMultiFlashHertz(55)
        expect(fixture.controller.multiFlashMaximumCount == 2)
        expect(fixture.controller.hasConservativeMultiFlashCountLimit)
        expect(!fixture.controller.hasVerifiedMultiFlashCountLimit)
        expect(!fixture.controller.hasUnverifiedMultiFlashCountLimit)
    }

    private static func checkMultiFlashModelChangeKeepsSafePendingDraft() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)

        fixture.controller.beginWorkspaceConfiguration()
        expect(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b],
            assignedFlashModelIDs: [.b: ["generic-512"]]
        ))
        prepareConfiguredReadyConnection(fixture)

        guard let oneOver4 = ManualPower.value(decimal: 80) else {
            preconditionFailure("Falta 1/4 para probar el cambio de matriz Multi")
        }
        fixture.controller.setGlobalMultiFlashEnabled(true)
        fixture.controller.setMultiFlashPower(oneOver4)
        fixture.controller.setMultiFlashHertz(100)
        fixture.controller.setMultiFlashCount(100)
        expect(fixture.controller.multiFlashDraft.count == 100)

        fixture.controller.applyPendingChanges()
        confirmCurrentGroup(fixture)
        expect(fixture.controller.multiFlashBaseline.count == 100)
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.controller.canSendTest)

        fixture.controller.setFlashModel("ad400pro-ii", assigned: true, to: .b)
        expect(fixture.controller.multiFlashMaximumCount == 2)
        expect(fixture.controller.multiFlashDraft.count == 2)
        expect(fixture.controller.multiFlashBaseline.count == 100)
        expect(fixture.controller.hasPendingMultiFlashChange)
        expect(!fixture.controller.canDiscardPendingChanges)
        expect(!fixture.controller.canSendTest)

        fixture.controller.discardPendingChanges()
        expect(
            fixture.controller.multiFlashDraft.count == 2,
            "Descartar no debe restaurar un conteo incompatible con los modelos actuales"
        )
        expect(fixture.controller.hasPendingMultiFlashChange)
        expect(!fixture.controller.canSendTest)

        fixture.controller.applyPendingChanges()
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(fixture.controller.multiFlashBaseline.count == 2)
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.controller.canSendTest)
    }

    private static func checkStoredMultiFlashLimitMigrationPersists() {
        let memory = MemoryStudioLibraryStorage()
        let store = memory.makeStore()
        guard let oneOver4 = ManualPower.value(decimal: 80),
              let unsafeMulti = MultiFlashSettings(
                  power: oneOver4,
                  count: 100,
                  hertz: 100
              ),
              let storedGroup = StudioWorkspaceGroup(
                  snapshot: ManualGroupSnapshot(
                      power: oneOver4,
                      modeling: .off,
                      operatingMode: .multi
                  ),
                  assignedFlashModelIDs: ["ad400pro-ii"],
                  lastKnownActiveMode: .manual
              ),
              let workspace = StudioWorkspace(
                  onboardingCompleted: true,
                  profileID: TransmitterProfile.observedGDBH.id,
                  workingGroups: [.b],
                  visibleGroups: [.b],
                  groupConfigurations: [.b: storedGroup],
                  multiFlashSettings: unsafeMulti
              ),
              let library = StudioLibrary(workspace: workspace, presets: []) else {
            preconditionFailure("No se pudo construir el workspace Multi legado")
        }
        expect(store.save(library))

        let migrated = makeFixture(studioLibraryStore: store)
        expect(migrated.controller.multiFlashDraft.count == 2)
        expect(migrated.controller.multiFlashBaseline.count == 2)
        expect(!migrated.controller.hasPendingMultiFlashChange)

        guard case .record(let persisted) = memory.makeStore().load() else {
            preconditionFailure("La migración Multi segura no se guardó")
        }
        expect(persisted.workspace.multiFlashSettings.count == 2)

        let restarted = makeFixture(studioLibraryStore: memory.makeStore())
        expect(restarted.controller.multiFlashDraft.count == 2)
        expect(restarted.controller.multiFlashBaseline.count == 2)
    }

    /// Regression seam for the user-visible Beep toggle. The radio exposes the
    /// audible gate as the global A0 byte 4; an A1 byte 7 mutation alone can be
    /// accepted by GATT while remaining silent when that global gate is off.
    private static func checkBeepIncludesGlobalA0Gate() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(fixture)

        let originalWriteCount = fixture.transport.controlWriteCount
        fixture.controller.setGlobalBeep(true)

        guard let payload = fixture.transport.controlPayloads.last else {
            preconditionFailure("El control Beep no entregó ninguna trama FEC7")
        }
        let bytes = [UInt8](payload)
        let hexadecimal = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        expect(
            bytes.count == 14 &&
                bytes.starts(with: [0xF0, 0xA0, 0x0A, 0xFF]) &&
                bytes[4] == 0x01,
            "Beep debe incluir A0 global byte 4; Estrobo entregó \(hexadecimal)"
        )
        expect(fixture.transport.controlWriteCount == originalWriteCount + 1)
        expect(fixture.controller.globalBeepEnabled)
        expect(fixture.controller.isGlobalControlPending)

        // A0 queda confirmado sólo con el acuse GATT. No existe una espera FEC8
        // global; inmediatamente después comienza la alineación A1 por grupo.
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(!fixture.controller.isGlobalControlPending)
        expect(fixture.transport.controlWriteCount == originalWriteCount + 2)

        for (offset, group) in fixture.controller.workingGroups.enumerated() {
            guard let decoded = SafeGodoxProtocol.groupSnapshot(
                from: fixture.transport.controlPayloads[originalWriteCount + 1 + offset]
            ) else {
                preconditionFailure("Beep global no produjo A1 para \(group.label)")
            }
            expect(decoded.0 == group)
            expect(decoded.1.beepEnabled, "Todos los A1 deben compartir el beep global")
            confirmCurrentGroup(fixture)
        }

        expect(fixture.controller.phase == .ready)
        expect(!fixture.controller.isGlobalControlPending)
        expect(fixture.controller.pendingCount == 0)
        expect(
            fixture.controller.workingGroups.allSatisfy {
                fixture.controller.groupDraft($0).draft.beepEnabled
            },
            "El estado local de todos los grupos debe quedar armonizado"
        )
        expect(fixture.transport.testWriteCount == 0, "Beep nunca debe disparar Test")
    }

    private static func checkGlobalStandbyPreservesGroups() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(fixture)

        let originalGroups = Dictionary(uniqueKeysWithValues: fixture.controller.workingGroups.map {
            ($0, fixture.controller.groupDraft($0).draft)
        })
        let originalWriteCount = fixture.transport.controlWriteCount

        expect(fixture.controller.canToggleGlobalStandby)
        fixture.controller.setGlobalStandby(true)
        guard let standbyFrame = fixture.transport.controlPayloads.last,
              let standbySnapshot = SafeGodoxProtocol.globalSnapshot(from: standbyFrame) else {
            preconditionFailure("Standby no generó una trama A0 válida")
        }
        expect(standbySnapshot.standbyEnabled)
        expect(fixture.transport.controlWriteCount == originalWriteCount + 1)
        expect(fixture.controller.isGlobalStandbyEnabled)
        expect(!fixture.controller.canEdit(.c))
        expect(!fixture.controller.canSendTest)
        expect(!fixture.controller.canToggleGlobalStandby, "No debe competir otro toggle con A0 pendiente")

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(fixture.controller.phase == .ready)
        expect(!fixture.controller.isGlobalControlPending)
        expect(
            fixture.transport.controlWriteCount == originalWriteCount + 1,
            "Standby sólo debe escribir A0; no debe apagar los grupos con A1"
        )
        expect(fixture.controller.canToggleGlobalStandby)

        fixture.controller.setGlobalStandby(false)
        guard let resumeFrame = fixture.transport.controlPayloads.last,
              let resumeSnapshot = SafeGodoxProtocol.globalSnapshot(from: resumeFrame) else {
            preconditionFailure("Reanudar no generó una trama A0 válida")
        }
        expect(!resumeSnapshot.standbyEnabled)
        expect(fixture.transport.controlWriteCount == originalWriteCount + 2)
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)

        expect(fixture.controller.phase == .ready)
        expect(!fixture.controller.isGlobalStandbyEnabled)
        expect(fixture.controller.canEdit(.c))
        expect(fixture.controller.canSendTest)
        expect(fixture.transport.testWriteCount == 0)
        for group in fixture.controller.workingGroups {
            expect(
                fixture.controller.groupDraft(group).draft == originalGroups[group],
                "Standby debe preservar íntegramente el grupo \(group.label)"
            )
        }
    }

    private static func checkGlobalControlsDoNotApplyPendingGroupChanges() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(fixture)

        expect(fixture.controller.groupDraft(.c).baseline.modeling == .proportional)
        fixture.controller.setDraftModeling(.c, modeling: .off)
        let pendingState = fixture.controller.groupDraft(.c)
        expect(pendingState.hasPendingChange)
        expect(fixture.controller.pendingGroups == [.c])
        expect(!fixture.controller.canToggleGlobalBeep)

        fixture.controller.setGlobalBeep(true)
        expect(!fixture.controller.globalBeepEnabled)
        expect(fixture.transport.controlWriteCount == 0)

        fixture.controller.setGlobalStandby(true)
        guard let standbyFrame = fixture.transport.controlPayloads.last,
              let standbySnapshot = SafeGodoxProtocol.globalSnapshot(from: standbyFrame) else {
            preconditionFailure("Standby con cambios pendientes no produjo A0")
        }
        expect(standbySnapshot.standbyEnabled)
        expect(
            standbySnapshot.modelingLightEnabled,
            "Standby debe conservar el gate A0 confirmado, no aplicar el modelado pendiente"
        )
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)

        expect(fixture.transport.controlWriteCount == 1)
        expect(fixture.controller.groupDraft(.c) == pendingState)
        expect(fixture.controller.pendingGroups == [.c])

        fixture.controller.setGlobalStandby(false)
        guard let resumeFrame = fixture.transport.controlPayloads.last,
              let resumeSnapshot = SafeGodoxProtocol.globalSnapshot(from: resumeFrame) else {
            preconditionFailure("Reanudar con cambios pendientes no produjo A0")
        }
        expect(!resumeSnapshot.standbyEnabled)
        expect(resumeSnapshot.modelingLightEnabled)
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)

        expect(fixture.transport.controlWriteCount == 2)
        expect(fixture.controller.groupDraft(.c) == pendingState)
        fixture.controller.discardPendingChanges()
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.controller.groupDraft(.c).draft.modeling == .proportional)
        expect(!fixture.controller.globalBeepEnabled)
    }

    private static func checkPresetPreservesGlobalBeep() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        completeDefaultWorkspace(fixture)
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)
        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        fixture.transport.emit(.commandSent(.sync))
        fixture.scheduler.fire(.valueSynchronizationSettle)
        confirmCurrentGroup(fixture)
        confirmCurrentGroup(fixture)
        expect(fixture.controller.phase == .ready)

        fixture.controller.setGlobalBeep(true)
        for _ in fixture.controller.workingGroups {
            confirmCurrentGroup(fixture)
        }
        expect(fixture.controller.globalBeepEnabled)
        expect(fixture.controller.savePreset(named: "Beep global"))
        guard let presetID = fixture.controller.presets.first?.id else {
            preconditionFailure("No se guardó el preset de beep global")
        }

        fixture.controller.setGlobalBeep(false)
        for _ in fixture.controller.workingGroups {
            confirmCurrentGroup(fixture)
        }
        expect(!fixture.controller.globalBeepEnabled)

        let writesBeforeLocalLoad = fixture.transport.controlWriteCount
        expect(fixture.controller.loadPreset(id: presetID, synchronizeIfConnected: false))
        expect(fixture.transport.controlWriteCount == writesBeforeLocalLoad)
        expect(fixture.controller.globalBeepEnabled)
        expect(
            fixture.controller.workingGroups.allSatisfy {
                fixture.controller.groupDraft($0).draft.beepEnabled
            }
        )
        expect(!fixture.controller.canToggleGlobalBeep)

        fixture.controller.discardPendingChanges()
        expect(!fixture.controller.globalBeepEnabled)
        expect(fixture.controller.pendingCount == 0)

        expect(fixture.controller.loadPreset(id: presetID, synchronizeIfConnected: true))
        guard let globalFrame = fixture.transport.controlPayloads.last,
              let globalSnapshot = SafeGodoxProtocol.globalSnapshot(from: globalFrame) else {
            preconditionFailure("Sincronizar el preset no comenzó con A0")
        }
        expect(globalSnapshot.beepEnabled)
        for _ in fixture.controller.workingGroups {
            confirmCurrentGroup(fixture)
        }

        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.globalBeepEnabled)
        expect(fixture.controller.pendingCount == 0)
        expect(
            fixture.controller.workingGroups.allSatisfy {
                let state = fixture.controller.groupDraft($0)
                return state.baseline.beepEnabled && state.draft.beepEnabled
            }
        )
        expect(fixture.transport.testWriteCount == 0)
    }

    private static func checkConnectionAndManualValueSynchronization() {
        let fixture = makeFixture()
        completeDefaultWorkspace(fixture)
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)
        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        fixture.transport.emit(.commandSent(.sync))

        expect(fixture.controller.phase == .synchronizing)
        expect(fixture.controller.isSynchronizingValues)
        expect(!fixture.controller.showsControlWorkspace)
        expect(fixture.transport.controlWriteCount == 0)
        expect(fixture.scheduler.activeCount(.valueSynchronizationSettle) == 1)

        fixture.scheduler.fire(.valueSynchronizationSettle)
        expect(fixture.transport.controlWriteCount == 1)
        expect(
            fixture.transport.controlPayloads.last.flatMap {
                SafeGodoxProtocol.globalSnapshot(from: $0)
            } != nil
        )
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.phase == .synchronizing)
        confirmCurrentGroup(fixture)

        expect(fixture.transport.controlWriteCount == 3)
        expect(fixture.controller.applySequenceStatus?.activeGroup == .c)
        expect(fixture.controller.phase == .synchronizing)
        confirmCurrentGroup(fixture)

        expect(fixture.controller.phase == .ready)
        expect(!fixture.controller.isSynchronizingValues)
        expect(fixture.controller.lastValueSynchronizationAt != nil)
        expect(fixture.controller.showsControlWorkspace)
        expect(fixture.controller.pendingCount == 0)
        let initialFrames = fixture.transport.controlPayloads
        expect(initialFrames.compactMap { SafeGodoxProtocol.groupSnapshot(from: $0)?.0 } == [.b, .c])

        fixture.controller.synchronizeValuesToRadio()
        expect(fixture.controller.isSynchronizingValues)
        expect(fixture.controller.phase == .applying)
        expect(fixture.transport.controlWriteCount == 4)
        confirmCurrentGroup(fixture)
        expect(fixture.transport.controlWriteCount == 6)
        confirmCurrentGroup(fixture)

        expect(fixture.controller.phase == .ready)
        expect(fixture.transport.controlPayloads[3] == initialFrames[0])
        expect(fixture.transport.controlPayloads[4] == initialFrames[1])
        expect(fixture.transport.controlPayloads[5] == initialFrames[2])
    }

    private static func checkNewWorkingGroupsCanBeActivated() {
        let memory = MemoryStudioLibraryStorage()
        let configured = makeFixture(studioLibraryStore: memory.makeStore())
        expect(configured.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.d, .e],
            assignedFlashModelIDs: [
                .d: ["ad400pro"],
                .e: ["ad600pro-ii"],
            ]
        ))
        let fixture = makeFixture(studioLibraryStore: memory.makeStore())
        expect(fixture.controller.workingGroups == [.d, .e])
        expect(fixture.controller.groupDraft(.d).draft.operatingMode == .off)
        expect(fixture.controller.groupDraft(.e).draft.operatingMode == .off)
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)
        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        fixture.transport.emit(.commandSent(.sync))
        fixture.scheduler.fire(.valueSynchronizationSettle)
        confirmCurrentGroup(fixture)
        confirmCurrentGroup(fixture)

        expect(fixture.controller.phase == .ready)
        expect(
            fixture.controller.canToggleRadioEnabled(.d),
            "D recién agregado debe poder activarse desde OFF"
        )
        expect(
            fixture.controller.canToggleRadioEnabled(.e),
            "E recién agregado debe poder activarse desde OFF"
        )

        fixture.controller.setDraftRadioEnabled(.d, enabled: true)
        fixture.controller.setDraftRadioEnabled(.e, enabled: true)
        expect(fixture.controller.groupDraft(.d).draft.operatingMode == .manual)
        expect(fixture.controller.groupDraft(.e).draft.operatingMode == .manual)

        let noCapabilityFixture = makeFixture()
        expect(noCapabilityFixture.controller.workingGroups.contains(.b))
        for modelID in noCapabilityFixture.controller
            .groupConfiguration(.b).assignedFlashModelIDs {
            noCapabilityFixture.controller.setFlashModel(
                modelID,
                assigned: false,
                to: .b
            )
        }
        expect(noCapabilityFixture.controller.groupConfiguration(.b).assignedFlashModelIDs.isEmpty)
        expect(noCapabilityFixture.controller.resolvedCapability(for: .b).powerScale.isEmpty)

        prepareConnection(noCapabilityFixture)
        noCapabilityFixture.transport.emit(.stateChanged(.ready(testDevice)))
        noCapabilityFixture.transport.emit(.readyForAuthentication)
        noCapabilityFixture.transport.emit(
            .notification(.authentication, validAuthenticationResponse())
        )
        noCapabilityFixture.transport.emit(.commandSent(.sync))

        expect(noCapabilityFixture.controller.phase == .ready)
        expect(
            !noCapabilityFixture.controller.canToggleRadioEnabled(.b),
            "Un grupo administrado sin modelo ni capacidad debe bloquear el toggle"
        )
        let unchangedDraft = noCapabilityFixture.controller.groupDraft(.b).draft
        noCapabilityFixture.controller.setDraftRadioEnabled(.b, enabled: false)
        expect(
            noCapabilityFixture.controller.groupDraft(.b).draft == unchangedDraft,
            "El setter también debe fallar cerrado si el grupo no tiene capacidad"
        )
    }

    private static func checkInitialSynchronizationRequiresRestorationJournal() {
        let restorationMemory = MemoryRestorationStorage()
        restorationMemory.acceptsWrites = false
        let fixture = makeFixture(restorationStore: restorationMemory.makeStore())
        completeDefaultWorkspace(fixture)
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)
        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        fixture.transport.emit(.commandSent(.sync))

        fixture.scheduler.fire(.valueSynchronizationSettle)

        expect(
            fixture.transport.controlWriteCount == 0,
            "La sincronización no debe transmitir A0 si no puede persistir toda la escena"
        )
        expect(fixture.controller.phase == .disconnecting)
        expect(!fixture.controller.showsControlWorkspace)
        expect(fixture.controller.restorationPoints.isEmpty)
        expect(fixture.transport.disconnectCount == 1)

        fixture.scheduler.fire(.disconnectRecovery)
        expectFailure(fixture.controller.phase, containing: "sincronización global inicial")
    }

    private static func checkPresetLoadAndSynchronization() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        completeDefaultWorkspace(fixture)
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)
        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        fixture.transport.emit(.commandSent(.sync))
        fixture.scheduler.fire(.valueSynchronizationSettle)
        confirmCurrentGroup(fixture)
        confirmCurrentGroup(fixture)
        expect(fixture.controller.phase == .ready)

        expect(fixture.controller.savePreset(named: "  Retrato  "))
        expect(fixture.controller.presets.count == 1)
        expect(fixture.controller.presets[0].name == "Retrato")
        expect(fixture.controller.presetNameExists("retráto"))
        expect(!fixture.controller.savePreset(named: "RETRATO"))

        guard let changedPower = ManualPower.value(decimal: 30) else {
            preconditionFailure("Falta la potencia canónica de preset")
        }
        fixture.controller.setDraftPower(.c, power: changedPower)
        expect(fixture.controller.groupDraft(.c).draft.power == changedPower)
        let writesBeforeLoad = fixture.transport.controlWriteCount
        let presetID = fixture.controller.presets[0].id
        expect(fixture.controller.loadPreset(id: presetID, synchronizeIfConnected: false))
        expect(fixture.transport.controlWriteCount == writesBeforeLoad)
        expect(fixture.controller.pendingCount == 0)

        expect(fixture.controller.loadPreset(id: presetID, synchronizeIfConnected: true))
        expect(fixture.transport.controlWriteCount == writesBeforeLoad + 1)
        confirmCurrentGroup(fixture)
        confirmCurrentGroup(fixture)
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.activePresetID == presetID)
        expect(fixture.controller.deletePreset(id: presetID))
        expect(fixture.controller.presets.isEmpty)
    }

    private static func checkLocalPresetLoadNeverSchedulesAutomaticDelivery() {
        let fixture = makeFixture()
        completeDefaultWorkspace(fixture)
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)
        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        fixture.transport.emit(.commandSent(.sync))
        fixture.scheduler.fire(.valueSynchronizationSettle)
        confirmCurrentGroup(fixture)
        confirmCurrentGroup(fixture)
        expect(fixture.controller.phase == .ready)

        guard let presetPower = ManualPower.value(decimal: 30) else {
            preconditionFailure("Falta una potencia canónica para el preset local")
        }
        fixture.controller.setDraftPower(.c, power: presetPower)
        expect(fixture.controller.pendingGroups == [.c])
        expect(fixture.controller.savePreset(named: "Escena local"))
        guard let presetID = fixture.controller.presets.first?.id else {
            preconditionFailure("No se creó el preset local")
        }

        fixture.controller.discardPendingChanges()
        expect(fixture.controller.pendingCount == 0)

        fixture.transport.emit(.notification(
            .control,
            Data([0xF0, 0xE0, 0x00, 0x00, 0x00, 0x00])
        ))
        let writesBeforeLoad = fixture.transport.controlWriteCount
        expect(fixture.transport.controlPayloads.last == Data([0xF0, 0xE0]))

        expect(fixture.controller.loadPreset(
            id: presetID,
            synchronizeIfConnected: false
        ))
        expect(fixture.controller.pendingGroups == [.c])

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)

        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.transport.controlWriteCount == writesBeforeLoad)

        guard let editedPower = ManualPower.value(decimal: 33) else {
            preconditionFailure("Falta una potencia canónica posterior a la carga local")
        }
        fixture.controller.setDraftPower(.c, power: editedPower)
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
    }

    private static func checkPresetCompatibilityFollowsCurrentModels() {
        let fixture = makeFixture()
        completeDefaultWorkspace(fixture)
        expect(fixture.controller.savePreset(named: "Rango amplio"))
        guard let preset = fixture.controller.presets.first else {
            preconditionFailure("No se creó el preset de rango")
        }
        expect(fixture.controller.presetCompatibilityIssue(preset) == nil)

        fixture.controller.setFlashModel("ad200pro", assigned: true, to: .b)
        fixture.controller.setFlashModel("ad600pro-ii", assigned: false, to: .b)

        expect(
            fixture.controller.presetCompatibilityIssue(preset)?.contains("grupo B") == true
        )
        expect(!fixture.controller.loadPreset(
            id: preset.id,
            synchronizeIfConnected: false
        ))
    }

    private static func checkWorkspaceAndPresetsSurviveControllerRestart() {
        let memory = MemoryStudioLibraryStorage()
        let first = makeFixture(studioLibraryStore: memory.makeStore())
        completeDefaultWorkspace(first)
        expect(first.controller.savePreset(named: "Producto"))
        let presetID = first.controller.presets.first?.id

        let restored = makeFixture(studioLibraryStore: memory.makeStore())
        expect(restored.controller.hasCompletedOnboarding)
        expect(restored.controller.transmitterProfile.id == TransmitterProfile.observedGDBH.id)
        expect(restored.controller.workingGroups == [.b, .c])
        expect(restored.controller.visibleGroups == [.b, .c])
        expect(
            restored.controller.groupConfiguration(.b).assignedFlashModelIDs == ["ad600pro-ii"]
        )
        expect(
            restored.controller.groupConfiguration(.c).assignedFlashModelIDs == ["ad400pro"]
        )
        expect(restored.controller.presets.first?.id == presetID)
        expect(restored.controller.presets.first?.name == "Producto")
    }

    private static func checkTransmitterProfileAvailabilityAndDefault() {
        let memory = MemoryTransmitterProfilePreferencesStorage()
        let first = makeFixture(
            transmitterProfilePreferences: memory.makePreferences()
        )
        let builtInIDs = TransmitterProfile.available.map(\.id)

        expect(first.controller.availableTransmitterProfiles.map(\.id) == builtInIDs)
        expect(first.controller.defaultTransmitterProfileID == TransmitterProfile.observedGDBH.id)
        expect(first.controller.transmitterProfile.id == TransmitterProfile.observedGDBH.id)
        expect(!first.controller.setDefaultTransmitterProfile("unknown"))
        expect(first.controller.setDefaultTransmitterProfile(
            TransmitterProfile.classicLetters.id
        ))
        expect(first.controller.transmitterProfile.id == TransmitterProfile.observedGDBH.id)

        expect(first.controller.removeTransmitterProfile(
            TransmitterProfile.classicLetters.id
        ))
        expect(
            first.controller.availableTransmitterProfiles.map(\.id) ==
                [TransmitterProfile.observedGDBH.id]
        )
        expect(first.controller.defaultTransmitterProfileID == TransmitterProfile.observedGDBH.id)
        expect(memory.makePreferences().load(
            builtInProfileIDs: builtInIDs,
            fallbackDefaultProfileID: TransmitterProfile.observedGDBH.id
        ) == TransmitterProfilePreferences.State(
            availableProfileIDs: [TransmitterProfile.observedGDBH.id],
            defaultProfileID: TransmitterProfile.observedGDBH.id
        ))
        expect(!first.controller.removeTransmitterProfile(
            TransmitterProfile.observedGDBH.id
        ))

        first.controller.restoreTransmitterProfiles()
        expect(first.controller.availableTransmitterProfiles.map(\.id) == builtInIDs)
        expect(first.controller.setDefaultTransmitterProfile(
            TransmitterProfile.classicLetters.id
        ))

        let restarted = makeFixture(
            transmitterProfilePreferences: memory.makePreferences()
        )
        expect(restarted.controller.transmitterProfile.id == TransmitterProfile.classicLetters.id)
        expect(restarted.controller.defaultTransmitterProfileID == TransmitterProfile.classicLetters.id)
        expect(restarted.controller.availableTransmitterProfiles.map(\.id) == builtInIDs)
        expect(!restarted.controller.removeTransmitterProfile(
            TransmitterProfile.classicLetters.id
        ))

        memory.acceptsWrites = false
        expect(!restarted.controller.setDefaultTransmitterProfile(
            TransmitterProfile.observedGDBH.id
        ))
        expect(restarted.controller.defaultTransmitterProfileID == TransmitterProfile.classicLetters.id)
        expect(!restarted.controller.removeTransmitterProfile(
            TransmitterProfile.observedGDBH.id
        ))
        expect(restarted.controller.availableTransmitterProfiles.map(\.id) == builtInIDs)

        let workspaceMemory = MemoryStudioLibraryStorage()
        let configured = makeFixture(studioLibraryStore: workspaceMemory.makeStore())
        completeDefaultWorkspace(configured)
        let fallbackMemory = MemoryTransmitterProfilePreferencesStorage()
        expect(fallbackMemory.makePreferences().save(
            TransmitterProfilePreferences.State(
                availableProfileIDs: [TransmitterProfile.classicLetters.id],
                defaultProfileID: TransmitterProfile.classicLetters.id
            ),
            builtInProfileIDs: builtInIDs,
            fallbackDefaultProfileID: TransmitterProfile.observedGDBH.id
        ))
        let fallback = makeFixture(
            transmitterProfilePreferences: fallbackMemory.makePreferences(),
            studioLibraryStore: workspaceMemory.makeStore()
        )
        expect(fallback.controller.transmitterProfile.id == TransmitterProfile.classicLetters.id)
        expect(!fallback.controller.hasCompletedOnboarding)
    }

    private static func checkWorkingGroupsKeepAtLeastOneFlashModel() {
        let memory = MemoryStudioLibraryStorage()
        let fixture = makeFixture(studioLibraryStore: memory.makeStore())
        completeDefaultWorkspace(fixture)

        fixture.controller.setFlashModel("ad600pro-ii", assigned: false, to: .b)

        expect(
            fixture.controller.groupConfiguration(.b).assignedFlashModelIDs == ["ad600pro-ii"]
        )
        expect(fixture.controller.workingConfigurationIssue == nil)
        expect(fixture.controller.activity.last?.message.contains("conservar") == true)

        let restored = makeFixture(studioLibraryStore: memory.makeStore())
        expect(restored.controller.hasCompletedOnboarding)
        expect(
            restored.controller.groupConfiguration(.b).assignedFlashModelIDs == ["ad600pro-ii"]
        )
    }

    private static func checkWorkspaceReconfigurationCanBeCancelled() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        completeDefaultWorkspace(fixture)
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)
        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        fixture.transport.emit(.commandSent(.sync))
        fixture.scheduler.fire(.valueSynchronizationSettle)
        confirmCurrentGroup(fixture)
        confirmCurrentGroup(fixture)

        guard let pendingPower = ManualPower.value(decimal: 30) else {
            preconditionFailure("Falta una potencia canónica para reconfigurar")
        }
        fixture.controller.setDraftPower(.c, power: pendingPower)
        expect(fixture.controller.pendingGroups == [.c])
        fixture.controller.disconnect()
        fixture.scheduler.fire(.disconnectRecovery)
        expect(fixture.controller.phase == .idle)
        expect(fixture.controller.pendingGroups == [.c])
        expect(fixture.controller.canConfigureHardwareProfile)

        fixture.controller.beginWorkspaceConfiguration()
        expect(fixture.controller.isReconfiguringWorkspace)
        expect(!fixture.controller.hasCompletedOnboarding)

        fixture.controller.cancelWorkspaceConfiguration()
        expect(!fixture.controller.isReconfiguringWorkspace)
        expect(fixture.controller.hasCompletedOnboarding)
        expect(fixture.controller.workingGroups == [.b, .c])
        expect(fixture.controller.workingConfigurationIssue == nil)

        fixture.controller.beginWorkspaceConfiguration()
        expect(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b],
            assignedFlashModelIDs: [.b: ["ad600pro-ii"]]
        ))
        expect(fixture.controller.workingGroups == [.b])
        expect(fixture.controller.pendingCount == 0)
    }

    private static func checkWorkspaceReconfigurationPreservesVisibility() {
        let fixture = makeFixture()
        completeDefaultWorkspace(fixture)
        fixture.controller.setGroupVisible(.b, isVisible: false)
        expect(fixture.controller.visibleGroups == [.c])

        fixture.controller.beginWorkspaceConfiguration()
        expect(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b, .c],
            assignedFlashModelIDs: [
                .b: ["ad600pro-ii"],
                .c: ["ad400pro"],
            ]
        ))

        expect(fixture.controller.visibleGroups == [.c])
    }

    private static func checkWorkspaceGroupsCanBeReconfiguredWhileReady() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        completeDefaultWorkspace(fixture)
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)
        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        fixture.transport.emit(.commandSent(.sync))
        fixture.scheduler.fire(.valueSynchronizationSettle)
        confirmCurrentGroup(fixture)
        confirmCurrentGroup(fixture)
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.canConfigureWorkspace)
        expect(!fixture.controller.canConfigureHardwareProfile)

        guard let pendingPower = ManualPower.value(decimal: 30) else {
            preconditionFailure("Falta una potencia canónica para reconfigurar conectado")
        }
        fixture.controller.setDraftPower(.c, power: pendingPower)
        expect(fixture.controller.pendingGroups == [.c])
        expect(fixture.controller.isAutomaticApplyScheduled)
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        let originalB = fixture.controller.groupDraft(.b)
        let pendingC = fixture.controller.groupDraft(.c)
        let writesBeforeConfiguration = fixture.transport.controlWriteCount

        fixture.controller.beginWorkspaceConfiguration()
        expect(
            fixture.controller.isReconfiguringWorkspace,
            "La configuración de grupos debe abrir con una sesión lista"
        )
        expect(!fixture.controller.hasCompletedOnboarding)
        expect(!fixture.controller.isAutomaticApplyScheduled)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.transport.controlWriteCount == writesBeforeConfiguration)
        expect(!fixture.controller.canApply)
        expect(!fixture.controller.canSendTest)

        fixture.controller.cancelWorkspaceConfiguration()
        expect(!fixture.controller.isReconfiguringWorkspace)
        expect(fixture.controller.hasCompletedOnboarding)
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.groupDraft(.b) == originalB)
        expect(fixture.controller.groupDraft(.c) == pendingC)
        expect(fixture.controller.pendingGroups == [.c])
        expect(!fixture.controller.isAutomaticApplyScheduled)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.transport.controlWriteCount == writesBeforeConfiguration)

        fixture.controller.beginWorkspaceConfiguration()
        expect(fixture.controller.isReconfiguringWorkspace)
        expect(!fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.classicLetters.id,
            selectedGroups: [.b, .c, .d],
            assignedFlashModelIDs: [
                .b: ["dpii"],
                .c: ["ad400pro"],
                .d: ["ad400pro"],
            ]
        ))
        expect(fixture.controller.transmitterProfile.id == TransmitterProfile.observedGDBH.id)
        expect(fixture.controller.workingGroups == [.b, .c])
        expect(fixture.controller.isReconfiguringWorkspace)

        let didCompleteWhileReady = fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b, .c, .d],
            assignedFlashModelIDs: [
                .b: ["dpii"],
                .c: ["ad400pro"],
                .d: ["ad400pro"],
            ]
        )
        expect(
            didCompleteWhileReady,
            "Los grupos y modelos deben guardarse con una sesión lista"
        )
        expect(fixture.controller.phase == .ready)
        expect(!fixture.controller.isReconfiguringWorkspace)
        expect(fixture.controller.hasCompletedOnboarding)
        expect(fixture.controller.workingGroups == [.b, .c, .d])
        expect(fixture.controller.visibleGroups == [.b, .c, .d])
        expect(fixture.controller.groupDraft(.c) == pendingC)
        expect(fixture.controller.groupDraft(.b).baseline == originalB.baseline)
        expect(
            fixture.controller.groupDraft(.b).draft.power ==
                fixture.controller.resolvedCapability(for: .b).powerScale.first
        )
        expect(fixture.controller.groupDraft(.d).baseline.operatingMode == .off)
        expect(fixture.controller.groupDraft(.d).draft.operatingMode == .off)
        expect(fixture.controller.groupDraft(.d).lastKnownActiveMode == nil)
        expect(!fixture.controller.groupDraft(.d).hasPendingChange)
        expect(fixture.controller.groupConfiguration(.d).assignedFlashModelIDs == ["ad400pro"])
        expect(fixture.transport.controlWriteCount == writesBeforeConfiguration)
        expect(fixture.controller.pendingGroups == [.b, .c])
        expect(fixture.controller.canApply)
        expect(fixture.controller.isAutomaticApplyScheduled)

        fixture.controller.applyPendingChanges()
        expect(fixture.controller.phase == .applying)
        expect(!fixture.controller.canConfigureWorkspace)
        expect(Set(fixture.controller.restorationPoints.keys) == [.b, .c])
        fixture.controller.beginWorkspaceConfiguration()
        expect(!fixture.controller.isReconfiguringWorkspace)
        confirmCurrentGroup(fixture)
        confirmCurrentGroup(fixture)
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.pendingCount == 0)

        let writesBeforeModelEdit = fixture.transport.controlWriteCount
        fixture.controller.setFlashModel("ad600pro-ii", assigned: true, to: .d)
        expect(
            fixture.controller.groupConfiguration(.d).assignedFlashModelIDs ==
                ["ad400pro", "ad600pro-ii"]
        )
        expect(fixture.transport.controlWriteCount == writesBeforeModelEdit)

        expect(fixture.controller.canToggleRadioEnabled(.d))
        fixture.controller.setDraftRadioEnabled(.d, enabled: true)
        expect(fixture.controller.groupDraft(.d).draft.operatingMode == .manual)
        expect(fixture.controller.pendingGroups == [.d])
        fixture.controller.applyPendingChanges()
        confirmCurrentGroup(fixture)
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.controller.canEdit(.d))

        fixture.controller.sendTestFlash()
        expect(fixture.controller.isTestPending)
        expect(!fixture.controller.canConfigureWorkspace)
        fixture.controller.beginWorkspaceConfiguration()
        expect(!fixture.controller.isReconfiguringWorkspace)
        fixture.transport.emit(.commandSent(.test))
        expect(fixture.controller.canConfigureWorkspace)
    }

    private static func checkTestRequiresReadyAndNoPendingChanges() {
        let fixture = makeFixture()

        expect(!fixture.controller.canSendTest)
        fixture.controller.sendTestFlash()
        expect(
            fixture.transport.testWriteCount == 0,
            "Test nunca debe salir antes de autenticar y sincronizar"
        )

        prepareReadyConnection(fixture)
        expect(fixture.controller.canSendTest)
        expect(fixture.controller.pendingCount == 0)
        let originalB = fixture.controller.groupDraft(.b)
        let originalC = fixture.controller.groupDraft(.c)

        fixture.controller.sendTestFlash()
        expect(fixture.transport.testWriteCount == 1)
        expect(fixture.transport.testPayloads.count == 1)
        expect(fixture.transport.controlWriteCount == 0)
        expect(fixture.controller.isTestPending)
        expect(!fixture.controller.canSendTest)
        expect(!fixture.controller.canDisconnect)
        expect(fixture.controller.restorationPoints.isEmpty)
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.controller.groupDraft(.b) == originalB)
        expect(fixture.controller.groupDraft(.c) == originalC)
        guard let payload = String(
            data: fixture.transport.testPayloads[0],
            encoding: .utf8
        ) else {
            preconditionFailure("Test debe ser un payload UTF-8 por FFF1")
        }
        expect(payload.hasSuffix(",Test"))
        expect(Int(payload.dropLast(",Test".count)) != nil)

        fixture.transport.emit(.commandSent(.test))
        expect(!fixture.controller.isTestPending)
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.canSendTest)
        expect(fixture.controller.canDisconnect)
        expect(
            !fixture.scheduler.fireNext(.testDelivery),
            "El éxito debe cancelar el timeout de entrega de Test"
        )
        expect(fixture.controller.restorationPoints.isEmpty)

        let activityCountAfterTest = fixture.controller.activity.count
        fixture.transport.emit(.commandFailed(
            .test,
            .writeFailed(command: .test, message: "fallo Test tardío")
        ))
        expect(
            fixture.controller.activity.count == activityCountAfterTest,
            "Un fallo Test tardío debe ignorarse después de cerrar la entrega"
        )

        guard let changedPower = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta una potencia canónica para bloquear Test con pendientes")
        }
        fixture.controller.setDraftPower(.c, power: changedPower)
        expect(fixture.controller.pendingGroups == [.c])
        expect(!fixture.controller.canSendTest)
        fixture.controller.sendTestFlash()
        expect(
            fixture.transport.testWriteCount == 1,
            "Test no debe saltarse cambios pendientes"
        )
        expect(fixture.transport.controlWriteCount == 0)
        expect(fixture.controller.pendingGroups == [.c])

        let modeAgnostic = makeFixture()
        modeAgnostic.controller.setFlashModel("ad600pro-ii", assigned: false, to: .a)
        modeAgnostic.controller.setFlashModel("ad600", assigned: false, to: .b)
        modeAgnostic.controller.setFlashModel("ad600pro-ii", assigned: false, to: .b)
        modeAgnostic.controller.setFlashModel("ad400pro", assigned: false, to: .c)
        prepareReadyConnection(modeAgnostic)
        expect(modeAgnostic.controller.globalPowerGroups.isEmpty)
        expect(
            modeAgnostic.controller.canSendTest,
            "Test es global y no debe depender de ningún modelo o modo manual local"
        )
        modeAgnostic.controller.sendTestFlash()
        expect(modeAgnostic.transport.testWriteCount == 1)
    }

    private static func checkTestDeliverySuccessFailureAndTimeout() {
        let failed = makeFixture()
        prepareReadyConnection(failed)
        failed.transport.onSendTest = { _ in
            failed.transport.emit(.commandFailed(
                .test,
                .writeFailed(command: .test, message: "fallo Test sintético")
            ))
        }
        failed.controller.sendTestFlash()
        failed.transport.onSendTest = nil

        expect(!failed.controller.isTestPending)
        expect(failed.controller.phase == .ready)
        expect(failed.controller.canSendTest)
        expect(failed.transport.disconnectCount == 0)
        expect(failed.controller.restorationPoints.isEmpty)
        expect(failed.controller.pendingCount == 0)
        expect(failed.transport.controlWriteCount == 0)
        expect(failed.controller.activity.last?.message.contains("Test no enviado") == true)
        expect(
            !failed.scheduler.fireNext(.testDelivery),
            "El fallo explícito debe cancelar el timeout de Test"
        )
        expect(failed.controller.restorationPoints.isEmpty)

        let timedOut = makeFixture()
        prepareReadyConnection(timedOut)
        timedOut.controller.sendTestFlash()
        expect(timedOut.transport.testWriteCount == 1)
        expect(timedOut.controller.isTestPending)
        timedOut.scheduler.fire(.testDelivery)

        expect(!timedOut.controller.isTestPending)
        expect(timedOut.controller.phase == .disconnecting)
        expect(timedOut.controller.restorationPoints.isEmpty)
        expect(timedOut.controller.pendingCount == 0)
        expect(timedOut.transport.controlWriteCount == 0)
        timedOut.scheduler.fire(.disconnectRecovery)
        expectFailure(timedOut.controller.phase, containing: "Test")
        expect(timedOut.controller.restorationPoints.isEmpty)
    }

    private static func checkAutomaticGlobalPowerAdjustmentIsAtomicAndSerialized() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)

        // B y C usan escalas 1/512 válidas. C queda oculto para comprobar que
        // la visibilidad local no altera el conjunto participante.
        fixture.controller.setFlashModel("ad600", assigned: false, to: .b)
        fixture.controller.setFlashModel("ad400pro", assigned: false, to: .c)
        fixture.controller.setFlashModel("ad600pro-ii", assigned: true, to: .c)
        fixture.controller.setGroupVisible(.c, isVisible: false)
        expect(!fixture.controller.visibleGroups.contains(.c))
        prepareReadyConnection(fixture)

        expect(fixture.controller.globalPowerGroups == [.b, .c])
        expect(
            !fixture.controller.resolvedCapability(for: .a).powerScale.isEmpty &&
                fixture.controller.groupDraft(.a).draft.operatingMode == .off &&
                !fixture.controller.globalPowerGroups.contains(.a),
            "Un grupo configurado pero OFF debe quedar fuera del ajuste global"
        )
        expect(
            fixture.controller.resolvedCapability(for: .d).powerScale.isEmpty &&
                !fixture.controller.globalPowerGroups.contains(.d),
            "Un grupo sin modelo debe quedar fuera del ajuste global"
        )
        expect(
            fixture.controller.globalPowerGroups.contains(.c),
            "Ocultar una tarjeta no debe excluir un grupo manual del control global"
        )
        let originalA = fixture.controller.groupDraft(.a)
        let originalD = fixture.controller.groupDraft(.d)

        fixture.controller.adjustGlobalPower(direction: 1)

        expect(fixture.controller.groupDraft(.b).draft.power.decimalValue == 13)
        expect(fixture.controller.groupDraft(.c).draft.power.decimalValue == 30)
        expect(fixture.controller.groupDraft(.a) == originalA)
        expect(fixture.controller.groupDraft(.d) == originalD)
        expect(fixture.controller.pendingGroups == [.b, .c])
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        expect(
            fixture.scheduler.fireNext(.automaticApply),
            "Un gesto global debe armar un único debounce, no uno por grupo"
        )
        expect(fixture.transport.controlPayloads.count == 1)
        guard let first = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[0]
        ) else {
            preconditionFailure("No se pudo decodificar B del ajuste global")
        }
        expect(first.0 == .b)
        expect(first.1.power.decimalValue == 13)
        expect(fixture.controller.applySequenceStatus?.remainingGroups == [.c])

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(
            fixture.transport.controlPayloads.count == 1,
            "El acuse GATT de B no debe adelantar C"
        )
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(fixture.transport.controlPayloads.count == 2)
        guard let second = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[1]
        ) else {
            preconditionFailure("No se pudo decodificar C del ajuste global")
        }
        expect(second.0 == .c)
        expect(second.1.power.decimalValue == 30)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.restorationPoints.isEmpty)
        expect(fixture.transport.testWriteCount == 0)
    }

    private static func checkGlobalPowerStopsAllGroupsAtSharedBoundary() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let maximum = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(maximum)

        guard let fullPower = ManualPower.value(decimal: 100),
              let belowFullPower = ManualPower.value(decimal: 97) else {
            preconditionFailure("Faltan potencias máximas canónicas")
        }
        maximum.controller.setDraftPower(.b, power: fullPower)
        maximum.controller.setDraftPower(.c, power: belowFullPower)
        let maximumDrafts = (
            maximum.controller.groupDraft(.b),
            maximum.controller.groupDraft(.c)
        )
        let maximumActivityCount = maximum.controller.activity.count

        expect(!maximum.controller.canAdjustGlobalPower(direction: 1))
        expect(maximum.controller.canAdjustGlobalPower(direction: -1))
        maximum.controller.adjustGlobalPower(direction: 1)

        expect(
            maximum.controller.groupDraft(.b) == maximumDrafts.0 &&
                maximum.controller.groupDraft(.c) == maximumDrafts.1,
            "Un grupo en 1/1 debe bloquear la subida global completa"
        )
        expect(maximum.controller.activity.count == maximumActivityCount)
        expect(maximum.scheduler.activeCount(.automaticApply) == 0)
        expect(maximum.transport.controlPayloads.isEmpty)

        let minimumMemory = MemoryChangeDeliveryStorage()
        let minimumPreferences = minimumMemory.makePreferences()
        minimumPreferences.save(.manual)
        let minimum = makeFixture(changeDeliveryPreferences: minimumPreferences)
        minimum.controller.setFlashModel("ad400pro", assigned: false, to: .c)
        minimum.controller.setFlashModel("ad600pro-ii", assigned: true, to: .c)
        prepareReadyConnection(minimum)
        guard let minimumB = ManualPower.value(decimal: 20),
              let aboveMinimumC = ManualPower.value(decimal: 13),
              let minimumC = ManualPower.value(decimal: 10) else {
            preconditionFailure("Faltan potencias mínimas canónicas")
        }
        minimum.controller.setDraftPower(.b, power: minimumB)
        minimum.controller.setDraftPower(.c, power: aboveMinimumC)
        let minimumDrafts = (
            minimum.controller.groupDraft(.b),
            minimum.controller.groupDraft(.c)
        )
        let minimumActivityCount = minimum.controller.activity.count

        expect(!minimum.controller.canAdjustGlobalPower(direction: -1))
        expect(minimum.controller.canAdjustGlobalPower(direction: 1))
        minimum.controller.adjustGlobalPower(direction: -1)

        expect(
            minimum.controller.groupDraft(.b) == minimumDrafts.0 &&
                minimum.controller.groupDraft(.c) == minimumDrafts.1,
            "B en su mínimo 1/256 debe bloquear la bajada global completa"
        )
        expect(minimum.controller.groupDraft(.c).draft.power != minimumC)
        expect(minimum.controller.activity.count == minimumActivityCount)
        expect(minimum.scheduler.activeCount(.automaticApply) == 0)
        expect(minimum.transport.controlPayloads.isEmpty)
    }

    private static func checkGlobalPowerCanReachBoundaryBeforeBlocking() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(fixture)

        guard let oneBelowMaximum = ManualPower.value(decimal: 97),
              let middlePower = ManualPower.value(decimal: 70),
              let maximum = ManualPower.value(decimal: 100),
              let middleRaised = ManualPower.value(decimal: 73) else {
            preconditionFailure("Faltan potencias para alcanzar el límite global")
        }
        fixture.controller.setDraftPower(.b, power: oneBelowMaximum)
        fixture.controller.setDraftPower(.c, power: middlePower)

        expect(fixture.controller.canAdjustGlobalPower(direction: 1))
        fixture.controller.adjustGlobalPower(direction: 1)
        expect(fixture.controller.groupDraft(.b).draft.power == maximum)
        expect(fixture.controller.groupDraft(.c).draft.power == middleRaised)
        expect(!fixture.controller.canAdjustGlobalPower(direction: 1))

        let boundaryDrafts = (
            fixture.controller.groupDraft(.b),
            fixture.controller.groupDraft(.c)
        )
        let activityCount = fixture.controller.activity.count
        fixture.controller.adjustGlobalPower(direction: 1)
        expect(fixture.controller.groupDraft(.b) == boundaryDrafts.0)
        expect(fixture.controller.groupDraft(.c) == boundaryDrafts.1)
        expect(fixture.controller.activity.count == activityCount)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.transport.controlPayloads.isEmpty)
    }

    private static func checkHistoricalOffScalePowerBlocksGlobalAdjustment() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(fixture)

        expect(fixture.controller.groupDraft(.b).draft.power.decimalValue == 10)
        expect(fixture.controller.allowedPowers(for: .b).first?.decimalValue == 20)
        expect(fixture.controller.globalPowerGroups == [.b, .c])
        expect(
            fixture.controller.makeGlobalPowerAnchor().isEmpty,
            "Un participante histórico fuera de escala debe invalidar el ancla completa"
        )
        expect(!fixture.controller.canAdjustGlobalPower(direction: -1))
        expect(!fixture.controller.canAdjustGlobalPower(direction: 1))

        let originalB = fixture.controller.groupDraft(.b)
        let originalC = fixture.controller.groupDraft(.c)
        let activityCount = fixture.controller.activity.count
        fixture.controller.adjustGlobalPower(direction: -1)
        fixture.controller.adjustGlobalPower(direction: 1)
        expect(fixture.controller.groupDraft(.b) == originalB)
        expect(fixture.controller.groupDraft(.c) == originalC)
        expect(fixture.controller.activity.count == activityCount)

        let invalidAnchor: [GodoxGroup: ManualPower] = [
            .b: originalB.draft.power,
            .c: originalC.draft.power,
        ]
        expect(fixture.controller.globalPowerOffsetBounds(from: invalidAnchor) == 0...0)
        fixture.controller.adjustGlobalPower(offsetSteps: Int.max, from: invalidAnchor)
        fixture.controller.adjustGlobalPower(offsetSteps: Int.min, from: invalidAnchor)
        expect(fixture.controller.groupDraft(.b) == originalB)
        expect(fixture.controller.groupDraft(.c) == originalC)
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.transport.controlPayloads.isEmpty)
    }

    private static func checkAnchoredGlobalPowerUsesCommonBoundsAndNoHysteresis() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        fixture.controller.setGroupVisible(.c, isVisible: false)
        prepareReadyConnection(fixture)

        guard let oneBelowMaximum = ManualPower.value(decimal: 97),
              let middlePower = ManualPower.value(decimal: 70),
              let maximum = ManualPower.value(decimal: 100),
              let middleRaised = ManualPower.value(decimal: 73),
              let oneAboveMinimum = ManualPower.value(decimal: 23),
              let minimum = ManualPower.value(decimal: 20),
              let middleLowered = ManualPower.value(decimal: 67) else {
            preconditionFailure("Faltan potencias para probar el slider global común")
        }

        fixture.controller.setDraftPower(.b, power: oneBelowMaximum)
        fixture.controller.setDraftPower(.c, power: middlePower)
        let maximumAnchor = fixture.controller.makeGlobalPowerAnchor()
        expect(Set(maximumAnchor.keys) == Set([.b, .c]))
        expect(
            maximumAnchor[.c] != nil && !fixture.controller.visibleGroups.contains(.c),
            "El ancla global debe incluir grupos manuales ocultos"
        )
        expect(maximumAnchor[.a] == nil, "Un grupo OFF no debe entrar en el ancla global")
        expect(maximumAnchor[.d] == nil, "Un grupo sin modelo no debe entrar en el ancla global")
        let maximumBounds = fixture.controller.globalPowerOffsetBounds(from: maximumAnchor)
        expect(maximumBounds.upperBound == 1)

        fixture.controller.adjustGlobalPower(offsetSteps: Int.max, from: maximumAnchor)
        expect(fixture.controller.groupDraft(.b).draft.power == maximum)
        expect(fixture.controller.groupDraft(.c).draft.power == middleRaised)

        fixture.controller.adjustGlobalPower(offsetSteps: 0, from: maximumAnchor)
        expect(fixture.controller.groupDraft(.b).draft.power == oneBelowMaximum)
        expect(fixture.controller.groupDraft(.c).draft.power == middlePower)

        fixture.controller.setDraftPower(.b, power: oneAboveMinimum)
        fixture.controller.setDraftPower(.c, power: middlePower)
        let minimumAnchor = fixture.controller.makeGlobalPowerAnchor()
        let minimumBounds = fixture.controller.globalPowerOffsetBounds(from: minimumAnchor)
        expect(minimumBounds.lowerBound == -1)

        fixture.controller.adjustGlobalPower(offsetSteps: Int.min, from: minimumAnchor)
        expect(fixture.controller.groupDraft(.b).draft.power == minimum)
        expect(fixture.controller.groupDraft(.c).draft.power == middleLowered)

        fixture.controller.adjustGlobalPower(offsetSteps: 0, from: minimumAnchor)
        expect(fixture.controller.groupDraft(.b).draft.power == oneAboveMinimum)
        expect(fixture.controller.groupDraft(.c).draft.power == middlePower)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.transport.controlPayloads.isEmpty)
    }

    private static func checkGlobalPowerConstraintReportsLimitingGroups() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(fixture)

        guard let oneBelowMaximum = ManualPower.value(decimal: 97),
              let middlePower = ManualPower.value(decimal: 70),
              let maximum = ManualPower.value(decimal: 100),
              let raisedMiddle = ManualPower.value(decimal: 73),
              let visualMiddle = ManualPower.value(decimal: 60) else {
            preconditionFailure("Faltan potencias para probar los límites globales")
        }

        fixture.controller.setDraftPower(.b, power: oneBelowMaximum)
        fixture.controller.setDraftPower(.c, power: middlePower)
        let upperAnchor = fixture.controller.makeGlobalPowerAnchor()
        guard let upperConstraint = fixture.controller.globalPowerConstraint(
            from: upperAnchor,
            limitedTo: 9
        ) else {
            preconditionFailure("Falta la restricción global superior")
        }
        expect(upperConstraint.allowedOffsets.upperBound == 1)
        expect(upperConstraint.upperBoundary == .groups([.b]))

        let limitedOutcome = fixture.controller.attemptGlobalPowerAdjustment(
            offsetSteps: 5,
            from: upperAnchor,
            limitedTo: 9
        )
        expect(limitedOutcome == .limited(offsetSteps: 1, cause: .groups([.b])))
        expect(fixture.controller.groupDraft(.b).draft.power == maximum)
        expect(fixture.controller.groupDraft(.c).draft.power == raisedMiddle)

        fixture.controller.setDraftPower(.b, power: maximum)
        fixture.controller.setDraftPower(.c, power: maximum)
        let tiedAnchor = fixture.controller.makeGlobalPowerAnchor()
        let tiedOutcome = fixture.controller.adjustGlobalPower(direction: 1)
        expect(tiedOutcome == .limited(offsetSteps: 0, cause: .groups([.b, .c])))
        expect(fixture.controller.makeGlobalPowerAnchor() == tiedAnchor)

        fixture.controller.setDraftPower(.b, power: visualMiddle)
        fixture.controller.setDraftPower(.c, power: visualMiddle)
        let visualAnchor = fixture.controller.makeGlobalPowerAnchor()
        guard let visualConstraint = fixture.controller.globalPowerConstraint(
            from: visualAnchor,
            limitedTo: 9
        ) else {
            preconditionFailure("Falta la ventana visual global")
        }
        expect(visualConstraint.allowedOffsets == -9...9)
        expect(visualConstraint.lowerBoundary == .visualWindow)
        expect(visualConstraint.upperBoundary == .visualWindow)
        expect(
            fixture.controller.attemptGlobalPowerAdjustment(
                offsetSteps: 10,
                from: visualAnchor,
                limitedTo: 9
            ) == .limited(offsetSteps: 9, cause: .visualWindow)
        )
        expect(fixture.transport.controlPayloads.isEmpty)
    }

    private static func checkAnchoredGlobalPowerUsesCapturedGroups() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(fixture)

        guard let powerB = ManualPower.value(decimal: 50),
              let raisedB = ManualPower.value(decimal: 53),
              let powerC = ManualPower.value(decimal: 60),
              let raisedC = ManualPower.value(decimal: 63) else {
            preconditionFailure("Faltan potencias para probar el conjunto capturado")
        }
        fixture.controller.setDraftPower(.b, power: powerB)
        fixture.controller.setDraftPower(.c, power: powerC)
        let anchor = fixture.controller.makeGlobalPowerAnchor()
        expect(Set(anchor.keys) == Set([.b, .c]))

        fixture.controller.setDraftRadioEnabled(.c, enabled: false)
        expect(fixture.controller.globalPowerGroups == [.b])
        fixture.controller.adjustGlobalPower(offsetSteps: 1, from: anchor)

        expect(fixture.controller.groupDraft(.b).draft.power == raisedB)
        expect(fixture.controller.groupDraft(.c).draft.power == raisedC)
        expect(fixture.controller.groupDraft(.c).draft.operatingMode == .off)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.transport.controlPayloads.isEmpty)
    }

    private static func checkAnchoredGlobalPowerAdjustmentIsAtomic() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        fixture.controller.setFlashModel("ad600", assigned: false, to: .b)
        fixture.controller.setGroupVisible(.c, isVisible: false)
        prepareReadyConnection(fixture)

        let anchor = fixture.controller.makeGlobalPowerAnchor()
        fixture.controller.adjustGlobalPower(offsetSteps: 2, from: anchor)

        expect(fixture.controller.pendingGroups == [.b, .c])
        expect(
            fixture.scheduler.activeCount(.automaticApply) == 1,
            "Un ajuste multi-grupo desde ancla debe armar un solo debounce"
        )
        expect(
            fixture.scheduler.fireNext(.automaticApply),
            "No debe existir un debounce cancelado por cada grupo del mismo ajuste"
        )
        expect(fixture.transport.controlPayloads.count == 1)
        expect(
            SafeGodoxProtocol.groupSnapshot(from: fixture.transport.controlPayloads[0])?.0 == .b
        )
        expect(fixture.controller.applySequenceStatus?.remainingGroups == [.c])
    }

    private static func checkAnchoredGlobalPowerAdjustmentHonorsSafetyGates() {
        let fixture = makeFixture()
        fixture.controller.setFlashModel("ad600", assigned: false, to: .b)
        expect(
            fixture.controller.makeGlobalPowerAnchor().isEmpty,
            "No debe capturarse un ancla sin una sesión lista"
        )
        prepareReadyConnection(fixture)

        let anchor = fixture.controller.makeGlobalPowerAnchor()
        expect(!anchor.isEmpty)
        let originalB = fixture.controller.groupDraft(.b)
        let originalC = fixture.controller.groupDraft(.c)

        fixture.controller.sendTestFlash()
        expect(fixture.controller.isTestPending)
        expect(
            fixture.controller.makeGlobalPowerAnchor().isEmpty,
            "Test pendiente debe bloquear nuevas anclas globales"
        )
        fixture.controller.adjustGlobalPower(offsetSteps: 3, from: anchor)
        expect(fixture.controller.groupDraft(.b) == originalB)
        expect(fixture.controller.groupDraft(.c) == originalC)
        expect(fixture.controller.pendingCount == 0)

        fixture.transport.emit(.commandSent(.test))
        fixture.controller.adjustGlobalPower(offsetSteps: 1, from: anchor)
        expect(fixture.controller.pendingGroups == [.b, .c])
        fixture.controller.applyPendingChanges()
        expect(fixture.controller.phase == .applying)

        let applyingB = fixture.controller.groupDraft(.b)
        let applyingC = fixture.controller.groupDraft(.c)
        expect(
            fixture.controller.makeGlobalPowerAnchor().isEmpty,
            "Una secuencia de escritura debe bloquear nuevas anclas globales"
        )
        fixture.controller.adjustGlobalPower(offsetSteps: 4, from: anchor)
        expect(fixture.controller.groupDraft(.b) == applyingB)
        expect(fixture.controller.groupDraft(.c) == applyingC)
    }

    private static func checkAutomaticDebounceCancelsAndRearms() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(fixture)

        guard let firstPower = ManualPower.value(decimal: 23),
              let latestPower = ManualPower.value(decimal: 20) else {
            preconditionFailure("Faltan potencias canónicas para probar el debounce")
        }

        fixture.controller.setDraftPower(.c, power: firstPower)
        expect(fixture.transport.controlPayloads.isEmpty)
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        expect(fixture.controller.isAutomaticApplyScheduled)

        fixture.controller.setDraftPower(.c, power: latestPower)
        expect(fixture.transport.controlPayloads.isEmpty)
        expect(
            fixture.scheduler.activeCount(.automaticApply) == 1,
            "Reeditar debe cancelar el plazo anterior y dejar sólo uno activo"
        )
        expect(
            !fixture.scheduler.fireNext(.automaticApply),
            "El primer plazo consumido debe ser el debounce cancelado"
        )
        expect(fixture.transport.controlPayloads.isEmpty)
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)

        expect(fixture.scheduler.fireNext(.automaticApply))
        expect(!fixture.controller.isAutomaticApplyScheduled)
        expect(fixture.transport.controlPayloads.count == 1)
        guard let decoded = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[0]
        ) else {
            preconditionFailure("No se pudo decodificar el envío automático")
        }
        expect(decoded.0 == .c)
        expect(decoded.1.power == latestPower)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.controller.groupDraft(.c).baseline.power == latestPower)
    }

    private static func checkManualModeCancelsAutomaticSend() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let fixture = makeFixture(changeDeliveryPreferences: preferences)
        prepareReadyConnection(fixture)

        guard let changedPower = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta la potencia canónica para probar el modo manual")
        }

        fixture.controller.setDraftPower(.c, power: changedPower)
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        fixture.controller.setChangeDeliveryMode(.manual)

        expect(fixture.controller.changeDeliveryMode == .manual)
        expect(preferences.load() == .manual)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(!fixture.controller.isAutomaticApplyScheduled)
        expect(
            !fixture.scheduler.fireNext(.automaticApply),
            "El plazo automático cancelado no debe enviar cambios en modo manual"
        )
        expect(fixture.transport.controlPayloads.isEmpty)
        expect(fixture.controller.pendingGroups == [.c])

        fixture.controller.applyPendingChanges()
        expect(fixture.transport.controlPayloads.count == 1)
        guard let decoded = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[0]
        ) else {
            preconditionFailure("No se pudo decodificar el envío manual")
        }
        expect(decoded.0 == .c)
        expect(decoded.1.power == changedPower)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.pendingCount == 0)
    }

    private static func checkAutomaticSerializesTwoGroups() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let restorationMemory = MemoryRestorationStorage()
        let restorationStore = restorationMemory.makeStore()
        let fixture = makeFixture(
            changeDeliveryPreferences: preferences,
            restorationStore: restorationStore
        )

        // B conserva modelos mixtos y por ello usa el rango estricto 1/256.
        // C se deja con un único flash 1/512 para demostrar que cada snapshot
        // de la cola conserva su propia capacidad.
        fixture.controller.setFlashModel("ad400pro", assigned: false, to: .c)
        fixture.controller.setFlashModel("ad600pro-ii", assigned: true, to: .c)
        prepareReadyConnection(fixture)

        guard let normalizedB = ManualPower.value(decimal: 20),
              let extendedC = ManualPower.value(decimal: 13) else {
            preconditionFailure("Faltan potencias canónicas para probar la cola")
        }
        expect(fixture.controller.allowedPowers(for: .b).first == normalizedB)
        expect(fixture.controller.allowedPowers(for: .c).contains(extendedC))

        fixture.controller.setDraftModeling(.b, modeling: .fixed(percent: 25))
        fixture.controller.setDraftPower(.c, power: extendedC)
        expect(fixture.controller.pendingGroups == [.b, .c])
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)

        expect(!fixture.scheduler.fireNext(.automaticApply))
        expect(fixture.transport.controlPayloads.isEmpty)
        expect(fixture.scheduler.fireNext(.automaticApply))
        expect(fixture.transport.controlPayloads.count == 1)

        guard let first = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[0]
        ) else {
            preconditionFailure("No se pudo decodificar el primer grupo de la cola")
        }
        expect(first.0 == .b)
        expect(first.1.power == normalizedB)
        expect(first.1.modeling == .fixed(percent: 25))
        expect(fixture.controller.applySequenceStatus?.activeGroup == .b)
        expect(fixture.controller.applySequenceStatus?.remainingGroups == [.c])

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(
            fixture.transport.controlPayloads.count == 1,
            "C no debe enviarse sólo con el acuse GATT de B"
        )
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(
            fixture.transport.controlPayloads.count == 2,
            "C debe enviarse únicamente después de GATT + FEC8 de B"
        )

        guard let second = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[1]
        ) else {
            preconditionFailure("No se pudo decodificar el segundo grupo de la cola")
        }
        expect(second.0 == .c)
        expect(second.1.power == extendedC)
        expect(fixture.controller.applySequenceStatus?.activeGroup == .c)
        expect(fixture.controller.applySequenceStatus?.remainingGroups.isEmpty == true)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(fixture.transport.controlPayloads.count == 2)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))

        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.restorationPoints.isEmpty)
        expect(restorationStore.load() == .none)
        expect(fixture.controller.groupDraft(.b).baseline.power == normalizedB)
        expect(fixture.controller.groupDraft(.c).baseline.power == extendedC)
    }

    private static func checkSynchronousHeartbeatFailuresPreserveAutomaticBatch() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let restorationMemory = MemoryRestorationStorage()
        let restorationStore = restorationMemory.makeStore()
        let fixture = makeFixture(
            changeDeliveryPreferences: preferences,
            restorationStore: restorationStore
        )
        prepareReadyConnection(fixture)

        guard let changedC = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta la potencia canónica para probar el heartbeat")
        }
        let originalB = fixture.controller.groupDraft(.b).baseline
        let originalC = fixture.controller.groupDraft(.c).baseline
        let expectedRestorations: [GodoxGroup: GroupRestorationPoint] = [
            .b: GroupRestorationPoint(deviceID: testDevice.id, snapshot: originalB),
            .c: GroupRestorationPoint(deviceID: testDevice.id, snapshot: originalC),
        ]
        fixture.controller.setDraftModeling(.b, modeling: .fixed(percent: 25))
        fixture.controller.setDraftPower(.c, power: changedC)
        fixture.scheduler.fire(.automaticApply)
        expect(fixture.transport.controlPayloads.count == 1)
        expect(
            SafeGodoxProtocol.groupSnapshot(from: fixture.transport.controlPayloads[0])?.0 == .b
        )
        expect(restorationStore.load() == .batch(points: expectedRestorations))
        fixture.transport.emit(.controlWriteStarted)

        var synchronousHeartbeatFailures = 0
        fixture.transport.onSendControl = { payload in
            guard payload == Data([0xF0, 0xE0]) else { return }
            synchronousHeartbeatFailures += 1
            fixture.transport.emit(.commandFailed(
                .control,
                .writeFailed(command: .control, message: "fallo heartbeat reentrante")
            ))
        }
        for _ in 0..<2 {
            fixture.transport.emit(.notification(
                .control,
                Data([0xF0, 0xE0, 0x00, 0x00, 0x00, 0x00])
            ))
        }
        fixture.transport.onSendControl = nil

        expect(synchronousHeartbeatFailures == 2)
        expect(fixture.transport.controlPayloads.count == 3)
        expect(fixture.transport.controlPayloads[1] == Data([0xF0, 0xE0]))
        expect(fixture.transport.controlPayloads[2] == Data([0xF0, 0xE0]))
        expect(fixture.controller.phase == .applying)
        expect(fixture.controller.applySequenceStatus?.activeGroup == .b)
        expect(fixture.controller.applySequenceStatus?.remainingGroups == [.c])
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))
        expect(fixture.scheduler.activeCount(.heartbeat) == 0)
        expect(
            !fixture.scheduler.fireNext(.heartbeat) && !fixture.scheduler.fireNext(.heartbeat),
            "Cada fallo reentrante debe cancelar sólo su propio deadline de heartbeat"
        )
        expect(fixture.controller.phase == .applying)
        expect(fixture.transport.controlPayloads.count == 3)

        fixture.transport.emit(.controlWriteCompleted)
        if case .gattAccepted = fixture.controller.groupDraft(.b).confirmation {
            // El intent y el timeout correlacionado de B sobrevivieron ambos fallos reentrantes.
        } else {
            preconditionFailure("Los heartbeats fallidos no deben retirar el intent activo de B")
        }
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(
            fixture.transport.controlPayloads.count == 4,
            "Confirmar B debe continuar con C tras retirar sólo los heartbeats fallidos"
        )
        guard let continued = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[3]
        ) else {
            preconditionFailure("No se pudo decodificar C después de los heartbeats fallidos")
        }
        expect(continued.0 == .c)
        expect(continued.1.power == changedC)
        expect(fixture.controller.phase == .applying)
        expect(fixture.controller.applySequenceStatus?.activeGroup == .c)
        expect(fixture.controller.applySequenceStatus?.remainingGroups.isEmpty == true)
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.restorationPoints.isEmpty)
        expect(restorationStore.load() == .none)
    }

    private static func checkHeartbeatTimeoutStopsAutomaticBatch() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let restorationMemory = MemoryRestorationStorage()
        let restorationStore = restorationMemory.makeStore()
        let fixture = makeFixture(
            changeDeliveryPreferences: preferences,
            restorationStore: restorationStore
        )
        prepareReadyConnection(fixture)

        guard let changedC = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta la potencia canónica para probar el timeout de heartbeat")
        }
        let originalB = fixture.controller.groupDraft(.b).baseline
        let originalC = fixture.controller.groupDraft(.c).baseline
        let expectedRestorations: [GodoxGroup: GroupRestorationPoint] = [
            .b: GroupRestorationPoint(deviceID: testDevice.id, snapshot: originalB),
            .c: GroupRestorationPoint(deviceID: testDevice.id, snapshot: originalC),
        ]
        fixture.controller.setDraftModeling(.b, modeling: .fixed(percent: 25))
        fixture.controller.setDraftPower(.c, power: changedC)
        fixture.scheduler.fire(.automaticApply)
        expect(fixture.transport.controlPayloads.count == 1)
        expect(fixture.controller.applySequenceStatus?.activeGroup == .b)
        expect(fixture.controller.applySequenceStatus?.remainingGroups == [.c])
        expect(restorationStore.load() == .batch(points: expectedRestorations))

        fixture.transport.emit(.notification(
            .control,
            Data([0xF0, 0xE0, 0x00, 0x00, 0x00, 0x00])
        ))
        expect(fixture.transport.controlPayloads.count == 2)
        expect(fixture.transport.controlPayloads[1] == Data([0xF0, 0xE0]))
        expect(
            fixture.scheduler.activeCount(.heartbeat) == 1,
            "Un heartbeat enviado debe quedar protegido por un único deadline"
        )

        expect(fixture.scheduler.fireNext(.heartbeat))

        expect(fixture.controller.phase == .disconnecting)
        expect(fixture.transport.disconnectCount == 1)
        expect(fixture.scheduler.activeCount(.heartbeat) == 0)
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.transport.controlPayloads.count == 2)
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))

        fixture.scheduler.fire(.disconnectRecovery)
        expectFailure(fixture.controller.phase, containing: "heartbeat")
        expect(
            fixture.transport.controlPayloads.count == 2,
            "C nunca debe salir después de que expire el heartbeat"
        )
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))
    }

    private static func checkControlFailureStopsAutomaticBatch() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let restorationMemory = MemoryRestorationStorage()
        let restorationStore = restorationMemory.makeStore()
        let fixture = makeFixture(
            changeDeliveryPreferences: preferences,
            restorationStore: restorationStore
        )
        prepareReadyConnection(fixture)

        guard let changedC = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta la potencia canónica para probar el fallo de la tanda")
        }
        let originalB = fixture.controller.groupDraft(.b).baseline
        let originalC = fixture.controller.groupDraft(.c).baseline
        let expectedRestorations: [GodoxGroup: GroupRestorationPoint] = [
            .b: GroupRestorationPoint(deviceID: testDevice.id, snapshot: originalB),
            .c: GroupRestorationPoint(deviceID: testDevice.id, snapshot: originalC),
        ]

        fixture.controller.setDraftModeling(.b, modeling: .fixed(percent: 25))
        fixture.controller.setDraftPower(.c, power: changedC)
        expect(fixture.controller.pendingGroups == [.b, .c])

        fixture.scheduler.fire(.automaticApply)
        expect(fixture.transport.controlPayloads.count == 1)
        expect(
            SafeGodoxProtocol.groupSnapshot(from: fixture.transport.controlPayloads[0])?.0 == .b
        )
        expect(fixture.controller.applySequenceStatus?.activeGroup == .b)
        expect(fixture.controller.applySequenceStatus?.remainingGroups == [.c])
        expect(restorationStore.load() == .batch(points: expectedRestorations))

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.commandFailed(
            .control,
            .writeFailed(command: .control, message: "fallo sintético de tanda")
        ))

        expect(fixture.transport.controlPayloads.count == 1)
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.phase == .disconnecting)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))

        fixture.scheduler.fire(.disconnectRecovery)
        expectFailure(fixture.controller.phase, containing: "incierto")
        expect(
            fixture.transport.controlPayloads.count == 1,
            "C nunca debe enviarse después de fallar B, ni al vencer la recuperación"
        )
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))
    }

    private static func checkLateControlNotificationsAreIgnoredDuringInvalidation() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.manual)
        let restorationMemory = MemoryRestorationStorage()
        let restorationStore = restorationMemory.makeStore()
        let fixture = makeFixture(
            changeDeliveryPreferences: preferences,
            restorationStore: restorationStore
        )
        prepareReadyConnection(fixture)

        guard let changedC = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta la potencia canónica para probar notificaciones tardías")
        }
        let originalC = fixture.controller.groupDraft(.c).baseline
        fixture.controller.setDraftPower(.c, power: changedC)
        fixture.controller.applyPendingChanges()
        expect(fixture.transport.controlPayloads.count == 1)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.commandFailed(
            .control,
            .writeFailed(command: .control, message: "fallo sintético antes de notificaciones tardías")
        ))
        expect(fixture.controller.phase == .disconnecting)
        let payloadCountBeforeLateNotifications = fixture.transport.controlPayloads.count
        let lastResponseBeforeLateNotifications = fixture.controller.lastRadioResponseAt

        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        fixture.transport.emit(.notification(
            .control,
            Data([0xF0, 0xE0, 0x00, 0x00, 0x00, 0x00])
        ))

        expect(
            fixture.controller.phase == .disconnecting,
            "Una notificación tardía nunca debe revivir la sesión"
        )
        expect(fixture.transport.disconnectCount == 1)
        expect(fixture.transport.controlPayloads.count == payloadCountBeforeLateNotifications)
        expect(fixture.controller.lastRadioResponseAt == lastResponseBeforeLateNotifications)
        expect(fixture.controller.restorationPoints[.c]?.snapshot == originalC)
        expect(
            fixture.controller.activity.suffix(2).allSatisfy {
                $0.message.contains("tardía") && $0.message.contains("ignorada")
            }
        )

        fixture.scheduler.fire(.disconnectRecovery)
        expectFailure(fixture.controller.phase, containing: "incierto")
        expect(fixture.transport.controlPayloads.count == payloadCountBeforeLateNotifications)
    }

    private static func checkFEC8TimeoutStopsAutomaticBatch() async {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let restorationMemory = MemoryRestorationStorage()
        let restorationStore = restorationMemory.makeStore()
        let fixture = makeFixture(
            changeDeliveryPreferences: preferences,
            restorationStore: restorationStore
        )
        prepareReadyConnection(fixture)

        guard let changedC = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta la potencia canónica para probar el timeout FEC8")
        }
        let originalB = fixture.controller.groupDraft(.b).baseline
        let originalC = fixture.controller.groupDraft(.c).baseline
        let expectedRestorations: [GodoxGroup: GroupRestorationPoint] = [
            .b: GroupRestorationPoint(deviceID: testDevice.id, snapshot: originalB),
            .c: GroupRestorationPoint(deviceID: testDevice.id, snapshot: originalC),
        ]

        fixture.controller.setDraftModeling(.b, modeling: .fixed(percent: 25))
        fixture.controller.setDraftPower(.c, power: changedC)
        fixture.scheduler.fire(.automaticApply)
        expect(fixture.transport.controlPayloads.count == 1)
        expect(
            SafeGodoxProtocol.groupSnapshot(from: fixture.transport.controlPayloads[0])?.0 == .b
        )

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(fixture.controller.phase == .applying)
        expect(fixture.controller.applySequenceStatus?.activeGroup == .b)
        expect(fixture.controller.applySequenceStatus?.remainingGroups == [.c])
        expect(restorationStore.load() == .batch(points: expectedRestorations))

        // El timeout de respuesta del radio usa un Task real de dos segundos.
        // Suspender el main actor permite que venza sin introducir hooks en Sources.
        try? await Task.sleep(for: .milliseconds(2_500))

        expect(fixture.controller.phase == .disconnecting)
        expect(fixture.transport.disconnectCount == 1)
        expect(fixture.transport.controlPayloads.count == 1)
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))

        fixture.scheduler.fire(.disconnectRecovery)
        expectFailure(fixture.controller.phase, containing: "FEC8")
        expect(
            fixture.transport.controlPayloads.count == 1,
            "C nunca debe enviarse cuando B recibió GATT pero agotó su FEC8"
        )
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))
    }

    private static func checkRestorationPersistenceFailurePreventsAutomaticBatch() {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let restorationMemory = MemoryRestorationStorage()
        restorationMemory.acceptsWrites = false
        let restorationStore = restorationMemory.makeStore()
        let fixture = makeFixture(
            changeDeliveryPreferences: preferences,
            restorationStore: restorationStore
        )
        prepareReadyConnection(fixture)

        guard let changedC = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta la potencia canónica para probar la persistencia fallida")
        }
        fixture.controller.setDraftModeling(.b, modeling: .fixed(percent: 25))
        fixture.controller.setDraftPower(.c, power: changedC)
        expect(fixture.controller.pendingGroups == [.b, .c])

        fixture.scheduler.fire(.automaticApply)

        expect(
            fixture.transport.controlPayloads.isEmpty,
            "Ninguna trama debe salir si no puede persistirse el ajuste anterior"
        )
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.restorationPoints.isEmpty)
        expect(restorationStore.load() == .none)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.controller.pendingGroups == [.b, .c])
    }

    private static func checkAutomaticSchedulingResumesAfterRestoration() {
        checkAutomaticSchedulingResumesAfterRestoration(heartbeatFails: false)
        checkAutomaticSchedulingResumesAfterRestoration(heartbeatFails: true)
    }

    private static func checkAutomaticSchedulingResumesAfterRestoration(
        heartbeatFails: Bool
    ) {
        let deliveryMemory = MemoryChangeDeliveryStorage()
        let preferences = deliveryMemory.makePreferences()
        preferences.save(.automatic)
        let restorationMemory = MemoryRestorationStorage()
        let restorationStore = restorationMemory.makeStore()
        let fixture = makeFixture(
            changeDeliveryPreferences: preferences,
            restorationStore: restorationStore
        )
        prepareReadyConnection(fixture)

        guard let changedC = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta la potencia canónica para probar el automático tras recuperar")
        }
        let originalB = fixture.controller.groupDraft(.b).baseline
        let originalC = fixture.controller.groupDraft(.c).baseline
        let expectedRestorations: [GodoxGroup: GroupRestorationPoint] = [
            .b: GroupRestorationPoint(deviceID: testDevice.id, snapshot: originalB),
            .c: GroupRestorationPoint(deviceID: testDevice.id, snapshot: originalC),
        ]
        fixture.controller.setDraftModeling(.b, modeling: .fixed(percent: 25))
        fixture.controller.setDraftPower(.c, power: changedC)
        fixture.scheduler.fire(.automaticApply)
        expect(fixture.transport.controlPayloads.count == 1)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.commandFailed(
            .control,
            .writeFailed(command: .control, message: "fallo sintético previo a recuperación")
        ))
        fixture.scheduler.fire(.disconnectRecovery)
        expectFailure(fixture.controller.phase, containing: "incierto")
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))
        expect(fixture.controller.pendingGroups == [.b, .c])

        prepareReadyConnection(fixture)
        expect(fixture.controller.phase == .ready)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        fixture.controller.prepareBaselineRestoration(for: .b)
        expect(fixture.controller.canApply)
        fixture.controller.applyPendingChanges()
        expect(fixture.transport.controlPayloads.count == 2)
        expect(
            SafeGodoxProtocol.globalSnapshot(
                from: fixture.transport.controlPayloads[1]
            ) != nil,
            "La recuperación debe restablecer A0 antes de reenviar A1"
        )
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        expect(fixture.transport.controlPayloads.count == 3)
        guard let restoration = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[2]
        ) else {
            preconditionFailure("No se pudo decodificar la recuperación de B")
        }
        expect(restoration.0 == .b)
        expect(restoration.1 == originalB)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.notification(
            .control,
            Data([0xF0, 0xE0, 0x00, 0x00, 0x00, 0x00])
        ))
        expect(fixture.transport.controlPayloads.count == 4)
        expect(fixture.transport.controlPayloads[3] == Data([0xF0, 0xE0]))
        expect(fixture.scheduler.activeCount(.heartbeat) == 1)
        fixture.transport.emit(.controlWriteCompleted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))

        expect(fixture.controller.phase == .applying)
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))
        expect(
            !fixture.controller.isAutomaticApplyScheduled,
            "El segundo A1 de recuperación debe esperar mientras el heartbeat siga pendiente"
        )
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(!fixture.controller.canApply)
        expect(
            fixture.transport.controlPayloads.count == 4,
            "El A1 original de C debe esperar al heartbeat pendiente"
        )

        fixture.transport.emit(.controlWriteStarted)
        if heartbeatFails {
            fixture.transport.emit(.commandFailed(
                .control,
                .writeFailed(command: .control, message: "fallo sintético de heartbeat tras recuperar")
            ))
        } else {
            fixture.transport.emit(.controlWriteCompleted)
        }

        expect(fixture.controller.phase == .applying)
        expect(fixture.scheduler.activeCount(.heartbeat) == 0)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.transport.controlPayloads.count == 5)
        expect(
            !fixture.scheduler.fireNext(.heartbeat),
            "El callback del heartbeat debe cancelar su deadline"
        )
        guard let restoredC = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[4]
        ) else {
            preconditionFailure("No se pudo decodificar la recuperación original de C")
        }
        expect(restoredC.0 == .c)
        expect(restoredC.1 == originalC)
        expect(fixture.controller.restorationPoints == expectedRestorations)
        expect(restorationStore.load() == .batch(points: expectedRestorations))

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.pendingCount == 0)
        expect(fixture.controller.applySequenceStatus == nil)
        expect(fixture.controller.restorationPoints.isEmpty)
        expect(restorationStore.load() == .none)
    }

    private static func checkReadySessionAppliesNormalChanges() {
        let restorationMemory = MemoryRestorationStorage()
        let restorationStore = restorationMemory.makeStore()
        let fixture = makeFixture(restorationStore: restorationStore)
        prepareReadyConnection(fixture)

        guard let lowerC = ManualPower.value(decimal: 23),
              let normalizedB = ManualPower.value(decimal: 20),
              let raisedB = ManualPower.value(decimal: 23) else {
            preconditionFailure("Faltan potencias canónicas para la prueba de control")
        }

        let originalC = fixture.controller.groupDraft(.c).baseline
        let originalCPoint = GroupRestorationPoint(
            deviceID: testDevice.id,
            snapshot: originalC
        )
        var persistedBeforeControlWrite = false
        fixture.transport.onSendControl = { _ in
            persistedBeforeControlWrite = restorationStore.load() == .batch(
                points: [.c: originalCPoint]
            )
        }
        fixture.controller.setDraftPower(.c, power: lowerC)
        expect(fixture.controller.pendingGroups == [.c])
        expect(
            fixture.controller.canApply,
            "C debe poder aplicarse directamente después de conectar, sin pasos adicionales"
        )
        fixture.controller.applyPendingChanges()
        fixture.transport.onSendControl = nil
        expect(
            persistedBeforeControlWrite,
            "El punto de recuperación debe persistirse antes de enviar la trama A1"
        )
        expect(fixture.transport.controlPayloads.count == 1)
        expect(
            SafeGodoxProtocol.groupSnapshot(from: fixture.transport.controlPayloads[0])?.0 == .c
        )
        expect(
            SafeGodoxProtocol.groupSnapshot(from: fixture.transport.controlPayloads[0])?.1.power == lowerC
        )
        expect(fixture.controller.phase == .applying)
        expect(fixture.controller.restorationPoints[.c]?.snapshot == originalC)
        expect(restorationStore.load() == .batch(points: [.c: originalCPoint]))
        expect(!fixture.controller.canEdit(.c))
        expect(!fixture.controller.canDisconnect)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(
            fixture.controller.phase == .applying,
            "Un FEC8 anterior al acuse GATT no debe cerrar el cambio"
        )
        expect(fixture.controller.groupDraft(.c).baseline == originalC)
        expect(fixture.controller.restorationPoints[.c]?.snapshot == originalC)
        expect(restorationStore.load() == .batch(points: [.c: originalCPoint]))
        expect(
            fixture.controller.activity.last?.message.contains("antes del acuse GATT") == true
        )

        fixture.transport.emit(.controlWriteCompleted)
        if case .gattAccepted = fixture.controller.groupDraft(.c).confirmation {
            // Estado esperado hasta recibir FEC8.
        } else {
            preconditionFailure("El acuse GATT debe quedar visible mientras se espera FEC8")
        }
        expect(fixture.controller.restorationPoints[.c] != nil)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))

        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.groupDraft(.c).baseline.power == lowerC)
        if case .radioResponded = fixture.controller.groupDraft(.c).confirmation {
            // El ajuste sólo se consolida después de GATT + FEC8.
        } else {
            preconditionFailure("FEC8 debe consolidar el ajuste enviado")
        }
        expect(fixture.controller.restorationPoints.isEmpty)
        expect(restorationStore.load() == .none)
        expect(fixture.controller.canEdit(.c))
        expect(fixture.controller.canDisconnect)

        let originalB = fixture.controller.groupDraft(.b).baseline
        expect(originalB.power.decimalValue == 10)
        expect(
            fixture.controller.allowedPowers(for: .b).first == normalizedB,
            "El rango editable mixto debe comenzar en el mínimo común 1/256"
        )
        expect(!fixture.controller.allowedPowers(for: .b).contains(originalB.power))
        fixture.controller.setDraftModeling(.b, modeling: .fixed(percent: 25))
        expect(
            fixture.controller.canApply,
            "Editar B debe normalizar el 1/512 heredado y permitir el cambio"
        )
        fixture.controller.applyPendingChanges()
        guard let modelingFrame = fixture.transport.controlPayloads.last,
              let modelingSnapshot = SafeGodoxProtocol.groupSnapshot(from: modelingFrame)?.1 else {
            preconditionFailure("No se pudo decodificar el cambio de modelado de B")
        }
        expect(modelingSnapshot.power == normalizedB)
        expect(modelingSnapshot.modeling == .fixed(percent: 25))
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(fixture.controller.restorationPoints.isEmpty)
        expect(fixture.controller.groupDraft(.b).baseline.power == normalizedB)
        expect(fixture.controller.groupDraft(.b).baseline.modeling == .fixed(percent: 25))

        fixture.controller.setDraftPower(.b, power: raisedB)
        expect(
            fixture.controller.canApply,
            "B debe seguir aceptando cambios dentro del rango común"
        )
        fixture.controller.applyPendingChanges()
        guard let powerFrame = fixture.transport.controlPayloads.last,
              let powerSnapshot = SafeGodoxProtocol.groupSnapshot(from: powerFrame)?.1 else {
            preconditionFailure("No se pudo decodificar el cambio de potencia de B")
        }
        expect(powerSnapshot.power == raisedB)
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(fixture.controller.groupDraft(.b).baseline.power == raisedB)
        expect(fixture.controller.restorationPoints.isEmpty)
        expect(restorationStore.load() == .none)
    }

    private static func checkUncertainWriteRequiresPersistedRecovery() {
        let restorationMemory = MemoryRestorationStorage()
        let restorationStore = restorationMemory.makeStore()
        let fixture = makeFixture(restorationStore: restorationStore)
        prepareReadyConnection(fixture)

        guard let lowerC = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta la potencia canónica para la recuperación incierta")
        }
        let originalC = fixture.controller.groupDraft(.c).baseline
        let originalCPoint = GroupRestorationPoint(
            deviceID: testDevice.id,
            snapshot: originalC
        )

        fixture.controller.setDraftPower(.c, power: lowerC)
        fixture.controller.applyPendingChanges()
        expect(restorationStore.load() == .batch(points: [.c: originalCPoint]))
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.commandFailed(
            .control,
            .writeFailed(command: .control, message: "fallo sintético")
        ))

        expect(fixture.controller.phase == .disconnecting)
        expect(fixture.controller.restorationPoints[.c]?.snapshot == originalC)
        expect(restorationStore.load() == .batch(points: [.c: originalCPoint]))
        expect(fixture.transport.disconnectCount == 1)

        fixture.scheduler.fire(.disconnectRecovery)
        expectFailure(fixture.controller.phase, containing: "incierto")
        expect(fixture.controller.restorationPoints[.c]?.snapshot == originalC)

        let recovered = makeFixture(restorationStore: restorationStore)
        expect(recovered.controller.phase == .idle)
        expect(recovered.controller.restorationPoints[.c]?.snapshot == originalC)
        expect(!recovered.controller.canEdit(.c))
        expect(!recovered.controller.canDisconnect)

        recovered.controller.startScanning()
        recovered.transport.emit(.discovered(otherTestDevice))
        recovered.controller.radioCode = dummyPassword(7)
        recovered.controller.connectSelectedDevice()
        expect(
            recovered.transport.connectCount == 0,
            "Una recuperación pendiente nunca debe enviarse a otro UUID"
        )
        expect(
            recovered.controller.activity.last?.message.contains("radio") == true,
            "El rechazo del radio incorrecto debe quedar explicado"
        )

        recovered.transport.emit(.discovered(testDevice))
        recovered.controller.selectDevice(testDevice.id)
        recovered.controller.radioCode = dummyPassword(8)
        recovered.controller.connectSelectedDevice()
        expect(recovered.transport.connectCount == 1)
        recovered.transport.emit(.stateChanged(.ready(testDevice)))
        recovered.transport.emit(.readyForAuthentication)
        recovered.transport.emit(.notification(
            .authentication,
            validAuthenticationResponse()
        ))
        recovered.transport.emit(.commandSent(.sync))
        expect(recovered.controller.phase == .ready)
        expect(!recovered.controller.canEdit(.c))
        expect(!recovered.controller.canApply)

        recovered.controller.prepareBaselineRestoration(for: .c)
        expect(recovered.controller.pendingGroups == [.c])
        expect(
            recovered.controller.canApply,
            "El radio original debe admitir únicamente la recuperación exacta persistida"
        )
        recovered.controller.applyPendingChanges()
        guard let recoveryGlobalFrame = recovered.transport.controlPayloads.last,
              SafeGodoxProtocol.globalSnapshot(from: recoveryGlobalFrame) != nil else {
            preconditionFailure("La recuperación no comenzó por A0")
        }
        recovered.transport.emit(.controlWriteStarted)
        recovered.transport.emit(.controlWriteCompleted)
        guard let recoveryFrame = recovered.transport.controlPayloads.last,
              let decodedRecovery = SafeGodoxProtocol.groupSnapshot(from: recoveryFrame) else {
            preconditionFailure("No se pudo decodificar la trama de recuperación")
        }
        expect(decodedRecovery.0 == .c)
        expect(decodedRecovery.1 == originalC)
        expect(restorationStore.load() == .batch(points: [.c: originalCPoint]))

        recovered.transport.emit(.controlWriteStarted)
        recovered.transport.emit(.controlWriteCompleted)
        recovered.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        expect(recovered.controller.phase == .ready)
        expect(recovered.controller.groupDraft(.c).baseline == originalC)
        expect(recovered.controller.restorationPoints.isEmpty)
        expect(restorationStore.load() == .none)
        expect(recovered.controller.canEdit(.c))
        expect(recovered.controller.canDisconnect)
    }

    private static func checkSavedRadioReconnectFlow() {
        let optOutStorage = MemorySavedRadioStorage()
        let optOutStore = optOutStorage.makeStore()
        let optOutFixture = makeFixture(savedRadioStore: optOutStore)
        expect(!optOutFixture.controller.rememberSelectedRadio)
        optOutFixture.controller.startScanning()
        optOutFixture.transport.emit(.discovered(testDevice))
        let optOutCode = dummyPassword(2)
        optOutFixture.controller.radioCode = optOutCode
        optOutFixture.controller.connectSelectedDevice()
        optOutFixture.transport.emit(.stateChanged(.ready(testDevice)))
        optOutFixture.transport.emit(.readyForAuthentication)
        optOutFixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        optOutFixture.transport.emit(.commandSent(.sync))
        expect(optOutStore.load() == .none, "El opt-in apagado nunca debe persistir el código")
        expect(optOutFixture.controller.radioCode.isEmpty)
        expect(!optOutFixture.controller.activity.contains { $0.message.contains(optOutCode) })

        let rememberedPassword = dummyPassword(4)
        guard let rememberedRadio = SavedRadio(
            deviceID: testDevice.id,
            name: testDevice.name,
            radioCode: rememberedPassword
        ) else {
            preconditionFailure("No se pudo construir el radio guardado sintético")
        }
        let rememberedStorage = MemorySavedRadioStorage()
        let rememberedStore = rememberedStorage.makeStore()
        expect(rememberedStore.save(rememberedRadio))
        let rememberedFixture = makeFixture(savedRadioStore: rememberedStore)

        expect(rememberedFixture.controller.savedRadio == rememberedRadio)
        expect(rememberedFixture.controller.radioCode.isEmpty)
        rememberedFixture.controller.startScanning()
        rememberedFixture.transport.emit(.discovered(otherTestDevice))
        expect(rememberedFixture.controller.selectedDeviceID == otherTestDevice.id)
        expect(rememberedFixture.controller.radioCode.isEmpty)

        rememberedFixture.transport.emit(.discovered(testDevice))
        expect(
            rememberedFixture.controller.selectedDeviceID == testDevice.id,
            "El radio guardado debe ganar aunque otro dispositivo tenga mejor RSSI"
        )
        expect(
            rememberedFixture.controller.radioCode == rememberedPassword,
            "El código guardado debe cargarse sólo al descubrir su mismo UUID"
        )
        rememberedFixture.scheduler.fire(.scan)
        expect(rememberedFixture.controller.phase == .idle)
        expect(
            rememberedFixture.controller.radioCode == rememberedPassword,
            "Terminar el escaneo no debe borrar el código del radio ya encontrado"
        )

        let newStorage = MemorySavedRadioStorage()
        let newStore = newStorage.makeStore()
        let newFixture = makeFixture(savedRadioStore: newStore)
        let newPassword = dummyPassword(6)
        newFixture.controller.rememberSelectedRadio = true
        newFixture.controller.startScanning()
        newFixture.transport.emit(.discovered(otherTestDevice))
        newFixture.controller.radioCode = newPassword
        newFixture.controller.connectSelectedDevice()

        expect(newStore.load() == .none, "Seleccionar o conectar no debe guardar todavía")
        newFixture.transport.emit(.stateChanged(.ready(otherTestDevice)))
        newFixture.transport.emit(.readyForAuthentication)
        expect(newStore.load() == .none, "Enviar el reto PWOK no debe guardar todavía")
        newFixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        expect(newStore.load() == .none, "Autenticar sin completar Sync no debe guardar todavía")
        newFixture.transport.emit(.commandSent(.sync))

        guard let expectedNewRadio = SavedRadio(
            deviceID: otherTestDevice.id,
            name: otherTestDevice.name,
            radioCode: newPassword
        ) else {
            preconditionFailure("No se pudo construir el segundo radio sintético")
        }
        expect(newStore.load() == .record(expectedNewRadio))
        expect(newFixture.controller.savedRadio == expectedNewRadio)
        expect(newFixture.controller.radioCode.isEmpty)
        expect(
            !newFixture.controller.activity.contains { $0.message.contains(newPassword) },
            "El código guardado nunca debe aparecer en actividad"
        )

        newFixture.controller.selectDevice(nil)
        newFixture.controller.selectDevice(otherTestDevice.id)
        expect(newFixture.controller.radioCode == newPassword)
        newFixture.controller.forgetSavedRadio()
        expect(newStore.load() == .none)
        expect(newFixture.controller.savedRadio == nil)
        expect(newFixture.controller.radioCode.isEmpty)
        expect(!newFixture.controller.rememberSelectedRadio)

        let rejectedStorage = MemorySavedRadioStorage()
        let rejectedStore = rejectedStorage.makeStore()
        let rejectedFixture = makeFixture(savedRadioStore: rejectedStore)
        rejectedFixture.controller.startScanning()
        rejectedFixture.transport.emit(.discovered(testDevice))
        rejectedFixture.controller.radioCode = dummyPassword(8)
        rejectedFixture.controller.connectSelectedDevice()
        rejectedFixture.transport.emit(.stateChanged(.ready(testDevice)))
        rejectedFixture.transport.emit(.readyForAuthentication)
        rejectedFixture.transport.emit(.notification(.authentication, Data([0x00])))
        expect(
            rejectedStore.load() == .none,
            "Un código rechazado nunca debe persistirse"
        )
    }

    private static func checkDuplicateRadioNamesRequireExplicitSelection() {
        let duplicate = BluetoothClient.Device(
            id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            name: testDevice.name,
            rssi: -18
        )
        let fixture = makeFixture()
        fixture.controller.startScanning()
        fixture.transport.emit(.discovered(testDevice))
        expect(fixture.controller.selectedDeviceID == testDevice.id)

        fixture.transport.emit(.discovered(duplicate))
        expect(fixture.controller.hasDuplicateDeviceNames)
        expect(fixture.controller.isDeviceNameDuplicated(testDevice))
        expect(fixture.controller.selectedDeviceID == nil)

        fixture.controller.selectDevice(duplicate.id)
        expect(fixture.controller.selectedDeviceID == duplicate.id)
        fixture.transport.emit(.discovered(BluetoothClient.Device(
            id: duplicate.id,
            name: duplicate.name,
            rssi: -17
        )))
        expect(
            fixture.controller.selectedDeviceID == duplicate.id,
            "Una selección explícita por RSSI y UUID no debe borrarse"
        )
        expect(fixture.controller.deviceIdentifierSuffix(duplicate) == "555555")
    }

    private static func checkControlsRequireReadySession() {
        let fixture = makeFixture()
        let initialDraft = fixture.controller.groupDraft(.c).draft
        guard let changedPower = ManualPower.value(decimal: 23) else {
            preconditionFailure("Falta la potencia canónica de prueba")
        }

        expect(
            !fixture.controller.canEdit(.c),
            "Los controles deben permanecer bloqueados antes de conectar el radio"
        )
        expect(
            !fixture.controller.showsControlWorkspace,
            "El primer flujo visible debe ser buscar y conectar, no los controles"
        )
        expect(
            !fixture.controller.canToggleRadioEnabled(.c),
            "El modo activo/off también debe permanecer bloqueado antes de conectar"
        )
        expect(
            !fixture.controller.canChangeOperatingMode(.c),
            "M/Auto también debe permanecer bloqueado antes de conectar"
        )
        expect(
            !fixture.controller.canEditBeep(.c),
            "El beep también debe permanecer bloqueado antes de conectar"
        )
        fixture.controller.setDraftPower(.c, power: changedPower)
        fixture.controller.setDraftModeling(.c, modeling: .off)
        fixture.controller.setDraftBeep(.c, enabled: true)
        fixture.controller.setDraftOperatingMode(.c, mode: .autoTTL)
        fixture.controller.setDraftRadioEnabled(.c, enabled: false)
        expect(
            fixture.controller.groupDraft(.c).draft == initialDraft,
            "Ninguna mutación programática debe alterar el borrador sin sesión lista"
        )

        fixture.controller.startScanning()
        expect(
            !fixture.controller.canEdit(.c),
            "Buscar un radio todavía no debe habilitar los controles"
        )
        expect(
            !fixture.controller.showsControlWorkspace,
            "El flujo de conexión debe permanecer visible durante la búsqueda"
        )

        fixture.transport.emit(.discovered(testDevice))
        fixture.controller.radioCode = dummyPassword(1)
        fixture.controller.connectSelectedDevice()
        expect(
            !fixture.controller.canEdit(.c),
            "Conectar sin completar autenticación y Sync todavía no debe habilitar controles"
        )
        expect(
            !fixture.controller.showsControlWorkspace,
            "El flujo de conexión debe permanecer visible mientras termina el enlace"
        )

        fixture.transport.emit(.stateChanged(.discovering(testDevice)))
        expect(!fixture.controller.canEdit(.c))
        expect(!fixture.controller.showsControlWorkspace)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        expect(!fixture.controller.canEdit(.c))
        fixture.transport.emit(.readyForAuthentication)
        expect(fixture.controller.phase == .authenticating)
        expect(!fixture.controller.canEdit(.c))
        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        expect(fixture.controller.phase == .synchronizing)
        expect(!fixture.controller.canEdit(.c))
        fixture.transport.emit(.commandSent(.sync))

        expect(fixture.controller.phase == .ready)
        expect(
            fixture.controller.showsControlWorkspace,
            "El workspace debe aparecer sólo después de autenticar y sincronizar"
        )
        expect(
            fixture.controller.canEdit(.c),
            "Los controles deben habilitarse después de autenticar y sincronizar el radio"
        )
        expect(fixture.controller.canEditBeep(.c))
        expect(fixture.controller.canToggleRadioEnabled(.c))
        expect(fixture.controller.canChangeOperatingMode(.c))
    }

    private static func checkSilentConnectionRecovers() {
        let fixture = makeFixture()
        prepareConnection(fixture)

        expect(fixture.controller.phase == .connecting)
        expect(fixture.transport.connectCount == 1)

        fixture.scheduler.fire(.connectionSetup)
        expect(fixture.controller.phase == .disconnecting)
        expect(fixture.transport.disconnectCount == 1)
        expect(fixture.controller.connectionRecoveryMessage?.contains("a tiempo") == true)

        fixture.scheduler.fire(.disconnectRecovery)
        expect(fixture.transport.forceResetCount == 1)
        expect(!fixture.controller.phase.isBusy)
        expectFailure(fixture.controller.phase, containing: "a tiempo")
        expect(fixture.controller.radioCode.isEmpty)

        fixture.controller.startScanning()
        fixture.transport.emit(.discovered(testDevice))
        fixture.controller.radioCode = dummyPassword(2)
        fixture.controller.connectSelectedDevice()
        expect(fixture.transport.connectCount == 2)
        expect(fixture.controller.phase == .connecting)
        fixture.controller.cancelConnectionAttempt()
        fixture.scheduler.fire(.disconnectRecovery)
        expect(fixture.controller.phase == .idle)
    }

    private static func checkRejectedPasswordRecoversWithoutCallback() {
        let fixture = makeFixture()
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)

        expect(fixture.controller.phase == .authenticating)
        expect(fixture.transport.authenticationWriteCount == 1)

        fixture.transport.emit(.notification(.authentication, Data([0x00])))
        expect(fixture.controller.phase == .disconnecting)
        expect(fixture.controller.connectionRecoveryMessage?.contains("rechazó") == true)
        expect(fixture.transport.syncWriteCount == 0)
        expect(fixture.transport.controlWriteCount == 0)

        fixture.scheduler.fire(.disconnectRecovery)
        expect(!fixture.controller.phase.isBusy)
        expectFailure(fixture.controller.phase, containing: "rechazó")
        expect(fixture.transport.forceResetCount == 1)

        fixture.controller.startScanning()
        fixture.transport.emit(.discovered(testDevice))
        fixture.controller.radioCode = dummyPassword(3)
        fixture.controller.connectSelectedDevice()
        expect(fixture.transport.connectCount == 2)
        expect(fixture.controller.phase == .connecting)
    }

    private static func checkSilentAuthenticationRecoversWithoutCallback() {
        let fixture = makeFixture()
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)

        expect(fixture.controller.phase == .authenticating)
        fixture.scheduler.fire(.authentication)
        expect(fixture.controller.phase == .disconnecting)
        expect(fixture.controller.connectionRecoveryMessage?.contains("handshake") == true)

        fixture.scheduler.fire(.disconnectRecovery)
        expectFailure(fixture.controller.phase, containing: "handshake")
        expect(!fixture.controller.phase.isBusy)
        expect(fixture.transport.syncWriteCount == 0)
    }

    private static func checkDiscoverySilenceRecovers() {
        let fixture = makeFixture()
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.discovering(testDevice)))
        expect(fixture.controller.phase == .discovering)

        fixture.scheduler.fire(.connectionSetup)
        expect(fixture.controller.phase == .disconnecting)
        fixture.scheduler.fire(.disconnectRecovery)
        expectFailure(fixture.controller.phase, containing: "a tiempo")
        expect(!fixture.controller.phase.isBusy)
    }

    private static func checkScanCanExpireAndBeCancelled() {
        let fixture = makeFixture()

        fixture.controller.startScanning()
        expect(fixture.controller.phase == .scanning)
        expect(fixture.controller.canCancelConnectionAttempt)
        fixture.scheduler.fire(.scan)
        expect(fixture.controller.phase == .idle)
        expect(fixture.transport.stopScanCount == 1)

        fixture.controller.startScanning()
        expect(fixture.controller.phase == .scanning)
        fixture.controller.cancelConnectionAttempt()
        expect(fixture.controller.phase == .idle)
        expect(fixture.transport.stopScanCount == 2)
    }

    private static func prepareConnection(
        _ fixture: (
            controller: GodoxSessionController,
            transport: FakeGodoxSessionTransport,
            scheduler: ManualSessionDeadlineScheduler
        )
    ) {
        fixture.controller.startScanning()
        fixture.transport.emit(.discovered(testDevice))
        fixture.controller.radioCode = dummyPassword(1)
        fixture.controller.connectSelectedDevice()
    }

    private static func completeDefaultWorkspace(
        _ fixture: (
            controller: GodoxSessionController,
            transport: FakeGodoxSessionTransport,
            scheduler: ManualSessionDeadlineScheduler
        )
    ) {
        expect(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b, .c],
            assignedFlashModelIDs: [
                .b: ["ad600pro-ii"],
                .c: ["ad400pro"],
            ]
        ))
        expect(fixture.controller.hasCompletedOnboarding)
        expect(fixture.controller.workingGroups == [.b, .c])
        expect(fixture.controller.workingConfigurationIssue == nil)
    }

    private static func confirmCurrentGroup(
        _ fixture: (
            controller: GodoxSessionController,
            transport: FakeGodoxSessionTransport,
            scheduler: ManualSessionDeadlineScheduler
        )
    ) {
        if fixture.controller.isGlobalControlPending,
           fixture.transport.controlPayloads.last.flatMap({
               SafeGodoxProtocol.globalSnapshot(from: $0)
           }) != nil {
            fixture.transport.emit(.controlWriteStarted)
            fixture.transport.emit(.controlWriteCompleted)
        }
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
    }

    private static func prepareReadyConnection(
        _ fixture: (
            controller: GodoxSessionController,
            transport: FakeGodoxSessionTransport,
            scheduler: ManualSessionDeadlineScheduler
        )
    ) {
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)
        expect(fixture.controller.phase == .authenticating)

        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        expect(fixture.controller.phase == .synchronizing)

        // El fake confirma la entrega de Sync directamente. No espera el delay
        // real ni inicializa CoreBluetooth, pero recorre el mismo state machine.
        fixture.transport.emit(.commandSent(.sync))
        expect(fixture.controller.phase == .ready)
    }

    private static func prepareConfiguredReadyConnection(
        _ fixture: (
            controller: GodoxSessionController,
            transport: FakeGodoxSessionTransport,
            scheduler: ManualSessionDeadlineScheduler
        )
    ) {
        expect(fixture.controller.hasCompletedOnboarding)
        prepareConnection(fixture)
        fixture.transport.emit(.stateChanged(.ready(testDevice)))
        fixture.transport.emit(.readyForAuthentication)
        expect(fixture.controller.phase == .authenticating)

        fixture.transport.emit(.notification(.authentication, validAuthenticationResponse()))
        fixture.transport.emit(.commandSent(.sync))
        expect(fixture.controller.phase == .synchronizing)
        fixture.scheduler.fire(.valueSynchronizationSettle)
        for _ in fixture.controller.workingGroups {
            confirmCurrentGroup(fixture)
        }
        expect(fixture.controller.phase == .ready)
        expect(fixture.controller.pendingCount == 0)
    }

    private static func makeFixture(
        changeDeliveryPreferences initialChangeDeliveryPreferences: ChangeDeliveryPreferences? = nil,
        restorationStore initialRestorationStore: PendingRestorationStore? = nil,
        savedRadioStore initialSavedRadioStore: SavedRadioStore? = nil,
        transmitterProfilePreferences initialTransmitterProfilePreferences: TransmitterProfilePreferences? = nil,
        studioLibraryStore initialStudioLibraryStore: StudioLibraryStore? = nil
    ) -> (
        controller: GodoxSessionController,
        transport: FakeGodoxSessionTransport,
        scheduler: ManualSessionDeadlineScheduler
    ) {
        let transport = FakeGodoxSessionTransport()
        let scheduler = ManualSessionDeadlineScheduler()
        let visibility = LocalGroupPreferences(
            storageKey: "session-recovery-test-visibility",
            readArray: { _ in nil },
            writeIntegers: { _, _ in }
        )
        let restoration = PendingRestorationStore(
            storageKey: "session-recovery-test-restoration",
            readObject: { _ in nil },
            writeData: { _, _ in true },
            removeValue: { _ in true }
        )
        let ephemeralSavedRadioStore = SavedRadioStore(
            storageKey: "session-recovery-test-saved-radio",
            readObject: { _ in nil },
            writeData: { _, _ in true },
            removeValue: { _ in true }
        )
        let ephemeralChangeDeliveryPreferences = ChangeDeliveryPreferences(
            storageKey: "session-recovery-test-change-delivery",
            readString: { _ in nil },
            writeString: { _, _ in }
        )
        var transmitterProfilePreferenceData: Data?
        let ephemeralTransmitterProfilePreferences = TransmitterProfilePreferences(
            storageKey: "session-recovery-test-transmitter-profiles",
            readObject: { _ in transmitterProfilePreferenceData },
            writeData: { data, _ in
                transmitterProfilePreferenceData = data
                return true
            }
        )
        var studioLibraryData: Data?
        let ephemeralStudioLibraryStore = StudioLibraryStore(
            storageKey: "session-recovery-test-studio-library",
            readObject: { _ in studioLibraryData },
            writeData: { data, _ in
                studioLibraryData = data
                return true
            }
        )
        let controller = GodoxSessionController(
            transport: transport,
            deadlineScheduler: scheduler,
            visibilityPreferences: visibility,
            restorationStore: initialRestorationStore ?? restoration,
            savedRadioStore: initialSavedRadioStore ?? ephemeralSavedRadioStore,
            changeDeliveryPreferences: initialChangeDeliveryPreferences
                ?? ephemeralChangeDeliveryPreferences,
            transmitterProfilePreferences: initialTransmitterProfilePreferences
                ?? ephemeralTransmitterProfilePreferences,
            studioLibraryStore: initialStudioLibraryStore ?? ephemeralStudioLibraryStore
        )
        return (controller, transport, scheduler)
    }

    private static func dummyPassword(_ digit: Int) -> String {
        String(repeating: String(digit), count: 6)
    }

    private static func validAuthenticationResponse(now: Date = Date()) -> Data {
        let unixSeconds = Int64(now.timeIntervalSince1970.rounded(.towardZero))
        let secondsSuffix = unixSeconds % 10_000
        let decodedTime = Int((10_000 - secondsSuffix) % 10_000)
        let decodedDigits = String(format: "%04d", decodedTime)

        // Selector 99: el decoder usa offset key[9] + key[9] = 6.
        // La respuesta es sintética, efímera y no contiene el código del radio.
        let encodedDigits = decodedDigits.map { character -> Character in
            guard let digit = character.wholeNumberValue,
                  let scalar = UnicodeScalar(48 + 6 + digit) else {
                preconditionFailure("No se pudo construir la respuesta PWOK sintética")
            }
            return Character(scalar)
        }
        let token = ";" + String(encodedDigits)
        return Data("PWOK,\(token)".utf8)
    }

    private static func expectFailure(_ phase: SessionPhase, containing text: String) {
        guard case .failed(let message) = phase, message.contains(text) else {
            preconditionFailure("Se esperaba un error recuperable que contuviera \(text)")
        }
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Falló una comprobación de recuperación de sesión",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        precondition(condition(), "\(message) [\(file):\(line)]")
    }
}
