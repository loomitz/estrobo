import XCTest
import EstroboCore
import EstroboPersistence

final class EstroboPersistenceSmokeTests: XCTestCase {
    @MainActor
    func testInMemoryFactoryPersistsThroughPortsWithoutExternalStorage() throws {
        let services = PersistenceServicesFactory.inMemory()
        let radio = try XCTUnwrap(SavedRadio(
            deviceID: UUID(),
            name: "Radio de prueba",
            radioCode: "123456"
        ))

        XCTAssertTrue(services.savedRadios.upsert(radio))
        XCTAssertEqual(services.savedRadios.load(), .records([radio]))
        XCTAssertTrue(services.savedRadios.remove(deviceID: radio.deviceID))
        XCTAssertEqual(services.savedRadios.load(), .none)
    }

    @MainActor
    func testSeparateInMemoryFactoriesDoNotShareState() throws {
        let first = PersistenceServicesFactory.inMemory()
        let second = PersistenceServicesFactory.inMemory()
        let radio = try XCTUnwrap(SavedRadio(
            deviceID: UUID(),
            name: "Aislado",
            radioCode: "654321"
        ))

        XCTAssertTrue(first.savedRadios.upsert(radio))
        XCTAssertEqual(second.savedRadios.load(), .none)
    }

    @MainActor
    func testInMemoryRestorationPortRoundTripsARecoveryPoint() throws {
        let services = PersistenceServicesFactory.inMemory()
        let power = try XCTUnwrap(ManualPower.value(decimal: 30))
        let point = GroupRestorationPoint(
            deviceID: UUID(),
            snapshot: ManualGroupSnapshot(power: power, modeling: .off)
        )

        XCTAssertTrue(services.restorations.save(group: .b, point: point))
        XCTAssertEqual(
            services.restorations.load(),
            .batch(points: [.b: point])
        )
        XCTAssertTrue(services.restorations.clear())
        XCTAssertEqual(services.restorations.load(), .none)
    }
}
