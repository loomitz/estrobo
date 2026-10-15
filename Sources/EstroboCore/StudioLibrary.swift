import Foundation

/// A complete, locally authoritative value for one group in the active studio.
///
/// The snapshot contains the six mutable A1 fields. Flash model identifiers are
/// kept beside it because they determine whether that snapshot is valid for a
/// particular studio configuration, but they are never sent to the radio.
public struct StudioWorkspaceGroup: Equatable, Sendable {
    public let snapshot: ManualGroupSnapshot
    public let assignedFlashModelIDs: Set<String>
    /// Modo que debe conservarse debajo de Multi o mientras el grupo está Off.
    /// Godox usa esta distinción para decidir el byte de potencia A1 al entrar
    /// en Multi desde M o desde TTL.
    public let lastKnownActiveMode: GroupOperatingMode?
    public let restoresAfterMulti: Bool

    public init?(
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
public struct StudioWorkspace: Equatable, Sendable {
    public let onboardingCompleted: Bool
    public let profileID: String
    public let workingGroups: [GodoxGroup]
    public let visibleGroups: [GodoxGroup]
    public let groupConfigurations: [GodoxGroup: StudioWorkspaceGroup]
    public let multiFlashSettings: MultiFlashSettings

    public init?(
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
public struct StudioPreset: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let profileID: String
    public let groups: [GodoxGroup]
    public let states: [GodoxGroup: ManualGroupSnapshot]
    public let lastKnownActiveModes: [GodoxGroup: GroupOperatingMode]
    public let groupsRestoredAfterMulti: Set<GodoxGroup>
    public let multiFlashSettings: MultiFlashSettings

    public init?(
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
public struct StudioLibrary: Equatable, Sendable {
    public let workspace: StudioWorkspace
    public let presets: [StudioPreset]

    public init?(workspace: StudioWorkspace, presets: [StudioPreset]) {
        guard Set(presets.map(\.id)).count == presets.count else { return nil }
        self.workspace = workspace
        self.presets = presets
    }
}

/// Validation shared with the persistence codec.
///
/// This remains `public` instead of `package`: the Mac compatibility build
/// compiles the same Core and Persistence sources directly with `swiftc`,
/// outside a named Swift package, where `package` access is unavailable.
public enum StudioLibraryValidation {
    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func hasUniqueGroups(_ groups: [GodoxGroup]) -> Bool {
        Set(groups).count == groups.count
    }

    public static func isValid(snapshot: ManualGroupSnapshot) -> Bool {
        ManualPower.value(decimal: snapshot.power.decimalValue) != nil &&
            snapshot.modelingState.isValidForWrite
    }

    public static func hasValidMultiModeCombination(
        _ snapshots: [ManualGroupSnapshot]
    ) -> Bool {
        guard snapshots.contains(where: { $0.operatingMode == .multi }) else {
            return true
        }
        return snapshots.allSatisfy {
            $0.operatingMode == .multi || $0.operatingMode == .off
        }
    }

    public static func isValid(
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

    public static func resolvedLastKnownActiveMode(
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
