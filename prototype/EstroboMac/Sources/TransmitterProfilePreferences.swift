import Foundation

/// Local availability and default selection for the built-in transmitter
/// profiles. Profiles themselves remain compile-time capability definitions;
/// this preference only hides or restores those definitions on this Mac.
struct TransmitterProfilePreferences {
    struct State: Equatable {
        let availableProfileIDs: [String]
        let defaultProfileID: String
    }

    static let defaultStorageKey = "GodoxMacControlPrototype.transmitterProfiles.v1"

    private static let currentVersion = 1

    private struct Record: Codable {
        let version: Int
        let availableProfileIDs: [String]
        let defaultProfileID: String
    }

    private let storageKey: String
    private let readObject: (String) -> Any?
    private let writeData: (Data, String) -> Bool

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = TransmitterProfilePreferences.defaultStorageKey
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

    func load(
        builtInProfileIDs: [String],
        fallbackDefaultProfileID: String
    ) -> State {
        guard let data = readObject(storageKey) as? Data,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == Self.currentVersion else {
            return Self.normalized(
                availableProfileIDs: builtInProfileIDs,
                defaultProfileID: fallbackDefaultProfileID,
                builtInProfileIDs: builtInProfileIDs,
                fallbackDefaultProfileID: fallbackDefaultProfileID
            )
        }

        return Self.normalized(
            availableProfileIDs: record.availableProfileIDs,
            defaultProfileID: record.defaultProfileID,
            builtInProfileIDs: builtInProfileIDs,
            fallbackDefaultProfileID: fallbackDefaultProfileID
        )
    }

    @discardableResult
    func save(
        _ state: State,
        builtInProfileIDs: [String],
        fallbackDefaultProfileID: String
    ) -> Bool {
        let normalized = Self.normalized(
            availableProfileIDs: state.availableProfileIDs,
            defaultProfileID: state.defaultProfileID,
            builtInProfileIDs: builtInProfileIDs,
            fallbackDefaultProfileID: fallbackDefaultProfileID
        )
        let record = Record(
            version: Self.currentVersion,
            availableProfileIDs: normalized.availableProfileIDs,
            defaultProfileID: normalized.defaultProfileID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record) else { return false }
        return writeData(data, storageKey)
    }

    private static func normalized(
        availableProfileIDs requestedAvailableProfileIDs: [String],
        defaultProfileID requestedDefaultProfileID: String,
        builtInProfileIDs requestedBuiltInProfileIDs: [String],
        fallbackDefaultProfileID requestedFallbackDefaultProfileID: String
    ) -> State {
        let builtInProfileIDs = uniqueNormalizedIDs(requestedBuiltInProfileIDs)
        precondition(!builtInProfileIDs.isEmpty, "At least one built-in transmitter profile is required")

        let requestedAvailable = Set(uniqueNormalizedIDs(requestedAvailableProfileIDs))
        let filteredAvailable = builtInProfileIDs.filter(requestedAvailable.contains)
        let availableProfileIDs = filteredAvailable.isEmpty
            ? builtInProfileIDs
            : filteredAvailable

        let requestedDefaultProfileID = normalizedID(requestedDefaultProfileID)
        let fallbackDefaultProfileID = normalizedID(requestedFallbackDefaultProfileID)
        let defaultProfileID: String
        if availableProfileIDs.contains(requestedDefaultProfileID) {
            defaultProfileID = requestedDefaultProfileID
        } else if availableProfileIDs.contains(fallbackDefaultProfileID) {
            defaultProfileID = fallbackDefaultProfileID
        } else {
            defaultProfileID = availableProfileIDs[0]
        }

        return State(
            availableProfileIDs: availableProfileIDs,
            defaultProfileID: defaultProfileID
        )
    }

    private static func uniqueNormalizedIDs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let normalized = normalizedID(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private static func normalizedID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
