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

    func testMultiFlashAccepts199HertzWithoutWideningLegacyEditorRange() throws {
        XCTAssertEqual(MultiFlashSettings.hertzRange, 1...100)
        XCTAssertEqual(MultiFlashSettings.acceptedHertzRange, 1...199)

        let power = try XCTUnwrap(ManualPower.value(decimal: 50))
        let legacy = try XCTUnwrap(
            MultiFlashSettings(power: power, count: 10, hertz: 55)
        )
        let maximum = try XCTUnwrap(
            MultiFlashSettings(power: power, count: 10, hertz: 199)
        )

        XCTAssertEqual(legacy.hertz, 55)
        XCTAssertEqual(maximum.hertzByte, 0xC7)
        XCTAssertEqual(
            MultiFlashSettings(
                countByte: maximum.countByte,
                hertzByte: maximum.hertzByte,
                powerByte: maximum.powerByte
            ),
            maximum
        )
        XCTAssertNil(MultiFlashSettings(power: power, count: 10, hertz: 200))

        var snapshot = GlobalRadioSnapshot(
            apkDefaultsWithBeepEnabled: false,
            modelingLightEnabled: false,
            standbyEnabled: false
        )
        snapshot.multiHertz = maximum.hertzByte
        let frame = try SafeGodoxProtocol.globalFrame(snapshot: snapshot)

        XCTAssertEqual([UInt8](frame)[9], 0xC7)
        XCTAssertEqual(
            SafeGodoxProtocol.globalSnapshot(from: frame)?.multiHertz,
            0xC7
        )
    }
}
