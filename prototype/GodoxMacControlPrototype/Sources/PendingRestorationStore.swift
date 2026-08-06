import Foundation

/// Registro local de recuperación. Guarda sólo identidad CoreBluetooth,
/// grupo y los seis bytes mutables del baseline A1; nunca credenciales.
struct PendingRestorationStore {
    enum LoadResult: Equatable {
        case none
        case record(group: GodoxGroup, point: GroupRestorationPoint)
        case invalid
    }

    static let defaultStorageKey = "GodoxMacControlPrototype.pendingRestoration.v1"

    private struct Record: Codable {
        let version: Int
        let group: UInt8
        let deviceID: String
        let modeByte: UInt8
        let powerByte: UInt8
        let modelingIntensityByte: UInt8
        let beepByte: UInt8
        let modelingModeByte: UInt8
        let compensationByte: UInt8
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

    func load() -> LoadResult {
        guard let object = readObject(storageKey) else { return .none }
        guard let data = object as? Data,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == 1,
              let group = GodoxGroup(rawValue: record.group),
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
                snapshot.operatingMode == .off else {
            return .invalid
        }
        return .record(
            group: group,
            point: GroupRestorationPoint(deviceID: deviceID, snapshot: snapshot)
        )
    }

    func save(group: GodoxGroup, point: GroupRestorationPoint) -> Bool {
        let snapshot = point.snapshot
        let record = Record(
            version: 1,
            group: group.rawValue,
            deviceID: point.deviceID.uuidString,
            modeByte: snapshot.operatingMode.rawValue,
            powerByte: snapshot.power.encodedByte,
            modelingIntensityByte: snapshot.modelingState.intensityByte,
            beepByte: snapshot.beepByte,
            modelingModeByte: snapshot.modelingState.mode.rawValue,
            compensationByte: snapshot.compensationByte
        )
        guard let data = try? JSONEncoder().encode(record) else { return false }
        return writeData(data, storageKey)
    }

    func clear() -> Bool {
        removeValue(storageKey)
    }
}
