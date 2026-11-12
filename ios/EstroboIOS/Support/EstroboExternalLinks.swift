import Foundation

enum EstroboExternalLinks {
    // Keep the reviewed privacy/support contract on an immutable source commit.
    // Before distribution, review this pin against the exact release candidate.
    private static let documentReference = "df89dc1c55527890fcd3791f1e4eba132a6bd03f"

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
        "https://github.com/loomitz/estrobo/blob/\(documentReference)/PRIVACY.md"
    )
    private static let englishPrivacyPolicy = validatedURL(
        "https://github.com/loomitz/estrobo/blob/\(documentReference)/PRIVACY.en.md"
    )
    private static let spanishSupport = validatedURL(
        "https://github.com/loomitz/estrobo/blob/\(documentReference)/SUPPORT.md"
    )
    private static let englishSupport = validatedURL(
        "https://github.com/loomitz/estrobo/blob/\(documentReference)/SUPPORT.en.md"
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
