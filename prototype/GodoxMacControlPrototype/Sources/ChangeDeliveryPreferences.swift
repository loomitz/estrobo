import Foundation

enum ChangeDeliveryMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic:
            "Automático"
        case .manual:
            "Manual"
        }
    }
}

/// Preferencia local para decidir cuándo se envían los cambios pendientes.
///
/// Un valor ausente o desconocido vuelve al modo automático. Esta preferencia
/// sólo controla la entrega; no representa el estado físico del radio.
struct ChangeDeliveryPreferences {
    static let defaultStorageKey = "GodoxMacControlPrototype.changeDeliveryMode.v1"

    private let storageKey: String
    private let readString: (String) -> String?
    private let writeString: (String, String) -> Void

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = ChangeDeliveryPreferences.defaultStorageKey
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

    func load() -> ChangeDeliveryMode {
        guard let rawValue = readString(storageKey),
              let mode = ChangeDeliveryMode(rawValue: rawValue) else {
            return .automatic
        }
        return mode
    }

    func save(_ mode: ChangeDeliveryMode) {
        writeString(mode.rawValue, storageKey)
    }
}
