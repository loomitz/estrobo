import Foundation

#if canImport(EstroboCore)
import EstroboCore
#endif

/// Metadata catalogue for remembered transmitters.
///
/// Version 3 contains UUID and display name only. Version 2 and version 1 are
/// plaintext import formats: migration stores and reads back every code from the
/// vault before publishing v3, then removes plaintext. Any incomplete step is
/// fail-closed and left retryable.
@MainActor
struct SavedRadioStore: SavedRadioRepository {
    typealias LoadResult = SavedRadioLoadResult

    nonisolated static let defaultStorageKey = "GodoxMacControlPrototype.savedRadios.v3"
    nonisolated static let defaultPlaintextStorageKey = "GodoxMacControlPrototype.savedRadios.v2"
    nonisolated static let defaultLegacyStorageKey = "GodoxMacControlPrototype.savedRadio.v1"

    private struct VersionEnvelope: Decodable {
        let version: Int
    }

    private struct LegacyRecord: Codable {
        let version: Int
        let deviceID: String
        let name: String
        let password: String
    }

    private struct PlaintextRadio: Codable {
        let deviceID: String
        let name: String
        let radioCode: String
    }

    private struct PlaintextRecord: Codable {
        let version: Int
        let radios: [PlaintextRadio]
    }

    private struct StoredMetadata: Codable {
        let deviceID: String
        let name: String

        init(_ radio: SavedRadio) {
            deviceID = radio.deviceID.uuidString
            name = radio.name
        }
    }

    private struct CatalogRecord: Codable {
        let version: Int
        let radios: [StoredMetadata]
    }

    private let storageKey: String
    private let plaintextStorageKey: String?
    private let legacyStorageKey: String?
    private let readObject: (String) -> Any?
    private let writeData: (Data, String) -> Bool
    private let removeValue: (String) -> Bool
    private let vault: RadioCodeVault

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = SavedRadioStore.defaultStorageKey,
        plaintextStorageKey: String? = SavedRadioStore.defaultPlaintextStorageKey,
        legacyStorageKey: String? = SavedRadioStore.defaultLegacyStorageKey,
        vault: RadioCodeVault? = nil
    ) {
        self.storageKey = storageKey
        self.plaintextStorageKey = plaintextStorageKey
        self.legacyStorageKey = legacyStorageKey
        self.vault = vault ?? KeychainRadioCodeVault()
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
        plaintextStorageKey: String? = nil,
        legacyStorageKey: String? = nil,
        vault: RadioCodeVault? = nil,
        readObject: @escaping (String) -> Any?,
        writeData: @escaping (Data, String) -> Bool,
        removeValue: @escaping (String) -> Bool
    ) {
        self.storageKey = storageKey
        self.plaintextStorageKey = plaintextStorageKey
        self.legacyStorageKey = legacyStorageKey
        self.vault = vault ?? InMemoryRadioCodeVault()
        self.readObject = readObject
        self.writeData = writeData
        self.removeValue = removeValue
    }

    func load() -> LoadResult {
        if let object = readObject(storageKey) {
            return load(object, sourceKey: storageKey)
        }

        for key in plaintextKeys where key != storageKey {
            if let object = readObject(key) {
                return load(object, sourceKey: key)
            }
        }
        return .none
    }

    /// Inserts at the end or updates in place without changing stable ordering.
    @discardableResult
    func upsert(_ radio: SavedRadio) -> Bool {
        var radios: [SavedRadio]
        switch load() {
        case .none:
            radios = []
        case .invalid:
            return false
        case .records(let loaded):
            radios = loaded
        }

        let priorCode = vault.read(deviceID: radio.deviceID)
        if case .failed = priorCode { return false }

        if let index = radios.firstIndex(where: { $0.deviceID == radio.deviceID }) {
            radios[index] = radio
        } else {
            radios.append(radio)
        }

        guard vault.store(radio.secureRadioCode, deviceID: radio.deviceID) == .succeeded,
              vault.read(deviceID: radio.deviceID) == .value(radio.secureRadioCode),
              writeCatalog(radios) else {
            rollbackVault(deviceID: radio.deviceID, prior: priorCode)
            return false
        }
        return true
    }

    @discardableResult
    func save(_ radio: SavedRadio) -> Bool {
        upsert(radio)
    }

    @discardableResult
    func remove(deviceID: UUID) -> Bool {
        let radios: [SavedRadio]
        switch load() {
        case .none:
            return true
        case .invalid:
            return false
        case .records(let loaded):
            radios = loaded
        }

        guard let removed = radios.first(where: { $0.deviceID == deviceID }) else {
            return true
        }
        guard vault.remove(deviceID: deviceID) == .succeeded else {
            return false
        }
        guard vault.read(deviceID: deviceID) == .missing else {
            _ = vault.store(removed.secureRadioCode, deviceID: deviceID)
            return false
        }

        let remaining = radios.filter { $0.deviceID != deviceID }
        let catalogChanged = remaining.isEmpty
            ? removeCatalogAndPlaintext()
            : writeCatalog(remaining)
        guard catalogChanged else {
            _ = vault.store(removed.secureRadioCode, deviceID: deviceID)
            return false
        }
        return true
    }

    func clear() -> Bool {
        let radios: [SavedRadio]
        switch load() {
        case .none:
            return removeCatalogAndPlaintext()
        case .invalid:
            return false
        case .records(let loaded):
            radios = loaded
        }

        var removed: [SavedRadio] = []
        for radio in radios {
            guard vault.remove(deviceID: radio.deviceID) == .succeeded else {
                restoreVault(removed)
                return false
            }
            guard vault.read(deviceID: radio.deviceID) == .missing else {
                restoreVault(removed + [radio])
                return false
            }
            removed.append(radio)
        }
        guard removeCatalogAndPlaintext() else {
            restoreVault(removed)
            return false
        }
        return true
    }

    private var plaintextKeys: [String] {
        var keys: [String] = []
        for key in [plaintextStorageKey, legacyStorageKey].compactMap({ $0 })
        where !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    private func load(_ object: Any, sourceKey: String) -> LoadResult {
        guard let data = object as? Data,
              let envelope = try? JSONDecoder().decode(VersionEnvelope.self, from: data) else {
            return .invalid
        }

        switch envelope.version {
        case 3:
            guard sourceKey == storageKey,
                  let metadata = decodeCatalog(data),
                  let radios = hydrate(metadata),
                  removeStalePlaintext(excluding: storageKey) else {
                return .invalid
            }
            return .records(radios)
        case 2:
            guard let radios = decodePlaintext(data) else { return .invalid }
            return migrate(radios, sourceKey: sourceKey)
        case 1:
            guard let radio = decodeLegacy(data) else { return .invalid }
            return migrate([radio], sourceKey: sourceKey)
        default:
            return .invalid
        }
    }

    private func decodeCatalog(_ data: Data) -> [StoredMetadata]? {
        guard let record = try? JSONDecoder().decode(CatalogRecord.self, from: data),
              record.version == 3,
              !record.radios.isEmpty else {
            return nil
        }
        var seen: Set<UUID> = []
        for stored in record.radios {
            guard let id = UUID(uuidString: stored.deviceID),
                  seen.insert(id).inserted,
                  !stored.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
        }
        return record.radios
    }

    private func decodePlaintext(_ data: Data) -> [SavedRadio]? {
        guard let record = try? JSONDecoder().decode(PlaintextRecord.self, from: data),
              record.version == 2,
              !record.radios.isEmpty else {
            return nil
        }
        var seen: Set<UUID> = []
        var radios: [SavedRadio] = []
        for stored in record.radios {
            guard let id = UUID(uuidString: stored.deviceID),
                  seen.insert(id).inserted,
                  let radio = SavedRadio(
                      deviceID: id,
                      name: stored.name,
                      radioCode: stored.radioCode
                  ) else {
                return nil
            }
            radios.append(radio)
        }
        return radios
    }

    private func decodeLegacy(_ data: Data) -> SavedRadio? {
        guard let record = try? JSONDecoder().decode(LegacyRecord.self, from: data),
              record.version == 1,
              let id = UUID(uuidString: record.deviceID) else {
            return nil
        }
        return SavedRadio(deviceID: id, name: record.name, radioCode: record.password)
    }

    private func hydrate(_ metadata: [StoredMetadata]) -> [SavedRadio]? {
        var radios: [SavedRadio] = []
        for stored in metadata {
            guard let id = UUID(uuidString: stored.deviceID),
                  case .value(let code) = vault.read(deviceID: id),
                  let radio = SavedRadio(deviceID: id, name: stored.name, code: code) else {
                return nil
            }
            radios.append(radio)
        }
        return radios
    }

    private func migrate(_ radios: [SavedRadio], sourceKey: String) -> LoadResult {
        // Phase 1: every secret must be present and readable before metadata moves.
        for radio in radios {
            guard vault.store(radio.secureRadioCode, deviceID: radio.deviceID) == .succeeded,
                  vault.read(deviceID: radio.deviceID) == .value(radio.secureRadioCode) else {
                return .invalid
            }
        }

        // Phase 2: publish and byte-verify the metadata-only catalogue.
        guard writeCatalog(radios),
              let catalogData = readObject(storageKey) as? Data,
              let metadata = decodeCatalog(catalogData),
              hydrate(metadata) == radios else {
            return .invalid
        }

        // Phase 3: only an authoritative v3 catalogue may delete plaintext.
        guard removeStalePlaintext(excluding: storageKey) else { return .invalid }
        if sourceKey != storageKey,
           readObject(sourceKey) != nil,
           !removeValue(sourceKey) {
            return .invalid
        }
        return .records(radios)
    }

    private func writeCatalog(_ radios: [SavedRadio]) -> Bool {
        guard !radios.isEmpty else { return removeCatalogAndPlaintext() }
        let record = CatalogRecord(version: 3, radios: radios.map(StoredMetadata.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record),
              writeData(data, storageKey),
              let persisted = readObject(storageKey) as? Data,
              persisted == data else {
            return false
        }
        return true
    }

    private func removeStalePlaintext(excluding excludedKey: String) -> Bool {
        for key in plaintextKeys where key != excludedKey && readObject(key) != nil {
            guard removeValue(key), readObject(key) == nil else { return false }
        }
        return true
    }

    private func removeCatalogAndPlaintext() -> Bool {
        // Remove plaintext first so a failed catalogue removal cannot resurrect it.
        guard removeStalePlaintext(excluding: storageKey) else { return false }
        if readObject(storageKey) != nil {
            guard removeValue(storageKey), readObject(storageKey) == nil else { return false }
        }
        return true
    }

    private func rollbackVault(deviceID: UUID, prior: RadioCodeVaultReadResult) {
        switch prior {
        case .value(let code):
            _ = vault.store(code, deviceID: deviceID)
        case .missing:
            _ = vault.remove(deviceID: deviceID)
        case .failed:
            break
        }
    }

    private func restoreVault(_ radios: [SavedRadio]) {
        for radio in radios {
            _ = vault.store(radio.secureRadioCode, deviceID: radio.deviceID)
        }
    }
}
