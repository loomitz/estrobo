import Foundation

public enum ChangeDeliveryMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case manual

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .automatic:
            "Automático"
        case .manual:
            "Manual"
        }
    }
}

public struct TransmitterProfilePreferenceState: Equatable, Sendable {
    public let availableProfileIDs: [String]
    public let defaultProfileID: String

    public init(availableProfileIDs: [String], defaultProfileID: String) {
        self.availableProfileIDs = availableProfileIDs
        self.defaultProfileID = defaultProfileID
    }
}

public enum SavedRadioLoadResult: Equatable, Sendable {
    case none
    case records([SavedRadio])
    case invalid
}

public enum RestorationLoadResult: Equatable, Sendable {
    case none
    case record(group: GodoxGroup, point: GroupRestorationPoint)
    case batch(points: [GodoxGroup: GroupRestorationPoint])
    case invalid
}

public enum StudioLibraryLoadResult: Equatable, Sendable {
    case none
    case record(StudioLibrary)
    case invalid
}

@MainActor
public protocol SavedRadioRepository {
    func load() -> SavedRadioLoadResult
    @discardableResult func upsert(_ radio: SavedRadio) -> Bool
    @discardableResult func remove(deviceID: UUID) -> Bool
    @discardableResult func clear() -> Bool
}

@MainActor
public protocol RestorationRepository {
    func load() -> RestorationLoadResult
    @discardableResult func save(points: [GodoxGroup: GroupRestorationPoint]) -> Bool
    @discardableResult func clear() -> Bool
}

public extension RestorationRepository {
    @discardableResult
    func save(group: GodoxGroup, point: GroupRestorationPoint) -> Bool {
        save(points: [group: point])
    }
}

@MainActor
public protocol StudioLibraryRepository {
    func load() -> StudioLibraryLoadResult
    @discardableResult func save(_ library: StudioLibrary) -> Bool
}

@MainActor
public protocol GroupVisibilityPreferencesStore {
    func loadVisibleGroups(
        supportedGroups: [GodoxGroup],
        defaultVisibleGroups: [GodoxGroup]?
    ) -> [GodoxGroup]

    @discardableResult
    func saveVisibleGroups(
        _ visibleGroups: [GodoxGroup],
        supportedGroups: [GodoxGroup]
    ) -> [GodoxGroup]
}

@MainActor
public protocol ChangeDeliveryPreferencesStore {
    func load() -> ChangeDeliveryMode
    func save(_ mode: ChangeDeliveryMode)
}

@MainActor
public protocol TransmitterProfilePreferencesStore {
    func load(
        builtInProfileIDs: [String],
        fallbackDefaultProfileID: String
    ) -> TransmitterProfilePreferenceState

    @discardableResult
    func save(
        _ state: TransmitterProfilePreferenceState,
        builtInProfileIDs: [String],
        fallbackDefaultProfileID: String
    ) -> Bool
}
