import Foundation

enum PrototypeVariant: String, CaseIterable, Identifiable {
    case channels = "Canales"
    case inspector = "Inspector"
    case matrix = "Matriz"

    var id: String { rawValue }

    var key: String {
        switch self {
        case .channels: "A"
        case .inspector: "B"
        case .matrix: "C"
        }
    }

    var storageValue: String {
        switch self {
        case .channels: "channels"
        case .inspector: "inspector"
        case .matrix: "matrix"
        }
    }

    static func matching(_ value: String) -> PrototypeVariant? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first {
            $0.storageValue == normalized ||
                $0.key.lowercased() == normalized ||
                $0.rawValue.lowercased() == normalized
        }
    }
}

/// Preferencia local de la vista activa del espacio de trabajo.
///
/// El cambio se aplica de inmediato, se conserva para la próxima sesión y no
/// produce ninguna escritura Bluetooth.
struct WorkspaceViewPreferences {
    static let defaultStorageKey = "Estrobo.initialWorkspaceView.v1"

    private let storageKey: String
    private let readString: (String) -> String?
    private let writeString: (String, String) -> Void

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = WorkspaceViewPreferences.defaultStorageKey
    ) {
        self.storageKey = storageKey
        readString = { defaults.string(forKey: $0) }
        writeString = { value, key in defaults.set(value, forKey: key) }
    }

    init(
        storageKey: String,
        readString: @escaping (String) -> String?,
        writeString: @escaping (String, String) -> Void
    ) {
        self.storageKey = storageKey
        self.readString = readString
        self.writeString = writeString
    }

    func load() -> PrototypeVariant {
        readString(storageKey).flatMap(PrototypeVariant.matching) ?? .channels
    }

    func save(_ variant: PrototypeVariant) {
        writeString(variant.storageValue, storageKey)
    }

    func launchVariant(arguments: [String]) -> PrototypeVariant {
        Self.launchOverride(arguments: arguments) ?? load()
    }

    private static func launchOverride(arguments: [String]) -> PrototypeVariant? {
        let requested: String?
        if let index = arguments.firstIndex(of: "--variant"),
           arguments.indices.contains(index + 1) {
            requested = arguments[index + 1]
        } else {
            requested = arguments
                .first(where: { $0.hasPrefix("--variant=") })?
                .dropFirst("--variant=".count)
                .description
        }
        return requested.flatMap(PrototypeVariant.matching)
    }
}

enum SessionPhase: Equatable {
    case idle
    case scanning
    case connecting
    case discovering
    case authenticating
    case synchronizing
    case ready
    case applying
    case disconnecting
    case unavailable(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle: "Sin conexión"
        case .scanning: "Buscando radio…"
        case .connecting: "Conectando…"
        case .discovering: "Preparando enlace…"
        case .authenticating: "Autenticando…"
        case .synchronizing: "Sincronizando…"
        case .ready: "Listo"
        case .applying: "Aplicando…"
        case .disconnecting: "Desconectando…"
        case .unavailable: "Bluetooth no disponible"
        case .failed: "Error de enlace"
        }
    }

    var isBusy: Bool {
        switch self {
        case .scanning, .connecting, .discovering, .authenticating,
             .synchronizing, .applying, .disconnecting:
            true
        default:
            false
        }
    }
}

enum GroupConfirmation: Equatable {
    case unread
    case gattAccepted(Date)
    case radioResponded(Date)
    case failed(String)

    var label: String {
        switch self {
        case .unread: "Sin cambios"
        case .gattAccepted: "Write aceptado"
        case .radioResponded: "Respuesta del radio"
        case .failed: "No aplicado"
        }
    }
}

enum PendingGroupField: String, CaseIterable, Hashable {
    case power = "Potencia"
    case modeling = "Modelado"
    case beep = "Beep"
    case mode = "Modo"
}

/// Estado público y compacto de una tanda de cambios. La implementación de la
/// cola y sus snapshots permanece dentro del controller; la UI sólo necesita
/// conocer el grupo activo, el orden restante y el progreso total.
struct ApplySequenceStatus: Equatable {
    let activeGroup: GodoxGroup
    let remainingGroups: [GodoxGroup]
    let completedCount: Int
    let totalCount: Int

    var currentPosition: Int { completedCount + 1 }
}

enum GlobalPowerLimitCause: Equatable {
    case groups([GodoxGroup])
    case visualWindow
}

struct GlobalPowerConstraint: Equatable {
    let allowedOffsets: ClosedRange<Int>
    let lowerBoundary: GlobalPowerLimitCause
    let upperBoundary: GlobalPowerLimitCause
}

enum GlobalPowerAdjustmentOutcome: Equatable {
    case applied(offsetSteps: Int)
    case limited(offsetSteps: Int, cause: GlobalPowerLimitCause)
    case unavailable

    var appliedOffsetSteps: Int? {
        switch self {
        case .applied(let offsetSteps), .limited(let offsetSteps, _): offsetSteps
        case .unavailable: nil
        }
    }
}

struct GroupDraft: Equatable {
    var baseline: ManualGroupSnapshot
    var draft: ManualGroupSnapshot
    var confirmation: GroupConfirmation = .unread
    var baselineLastKnownActiveMode: GroupOperatingMode?
    var lastKnownActiveMode: GroupOperatingMode?
    var baselineRestoresAfterMulti: Bool
    var draftRestoresAfterMulti: Bool

    init(
        baseline: ManualGroupSnapshot,
        draft: ManualGroupSnapshot,
        confirmation: GroupConfirmation = .unread,
        lastKnownActiveMode: GroupOperatingMode? = nil,
        restoresAfterMulti: Bool = false
    ) {
        self.baseline = baseline
        self.draft = draft
        self.confirmation = confirmation
        if lastKnownActiveMode == .manual || lastKnownActiveMode == .autoTTL {
            baselineLastKnownActiveMode = lastKnownActiveMode
            self.lastKnownActiveMode = lastKnownActiveMode
        } else if baseline.operatingMode == .manual || baseline.operatingMode == .autoTTL {
            baselineLastKnownActiveMode = baseline.operatingMode
            self.lastKnownActiveMode = baseline.operatingMode
        } else {
            baselineLastKnownActiveMode = nil
            self.lastKnownActiveMode = nil
        }
        baselineRestoresAfterMulti = restoresAfterMulti
        draftRestoresAfterMulti = restoresAfterMulti
    }

    var hasPendingChange: Bool { baseline != draft }

    var hasPendingPowerChange: Bool { baseline.power != draft.power }
    var hasPendingModelingChange: Bool { baseline.modelingState != draft.modelingState }
    var hasPendingBeepChange: Bool { baseline.beepEnabled != draft.beepEnabled }
    var hasPendingModeChange: Bool { baseline.operatingMode != draft.operatingMode }

    var pendingFields: Set<PendingGroupField> {
        var result: Set<PendingGroupField> = []
        if hasPendingPowerChange { result.insert(.power) }
        if hasPendingModelingChange { result.insert(.modeling) }
        if hasPendingBeepChange { result.insert(.beep) }
        if hasPendingModeChange { result.insert(.mode) }
        return result
    }

    mutating func discard() {
        draft = baseline
        draftRestoresAfterMulti = baselineRestoresAfterMulti
        lastKnownActiveMode = baselineLastKnownActiveMode
    }
}

struct GroupRestorationPoint: Equatable {
    let deviceID: UUID
    let snapshot: ManualGroupSnapshot
    let globalSnapshot: GlobalRadioSnapshot?
    let multiUnderlyingMode: GroupOperatingMode?
    let restoresAfterMulti: Bool

    init(
        deviceID: UUID,
        snapshot: ManualGroupSnapshot,
        globalSnapshot: GlobalRadioSnapshot? = nil,
        multiUnderlyingMode: GroupOperatingMode? = nil,
        restoresAfterMulti: Bool = false
    ) {
        self.deviceID = deviceID
        self.snapshot = snapshot
        self.globalSnapshot = globalSnapshot
        self.multiUnderlyingMode = multiUnderlyingMode
        self.restoresAfterMulti = restoresAfterMulti
    }

    static func isValidMultiUnderlyingMode(_ mode: GroupOperatingMode?) -> Bool {
        mode == nil || mode == .manual || mode == .autoTTL
    }

    /// MULTI ocupa dos órdenes del protocolo (A0 global y A1 por grupo). Un
    /// diario que sólo conserve la mitad de ese par no puede restaurarse sin
    /// inventar estado, por lo que se rechaza antes de cualquier escritura.
    static func isCoherent(
        snapshot: ManualGroupSnapshot,
        globalSnapshot: GlobalRadioSnapshot?,
        multiUnderlyingMode: GroupOperatingMode?,
        restoresAfterMulti: Bool
    ) -> Bool {
        guard isValidMultiUnderlyingMode(multiUnderlyingMode) else { return false }

        let carriesMultiGroupState = snapshot.operatingMode == .multi ||
            restoresAfterMulti
        if carriesMultiGroupState {
            guard snapshot.operatingMode == .multi || snapshot.operatingMode == .off,
                  globalSnapshot?.multiEnabled == true,
                  multiUnderlyingMode == .manual || multiUnderlyingMode == .autoTTL,
                  let globalSnapshot,
                  MultiFlashSettings(
                      countByte: globalSnapshot.multiCount,
                      hertzByte: globalSnapshot.multiHertz,
                      powerByte: globalSnapshot.multiPowerByte
                  ) != nil else {
                return false
            }
        } else if multiUnderlyingMode != nil && snapshot.operatingMode != .off {
            return false
        }
        return true
    }

    static func isCoherent(_ point: GroupRestorationPoint) -> Bool {
        isCoherent(
            snapshot: point.snapshot,
            globalSnapshot: point.globalSnapshot,
            multiUnderlyingMode: point.multiUnderlyingMode,
            restoresAfterMulti: point.restoresAfterMulti
        )
    }

    /// Una operación física puede abarcar varios A1, pero todos pertenecen al
    /// mismo radio y al mismo A0. Rechazar la tanda completa evita conservar un
    /// journal parcial o mezclar snapshots que no se pueden restaurar juntos.
    static func isCoherentBatch(
        _ points: [GodoxGroup: GroupRestorationPoint]
    ) -> Bool {
        guard let firstPoint = points.values.first else { return false }
        return points.values.allSatisfy { point in
            point.deviceID == firstPoint.deviceID &&
                point.globalSnapshot == firstPoint.globalSnapshot &&
                isCoherent(point)
        }
    }
}

struct PhysicalOperationSafetyState: Equatable {
    private(set) var restorationPoints: [GodoxGroup: GroupRestorationPoint] = [:]
    private(set) var preparedRestorations: Set<GodoxGroup> = []

    var allowsNewEdits: Bool { restorationPoints.isEmpty }

    func permitsConnection(to deviceID: UUID) -> Bool {
        guard let required = restorationPoints.values.first?.deviceID else { return true }
        return restorationPoints.values.allSatisfy { $0.deviceID == required } &&
            required == deviceID
    }

    mutating func begin(
        group: GodoxGroup,
        deviceID: UUID,
        baseline: ManualGroupSnapshot,
        globalSnapshot: GlobalRadioSnapshot? = nil,
        multiUnderlyingMode: GroupOperatingMode? = nil,
        restoresAfterMulti: Bool = false
    ) -> Bool {
        let point = GroupRestorationPoint(
            deviceID: deviceID,
            snapshot: baseline,
            globalSnapshot: globalSnapshot,
            multiUnderlyingMode: multiUnderlyingMode,
            restoresAfterMulti: restoresAfterMulti
        )
        return begin(points: [group: point])
    }

    mutating func begin(
        points: [GodoxGroup: GroupRestorationPoint]
    ) -> Bool {
        guard GroupRestorationPoint.isCoherentBatch(points) else { return false }
        if restorationPoints.isEmpty {
            restorationPoints = points
            preparedRestorations.removeAll()
            return true
        }
        return restorationPoints == points
    }

    mutating func prepareRestoration(for group: GodoxGroup) -> ManualGroupSnapshot? {
        guard let point = restorationPoints[group] else { return nil }
        preparedRestorations = Set(restorationPoints.keys)
        return point.snapshot
    }

    mutating func cancelUnsentOperation(
        group: GodoxGroup,
        deviceID: UUID,
        baseline: ManualGroupSnapshot,
        globalSnapshot: GlobalRadioSnapshot? = nil,
        multiUnderlyingMode: GroupOperatingMode? = nil,
        restoresAfterMulti: Bool = false
    ) -> Bool {
        cancelUnsentOperation(points: [
            group: GroupRestorationPoint(
                deviceID: deviceID,
                snapshot: baseline,
                globalSnapshot: globalSnapshot,
                multiUnderlyingMode: multiUnderlyingMode,
                restoresAfterMulti: restoresAfterMulti
            ),
        ])
    }

    mutating func cancelUnsentOperation(
        points: [GodoxGroup: GroupRestorationPoint]
    ) -> Bool {
        guard GroupRestorationPoint.isCoherentBatch(points),
              restorationPoints == points,
              preparedRestorations.isEmpty else {
            return false
        }
        restorationPoints.removeAll()
        return true
    }

    func permitsOnlyExactRestoration(
        group: GodoxGroup,
        deviceID: UUID,
        snapshot: ManualGroupSnapshot
    ) -> Bool {
        guard !restorationPoints.isEmpty,
              let point = restorationPoints[group] else {
            return false
        }
        return point.deviceID == deviceID && point.snapshot == snapshot
    }

    mutating func completeRestoration(
        group: GodoxGroup,
        deviceID: UUID,
        snapshot: ManualGroupSnapshot
    ) -> Bool {
        guard restorationPoints.count == 1,
              permitsOnlyExactRestoration(
            group: group,
            deviceID: deviceID,
            snapshot: snapshot
        ) else {
            return false
        }
        restorationPoints[group] = nil
        preparedRestorations.remove(group)
        return true
    }

    /// Cierra la recuperación sólo después de que todos los A1 del journal se
    /// prepararon. La verificación exacta de cada A1 se realiza por grupo con
    /// `permitsOnlyExactRestoration` antes de confirmar la tanda.
    mutating func completeRestoration(deviceID: UUID) -> Bool {
        let groups = Set(restorationPoints.keys)
        guard !groups.isEmpty,
              preparedRestorations == groups,
              restorationPoints.values.allSatisfy({ $0.deviceID == deviceID }) else {
            return false
        }
        restorationPoints.removeAll()
        preparedRestorations.removeAll()
        return true
    }

    /// Cierra el punto de recuperación después de que el write del nuevo
    /// ajuste recibió acuse GATT y respuesta FEC8 en la misma sesión/radio.
    /// El snapshot anterior sólo se conserva mientras el resultado es incierto.
    mutating func completeSuccessfulOperation(
        group: GodoxGroup,
        deviceID: UUID
    ) -> Bool {
        guard restorationPoints.count == 1,
              restorationPoints[group]?.deviceID == deviceID else {
            return false
        }
        restorationPoints.removeAll()
        preparedRestorations.removeAll()
        return true
    }

    /// Cierra atómicamente el journal después de confirmar todos los writes de
    /// la nueva tanda. Un journal ya preparado pertenece al flujo de recovery.
    mutating func completeSuccessfulOperation(deviceID: UUID) -> Bool {
        guard !restorationPoints.isEmpty,
              preparedRestorations.isEmpty,
              restorationPoints.values.allSatisfy({ $0.deviceID == deviceID }) else {
            return false
        }
        restorationPoints.removeAll()
        preparedRestorations.removeAll()
        return true
    }
}

enum ActivityLevel {
    case info
    case success
    case warning
    case error
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let date = Date()
    let level: ActivityLevel
    let message: String
}
