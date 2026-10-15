import XCTest
import CoreBluetooth
@testable import EstroboBluetooth
import EstroboCore

@MainActor
final class EstroboBluetoothSmokeTests: XCTestCase {
    func testSimulatedFactoryDoesNotCreateLiveBluetooth() {
        let transport = RadioTransportFactory.simulated()
        XCTAssertTrue(transport.isSimulation)
        XCTAssertEqual(RadioTransportFactory.simulatedCandidate.name, "ESTROBO SIMULADO")
    }

    func testResetDropsAQueuedControlWriteBeforeDelivery() {
        let coordinator = CoreBluetoothWriteCoordinator()
        let access = CoreBluetoothWriteAccess(
            maximumPayloadLength: 20,
            supportsWrite: true,
            canSendWithoutResponse: true
        )
        coordinator.enqueueControl(
            Data([0xF0, 0xA0]),
            access: access,
            characteristicID: "FEC7"
        )

        coordinator.reset()
        var wasDelivered = false
        let didBegin = coordinator.beginNextControlWrite { _ in
            wasDelivered = true
        }

        XCTAssertFalse(didBegin)
        XCTAssertFalse(wasDelivered)
    }

    func testScanStartDistinguishesTemporaryAndTerminalBluetoothStates() {
        XCTAssertEqual(
            CoreBluetoothRadioTransport.scanStartDisposition(for: .poweredOn),
            .ready
        )
        for state in [CBManagerState.unknown, .resetting, .poweredOff] {
            XCTAssertEqual(
                CoreBluetoothRadioTransport.scanStartDisposition(for: state),
                .waiting
            )
        }
        XCTAssertEqual(
            CoreBluetoothRadioTransport.scanStartDisposition(for: .unauthorized),
            .unavailable(
                reason: "permission denied",
                resumesIfPoweredOn: true
            )
        )
        XCTAssertEqual(
            CoreBluetoothRadioTransport.scanStartDisposition(for: .unsupported),
            .unavailable(
                reason: "unsupported on this Mac",
                resumesIfPoweredOn: false
            )
        )
    }
}
