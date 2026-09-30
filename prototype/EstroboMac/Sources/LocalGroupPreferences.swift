import Foundation

/// Persistencia exclusivamente local de los grupos que aparecen en la interfaz.
///
/// Los valores guardados son únicamente los `rawValue` técnicos de cada grupo.
/// Esta preferencia no representa el estado del radio y nunca debe provocar una
/// escritura Bluetooth.
struct LocalGroupPreferences {
    enum VisibilityToggleResult: Equatable {
        case accepted([GodoxGroup])
        case rejectedWouldHideLast([GodoxGroup])

        var visibleGroups: [GodoxGroup] {
            switch self {
            case .accepted(let groups), .rejectedWouldHideLast(let groups):
                groups
            }
        }

        var wasAccepted: Bool {
            if case .accepted = self { return true }
            return false
        }
    }

    static let defaultStorageKey = "GodoxMacControlPrototype.visibleGroups.v1"

    private let storageKey: String
    private let readArray: (String) -> [Any]?
    private let writeIntegers: ([Int], String) -> Void

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = LocalGroupPreferences.defaultStorageKey
    ) {
        self.storageKey = storageKey
        readArray = { defaults.array(forKey: $0) }
        writeIntegers = { values, key in defaults.set(values, forKey: key) }
    }

    init(
        storageKey: String,
        readArray: @escaping (String) -> [Any]?,
        writeIntegers: @escaping ([Int], String) -> Void
    ) {
        self.storageKey = storageKey
        self.readArray = readArray
        self.writeIntegers = writeIntegers
    }

    /// Carga la selección persistida y la limita a los grupos del perfil actual.
    ///
    /// Sin una preferencia previa se muestran todos los grupos soportados. Si una
    /// preferencia antigua ya no comparte grupos con el perfil, se conserva al
    /// menos el primer grupo soportado.
    func loadVisibleGroups(
        supportedGroups: [GodoxGroup],
        defaultVisibleGroups: [GodoxGroup]? = nil
    ) -> [GodoxGroup] {
        guard let storedValues = readArray(storageKey) else {
            return Self.normalizedVisibleGroups(
                defaultVisibleGroups,
                supportedGroups: supportedGroups
            )
        }

        let storedGroups = storedValues.compactMap(Self.group(fromStoredValue:))
        return Self.normalizedVisibleGroups(storedGroups, supportedGroups: supportedGroups)
    }

    /// Normaliza y guarda una selección. Devuelve exactamente lo que quedó
    /// persistido para que el caller actualice su estado con la misma versión.
    @discardableResult
    func saveVisibleGroups(
        _ visibleGroups: [GodoxGroup],
        supportedGroups: [GodoxGroup]
    ) -> [GodoxGroup] {
        let normalized = Self.normalizedVisibleGroups(
            visibleGroups,
            supportedGroups: supportedGroups
        )
        writeIntegers(normalized.map { Int($0.rawValue) }, storageKey)
        return normalized
    }

    /// Propone un cambio local sin persistirlo.
    ///
    /// El orden del resultado siempre sigue al perfil y una solicitud para
    /// ocultar el último grupo visible se rechaza explícitamente.
    static func visibilityAfterToggling(
        _ group: GodoxGroup,
        isVisible: Bool,
        currentVisibleGroups: [GodoxGroup],
        supportedGroups: [GodoxGroup]
    ) -> VisibilityToggleResult {
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

        let updated = supported.filter(requested.contains)
        return .accepted(updated)
    }

    /// Intersección estable con el perfil, sin duplicados y nunca vacía cuando
    /// existe al menos un grupo soportado. `nil` significa que aún no hay una
    /// preferencia guardada y conserva visible todo el perfil.
    static func normalizedVisibleGroups(
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

    static func validSelection(
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

    private static func group(fromStoredValue value: Any) -> GodoxGroup? {
        guard let number = value as? NSNumber else { return nil }
        let rawValue = number.intValue
        guard (Int(UInt8.min)...Int(UInt8.max)).contains(rawValue) else { return nil }
        return GodoxGroup(rawValue: UInt8(rawValue))
    }
}
