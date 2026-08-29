import Foundation

#if canImport(EstroboCore)
import EstroboCore
#endif

/// Versioned JSON persistence for the active workspace and named presets.
///
/// Its external interface is deliberately limited to `load()` and `save(_:)`.
/// Production uses `UserDefaults`; tests can inject read/write closures without
/// exposing any persisted record type to callers.
@MainActor
struct StudioLibraryStore: StudioLibraryRepository {
    typealias LoadResult = StudioLibraryLoadResult

    nonisolated static let defaultStorageKey = "GodoxMacControlPrototype.studioLibrary.v1"

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
        let multiFlashSettings: PersistedMultiFlashSettings?
    }

    private struct PersistedWorkspaceGroup: Codable {
        let group: UInt8
        let assignedFlashModelIDs: [String]
        let state: PersistedA1State
        let lastKnownActiveModeByte: UInt8?
        let restoresAfterMulti: Bool?
    }

    private struct PersistedPreset: Codable {
        let id: String
        let name: String
        let createdAt: Double
        let updatedAt: Double
        let profileID: String
        let groups: [UInt8]
        let states: [PersistedPresetState]
        let multiFlashSettings: PersistedMultiFlashSettings?
    }

    private struct PersistedPresetState: Codable {
        let group: UInt8
        let state: PersistedA1State
        let lastKnownActiveModeByte: UInt8?
        let restoresAfterMulti: Bool?
    }

    /// Optional inside the v1 envelope so records written before Multi editing
    /// continue to decode. New saves always include this complete value.
    private struct PersistedMultiFlashSettings: Codable {
        let countByte: UInt8
        let hertzByte: UInt8
        let powerByte: UInt8

        init(settings: MultiFlashSettings) {
            countByte = settings.countByte
            hertzByte = settings.hertzByte
            powerByte = settings.powerByte
        }

        func settings() -> MultiFlashSettings? {
            MultiFlashSettings(
                countByte: countByte,
                hertzByte: hertzByte,
                powerByte: powerByte
            )
        }
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
              let visibleGroups = decodedGroups(persisted.visibleGroups),
              let multiFlashSettings = decodedMultiFlashSettings(
                  persisted.multiFlashSettings
              ) else {
            return nil
        }

        var configurations: [GodoxGroup: StudioWorkspaceGroup] = [:]
        for record in persisted.groupStates {
            guard let group = GodoxGroup(rawValue: record.group),
                  configurations[group] == nil,
                  let snapshot = record.state.snapshot(),
                  let lastKnownActiveMode = decodedLastKnownActiveMode(
                      record.lastKnownActiveModeByte,
                      for: snapshot
                  ),
                  let configuration = StudioWorkspaceGroup(
                      snapshot: snapshot,
                      assignedFlashModelIDs: Set(record.assignedFlashModelIDs),
                      lastKnownActiveMode: lastKnownActiveMode,
                      restoresAfterMulti: record.restoresAfterMulti ??
                        (snapshot.operatingMode == .multi)
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
            groupConfigurations: configurations,
            multiFlashSettings: multiFlashSettings
        )
    }

    private static func preset(from persisted: PersistedPreset) -> StudioPreset? {
        guard let id = UUID(uuidString: persisted.id),
              let groups = decodedGroups(persisted.groups),
              persisted.createdAt.isFinite,
              persisted.updatedAt.isFinite,
              let multiFlashSettings = decodedMultiFlashSettings(
                  persisted.multiFlashSettings
              ) else {
            return nil
        }

        var states: [GodoxGroup: ManualGroupSnapshot] = [:]
        var lastKnownActiveModes: [GodoxGroup: GroupOperatingMode] = [:]
        var groupsRestoredAfterMulti: Set<GodoxGroup> = []
        for record in persisted.states {
            guard let group = GodoxGroup(rawValue: record.group),
                  states[group] == nil,
                  let snapshot = record.state.snapshot(),
                  let lastKnownActiveMode = decodedLastKnownActiveMode(
                      record.lastKnownActiveModeByte,
                      for: snapshot
                  ) else {
                return nil
            }
            states[group] = snapshot
            if let lastKnownActiveMode {
                lastKnownActiveModes[group] = lastKnownActiveMode
            }
            if record.restoresAfterMulti ?? (snapshot.operatingMode == .multi) {
                groupsRestoredAfterMulti.insert(group)
            }
        }

        return StudioPreset(
            id: id,
            name: persisted.name,
            createdAt: Date(timeIntervalSince1970: persisted.createdAt),
            updatedAt: Date(timeIntervalSince1970: persisted.updatedAt),
            profileID: persisted.profileID,
            groups: groups,
            states: states,
            lastKnownActiveModes: lastKnownActiveModes,
            groupsRestoredAfterMulti: groupsRestoredAfterMulti,
            multiFlashSettings: multiFlashSettings
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
            groupConfigurations: workspace.groupConfigurations,
            multiFlashSettings: workspace.multiFlashSettings
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
                state: state,
                lastKnownActiveModeByte: configuration.lastKnownActiveMode?.rawValue,
                restoresAfterMulti: configuration.restoresAfterMulti
            ))
        }

        return PersistedWorkspace(
            onboardingCompleted: verified.onboardingCompleted,
            profileID: verified.profileID,
            workingGroups: verified.workingGroups.map(\.rawValue),
            visibleGroups: verified.visibleGroups.map(\.rawValue),
            groupStates: groupStates,
            multiFlashSettings: PersistedMultiFlashSettings(
                settings: verified.multiFlashSettings
            )
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
            states: preset.states,
            lastKnownActiveModes: preset.lastKnownActiveModes,
            groupsRestoredAfterMulti: preset.groupsRestoredAfterMulti,
            multiFlashSettings: preset.multiFlashSettings
        ) else {
            return nil
        }

        var states: [PersistedPresetState] = []
        for group in verified.groups {
            guard let snapshot = verified.states[group],
                  let state = PersistedA1State(snapshot: snapshot) else {
                return nil
            }
            states.append(PersistedPresetState(
                group: group.rawValue,
                state: state,
                lastKnownActiveModeByte: verified.lastKnownActiveModes[group]?.rawValue,
                restoresAfterMulti: verified.groupsRestoredAfterMulti.contains(group)
            ))
        }

        return PersistedPreset(
            id: verified.id.uuidString,
            name: verified.name,
            createdAt: verified.createdAt.timeIntervalSince1970,
            updatedAt: verified.updatedAt.timeIntervalSince1970,
            profileID: verified.profileID,
            groups: verified.groups.map(\.rawValue),
            states: states,
            multiFlashSettings: PersistedMultiFlashSettings(
                settings: verified.multiFlashSettings
            )
        )
    }

    private static func decodedMultiFlashSettings(
        _ persisted: PersistedMultiFlashSettings?
    ) -> MultiFlashSettings? {
        guard let persisted else { return .default }
        return persisted.settings()
    }

    /// `nil` en registros v1 antiguos se resuelve desde el propio A1 cuando
    /// éste todavía expresa M/TTL. Para Multi/Off queda ausente y el controller
    /// adopta M como fallback conservador.
    private static func decodedLastKnownActiveMode(
        _ rawValue: UInt8?,
        for snapshot: ManualGroupSnapshot
    ) -> GroupOperatingMode?? {
        guard let rawValue else {
            return .some(
                StudioLibraryValidation.resolvedLastKnownActiveMode(nil, for: snapshot)
            )
        }
        guard let mode = GroupOperatingMode(rawValue: rawValue),
              StudioLibraryValidation.isValid(
                  lastKnownActiveMode: mode,
                  for: snapshot
              ) else {
            return nil
        }
        return .some(mode)
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
