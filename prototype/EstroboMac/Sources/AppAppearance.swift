import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "Estrobo.appearance.v1"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var localizationKey: String {
        "appearance.\(rawValue)"
    }
}

@MainActor
final class AppAppearanceStore: ObservableObject {
    @Published private(set) var appearance: AppAppearance

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        arguments: [String] = CommandLine.arguments
    ) {
        self.defaults = defaults
        if let launchAppearance = Self.launchAppearance(arguments: arguments) {
            appearance = launchAppearance
        } else if let stored = defaults.string(forKey: AppAppearance.storageKey),
                  let storedAppearance = AppAppearance(rawValue: stored) {
            appearance = storedAppearance
        } else {
            appearance = .system
        }
    }

    func select(_ appearance: AppAppearance) {
        self.appearance = appearance
        defaults.set(appearance.rawValue, forKey: AppAppearance.storageKey)
    }

    private static func launchAppearance(arguments: [String]) -> AppAppearance? {
        let requested: String?
        if let index = arguments.firstIndex(of: "--theme"),
           arguments.indices.contains(index + 1) {
            requested = arguments[index + 1]
        } else {
            requested = arguments
                .first(where: { $0.hasPrefix("--theme=") })?
                .dropFirst("--theme=".count)
                .description
        }
        return requested.flatMap { AppAppearance(rawValue: $0.lowercased()) }
    }
}
