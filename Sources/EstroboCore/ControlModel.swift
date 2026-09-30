import Foundation

public enum SessionPhase: Equatable, Sendable {
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

    public var title: String {
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

    public var isBusy: Bool {
        switch self {
        case .scanning, .connecting, .discovering, .authenticating,
             .synchronizing, .applying, .disconnecting:
            true
        default:
            false
        }
    }
}

public enum GroupConfirmation: Equatable, Sendable {
    case unread
    case gattAccepted(Date)
    case radioResponded(Date)
    case failed(String)

    public var label: String {
        switch self {
        case .unread: "Sin cambios"
        case .gattAccepted: "Write aceptado"
        case .radioResponded: "Respuesta del radio"
        case .failed: "No aplicado"
        }
    }
}

public enum PendingGroupField: String, CaseIterable, Hashable, Sendable {
    case power = "Potencia"
    case modeling = "Modelado"
    case beep = "Beep"
    case mode = "Modo"
}

/// Estado público y compacto de una tanda de cambios. La implementación de la
/// cola y sus snapshots permanece dentro del controller; la UI sólo necesita
/// conocer el grupo activo, el orden restante y el progreso total.
public struct ApplySequenceStatus: Equatable, Sendable {
    public let activeGroup: GodoxGroup
    public let remainingGroups: [GodoxGroup]
    public let completedCount: Int
    public let totalCount: Int

    public var currentPosition: Int { completedCount + 1 }

    public init(
        activeGroup: GodoxGroup,
        remainingGroups: [GodoxGroup],
        completedCount: Int,
        totalCount: Int
    ) {
        self.activeGroup = activeGroup
        self.remainingGroups = remainingGroups
        self.completedCount = completedCount
        self.totalCount = totalCount
    }
}

public enum GlobalPowerLimitCause: Equatable, Sendable {
    case groups([GodoxGroup])
    case visualWindow
}

public struct GlobalPowerConstraint: Equatable, Sendable {
    public let allowedOffsets: ClosedRange<Int>
    public let lowerBoundary: GlobalPowerLimitCause
    public let upperBoundary: GlobalPowerLimitCause

    public init(
        allowedOffsets: ClosedRange<Int>,
        lowerBoundary: GlobalPowerLimitCause,
        upperBoundary: GlobalPowerLimitCause
    ) {
        self.allowedOffsets = allowedOffsets
        self.lowerBoundary = lowerBoundary
        self.upperBoundary = upperBoundary
    }
}

public enum GlobalPowerAdjustmentOutcome: Equatable, Sendable {
    case applied(offsetSteps: Int)
    case limited(offsetSteps: Int, cause: GlobalPowerLimitCause)
    case unavailable

    public var appliedOffsetSteps: Int? {
        switch self {
        case .applied(let offsetSteps), .limited(let offsetSteps, _): offsetSteps
        case .unavailable: nil
        }
    }
}

public struct GroupDraft: Equatable, Sendable {
    public var baseline: ManualGroupSnapshot
    public var draft: ManualGroupSnapshot
    public var confirmation: GroupConfirmation = .unread
    public var baselineLastKnownActiveMode: GroupOperatingMode?
    public var lastKnownActiveMode: GroupOperatingMode?
    public var baselineRestoresAfterMulti: Bool
    public var draftRestoresAfterMulti: Bool

    public init(
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

    public var hasPendingChange: Bool { baseline != draft }

    public var hasPendingPowerChange: Bool { baseline.power != draft.power }
    public var hasPendingModelingChange: Bool { baseline.modelingState != draft.modelingState }
    public var hasPendingBeepChange: Bool { baseline.beepEnabled != draft.beepEnabled }
    public var hasPendingModeChange: Bool { baseline.operatingMode != draft.operatingMode }

    public var pendingFields: Set<PendingGroupField> {
        var result: Set<PendingGroupField> = []
        if hasPendingPowerChange { result.insert(.power) }
        if hasPendingModelingChange { result.insert(.modeling) }
        if hasPendingBeepChange { result.insert(.beep) }
        if hasPendingModeChange { result.insert(.mode) }
        return result
    }

    public mutating func discard() {
        draft = baseline
        draftRestoresAfterMulti = baselineRestoresAfterMulti
        lastKnownActiveMode = baselineLastKnownActiveMode
    }
}

public struct GroupRestorationPoint: Equatable, Sendable {
    public let deviceID: UUID
    public let snapshot: ManualGroupSnapshot
    public let globalSnapshot: GlobalRadioSnapshot?
    public let multiUnderlyingMode: GroupOperatingMode?
    public let restoresAfterMulti: Bool

    public init(
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

    public static func isValidMultiUnderlyingMode(_ mode: GroupOperatingMode?) -> Bool {
        mode == nil || mode == .manual || mode == .autoTTL
    }

    /// MULTI ocupa dos órdenes del protocolo (A0 global y A1 por grupo). Un
    /// diario que sólo conserve la mitad de ese par no puede restaurarse sin
    /// inventar estado, por lo que se rechaza antes de cualquier escritura.
    public static func isCoherent(
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

    public static func isCoherent(_ point: GroupRestorationPoint) -> Bool {
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
    public static func isCoherentBatch(
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

public struct PhysicalOperationSafetyState: Equatable, Sendable {
    public private(set) var restorationPoints: [GodoxGroup: GroupRestorationPoint] = [:]
    public private(set) var preparedRestorations: Set<GodoxGroup> = []

    public init() {}

    public var allowsNewEdits: Bool { restorationPoints.isEmpty }

    public func permitsConnection(to deviceID: UUID) -> Bool {
        guard let required = restorationPoints.values.first?.deviceID else { return true }
        return restorationPoints.values.allSatisfy { $0.deviceID == required } &&
            required == deviceID
    }

    public mutating func begin(
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

    public mutating func begin(
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

    public mutating func prepareRestoration(for group: GodoxGroup) -> ManualGroupSnapshot? {
        guard let point = restorationPoints[group] else { return nil }
        preparedRestorations = Set(restorationPoints.keys)
        return point.snapshot
    }

    public mutating func cancelUnsentOperation(
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

    public mutating func cancelUnsentOperation(
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

    public func permitsOnlyExactRestoration(
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

    public mutating func completeRestoration(
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
    public mutating func completeRestoration(deviceID: UUID) -> Bool {
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
    public mutating func completeSuccessfulOperation(
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
    public mutating func completeSuccessfulOperation(deviceID: UUID) -> Bool {
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

public enum ActivityLevel: Sendable {
    case info
    case success
    case warning
    case error
}

public struct ActivityItem: Identifiable, Sendable {
    public let id = UUID()
    public let date = Date()
    public let level: ActivityLevel
    public let message: String

    public init(level: ActivityLevel, message: String) {
        self.level = level
        self.message = message
    }
}
