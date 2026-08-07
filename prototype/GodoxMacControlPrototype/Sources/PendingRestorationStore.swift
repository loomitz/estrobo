import Foundation

/// Registro local de recuperación. Guarda identidad CoreBluetooth, grupo, los
/// seis bytes mutables del baseline A1 y, cuando existe, el A0 global previo y
/// el modo M/TTL recordado debajo de MULTI u Off; nunca credenciales.
struct PendingRestorationStore {
    enum LoadResult: Equatable {
        case none
        case record(group: GodoxGroup, point: GroupRestorationPoint)
        case batch(points: [GodoxGroup: GroupRestorationPoint])
        case invalid
    }

    static let defaultStorageKey = "GodoxMacControlPrototype.pendingRestoration.v1"

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

    private let storageKey: String
    private let readObject: (String) -> Any?
    private let writeData: (Data, String) -> Bool
    private let removeValue: (String) -> Bool

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = PendingRestorationStore.defaultStorageKey
    ) {
        self.storageKey = storageKey
        readObject = { defaults.object(forKey: $0) }
        writeData = { data, key in
            defaults.set(data, forKey: key)
            return defaults.data(forKey: key) == data
        }
        removeValue = { key in
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
        self.storageKey = storageKey
        self.readObject = readObject
        self.writeData = writeData
        self.removeValue = removeValue
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
        guard let object = readObject(storageKey) else { return .none }
        guard let data = object as? Data,
              let envelope = try? JSONDecoder().decode(
                  VersionEnvelope.self,
                  from: data
              ) else {
            return .invalid
        }

        switch envelope.version {
        case 1:
            guard let record = try? JSONDecoder().decode(
                      LegacyRecord.self,
                      from: data
                  ),
                  record.version == 1,
                  let decoded = Self.decodePoint(PersistedPoint(record)) else {
                return .invalid
            }
            return .record(group: decoded.group, point: decoded.point)
        case 2:
            guard let record = try? JSONDecoder().decode(
                      BatchRecord.self,
                      from: data
                  ),
                  record.version == 2,
                  let points = Self.decodeBatch(record.points) else {
                return .invalid
            }
            return .batch(points: points)
        default:
            return .invalid
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
        return writeData(data, storageKey)
    }

    func clear() -> Bool {
        removeValue(storageKey)
    }
}
