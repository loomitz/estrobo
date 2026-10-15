import Foundation

#if canImport(EstroboCore)
import EstroboCore
#endif

/// Local, non-secret metadata used to resume connection discovery.
///
/// The UUIDs are CoreBluetooth identifiers scoped to this Apple device. Radio
/// credentials remain in `RadioCodeVault`; this store must never contain them.
@MainActor
struct RadioConnectionPreferences: RadioConnectionPreferencesStore {
    typealias State = RadioConnectionPreferenceState

    nonisolated static let defaultStorageKey = "Estrobo.radioConnectionPreferences.v1"

    private static let currentVersion = 1

    private struct Record: Codable {
        let version: Int
        let lastConnectedRadioID: UUID?
        let automaticConnectionRadioID: UUID?
    }

    private let storageKey: String
    private let readObject: (String) -> Any?
    private let writeData: (Data, String) -> Bool

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = RadioConnectionPreferences.defaultStorageKey
    ) {
        self.storageKey = storageKey
        readObject = { defaults.object(forKey: $0) }
        writeData = { data, key in
            defaults.set(data, forKey: key)
            return defaults.data(forKey: key) == data
        }
    }

    init(
        storageKey: String,
        readObject: @escaping (String) -> Any?,
        writeData: @escaping (Data, String) -> Bool
    ) {
        self.storageKey = storageKey
        self.readObject = readObject
        self.writeData = writeData
    }

    func load() -> State {
        guard let data = readObject(storageKey) as? Data,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == Self.currentVersion else {
            return State(
                lastConnectedRadioID: nil,
                automaticConnectionRadioID: nil
            )
        }

        return State(
            lastConnectedRadioID: record.lastConnectedRadioID,
            automaticConnectionRadioID: record.automaticConnectionRadioID
        )
    }

    @discardableResult
    func save(_ state: State) -> Bool {
        let record = Record(
            version: Self.currentVersion,
            lastConnectedRadioID: state.lastConnectedRadioID,
            automaticConnectionRadioID: state.automaticConnectionRadioID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record) else { return false }
        return writeData(data, storageKey)
    }
}
