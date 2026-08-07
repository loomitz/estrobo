import Foundation

/// A complete, locally authoritative value for one group in the active studio.
///
/// The snapshot contains the six mutable A1 fields. Flash model identifiers are
/// kept beside it because they determine whether that snapshot is valid for a
/// particular studio configuration, but they are never sent to the radio.
struct StudioWorkspaceGroup: Equatable {
    let snapshot: ManualGroupSnapshot
    let assignedFlashModelIDs: Set<String>
    /// Modo que debe conservarse debajo de Multi o mientras el grupo está Off.
    /// Godox usa esta distinción para decidir el byte de potencia A1 al entrar
    /// en Multi desde M o desde TTL.
    let lastKnownActiveMode: GroupOperatingMode?
    let restoresAfterMulti: Bool

    init?(
        snapshot: ManualGroupSnapshot,
        assignedFlashModelIDs: Set<String>,
        lastKnownActiveMode: GroupOperatingMode? = nil,
        restoresAfterMulti: Bool? = nil
    ) {
        let resolvedRestoresAfterMulti = restoresAfterMulti ??
            (snapshot.operatingMode == .multi)
        guard StudioLibraryValidation.isValid(snapshot: snapshot),
              StudioLibraryValidation.isValid(
                  lastKnownActiveMode: lastKnownActiveMode,
                  for: snapshot
              ),
              !resolvedRestoresAfterMulti || snapshot.operatingMode == .multi ||
                snapshot.operatingMode == .off else { return nil }

        var normalizedModelIDs: Set<String> = []
        for modelID in assignedFlashModelIDs {
            let normalized = StudioLibraryValidation.normalized(modelID)
            guard !normalized.isEmpty else { return nil }
            normalizedModelIDs.insert(normalized)
        }

        self.snapshot = snapshot
        self.assignedFlashModelIDs = normalizedModelIDs
        self.lastKnownActiveMode = StudioLibraryValidation.resolvedLastKnownActiveMode(
            lastKnownActiveMode,
            for: snapshot
        )
        self.restoresAfterMulti = resolvedRestoresAfterMulti
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
    let multiFlashSettings: MultiFlashSettings

    init?(
        onboardingCompleted: Bool,
        profileID: String,
        workingGroups: [GodoxGroup],
        visibleGroups: [GodoxGroup],
        groupConfigurations: [GodoxGroup: StudioWorkspaceGroup],
        multiFlashSettings: MultiFlashSettings = .default
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
              Set(groupConfigurations.keys) == workingSet,
              StudioLibraryValidation.hasValidMultiModeCombination(
                  workingGroups.compactMap { groupConfigurations[$0]?.snapshot }
              ),
              !groupConfigurations.values.contains(where: { $0.restoresAfterMulti }) ||
                groupConfigurations.values.contains(where: {
                    $0.snapshot.operatingMode == .multi
                }) else {
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
        self.multiFlashSettings = multiFlashSettings
    }
}

/// A named, device-independent collection of desired A1 values and the global
/// Multi settings required to reproduce those group modes.
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
    let lastKnownActiveModes: [GodoxGroup: GroupOperatingMode]
    let groupsRestoredAfterMulti: Set<GodoxGroup>
    let multiFlashSettings: MultiFlashSettings

    init?(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        profileID: String,
        groups: [GodoxGroup],
        states: [GodoxGroup: ManualGroupSnapshot],
        lastKnownActiveModes: [GodoxGroup: GroupOperatingMode] = [:],
        groupsRestoredAfterMulti: Set<GodoxGroup>? = nil,
        multiFlashSettings: MultiFlashSettings = .default
    ) {
        let normalizedName = StudioLibraryValidation.normalized(name)
        let normalizedProfileID = StudioLibraryValidation.normalized(profileID)
        let resolvedUpdatedAt = updatedAt ?? createdAt
        let resolvedGroupsRestoredAfterMulti = groupsRestoredAfterMulti ?? Set(
            groups.filter { states[$0]?.operatingMode == .multi }
        )
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
              }),
              Set(lastKnownActiveModes.keys).isSubset(of: Set(groups)),
              resolvedGroupsRestoredAfterMulti.isSubset(of: Set(groups)),
              resolvedGroupsRestoredAfterMulti.allSatisfy({
                  states[$0]?.operatingMode == .multi ||
                    states[$0]?.operatingMode == .off
              }),
              lastKnownActiveModes.allSatisfy({ group, mode in
                  guard let snapshot = states[group] else { return false }
                  return StudioLibraryValidation.isValid(
                      lastKnownActiveMode: mode,
                      for: snapshot
                  )
              }),
              StudioLibraryValidation.hasValidMultiModeCombination(
                  groups.compactMap { states[$0] }
              ),
              resolvedGroupsRestoredAfterMulti.isEmpty ||
                states.values.contains(where: { $0.operatingMode == .multi }) else {
            return nil
        }

        self.id = id
        self.name = normalizedName
        self.createdAt = createdAt
        self.updatedAt = resolvedUpdatedAt
        self.profileID = normalizedProfileID
        self.groups = groups
        self.states = states
        self.lastKnownActiveModes = Dictionary(uniqueKeysWithValues: groups.compactMap { group in
            guard let snapshot = states[group],
                  let mode = StudioLibraryValidation.resolvedLastKnownActiveMode(
                      lastKnownActiveModes[group],
                      for: snapshot
                  ) else { return nil }
            return (group, mode)
        })
        self.groupsRestoredAfterMulti = resolvedGroupsRestoredAfterMulti
        self.multiFlashSettings = multiFlashSettings
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

    static func hasValidMultiModeCombination(
        _ snapshots: [ManualGroupSnapshot]
    ) -> Bool {
        guard snapshots.contains(where: { $0.operatingMode == .multi }) else {
            return true
        }
        return snapshots.allSatisfy {
            $0.operatingMode == .multi || $0.operatingMode == .off
        }
    }

    static func isValid(
        lastKnownActiveMode: GroupOperatingMode?,
        for snapshot: ManualGroupSnapshot
    ) -> Bool {
        guard let lastKnownActiveMode else { return true }
        guard lastKnownActiveMode == .manual || lastKnownActiveMode == .autoTTL else {
            return false
        }
        if snapshot.operatingMode == .manual || snapshot.operatingMode == .autoTTL {
            return lastKnownActiveMode == snapshot.operatingMode
        }
        return true
    }

    static func resolvedLastKnownActiveMode(
        _ mode: GroupOperatingMode?,
        for snapshot: ManualGroupSnapshot
    ) -> GroupOperatingMode? {
        if let mode { return mode }
        switch snapshot.operatingMode {
        case .manual, .autoTTL:
            return snapshot.operatingMode
        case .multi, .off:
            return nil
        }
    }
}
