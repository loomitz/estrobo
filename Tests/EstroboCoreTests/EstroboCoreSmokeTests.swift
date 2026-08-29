import XCTest
@testable import EstroboCore

final class EstroboCoreSmokeTests: XCTestCase {
    func testRadioCandidateIdentityIsStable() {
        let id = UUID()
        XCTAssertEqual(RadioCandidate(id: id, name: "Radio", rssi: -40).id, id)
    }

    func testRadioCodeNeverDescribesItsSecret() throws {
        let code = try XCTUnwrap(RadioCode("123456"))

        XCTAssertEqual(code.description, "<redacted>")
        XCTAssertEqual(code.debugDescription, "RadioCode(<redacted>)")
        XCTAssertFalse(String(describing: code).contains("123456"))
        XCTAssertFalse(String(reflecting: code).contains("123456"))
    }

    func testVisibilityPolicyRejectsHidingLastGroup() {
        let result = GroupVisibilityPolicy.visibilityAfterToggling(
            .b,
            isVisible: false,
            currentVisibleGroups: [.b],
            supportedGroups: [.a, .b, .c]
        )

        XCTAssertEqual(result, .rejectedWouldHideLast([.b]))
    }

    func testSafeProtocolRoundTripsAGroupFrame() throws {
        let power = try XCTUnwrap(ManualPower.value(decimal: 23))
        let snapshot = ManualGroupSnapshot(power: power, modeling: .off)
        let frame = try SafeGodoxProtocol.manualGroupFrame(group: .b, snapshot: snapshot)

        let decoded = try XCTUnwrap(SafeGodoxProtocol.groupSnapshot(from: frame))
        XCTAssertEqual(decoded.0, .b)
        XCTAssertEqual(decoded.1, snapshot)
    }
}
