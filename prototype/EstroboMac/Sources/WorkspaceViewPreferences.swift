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

/// App-local preference for the active Mac workspace view.
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
