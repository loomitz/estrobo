import Foundation

public enum GroupVisibilityToggleResult: Equatable, Sendable {
    case accepted([GodoxGroup])
    case rejectedWouldHideLast([GodoxGroup])

    public var visibleGroups: [GodoxGroup] {
        switch self {
        case .accepted(let groups), .rejectedWouldHideLast(let groups):
            groups
        }
    }

    public var wasAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }
}

public enum GroupVisibilityPolicy {
    public static func visibilityAfterToggling(
        _ group: GodoxGroup,
        isVisible: Bool,
        currentVisibleGroups: [GodoxGroup],
        supportedGroups: [GodoxGroup]
    ) -> GroupVisibilityToggleResult {
        let supported = uniqueGroups(supportedGroups)
        let current = normalizedVisibleGroups(
            currentVisibleGroups,
            supportedGroups: supported
        )

        guard supported.contains(group) else {
            return .accepted(current)
        }

        var requested = Set(current)
        if isVisible {
            requested.insert(group)
        } else {
            guard requested.contains(group) else {
                return .accepted(current)
            }
            guard requested.count > 1 else {
                return .rejectedWouldHideLast(current)
            }
            requested.remove(group)
        }

        return .accepted(supported.filter(requested.contains))
    }

    public static func normalizedVisibleGroups(
        _ requestedGroups: [GodoxGroup]?,
        supportedGroups: [GodoxGroup]
    ) -> [GodoxGroup] {
        let supported = uniqueGroups(supportedGroups)
        guard !supported.isEmpty else { return [] }
        guard let requestedGroups else { return supported }

        let requested = Set(requestedGroups)
        let normalized = supported.filter(requested.contains)
        return normalized.isEmpty ? [supported[0]] : normalized
    }

    public static func validSelection(
        current: GodoxGroup?,
        visibleGroups: [GodoxGroup]
    ) -> GodoxGroup? {
        if let current, visibleGroups.contains(current) { return current }
        return visibleGroups.first
    }

    private static func uniqueGroups(_ groups: [GodoxGroup]) -> [GodoxGroup] {
        var seen: Set<GodoxGroup> = []
        return groups.filter { seen.insert($0).inserted }
    }
}
