import SwiftUI

enum EstroboLanguage: String, CaseIterable, Identifiable {
    case es
    case en

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var displayName: String {
        switch self {
        case .es: "Español"
        case .en: "English"
        }
    }

    func localized(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

enum EstroboAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum PhoneWorkspaceSection: String, CaseIterable, Identifiable, Hashable {
    case groups
    case presets
    case settings

    var id: String { rawValue }
}

enum TabletDestination: String, CaseIterable, Identifiable, Hashable {
    case connection
    case groups
    case presets
    case savedRadios
    case settings
    case demo

    var id: String { rawValue }
}
