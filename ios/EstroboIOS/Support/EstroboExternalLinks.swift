import Foundation

enum EstroboExternalLinks {
    // Candidate builds must show the privacy/support contract from their source
    // branch. Before distribution, pin this to the reviewed release tag or commit.
    private static let documentReference = "codex/integration-20260929"

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
