import Foundation

enum EstroboExternalLinks {
    static func privacyPolicy(for language: EstroboLanguage) -> URL {
        switch language {
        case .es:
            spanishPrivacyPolicy
        case .en:
            englishPrivacyPolicy
        }
    }

    static func support(for language: EstroboLanguage) -> URL {
        switch language {
        case .es:
            spanishSupport
        case .en:
            englishSupport
        }
    }

    private static let spanishPrivacyPolicy = validatedURL(
        "https://github.com/loomitz/estrobo/blob/main/PRIVACY.md"
    )
    private static let englishPrivacyPolicy = validatedURL(
        "https://github.com/loomitz/estrobo/blob/main/PRIVACY.en.md"
    )
    private static let spanishSupport = validatedURL(
        "https://github.com/loomitz/estrobo/blob/main/SUPPORT.md"
    )
    private static let englishSupport = validatedURL(
        "https://github.com/loomitz/estrobo/blob/main/SUPPORT.en.md"
    )

    private static func validatedURL(_ value: String) -> URL {
        guard let url = URL(string: value),
              url.scheme == "https",
              url.host == "github.com" else {
            preconditionFailure("Invalid Estrobo external URL.")
        }
        return url
    }
}
