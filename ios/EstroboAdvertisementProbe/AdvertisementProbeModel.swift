import CoreBluetooth
import Foundation
import OSLog

@MainActor
final class AdvertisementProbeModel: NSObject, ObservableObject {
    @Published private(set) var observations: [AdvertisementObservation] = []
    @Published private(set) var bluetoothState = "Starting"
    @Published private(set) var isScanning = false

    private let logger = Logger(
        subsystem: "mx.loo.estrobo.advertisement-probe",
        category: "advertisement-metadata"
    )
    private var centralManager: CBCentralManager!
    private var observationsByID: [UUID: AdvertisementObservation] = [:]

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        guard !centralManager.isScanning else { return }
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        logger.info("Started unfiltered foreground advertisement scan")
    }

    func stopScanning() {
        guard centralManager.isScanning else { return }
        centralManager.stopScan()
        isScanning = false
        logger.info("Stopped advertisement scan")
    }

    func clear() {
        observationsByID.removeAll()
        observations.removeAll()
    }

    private func publish(_ observation: AdvertisementObservation) {
        observationsByID[observation.id] = observation
        observations = observationsByID.values.sorted {
            if $0.lastSeenAt == $1.lastSeenAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.lastSeenAt > $1.lastSeenAt
        }
        logger.info("\(observation.logSummary, privacy: .public)")
    }
}

extension AdvertisementProbeModel: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === centralManager else { return }
        switch central.state {
        case .poweredOn:
            bluetoothState = "Powered on"
        case .poweredOff:
            bluetoothState = "Powered off"
        case .unauthorized:
            bluetoothState = "Unauthorized"
        case .unsupported:
            bluetoothState = "Unsupported"
        case .resetting:
            bluetoothState = "Resetting"
        case .unknown:
            bluetoothState = "Unknown"
        @unknown default:
            bluetoothState = "Unrecognized"
        }
        if central.state != .poweredOn {
            isScanning = false
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard central === centralManager, central.isScanning else { return }
        let observation = AdvertisementObservation.make(
            peripheral: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI,
            previousSampleCount: observationsByID[peripheral.identifier]?.sampleCount ?? 0
        )
        publish(observation)
    }
}
