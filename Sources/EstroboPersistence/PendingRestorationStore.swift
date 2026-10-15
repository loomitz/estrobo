import Foundation

#if canImport(EstroboCore)
import EstroboCore
#endif

/// Registro local de recuperación. Guarda identidad CoreBluetooth, grupo, los
/// seis bytes mutables del baseline A1 y, cuando existe, el A0 global previo y
/// el modo M/TTL recordado debajo de MULTI u Off; nunca credenciales.
@MainActor
struct PendingRestorationStore: RestorationRepository {
    typealias LoadResult = RestorationLoadResult

    nonisolated static let defaultStorageKey = "GodoxMacControlPrototype.pendingRestoration.v1"

    static var defaultJournalURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("mx.loo.estrobo", isDirectory: true)
            .appendingPathComponent("pending-restoration.json", isDirectory: false)
    }

    private struct PersistedGlobalSnapshot: Codable {
        let beepEnabled: Bool
        let modelingLightEnabled: Bool
        let relativeAdjustmentByte: UInt8
        let multiEnabled: Bool
        let multiCount: UInt8
        let multiHertz: UInt8
        let multiPowerByte: UInt8
        let standbyEnabled: Bool
        let adjustmentCounter: UInt8

        init(_ snapshot: GlobalRadioSnapshot) {
            beepEnabled = snapshot.beepEnabled
            modelingLightEnabled = snapshot.modelingLightEnabled
            relativeAdjustmentByte = snapshot.relativeAdjustmentByte
            multiEnabled = snapshot.multiEnabled
            multiCount = snapshot.multiCount
            multiHertz = snapshot.multiHertz
            multiPowerByte = snapshot.multiPowerByte
            standbyEnabled = snapshot.standbyEnabled
            adjustmentCounter = snapshot.adjustmentCounter
        }

        var snapshot: GlobalRadioSnapshot? {
            guard multiPowerByte <= 100 else { return nil }
            return GlobalRadioSnapshot(
                beepEnabled: beepEnabled,
                modelingLightEnabled: modelingLightEnabled,
                relativeAdjustmentByte: relativeAdjustmentByte,
                multiEnabled: multiEnabled,
                multiCount: multiCount,
                multiHertz: multiHertz,
                multiPowerByte: multiPowerByte,
                standbyEnabled: standbyEnabled,
                adjustmentCounter: adjustmentCounter
            )
        }
    }

    private struct VersionEnvelope: Decodable {
        let version: Int
    }

    /// Forma original. Se conserva exclusivamente para leer journals ya
    /// existentes; toda escritura nueva usa BatchRecord v2.
    private struct LegacyRecord: Codable {
        let version: Int
        let group: UInt8
        let deviceID: String
        let modeByte: UInt8
        let powerByte: UInt8
        let modelingIntensityByte: UInt8
        let beepByte: UInt8
        let modelingModeByte: UInt8
        let compensationByte: UInt8
        let globalSnapshot: PersistedGlobalSnapshot?
        let multiUnderlyingModeByte: UInt8?
        let restoresAfterMulti: Bool?
    }

    private struct PersistedPoint: Codable {
        let group: UInt8
        let deviceID: String
        let modeByte: UInt8
        let powerByte: UInt8
        let modelingIntensityByte: UInt8
        let beepByte: UInt8
        let modelingModeByte: UInt8
        let compensationByte: UInt8
        let globalSnapshot: PersistedGlobalSnapshot?
        let multiUnderlyingModeByte: UInt8?
        let restoresAfterMulti: Bool

        init(group: GodoxGroup, point: GroupRestorationPoint) {
            let snapshot = point.snapshot
            self.group = group.rawValue
            deviceID = point.deviceID.uuidString
            modeByte = snapshot.operatingMode.rawValue
            powerByte = snapshot.power.encodedByte
            modelingIntensityByte = snapshot.modelingState.intensityByte
            beepByte = snapshot.beepByte
            modelingModeByte = snapshot.modelingState.mode.rawValue
            compensationByte = snapshot.compensationByte
            globalSnapshot = point.globalSnapshot.map(PersistedGlobalSnapshot.init)
            multiUnderlyingModeByte = point.multiUnderlyingMode?.rawValue
            restoresAfterMulti = point.restoresAfterMulti
        }

        init(_ record: LegacyRecord) {
            group = record.group
            deviceID = record.deviceID
            modeByte = record.modeByte
            powerByte = record.powerByte
            modelingIntensityByte = record.modelingIntensityByte
            beepByte = record.beepByte
            modelingModeByte = record.modelingModeByte
            compensationByte = record.compensationByte
            globalSnapshot = record.globalSnapshot
            multiUnderlyingModeByte = record.multiUnderlyingModeByte
            restoresAfterMulti = record.restoresAfterMulti ??
                (record.modeByte == GroupOperatingMode.multi.rawValue)
        }
    }

    private struct BatchRecord: Codable {
        let version: Int
        let points: [PersistedPoint]
    }

    private let journal: RestorationJournal
    private let legacyStorageKey: String?
    private let readLegacyObject: ((String) -> Any?)?
    private let removeLegacyValue: ((String) -> Bool)?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = PendingRestorationStore.defaultStorageKey,
        journal: RestorationJournal? = nil
    ) {
        self.journal = journal ?? AtomicFileRestorationJournal(
            fileURL: Self.defaultJournalURL
        )
        legacyStorageKey = storageKey
        readLegacyObject = { defaults.object(forKey: $0) }
        removeLegacyValue = { key in
            defaults.removeObject(forKey: key)
            return defaults.object(forKey: key) == nil
        }
    }

    init(
        storageKey: String,
        readObject: @escaping (String) -> Any?,
        writeData: @escaping (Data, String) -> Bool,
        removeValue: @escaping (String) -> Bool
    ) {
        journal = ClosureRestorationJournal(
            readObject: { readObject(storageKey) },
            writeData: { writeData($0, storageKey) },
            removeValue: { removeValue(storageKey) }
        )
        legacyStorageKey = nil
        readLegacyObject = nil
        removeLegacyValue = nil
    }

    init(
        journal: RestorationJournal,
        legacyStorageKey: String? = nil,
        readLegacyObject: ((String) -> Any?)? = nil,
        removeLegacyValue: ((String) -> Bool)? = nil
    ) {
        self.journal = journal
        self.legacyStorageKey = legacyStorageKey
        self.readLegacyObject = readLegacyObject
        self.removeLegacyValue = removeLegacyValue
    }

    private static func decodePoint(
        _ record: PersistedPoint
    ) -> (group: GodoxGroup, point: GroupRestorationPoint)? {
        guard let group = GodoxGroup(rawValue: record.group),
              let deviceID = UUID(uuidString: record.deviceID),
              let snapshot = ManualGroupSnapshot(
                  modeByte: record.modeByte,
                  powerByte: record.powerByte,
                  modelingIntensityByte: record.modelingIntensityByte,
                  beepByte: record.beepByte,
                  modelingModeByte: record.modelingModeByte,
                  compensationByte: record.compensationByte
              ),
              snapshot.modelingState.isValidForWrite,
              snapshot.operatingMode == .autoTTL ||
                snapshot.operatingMode == .manual ||
                snapshot.operatingMode == .multi ||
                snapshot.operatingMode == .off else {
            return nil
        }
        let globalSnapshot: GlobalRadioSnapshot?
        if let persistedGlobalSnapshot = record.globalSnapshot {
            guard let decodedSnapshot = persistedGlobalSnapshot.snapshot else {
                return nil
            }
            globalSnapshot = decodedSnapshot
        } else {
            globalSnapshot = nil
        }

        let multiUnderlyingMode: GroupOperatingMode?
        if let modeByte = record.multiUnderlyingModeByte {
            guard let decodedMode = GroupOperatingMode(rawValue: modeByte),
                  GroupRestorationPoint.isValidMultiUnderlyingMode(decodedMode) else {
                return nil
            }
            multiUnderlyingMode = decodedMode
        } else {
            multiUnderlyingMode = nil
        }

        guard GroupRestorationPoint.isCoherent(
            snapshot: snapshot,
            globalSnapshot: globalSnapshot,
            multiUnderlyingMode: multiUnderlyingMode,
            restoresAfterMulti: record.restoresAfterMulti
        ) else {
            return nil
        }

        return (
            group: group,
            point: GroupRestorationPoint(
                deviceID: deviceID,
                snapshot: snapshot,
                globalSnapshot: globalSnapshot,
                multiUnderlyingMode: multiUnderlyingMode,
                restoresAfterMulti: record.restoresAfterMulti
            )
        )
    }

    private static func decodeBatch(
        _ records: [PersistedPoint]
    ) -> [GodoxGroup: GroupRestorationPoint]? {
        guard !records.isEmpty else { return nil }
        var points: [GodoxGroup: GroupRestorationPoint] = [:]
        for record in records {
            guard let decoded = decodePoint(record),
                  points[decoded.group] == nil else {
                return nil
            }
            points[decoded.group] = decoded.point
        }
        guard GroupRestorationPoint.isCoherentBatch(points) else { return nil }
        return points
    }

    func load() -> LoadResult {
        switch journal.read() {
        case .failed:
            return .invalid
        case .data(let data):
            guard let decoded = decode(data), removeLegacyIfPresent() else {
                return .invalid
            }
            return decoded
        case .none:
            break
        }

        guard let legacyStorageKey,
              let readLegacyObject,
              let object = readLegacyObject(legacyStorageKey) else {
            return .none
        }
        guard let data = object as? Data,
              let decoded = decode(data),
              journal.replace(with: data) == .committed,
              journal.read() == .data(data),
              decode(data) == decoded,
              removeLegacyIfPresent() else {
            return .invalid
        }
        return decoded
    }

    private func decode(_ data: Data) -> LoadResult? {
        guard let envelope = try? JSONDecoder().decode(
            VersionEnvelope.self,
            from: data
        ) else {
            return nil
        }
        switch envelope.version {
        case 1:
            guard let record = try? JSONDecoder().decode(
                      LegacyRecord.self,
                      from: data
                  ),
                  record.version == 1,
                  let decoded = Self.decodePoint(PersistedPoint(record)) else {
                return nil
            }
            return .record(group: decoded.group, point: decoded.point)
        case 2:
            guard let record = try? JSONDecoder().decode(
                      BatchRecord.self,
                      from: data
                  ),
                  record.version == 2,
                  let points = Self.decodeBatch(record.points) else {
                return nil
            }
            return .batch(points: points)
        default:
            return nil
        }
    }

    func save(group: GodoxGroup, point: GroupRestorationPoint) -> Bool {
        save(points: [group: point])
    }

    func save(points: [GodoxGroup: GroupRestorationPoint]) -> Bool {
        guard GroupRestorationPoint.isCoherentBatch(points),
              points.values.allSatisfy({
                  ($0.globalSnapshot?.multiPowerByte ?? 0) <= 100
              }) else {
            return false
        }
        let persistedPoints = points
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { PersistedPoint(group: $0.key, point: $0.value) }
        let record = BatchRecord(
            version: 2,
            points: persistedPoints
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record) else { return false }
        guard journal.replace(with: data) == .committed,
              journal.read() == .data(data),
              decode(data) != nil,
              removeLegacyIfPresent() else {
            return false
        }
        return true
    }

    func clear() -> Bool {
        guard removeLegacyIfPresent(),
              journal.clear() == .committed,
              journal.read() == .none else {
            return false
        }
        return true
    }

    private func removeLegacyIfPresent() -> Bool {
        guard let legacyStorageKey,
              let readLegacyObject,
              readLegacyObject(legacyStorageKey) != nil else {
            return true
        }
        guard let removeLegacyValue,
              removeLegacyValue(legacyStorageKey),
              readLegacyObject(legacyStorageKey) == nil else {
            return false
        }
        return true
    }
}
