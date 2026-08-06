import Foundation

/// A complete, locally authoritative value for one group in the active studio.
///
/// The snapshot contains the six mutable A1 fields. Flash model identifiers are
/// kept beside it because they determine whether that snapshot is valid for a
/// particular studio configuration, but they are never sent to the radio.
struct StudioWorkspaceGroup: Equatable {
    let snapshot: ManualGroupSnapshot
    let assignedFlashModelIDs: Set<String>

    init?(
        snapshot: ManualGroupSnapshot,
        assignedFlashModelIDs: Set<String>
    ) {
        guard StudioLibraryValidation.isValid(snapshot: snapshot) else { return nil }

        var normalizedModelIDs: Set<String> = []
        for modelID in assignedFlashModelIDs {
            let normalized = StudioLibraryValidation.normalized(modelID)
            guard !normalized.isEmpty else { return nil }
            normalizedModelIDs.insert(normalized)
        }

        self.snapshot = snapshot
        self.assignedFlashModelIDs = normalizedModelIDs
    }
}

/// The app-side source of truth used by onboarding and connection sync.
///
/// `workingGroups` defines which groups estrobo is allowed to manage. It is
/// intentionally distinct from `visibleGroups`, which only controls local UI.
/// Every working group must have one complete A1 snapshot and model assignment
/// entry. A completed onboarding must retain at least one working and visible
/// group.
struct StudioWorkspace: Equatable {
    let onboardingCompleted: Bool
    let profileID: String
    let workingGroups: [GodoxGroup]
    let visibleGroups: [GodoxGroup]
    let groupConfigurations: [GodoxGroup: StudioWorkspaceGroup]

    init?(
        onboardingCompleted: Bool,
        profileID: String,
        workingGroups: [GodoxGroup],
        visibleGroups: [GodoxGroup],
        groupConfigurations: [GodoxGroup: StudioWorkspaceGroup]
    ) {
        let normalizedProfileID = StudioLibraryValidation.normalized(profileID)
        guard !normalizedProfileID.isEmpty,
              StudioLibraryValidation.hasUniqueGroups(workingGroups),
              StudioLibraryValidation.hasUniqueGroups(visibleGroups) else {
            return nil
        }

        let workingSet = Set(workingGroups)
        let visibleSet = Set(visibleGroups)
        guard visibleSet.isSubset(of: workingSet),
              Set(groupConfigurations.keys) == workingSet else {
            return nil
        }
        if onboardingCompleted && (workingGroups.isEmpty || visibleGroups.isEmpty) {
            return nil
        }

        self.onboardingCompleted = onboardingCompleted
        self.profileID = normalizedProfileID
        self.workingGroups = workingGroups
        self.visibleGroups = visibleGroups
        self.groupConfigurations = groupConfigurations
    }
}

/// A named, device-independent collection of desired A1 values.
///
/// A preset deliberately contains no radio identifier or credential. Its UUID
/// identifies only this local preset. Loading a preset therefore requires the
/// caller to validate it against the active workspace before sending anything.
struct StudioPreset: Equatable, Identifiable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let profileID: String
    let groups: [GodoxGroup]
    let states: [GodoxGroup: ManualGroupSnapshot]

    init?(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        profileID: String,
        groups: [GodoxGroup],
        states: [GodoxGroup: ManualGroupSnapshot]
    ) {
        let normalizedName = StudioLibraryValidation.normalized(name)
        let normalizedProfileID = StudioLibraryValidation.normalized(profileID)
        let resolvedUpdatedAt = updatedAt ?? createdAt
        guard !normalizedName.isEmpty,
              !normalizedProfileID.isEmpty,
              createdAt.timeIntervalSince1970.isFinite,
              resolvedUpdatedAt.timeIntervalSince1970.isFinite,
              createdAt <= resolvedUpdatedAt,
              !groups.isEmpty,
              StudioLibraryValidation.hasUniqueGroups(groups),
              Set(states.keys) == Set(groups),
              states.values.allSatisfy({
                  StudioLibraryValidation.isValid(snapshot: $0)
              }) else {
            return nil
        }

        self.id = id
        self.name = normalizedName
        self.createdAt = createdAt
        self.updatedAt = resolvedUpdatedAt
        self.profileID = normalizedProfileID
        self.groups = groups
        self.states = states
    }
}

/// The single durable document owned by `StudioLibraryStore`.
struct StudioLibrary: Equatable {
    let workspace: StudioWorkspace
    let presets: [StudioPreset]

    init?(workspace: StudioWorkspace, presets: [StudioPreset]) {
        guard Set(presets.map(\.id)).count == presets.count else { return nil }
        self.workspace = workspace
        self.presets = presets
    }
}

/// Versioned JSON persistence for the active workspace and named presets.
///
/// Its external interface is deliberately limited to `load()` and `save(_:)`.
/// Production uses `UserDefaults`; tests can inject read/write closures without
/// exposing any persisted record type to callers.
struct StudioLibraryStore {
    enum LoadResult: Equatable {
        case none
        case record(StudioLibrary)
        case invalid
    }

    static let defaultStorageKey = "GodoxMacControlPrototype.studioLibrary.v1"

    private static let currentVersion = 1

    private struct PersistedLibrary: Codable {
        let version: Int
        let workspace: PersistedWorkspace
        let presets: [PersistedPreset]
    }

    private struct PersistedWorkspace: Codable {
        let onboardingCompleted: Bool
        let profileID: String
        let workingGroups: [UInt8]
        let visibleGroups: [UInt8]
        let groupStates: [PersistedWorkspaceGroup]
    }

    private struct PersistedWorkspaceGroup: Codable {
        let group: UInt8
        let assignedFlashModelIDs: [String]
        let state: PersistedA1State
    }

    private struct PersistedPreset: Codable {
        let id: String
        let name: String
        let createdAt: Double
        let updatedAt: Double
        let profileID: String
        let groups: [UInt8]
        let states: [PersistedPresetState]
    }

    private struct PersistedPresetState: Codable {
        let group: UInt8
        let state: PersistedA1State
    }

    /// Primitive representation of the six mutable A1 bytes. No current domain
    /// type needs to adopt `Codable`; decode always crosses its validating init.
    private struct PersistedA1State: Codable {
        let modeByte: UInt8
        let powerByte: UInt8
        let modelingIntensityByte: UInt8
        let beepByte: UInt8
        let modelingModeByte: UInt8
        let compensationByte: UInt8

        init?(snapshot: ManualGroupSnapshot) {
            guard StudioLibraryValidation.isValid(snapshot: snapshot) else { return nil }
            modeByte = snapshot.operatingMode.rawValue
            powerByte = snapshot.power.encodedByte
            modelingIntensityByte = snapshot.modelingState.intensityByte
            beepByte = snapshot.beepByte
            modelingModeByte = snapshot.modelingState.mode.rawValue
            compensationByte = snapshot.compensationByte
        }

        func snapshot() -> ManualGroupSnapshot? {
            guard let snapshot = ManualGroupSnapshot(
                modeByte: modeByte,
                powerByte: powerByte,
                modelingIntensityByte: modelingIntensityByte,
                beepByte: beepByte,
                modelingModeByte: modelingModeByte,
                compensationByte: compensationByte
            ), StudioLibraryValidation.isValid(snapshot: snapshot) else {
                return nil
            }
            return snapshot
        }
    }

    private let storageKey: String
    private let readObject: (String) -> Any?
    private let writeData: (Data, String) -> Bool

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = StudioLibraryStore.defaultStorageKey
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

    func load() -> LoadResult {
        guard let object = readObject(storageKey) else { return .none }
        guard let data = object as? Data,
              let persisted = try? JSONDecoder().decode(PersistedLibrary.self, from: data),
              persisted.version == Self.currentVersion,
              let library = Self.library(from: persisted) else {
            return .invalid
        }
        return .record(library)
    }

    @discardableResult
    func save(_ library: StudioLibrary) -> Bool {
        guard let persisted = Self.persistedLibrary(from: library) else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(persisted) else { return false }
        return writeData(data, storageKey)
    }

    private static func library(from persisted: PersistedLibrary) -> StudioLibrary? {
        guard let workspace = workspace(from: persisted.workspace) else { return nil }
        var presets: [StudioPreset] = []
        var seenPresetIDs: Set<UUID> = []
        for record in persisted.presets {
            guard let preset = preset(from: record),
                  seenPresetIDs.insert(preset.id).inserted else {
                return nil
            }
            presets.append(preset)
        }
        return StudioLibrary(workspace: workspace, presets: presets)
    }

    private static func workspace(from persisted: PersistedWorkspace) -> StudioWorkspace? {
        guard let workingGroups = decodedGroups(persisted.workingGroups),
              let visibleGroups = decodedGroups(persisted.visibleGroups) else {
            return nil
        }

        var configurations: [GodoxGroup: StudioWorkspaceGroup] = [:]
        for record in persisted.groupStates {
            guard let group = GodoxGroup(rawValue: record.group),
                  configurations[group] == nil,
                  let snapshot = record.state.snapshot(),
                  let configuration = StudioWorkspaceGroup(
                      snapshot: snapshot,
                      assignedFlashModelIDs: Set(record.assignedFlashModelIDs)
                  ) else {
                return nil
            }
            configurations[group] = configuration
        }

        return StudioWorkspace(
            onboardingCompleted: persisted.onboardingCompleted,
            profileID: persisted.profileID,
            workingGroups: workingGroups,
            visibleGroups: visibleGroups,
            groupConfigurations: configurations
        )
    }

    private static func preset(from persisted: PersistedPreset) -> StudioPreset? {
        guard let id = UUID(uuidString: persisted.id),
              let groups = decodedGroups(persisted.groups),
              persisted.createdAt.isFinite,
              persisted.updatedAt.isFinite else {
            return nil
        }

        var states: [GodoxGroup: ManualGroupSnapshot] = [:]
        for record in persisted.states {
            guard let group = GodoxGroup(rawValue: record.group),
                  states[group] == nil,
                  let snapshot = record.state.snapshot() else {
                return nil
            }
            states[group] = snapshot
        }

        return StudioPreset(
            id: id,
            name: persisted.name,
            createdAt: Date(timeIntervalSince1970: persisted.createdAt),
            updatedAt: Date(timeIntervalSince1970: persisted.updatedAt),
            profileID: persisted.profileID,
            groups: groups,
            states: states
        )
    }

    private static func persistedLibrary(from library: StudioLibrary) -> PersistedLibrary? {
        guard let verifiedLibrary = StudioLibrary(
            workspace: library.workspace,
            presets: library.presets
        ), let workspace = persistedWorkspace(from: verifiedLibrary.workspace) else {
            return nil
        }

        var presets: [PersistedPreset] = []
        for preset in verifiedLibrary.presets {
            guard let record = persistedPreset(from: preset) else { return nil }
            presets.append(record)
        }
        return PersistedLibrary(
            version: currentVersion,
            workspace: workspace,
            presets: presets
        )
    }

    private static func persistedWorkspace(
        from workspace: StudioWorkspace
    ) -> PersistedWorkspace? {
        guard let verified = StudioWorkspace(
            onboardingCompleted: workspace.onboardingCompleted,
            profileID: workspace.profileID,
            workingGroups: workspace.workingGroups,
            visibleGroups: workspace.visibleGroups,
            groupConfigurations: workspace.groupConfigurations
        ) else {
            return nil
        }

        var groupStates: [PersistedWorkspaceGroup] = []
        for group in verified.workingGroups {
            guard let configuration = verified.groupConfigurations[group],
                  let state = PersistedA1State(snapshot: configuration.snapshot) else {
                return nil
            }
            groupStates.append(PersistedWorkspaceGroup(
                group: group.rawValue,
                assignedFlashModelIDs: configuration.assignedFlashModelIDs.sorted(),
                state: state
            ))
        }

        return PersistedWorkspace(
            onboardingCompleted: verified.onboardingCompleted,
            profileID: verified.profileID,
            workingGroups: verified.workingGroups.map(\.rawValue),
            visibleGroups: verified.visibleGroups.map(\.rawValue),
            groupStates: groupStates
        )
    }

    private static func persistedPreset(from preset: StudioPreset) -> PersistedPreset? {
        guard let verified = StudioPreset(
            id: preset.id,
            name: preset.name,
            createdAt: preset.createdAt,
            updatedAt: preset.updatedAt,
            profileID: preset.profileID,
            groups: preset.groups,
            states: preset.states
        ) else {
            return nil
        }

        var states: [PersistedPresetState] = []
        for group in verified.groups {
            guard let snapshot = verified.states[group],
                  let state = PersistedA1State(snapshot: snapshot) else {
                return nil
            }
            states.append(PersistedPresetState(group: group.rawValue, state: state))
        }

        return PersistedPreset(
            id: verified.id.uuidString,
            name: verified.name,
            createdAt: verified.createdAt.timeIntervalSince1970,
            updatedAt: verified.updatedAt.timeIntervalSince1970,
            profileID: verified.profileID,
            groups: verified.groups.map(\.rawValue),
            states: states
        )
    }

    private static func decodedGroups(_ rawValues: [UInt8]) -> [GodoxGroup]? {
        let groups = rawValues.compactMap(GodoxGroup.init(rawValue:))
        guard groups.count == rawValues.count,
              StudioLibraryValidation.hasUniqueGroups(groups) else {
            return nil
        }
        return groups
    }
}

private enum StudioLibraryValidation {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasUniqueGroups(_ groups: [GodoxGroup]) -> Bool {
        Set(groups).count == groups.count
    }

    static func isValid(snapshot: ManualGroupSnapshot) -> Bool {
        ManualPower.value(decimal: snapshot.power.decimalValue) != nil &&
            snapshot.modelingState.isValidForWrite
    }
}
