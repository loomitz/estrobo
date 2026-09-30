import XCTest
@testable import EstroboIOS

final class EstroboExternalLinksTests: XCTestCase {
    func testPrivacyAndSupportLinksAreLocalizedPublicHTTPSURLs() {
        let spanishPrivacy = EstroboExternalLinks.privacyPolicy(for: .es)
        let englishPrivacy = EstroboExternalLinks.privacyPolicy(for: .en)
        let spanishSupport = EstroboExternalLinks.support(for: .es)
        let englishSupport = EstroboExternalLinks.support(for: .en)

        for url in [
            spanishPrivacy,
            englishPrivacy,
            spanishSupport,
            englishSupport,
        ] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "github.com")
            XCTAssertTrue(url.path.hasPrefix(
                "/loomitz/estrobo/blob/codex/integration-20260929/"
            ))
        }

        XCTAssertTrue(spanishPrivacy.path.hasSuffix("/PRIVACY.md"))
        XCTAssertTrue(englishPrivacy.path.hasSuffix("/PRIVACY.en.md"))
        XCTAssertTrue(spanishSupport.path.hasSuffix("/SUPPORT.md"))
        XCTAssertTrue(englishSupport.path.hasSuffix("/SUPPORT.en.md"))
        XCTAssertNotEqual(spanishPrivacy, englishPrivacy)
        XCTAssertNotEqual(spanishSupport, englishSupport)
    }
}
