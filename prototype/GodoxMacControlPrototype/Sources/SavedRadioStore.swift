import Foundation

/// Identidad y código local de un radio que ya completó el handshake.
///
/// El código se conserva como datos locales de `UserDefaults`, sin cifrado,
/// únicamente cuando el usuario activa el opt-in correspondiente. No protege
/// cuentas ni servicios remotos y nunca debe tratarse como una credencial fuerte.
/// Nunca debe incluirse en logs, mensajes de actividad ni diagnósticos.
struct SavedRadio: Equatable, Identifiable {
    let deviceID: UUID
    let name: String
    let radioCode: String

    var id: UUID { deviceID }

    init?(deviceID: UUID, name: String, radioCode: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              Self.isValidRadioCode(radioCode) else {
            return nil
        }

        self.deviceID = deviceID
        self.name = normalizedName
        self.radioCode = radioCode
    }

    static func isValidRadioCode(_ radioCode: String) -> Bool {
        radioCode.count == 6 && radioCode.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }
}

/// Persistencia local de los radios recordados, en orden estable de inserción.
///
/// La versión 2 conserva varios radios y actualiza por UUID sin mover el registro.
/// Al encontrar el singleton v1 lo migra de forma transparente antes de devolverlo.
/// La interfaz mantiene codificación, validación y verificación de escritura fuera
/// del controller de sesión.
struct SavedRadioStore {
    enum LoadResult: Equatable {
        case none
        case records([SavedRadio])
        case invalid
    }

    static let defaultStorageKey = "GodoxMacControlPrototype.savedRadios.v2"
    static let defaultLegacyStorageKey = "GodoxMacControlPrototype.savedRadio.v1"

    private struct LegacyRecord: Codable {
        let version: Int
        let deviceID: String
        let name: String
        let password: String
    }

    private struct StoredRadio: Codable {
        let deviceID: String
        let name: String
        let radioCode: String

        init(_ radio: SavedRadio) {
            deviceID = radio.deviceID.uuidString
            name = radio.name
            radioCode = radio.radioCode
        }
    }

    private struct Record: Codable {
        let version: Int
        let radios: [StoredRadio]
    }

    private let storageKey: String
    private let legacyStorageKey: String?
    private let readObject: (String) -> Any?
    private let writeData: (Data, String) -> Bool
    private let removeValue: (String) -> Bool

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = SavedRadioStore.defaultStorageKey,
        legacyStorageKey: String? = SavedRadioStore.defaultLegacyStorageKey
    ) {
        self.storageKey = storageKey
        self.legacyStorageKey = legacyStorageKey
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
        legacyStorageKey: String? = nil,
        readObject: @escaping (String) -> Any?,
        writeData: @escaping (Data, String) -> Bool,
        removeValue: @escaping (String) -> Bool
    ) {
        self.storageKey = storageKey
        self.legacyStorageKey = legacyStorageKey
        self.readObject = readObject
        self.writeData = writeData
        self.removeValue = removeValue
    }

    func load() -> LoadResult {
        if let object = readObject(storageKey) {
            return load(object, sourceKey: storageKey)
        }

        guard let legacyStorageKey,
              legacyStorageKey != storageKey,
              let object = readObject(legacyStorageKey) else {
            return .none
        }
        return load(object, sourceKey: legacyStorageKey)
    }

    /// Inserta un radio nuevo al final o actualiza el UUID existente sin moverlo.
    @discardableResult
    func upsert(_ radio: SavedRadio) -> Bool {
        var radios: [SavedRadio]
        switch load() {
        case .none:
            radios = []
        case .invalid:
            // No reemplaces bytes que podrían requerir recuperación explícita.
            return false
        case .records(let loaded):
            radios = loaded
        }

        if let index = radios.firstIndex(where: { $0.deviceID == radio.deviceID }) {
            radios[index] = radio
        } else {
            radios.append(radio)
        }
        return write(radios)
    }

    /// Compatibilidad para callers existentes; la semántica ahora es upsert.
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

        guard radios.contains(where: { $0.deviceID == deviceID }) else { return true }
        let remaining = radios.filter { $0.deviceID != deviceID }
        if remaining.isEmpty {
            return removeAllStoredValues()
        }
        return write(remaining)
    }

    func clear() -> Bool {
        removeAllStoredValues()
    }

    private func load(_ object: Any, sourceKey: String) -> LoadResult {
        guard let data = object as? Data else { return .invalid }
        if let radios = decodeCurrentRecord(data) {
            removeLegacyValueIfCurrentRecordIsAuthoritative()
            return .records(radios)
        }
        guard let legacyRadio = decodeLegacyRecord(data) else { return .invalid }

        let radios = [legacyRadio]
        if write(radios), sourceKey != storageKey {
            // Si falla, una carga futura del v2 vuelve a intentar retirar v1.
            _ = removeValue(sourceKey)
        }
        return .records(radios)
    }

    private func decodeCurrentRecord(_ data: Data) -> [SavedRadio]? {
        guard let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == 2,
              !record.radios.isEmpty else {
            return nil
        }

        var seen: Set<UUID> = []
        var radios: [SavedRadio] = []
        for stored in record.radios {
            guard let deviceID = UUID(uuidString: stored.deviceID),
                  seen.insert(deviceID).inserted,
                  let radio = SavedRadio(
                      deviceID: deviceID,
                      name: stored.name,
                      radioCode: stored.radioCode
                  ) else {
                return nil
            }
            radios.append(radio)
        }
        return radios
    }

    private func decodeLegacyRecord(_ data: Data) -> SavedRadio? {
        guard let record = try? JSONDecoder().decode(LegacyRecord.self, from: data),
              record.version == 1,
              let deviceID = UUID(uuidString: record.deviceID) else {
            return nil
        }
        return SavedRadio(
            deviceID: deviceID,
            name: record.name,
            radioCode: record.password
        )
    }

    private func write(_ radios: [SavedRadio]) -> Bool {
        guard !radios.isEmpty else { return removeAllStoredValues() }
        let record = Record(
            version: 2,
            radios: radios.map(StoredRadio.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record) else { return false }
        return writeData(data, storageKey)
    }

    private func removeAllStoredValues() -> Bool {
        if let legacyStorageKey, legacyStorageKey != storageKey {
            // Retira primero el registro que podría resucitar la credencial.
            // Si falla, conserva v2 y deja el borrado como no completado.
            guard removeValue(legacyStorageKey) else { return false }
        }
        return removeValue(storageKey)
    }

    private func removeLegacyValueIfCurrentRecordIsAuthoritative() {
        guard let legacyStorageKey,
              legacyStorageKey != storageKey,
              readObject(legacyStorageKey) != nil else {
            return
        }
        _ = removeValue(legacyStorageKey)
    }
}
