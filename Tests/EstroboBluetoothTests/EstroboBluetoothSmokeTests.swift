import XCTest
import EstroboBluetooth
import EstroboCore

@MainActor
final class EstroboBluetoothSmokeTests: XCTestCase {
    func testSimulatedFactoryDoesNotCreateLiveBluetooth() {
        let transport = RadioTransportFactory.simulated()
        XCTAssertTrue(transport.isSimulation)
        XCTAssertEqual(RadioTransportFactory.simulatedCandidate.name, "ESTROBO SIMULADO")
    }
}
