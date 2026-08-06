import Foundation
import CoreBluetooth

@MainActor
protocol BluetoothClientDelegate: AnyObject {
    func bluetoothClient(didReceive event: BluetoothClient.Event)
}

/// A deliberately small CoreBluetooth central for the Godox proof of concept.
///
/// This type owns transport and GATT sequencing only. Callers are responsible for
/// constructing and validating authentication, sync, and control payloads.
@MainActor
final class BluetoothClient: NSObject {
    struct Device: Hashable, Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    enum State: Equatable {
        case idle
        case waitingForBluetooth
        case bluetoothUnavailable(String)
        case scanning
        case connecting(Device)
        case discovering(Device)
        case subscribing(Device)
        case ready(Device)
        case disconnecting(Device)
        case failed(String)
    }

    enum LogLevel {
        case debug
        case info
        case warning
        case error
    }

    enum NotificationSource {
        case authentication
        case control
    }

    enum CommandKind {
        case authentication
        case sync
        case test
        case control
    }

    enum ClientError: LocalizedError, Equatable {
        case bluetoothUnavailable(String)
        case unknownDevice(UUID)
        case busy(String)
        case connectionFailed(String)
        case disconnected(String)
        case serviceDiscoveryFailed(String)
        case missingService(String)
        case characteristicDiscoveryFailed(String)
        case missingCharacteristic(String)
        case unsupportedCharacteristic(String)
        case subscriptionFailed(String)
        case notReady
        case payloadTooLarge(command: CommandKind, maximum: Int)
        case writeFailed(command: CommandKind, message: String)

        var errorDescription: String? {
            switch self {
            case .bluetoothUnavailable(let reason):
                return "Bluetooth is unavailable: \(reason)"
            case .unknownDevice:
                return "The selected Bluetooth device is no longer available."
            case .busy(let reason):
                return reason
            case .connectionFailed(let reason):
                return "Could not connect: \(reason)"
            case .disconnected(let reason):
                return "The device disconnected: \(reason)"
            case .serviceDiscoveryFailed(let reason):
                return "Service discovery failed: \(reason)"
            case .missingService(let uuid):
                return "The device does not expose required service \(uuid)."
            case .characteristicDiscoveryFailed(let reason):
                return "Characteristic discovery failed: \(reason)"
            case .missingCharacteristic(let uuid):
                return "The device does not expose required characteristic \(uuid)."
            case .unsupportedCharacteristic(let uuid):
                return "Characteristic \(uuid) does not support the required operation."
            case .subscriptionFailed(let reason):
                return "Notification subscription failed: \(reason)"
            case .notReady:
                return "The Godox device is not ready for commands."
            case .payloadTooLarge(let command, let maximum):
                return "The \(command.label) payload exceeds the Bluetooth limit of \(maximum) bytes."
            case .writeFailed(let command, let message):
                return "The \(command.label) write failed: \(message)"
            }
        }
    }

    enum Event {
        case stateChanged(State)
        case discoveryReset
        case discovered(Device)
        case log(LogLevel, String)
        case readyForAuthentication
        case notification(NotificationSource, Data)
        case commandSent(CommandKind)
        case controlWriteStarted
        case controlWriteCompleted
        case commandFailed(CommandKind, ClientError)
        case failed(ClientError)
    }

    weak var delegate: (any BluetoothClientDelegate)?

    private(set) var state: State = .idle
    private(set) var discoveredDevices: [Device] = []

    private static let controlServiceUUID = CBUUID(string: "FEC0")
    private static let authenticationServiceUUID = CBUUID(string: "FFF0")
    private static let controlWriteUUID = CBUUID(string: "FEC7")
    private static let controlNotifyUUID = CBUUID(string: "FEC8")
    private static let authenticationWriteUUID = CBUUID(string: "FFF1")
    private static let authenticationNotifyUUID = CBUUID(string: "FFF4")

    private enum SubscriptionStep {
        case idle
        case authenticationRequested
        case waitingForControl
        case controlRequested
        case ready
    }

    private struct PendingUnacknowledgedWrite {
        let kind: CommandKind
        let payload: Data
    }

    private var centralManager: CBCentralManager!
    private var scanRequested = false

    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var devicesByID: [UUID: Device] = [:]
    private var currentPeripheral: CBPeripheral?
    private var currentDevice: Device?
    private var pendingConnectionID: UUID?
    private var disconnectWasRequested = false
    private var pendingFailureError: ClientError?
    private var disconnectionWatchdog: Task<Void, Never>?

    private var controlService: CBService?
    private var authenticationService: CBService?
    private var controlWriteCharacteristic: CBCharacteristic?
    private var controlNotifyCharacteristic: CBCharacteristic?
    private var authenticationWriteCharacteristic: CBCharacteristic?
    private var authenticationNotifyCharacteristic: CBCharacteristic?
    private var discoveredControlCharacteristics = false
    private var discoveredAuthenticationCharacteristics = false
    private var subscriptionStep: SubscriptionStep = .idle
    private var subscriptionTask: Task<Void, Never>?

    private var unacknowledgedWriteQueue: [PendingUnacknowledgedWrite] = []
    private var controlWriteQueue: [Data] = []
    private var controlWriteInFlight = false
    private var controlWriteTask: Task<Void, Never>?

    init(delegate: (any BluetoothClientDelegate)? = nil) {
        self.delegate = delegate
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard currentPeripheral == nil else {
            let error = ClientError.busy("Disconnect the current Godox device before scanning.")
            emit(.failed(error))
            emit(.log(.warning, error.localizedDescription))
            return
        }

        scanRequested = true
        guard centralManager.state == .poweredOn else {
            updateState(.waitingForBluetooth)
            emit(.log(.info, "Waiting for Bluetooth to become available."))
            return
        }

        beginScanning()
    }

    func stopScanning() {
        scanRequested = false
        guard centralManager.isScanning else { return }
        centralManager.stopScan()
        emit(.log(.info, "Bluetooth scan stopped."))
        if case .scanning = state {
            updateState(.idle)
        }
    }

    func connect(to device: Device) {
        connect(to: device.id)
    }

    func connect(to identifier: UUID) {
        guard centralManager.state == .poweredOn else {
            let reason = Self.description(for: centralManager.state)
            let error = ClientError.bluetoothUnavailable(reason)
            emit(.failed(error))
            updateState(.bluetoothUnavailable(reason))
            return
        }
        guard let peripheral = peripheralsByID[identifier], let device = devicesByID[identifier] else {
            let error = ClientError.unknownDevice(identifier)
            emit(.failed(error))
            emit(.log(.error, error.localizedDescription))
            return
        }

        scanRequested = false
        if centralManager.isScanning {
            centralManager.stopScan()
        }

        if let currentPeripheral {
            if currentPeripheral.identifier == identifier {
                emit(.log(.debug, "The selected Godox device is already active."))
                return
            }

            pendingConnectionID = identifier
            disconnectWasRequested = true
            pendingFailureError = nil
            if let currentDevice {
                updateState(.disconnecting(currentDevice))
            }
            emit(.log(.info, "Disconnecting before switching Godox devices."))
            if currentPeripheral.state == .disconnected {
                finishDisconnection(of: currentPeripheral, error: nil)
            } else {
                scheduleDisconnectionWatchdog(for: currentPeripheral)
                centralManager.cancelPeripheralConnection(currentPeripheral)
            }
            return
        }

        beginConnection(to: peripheral, device: device)
    }

    func disconnect() {
        scanRequested = false
        pendingConnectionID = nil
        if centralManager.isScanning {
            centralManager.stopScan()
        }

        guard let peripheral = currentPeripheral else {
            resetGATTState()
            updateState(.idle)
            return
        }

        disconnectWasRequested = true
        pendingFailureError = nil
        if let currentDevice {
            updateState(.disconnecting(currentDevice))
        }
        emit(.log(.info, "Disconnecting from the Godox device."))

        if peripheral.state == .disconnected {
            finishDisconnection(of: peripheral, error: nil)
        } else {
            scheduleDisconnectionWatchdog(for: peripheral)
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    /// Last-resort local cleanup when CoreBluetooth never delivers its
    /// disconnection callback. The OS cancellation is still requested first,
    /// but callers are no longer held hostage by a missing callback.
    func forceResetConnection() {
        scanRequested = false
        pendingConnectionID = nil
        disconnectWasRequested = false
        pendingFailureError = nil
        disconnectionWatchdog?.cancel()
        disconnectionWatchdog = nil
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        if let peripheral = currentPeripheral,
           peripheral.state != .disconnected {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        if let peripheral = currentPeripheral {
            clearCurrentPeripheral(peripheral)
        } else {
            resetGATTState()
        }
        peripheralsByID.removeAll()
        devicesByID.removeAll()
        discoveredDevices.removeAll()
        emit(.discoveryReset)
        rebuildCentralManager()
        emit(.log(.warning, "Bluetooth transport was rebuilt after a missing disconnection callback."))
        updateState(.idle)
    }

    /// Writes a caller-built radio-code challenge to FFF1 without response.
    /// The payload itself is never emitted to logs or delegate events.
    func sendAuthentication(_ payload: Data) {
        enqueueUnacknowledgedWrite(payload, kind: .authentication)
    }

    /// Writes a caller-built clock synchronization payload to FFF1 without response.
    func sendSync(_ payload: Data) {
        enqueueUnacknowledgedWrite(payload, kind: .sync)
    }

    /// Writes an explicit user-requested flash test payload to FFF1 without response.
    ///
    /// A Test command can fire physical flashes, so it is deliberately fail-fast:
    /// unlike authentication and sync it is never queued for a later radio-ready
    /// callback. This prevents a timed-out Test from firing unexpectedly afterward.
    func sendTest(_ payload: Data) {
        guard let peripheral = readyPeripheral(), let characteristic = authenticationWriteCharacteristic else {
            reportCommandFailure(.test, .notReady)
            return
        }
        let maximum = peripheral.maximumWriteValueLength(for: .withoutResponse)
        guard payload.count <= maximum else {
            reportCommandFailure(.test, .payloadTooLarge(command: .test, maximum: maximum))
            return
        }
        guard characteristic.properties.contains(.writeWithoutResponse) else {
            reportCommandFailure(
                .test,
                .unsupportedCharacteristic(Self.authenticationWriteUUID.uuidString)
            )
            return
        }
        guard peripheral.canSendWriteWithoutResponse else {
            reportCommandFailure(
                .test,
                .busy("The Bluetooth radio cannot deliver Test right now. Try again.")
            )
            return
        }

        emit(.log(.info, "Explicit flash test sent."))
        peripheral.writeValue(payload, for: characteristic, type: .withoutResponse)
        emit(.commandSent(.test))
    }

    /// Serializes caller-built A0/A1 (or heartbeat) frames through FEC7 with response.
    func sendControl(_ payload: Data) {
        guard let peripheral = readyPeripheral(), let characteristic = controlWriteCharacteristic else {
            reportCommandFailure(.control, .notReady)
            return
        }
        let maximum = peripheral.maximumWriteValueLength(for: .withResponse)
        guard payload.count <= maximum else {
            reportCommandFailure(.control, .payloadTooLarge(command: .control, maximum: maximum))
            return
        }
        guard characteristic.properties.contains(.write) else {
            reportCommandFailure(
                .control,
                .unsupportedCharacteristic(Self.controlWriteUUID.uuidString)
            )
            return
        }

        controlWriteQueue.append(payload)
        scheduleNextControlWrite()
    }

    private func beginScanning() {
        guard !centralManager.isScanning else { return }
        peripheralsByID.removeAll()
        devicesByID.removeAll()
        discoveredDevices.removeAll()
        emit(.discoveryReset)
        updateState(.scanning)
        emit(.log(.info, "Scanning for compatible Godox Bluetooth devices."))
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func beginConnection(to peripheral: CBPeripheral, device: Device) {
        resetGATTState()
        currentPeripheral = peripheral
        currentDevice = device
        disconnectWasRequested = false
        pendingFailureError = nil
        peripheral.delegate = self
        updateState(.connecting(device))
        emit(.log(.info, "Connecting to \(device.name)."))
        centralManager.connect(peripheral, options: nil)
    }

    private func beginCharacteristicSubscriptions() {
        guard let peripheral = currentPeripheral,
              let authenticationNotifyCharacteristic,
              let currentDevice else {
            failSession(.missingCharacteristic(Self.authenticationNotifyUUID.uuidString))
            return
        }

        subscriptionStep = .authenticationRequested
        updateState(.subscribing(currentDevice))
        emit(.log(.info, "Subscribing to authentication notifications."))
        peripheral.setNotifyValue(true, for: authenticationNotifyCharacteristic)
    }

    private func scheduleControlSubscription() {
        subscriptionTask?.cancel()
        subscriptionStep = .waitingForControl
        let expectedPeripheral = currentPeripheral

        subscriptionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard let self,
                  self.currentPeripheral === expectedPeripheral,
                  let peripheral = self.currentPeripheral,
                  let characteristic = self.controlNotifyCharacteristic else {
                return
            }

            self.subscriptionStep = .controlRequested
            self.emit(.log(.info, "Subscribing to control indications."))
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    private func enqueueUnacknowledgedWrite(_ payload: Data, kind: CommandKind) {
        guard let peripheral = readyPeripheral(), let characteristic = authenticationWriteCharacteristic else {
            reportCommandFailure(kind, .notReady)
            return
        }
        let maximum = peripheral.maximumWriteValueLength(for: .withoutResponse)
        guard payload.count <= maximum else {
            reportCommandFailure(kind, .payloadTooLarge(command: kind, maximum: maximum))
            return
        }
        guard characteristic.properties.contains(.writeWithoutResponse) else {
            reportCommandFailure(
                kind,
                .unsupportedCharacteristic(Self.authenticationWriteUUID.uuidString)
            )
            return
        }

        unacknowledgedWriteQueue.append(PendingUnacknowledgedWrite(kind: kind, payload: payload))
        flushUnacknowledgedWriteQueue()
    }

    private func flushUnacknowledgedWriteQueue() {
        guard let peripheral = readyPeripheral(),
              let characteristic = authenticationWriteCharacteristic else {
            return
        }

        while peripheral.canSendWriteWithoutResponse, !unacknowledgedWriteQueue.isEmpty {
            let write = unacknowledgedWriteQueue.removeFirst()
            peripheral.writeValue(write.payload, for: characteristic, type: .withoutResponse)
            emit(.commandSent(write.kind))
            switch write.kind {
            case .authentication:
                emit(.log(.info, "Authentication request sent."))
            case .sync:
                emit(.log(.info, "Clock synchronization sent."))
            case .test:
                assertionFailure("Test writes must never enter the deferred queue.")
            case .control:
                break
            }
        }
    }

    private func scheduleNextControlWrite() {
        guard !controlWriteInFlight, controlWriteTask == nil, !controlWriteQueue.isEmpty else {
            return
        }

        let expectedPeripheral = currentPeripheral
        controlWriteTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard let self else { return }
            self.controlWriteTask = nil
            guard self.currentPeripheral === expectedPeripheral,
                  let peripheral = self.readyPeripheral(),
                  let characteristic = self.controlWriteCharacteristic,
                  !self.controlWriteQueue.isEmpty else {
                return
            }

            let payload = self.controlWriteQueue.removeFirst()
            self.controlWriteInFlight = true
            peripheral.writeValue(payload, for: characteristic, type: .withResponse)
            self.emit(.controlWriteStarted)
        }
    }

    private func readyPeripheral() -> CBPeripheral? {
        guard subscriptionStep == .ready,
              let peripheral = currentPeripheral,
              peripheral.state == .connected else {
            return nil
        }
        return peripheral
    }

    private func validateCharacteristicsAndSubscribe() {
        guard discoveredControlCharacteristics, discoveredAuthenticationCharacteristics else {
            return
        }

        guard let controlWriteCharacteristic else {
            failSession(.missingCharacteristic(Self.controlWriteUUID.uuidString))
            return
        }
        guard let controlNotifyCharacteristic else {
            failSession(.missingCharacteristic(Self.controlNotifyUUID.uuidString))
            return
        }
        guard let authenticationWriteCharacteristic else {
            failSession(.missingCharacteristic(Self.authenticationWriteUUID.uuidString))
            return
        }
        guard let authenticationNotifyCharacteristic else {
            failSession(.missingCharacteristic(Self.authenticationNotifyUUID.uuidString))
            return
        }

        guard controlWriteCharacteristic.properties.contains(.write) else {
            failSession(.unsupportedCharacteristic(Self.controlWriteUUID.uuidString))
            return
        }
        guard controlNotifyCharacteristic.properties.contains(.notify)
                || controlNotifyCharacteristic.properties.contains(.indicate) else {
            failSession(.unsupportedCharacteristic(Self.controlNotifyUUID.uuidString))
            return
        }
        guard authenticationWriteCharacteristic.properties.contains(.writeWithoutResponse) else {
            failSession(.unsupportedCharacteristic(Self.authenticationWriteUUID.uuidString))
            return
        }
        guard authenticationNotifyCharacteristic.properties.contains(.notify)
                || authenticationNotifyCharacteristic.properties.contains(.indicate) else {
            failSession(.unsupportedCharacteristic(Self.authenticationNotifyUUID.uuidString))
            return
        }

        beginCharacteristicSubscriptions()
    }

    private func failSession(_ error: ClientError) {
        emit(.log(.error, error.localizedDescription))
        pendingFailureError = error
        disconnectWasRequested = false
        pendingConnectionID = nil

        guard let peripheral = currentPeripheral else {
            resetGATTState()
            publishFailure(error)
            return
        }
        if peripheral.state == .disconnected {
            finishDisconnection(of: peripheral, error: nil)
        } else {
            if let currentDevice {
                updateState(.disconnecting(currentDevice))
            }
            scheduleDisconnectionWatchdog(for: peripheral)
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    private func reportCommandFailure(_ kind: CommandKind, _ error: ClientError) {
        emit(.commandFailed(kind, error))
        emit(.log(.error, error.localizedDescription))
    }

    private func finishDisconnection(
        of peripheral: CBPeripheral,
        error: Error?,
        forced: Bool = false
    ) {
        guard currentPeripheral === peripheral else { return }
        let requested = disconnectWasRequested
        let pendingFailure = pendingFailureError
        let nextConnectionID = pendingConnectionID

        disconnectionWatchdog?.cancel()
        disconnectionWatchdog = nil
        pendingConnectionID = nil
        disconnectWasRequested = false
        pendingFailureError = nil
        clearCurrentPeripheral(peripheral)
        if forced {
            peripheralsByID.removeAll()
            devicesByID.removeAll()
            discoveredDevices.removeAll()
            emit(.discoveryReset)
            rebuildCentralManager()
        }

        if let pendingFailure {
            publishFailure(pendingFailure)
            return
        }

        if let error, !requested {
            let clientError = ClientError.disconnected(error.localizedDescription)
            emit(.log(.error, clientError.localizedDescription))
            publishFailure(clientError)
        } else {
            emit(.log(.info, "Godox device disconnected."))
            updateState(.idle)
        }

        if !forced, let nextConnectionID,
           let nextPeripheral = peripheralsByID[nextConnectionID],
           let nextDevice = devicesByID[nextConnectionID] {
            beginConnection(to: nextPeripheral, device: nextDevice)
        }
    }

    private func scheduleDisconnectionWatchdog(for peripheral: CBPeripheral) {
        disconnectionWatchdog?.cancel()
        disconnectionWatchdog = Task { @MainActor [weak self, weak peripheral] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard let self, let peripheral,
                  self.currentPeripheral === peripheral else {
                return
            }
            self.disconnectionWatchdog = nil
            self.emit(.log(.warning, "CoreBluetooth did not confirm disconnection; local transport state was released."))
            self.finishDisconnection(of: peripheral, error: nil, forced: true)
        }
    }

    private func publishFailure(_ error: ClientError) {
        updateState(.failed(error.localizedDescription))
        emit(.failed(error))
    }

    /// Creates a new CoreBluetooth callback generation after a forced cleanup.
    /// Late callbacks from the retired manager fail the identity guards in the
    /// delegate methods and therefore cannot clear a newer connection attempt.
    private func rebuildCentralManager() {
        centralManager.delegate = nil
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    private func clearCurrentPeripheral(_ peripheral: CBPeripheral) {
        peripheral.delegate = nil
        resetGATTState()
        currentPeripheral = nil
        currentDevice = nil
    }

    private func resetGATTState() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        controlWriteTask?.cancel()
        controlWriteTask = nil

        controlService = nil
        authenticationService = nil
        controlWriteCharacteristic = nil
        controlNotifyCharacteristic = nil
        authenticationWriteCharacteristic = nil
        authenticationNotifyCharacteristic = nil
        discoveredControlCharacteristics = false
        discoveredAuthenticationCharacteristics = false
        subscriptionStep = .idle
        unacknowledgedWriteQueue.removeAll()
        controlWriteQueue.removeAll()
        controlWriteInFlight = false
    }

    private func updateState(_ newState: State) {
        guard state != newState else { return }
        state = newState
        emit(.stateChanged(newState))
    }

    private func emit(_ event: Event) {
        delegate?.bluetoothClient(didReceive: event)
    }

    private static func isCompatibleName(_ name: String) -> Bool {
        name.contains("-") && (name.hasPrefix("GD") || name.hasPrefix("Ami-"))
    }

    private static func description(for state: CBManagerState) -> String {
        switch state {
        case .unknown:
            return "state unknown"
        case .resetting:
            return "resetting"
        case .unsupported:
            return "unsupported on this Mac"
        case .unauthorized:
            return "permission denied"
        case .poweredOff:
            return "powered off"
        case .poweredOn:
            return "powered on"
        @unknown default:
            return "unrecognized state"
        }
    }
}

private extension BluetoothClient.CommandKind {
    var label: String {
        switch self {
        case .authentication:
            return "authentication"
        case .sync:
            return "sync"
        case .test:
            return "test"
        case .control:
            return "control"
        }
    }
}

extension BluetoothClient: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === centralManager else { return }

        if central.state == .poweredOn {
            emit(.log(.info, "Bluetooth is available."))
            if scanRequested, currentPeripheral == nil {
                beginScanning()
            } else if currentPeripheral == nil,
                      case .bluetoothUnavailable = state {
                updateState(.idle)
            } else if currentPeripheral == nil,
                      case .waitingForBluetooth = state {
                updateState(.idle)
            }
            return
        }

        if central.isScanning {
            central.stopScan()
        }

        let reason = Self.description(for: central.state)
        if currentPeripheral != nil {
            resetGATTState()
            currentPeripheral?.delegate = nil
            currentPeripheral = nil
            currentDevice = nil
        }
        pendingConnectionID = nil
        disconnectWasRequested = false
        pendingFailureError = nil
        disconnectionWatchdog?.cancel()
        disconnectionWatchdog = nil
        updateState(.bluetoothUnavailable(reason))
        emit(.log(.warning, "Bluetooth is unavailable (\(reason))."))
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard central === centralManager, central.isScanning else { return }

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let candidateName = (advertisedName ?? peripheral.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isCompatibleName(candidateName) else { return }

        let device = Device(id: peripheral.identifier, name: candidateName, rssi: RSSI.intValue)
        peripheralsByID[device.id] = peripheral
        devicesByID[device.id] = device
        discoveredDevices = devicesByID.values.sorted {
            if $0.name == $1.name { return $0.id.uuidString < $1.id.uuidString }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        emit(.discovered(device))
        emit(.log(.info, "Found compatible device \(device.name)."))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === centralManager,
              currentPeripheral === peripheral,
              let currentDevice else {
            return
        }
        if disconnectWasRequested {
            central.cancelPeripheralConnection(peripheral)
            return
        }

        updateState(.discovering(currentDevice))
        emit(.log(.info, "Connected. Discovering Godox services."))
        peripheral.discoverServices([
            Self.controlServiceUUID,
            Self.authenticationServiceUUID,
        ])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard central === centralManager,
              currentPeripheral === peripheral else {
            return
        }
        if disconnectWasRequested {
            finishDisconnection(of: peripheral, error: nil)
            return
        }

        let clientError = ClientError.connectionFailed(error?.localizedDescription ?? "unknown error")
        pendingConnectionID = nil
        pendingFailureError = nil
        clearCurrentPeripheral(peripheral)
        emit(.failed(clientError))
        emit(.log(.error, clientError.localizedDescription))
        updateState(.failed(clientError.localizedDescription))
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard central === centralManager else { return }
        finishDisconnection(of: peripheral, error: error)
    }
}

extension BluetoothClient: @MainActor CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard currentPeripheral === peripheral else { return }
        if let error {
            failSession(.serviceDiscoveryFailed(error.localizedDescription))
            return
        }

        let services = peripheral.services ?? []
        controlService = services.first { $0.uuid == Self.controlServiceUUID }
        authenticationService = services.first { $0.uuid == Self.authenticationServiceUUID }

        guard let controlService else {
            failSession(.missingService(Self.controlServiceUUID.uuidString))
            return
        }
        guard let authenticationService else {
            failSession(.missingService(Self.authenticationServiceUUID.uuidString))
            return
        }

        emit(.log(.info, "Required services found. Discovering characteristics."))
        peripheral.discoverCharacteristics(
            [Self.controlWriteUUID, Self.controlNotifyUUID],
            for: controlService
        )
        peripheral.discoverCharacteristics(
            [Self.authenticationWriteUUID, Self.authenticationNotifyUUID],
            for: authenticationService
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard currentPeripheral === peripheral else { return }
        if let error {
            failSession(.characteristicDiscoveryFailed(error.localizedDescription))
            return
        }

        if service.uuid == Self.controlServiceUUID {
            controlWriteCharacteristic = service.characteristics?.first {
                $0.uuid == Self.controlWriteUUID
            }
            controlNotifyCharacteristic = service.characteristics?.first {
                $0.uuid == Self.controlNotifyUUID
            }
            discoveredControlCharacteristics = true
        } else if service.uuid == Self.authenticationServiceUUID {
            authenticationWriteCharacteristic = service.characteristics?.first {
                $0.uuid == Self.authenticationWriteUUID
            }
            authenticationNotifyCharacteristic = service.characteristics?.first {
                $0.uuid == Self.authenticationNotifyUUID
            }
            discoveredAuthenticationCharacteristics = true
        }

        validateCharacteristicsAndSubscribe()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard currentPeripheral === peripheral else { return }
        if let error {
            failSession(.subscriptionFailed(error.localizedDescription))
            return
        }
        guard characteristic.isNotifying else {
            failSession(.subscriptionFailed("the device declined notifications"))
            return
        }

        if characteristic.uuid == Self.authenticationNotifyUUID,
           subscriptionStep == .authenticationRequested {
            emit(.log(.info, "Authentication notifications are active."))
            scheduleControlSubscription()
        } else if characteristic.uuid == Self.controlNotifyUUID,
                  subscriptionStep == .controlRequested,
                  let currentDevice {
            subscriptionTask?.cancel()
            subscriptionTask = nil
            subscriptionStep = .ready
            updateState(.ready(currentDevice))
            emit(.readyForAuthentication)
            emit(.log(.info, "Godox Bluetooth transport is ready."))
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard currentPeripheral === peripheral else { return }
        if let error {
            emit(.log(.error, "A Bluetooth notification failed: \(error.localizedDescription)"))
            return
        }
        guard let value = characteristic.value else {
            emit(.log(.warning, "The device sent an empty Bluetooth notification."))
            return
        }

        if characteristic.uuid == Self.authenticationNotifyUUID {
            emit(.notification(.authentication, value))
        } else if characteristic.uuid == Self.controlNotifyUUID {
            emit(.notification(.control, value))
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard currentPeripheral === peripheral,
              characteristic.uuid == Self.controlWriteUUID,
              controlWriteInFlight else {
            return
        }

        controlWriteInFlight = false
        if let error {
            reportCommandFailure(
                .control,
                .writeFailed(command: .control, message: error.localizedDescription)
            )
        } else {
            emit(.commandSent(.control))
            emit(.controlWriteCompleted)
            emit(.log(.info, "Control write acknowledged."))
        }
        scheduleNextControlWrite()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard currentPeripheral === peripheral else { return }
        flushUnacknowledgedWriteQueue()
    }
}
