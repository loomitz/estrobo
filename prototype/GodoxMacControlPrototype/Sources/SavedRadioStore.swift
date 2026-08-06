import Foundation

/// Identidad y código local de un radio que ya completó el handshake.
///
/// El código se conserva como datos locales de `UserDefaults`, sin cifrado,
/// únicamente cuando el usuario activa el opt-in correspondiente. No protege
/// cuentas ni servicios remotos y nunca debe tratarse como una credencial fuerte.
/// Nunca debe incluirse en logs, mensajes de actividad ni diagnósticos.
struct SavedRadio: Equatable {
    let deviceID: UUID
    let name: String
    let radioCode: String

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

/// Persistencia local de un único radio recordado.
///
/// Guardar reemplaza el registro anterior. La interfaz mantiene la codificación,
/// validación y verificación de escritura fuera del controller de sesión.
struct SavedRadioStore {
    enum LoadResult: Equatable {
        case none
        case record(SavedRadio)
        case invalid
    }

    static let defaultStorageKey = "GodoxMacControlPrototype.savedRadio.v1"

    private struct Record: Codable {
        let version: Int
        let deviceID: String
        let name: String
        let password: String
    }

    private let storageKey: String
    private let readObject: (String) -> Any?
    private let writeData: (Data, String) -> Bool
    private let removeValue: (String) -> Bool

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = SavedRadioStore.defaultStorageKey
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
              let deviceID = UUID(uuidString: record.deviceID),
              let radio = SavedRadio(
                  deviceID: deviceID,
                  name: record.name,
                  radioCode: record.password
              ) else {
            return .invalid
        }
        return .record(radio)
    }

    func save(_ radio: SavedRadio) -> Bool {
        let record = Record(
            version: 1,
            deviceID: radio.deviceID.uuidString,
            name: radio.name,
            password: radio.radioCode
        )
        guard let data = try? JSONEncoder().encode(record) else { return false }
        return writeData(data, storageKey)
    }

    func clear() -> Bool {
        removeValue(storageKey)
    }
}
