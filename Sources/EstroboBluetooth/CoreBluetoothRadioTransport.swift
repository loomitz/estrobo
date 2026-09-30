import Foundation
import CoreBluetooth

#if canImport(EstroboCore)
import EstroboCore
#endif

/// A deliberately small CoreBluetooth central for the Godox proof of concept.
///
/// This type owns transport and GATT sequencing only. Callers are responsible for
/// constructing and validating authentication, sync, and control payloads.
@MainActor
final class CoreBluetoothRadioTransport: NSObject, RadioTransport {
    var eventHandler: ((TransportEvent) -> Void)?

    private(set) var state: RadioTransportState = .idle
    private(set) var discoveredDevices: [RadioCandidate] = []

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

    enum ScanStartDisposition: Equatable {
        case ready
        case waiting
        case unavailable(reason: String, resumesIfPoweredOn: Bool)
    }

    private struct WriteContext {
        let peripheral: CBPeripheral
        let characteristic: CBCharacteristic
        let access: CoreBluetoothWriteAccess
    }

    private var centralManager: CBCentralManager!
    private var scanRequested = false

    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var devicesByID: [UUID: RadioCandidate] = [:]
    private var currentPeripheral: CBPeripheral?
    private var currentDevice: RadioCandidate?
    private var pendingConnectionID: UUID?
    private var disconnectWasRequested = false
    private var pendingFailureError: RadioTransportError?
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

    private lazy var writeCoordinator = CoreBluetoothWriteCoordinator { [weak self] event in
        self?.emit(event)
    }
    private var controlWriteTask: Task<Void, Never>?

    init(eventHandler: ((TransportEvent) -> Void)? = nil) {
        self.eventHandler = eventHandler
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard currentPeripheral == nil else {
            let error = RadioTransportError.busy("Disconnect the current Godox device before scanning.")
            emit(.failed(error))
            emit(.log(.warning, error.localizedDescription))
            return
        }

        switch Self.scanStartDisposition(for: centralManager.state) {
        case .ready:
            scanRequested = true
            beginScanning()
        case .waiting:
            scanRequested = true
            updateState(.waitingForBluetooth, forceEvent: true)
            emit(.log(.info, "Waiting for Bluetooth to become available."))
        case .unavailable(let reason, let resumesIfPoweredOn):
            scanRequested = resumesIfPoweredOn
            updateState(.bluetoothUnavailable(reason), forceEvent: true)
            emit(.log(.warning, "Bluetooth is unavailable (\(reason))."))
        }
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

    func connect(to device: RadioCandidate) {
        connect(to: device.id)
    }

    func connect(to identifier: UUID) {
        guard centralManager.state == .poweredOn else {
            let reason = Self.description(for: centralManager.state)
            let error = RadioTransportError.bluetoothUnavailable(reason)
            emit(.failed(error))
            updateState(.bluetoothUnavailable(reason))
            return
        }
        guard let peripheral = peripheralsByID[identifier], let device = devicesByID[identifier] else {
            let error = RadioTransportError.unknownDevice(identifier)
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
            beginPeripheralDisconnection(currentPeripheral)
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
        beginPeripheralDisconnection(peripheral)
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
    /// The payload itself is never emitted to logs or transport log events.
    func sendAuthentication(_ payload: Data) {
        enqueueDeferredWrite(payload, command: .authentication)
    }

    /// Writes a caller-built clock synchronization payload to FFF1 without response.
    func sendSync(_ payload: Data) {
        enqueueDeferredWrite(payload, command: .sync)
    }

    /// Writes an explicit user-requested flash test payload to FFF1 without response.
    ///
    /// A Test command can fire physical flashes, so it is deliberately fail-fast:
    /// unlike authentication and sync it is never queued for a later radio-ready
    /// callback. This prevents a timed-out Test from firing unexpectedly afterward.
    func sendTest(_ payload: Data) {
        guard let context = authenticationWriteContext() else {
            writeCoordinator.sendTest(
                payload,
                access: nil,
                characteristicID: Self.authenticationWriteUUID.uuidString,
                deliver: { _ in }
            )
            return
        }
        writeCoordinator.sendTest(
            payload,
            access: context.access,
            characteristicID: Self.authenticationWriteUUID.uuidString
        ) { payload in
            context.peripheral.writeValue(
                payload,
                for: context.characteristic,
                type: .withoutResponse
            )
        }
    }

    /// Serializes caller-built A0/A1 (or heartbeat) frames through FEC7 with response.
    func sendControl(_ payload: Data) {
        let context = controlWriteContext()
        writeCoordinator.enqueueControl(
            payload,
            access: context?.access,
            characteristicID: Self.controlWriteUUID.uuidString
        )
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

    private func beginConnection(to peripheral: CBPeripheral, device: RadioCandidate) {
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

    private func enqueueDeferredWrite(_ payload: Data, command: RadioCommand) {
        let context = authenticationWriteContext()
        writeCoordinator.enqueueDeferred(
            payload,
            command: command,
            access: context?.access,
            characteristicID: Self.authenticationWriteUUID.uuidString
        )
        flushDeferredWrites(context: context)
    }

    private func flushDeferredWrites(context: WriteContext? = nil) {
        guard let context = context ?? authenticationWriteContext() else { return }
        writeCoordinator.flushDeferred(
            canSendWithoutResponse: {
                context.peripheral.canSendWriteWithoutResponse
            },
            deliver: { payload in
                context.peripheral.writeValue(
                    payload,
                    for: context.characteristic,
                    type: .withoutResponse
                )
            }
        )
    }

    private func scheduleNextControlWrite() {
        guard !writeCoordinator.isControlWriteInFlight,
              controlWriteTask == nil,
              writeCoordinator.hasPendingControlWrite else {
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
                  let context = self.controlWriteContext() else {
                return
            }
            self.writeCoordinator.beginNextControlWrite { payload in
                context.peripheral.writeValue(
                    payload,
                    for: context.characteristic,
                    type: .withResponse
                )
            }
        }
    }

    private func authenticationWriteContext() -> WriteContext? {
        guard let peripheral = readyPeripheral(),
              let characteristic = authenticationWriteCharacteristic else {
            return nil
        }
        return WriteContext(
            peripheral: peripheral,
            characteristic: characteristic,
            access: CoreBluetoothWriteAccess(
                maximumPayloadLength: peripheral.maximumWriteValueLength(
                    for: .withoutResponse
                ),
                supportsWrite: characteristic.properties.contains(.writeWithoutResponse),
                canSendWithoutResponse: peripheral.canSendWriteWithoutResponse
            )
        )
    }

    private func controlWriteContext() -> WriteContext? {
        guard let peripheral = readyPeripheral(),
              let characteristic = controlWriteCharacteristic else {
            return nil
        }
        return WriteContext(
            peripheral: peripheral,
            characteristic: characteristic,
            access: CoreBluetoothWriteAccess(
                maximumPayloadLength: peripheral.maximumWriteValueLength(for: .withResponse),
                supportsWrite: characteristic.properties.contains(.write),
                canSendWithoutResponse: false
            )
        )
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

    private func failSession(_ error: RadioTransportError) {
        emit(.log(.error, error.localizedDescription))
        pendingFailureError = error
        disconnectWasRequested = false
        pendingConnectionID = nil

        guard let peripheral = currentPeripheral else {
            resetGATTState()
            publishFailure(error)
            return
        }
        if peripheral.state != .disconnected, let currentDevice {
            updateState(.disconnecting(currentDevice))
        }
        beginPeripheralDisconnection(peripheral)
    }

    /// Every path that tears down a peripheral must invalidate queued control
    /// writes before CoreBluetooth begins its asynchronous disconnect. This
    /// prevents a delayed A0/A1 or heartbeat from starting while the link is
    /// still closing.
    private func beginPeripheralDisconnection(_ peripheral: CBPeripheral) {
        cancelPendingWrites()
        if peripheral.state == .disconnected {
            finishDisconnection(of: peripheral, error: nil)
        } else {
            scheduleDisconnectionWatchdog(for: peripheral)
            centralManager.cancelPeripheralConnection(peripheral)
        }
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
            let clientError = RadioTransportError.disconnected(error.localizedDescription)
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

    private func publishFailure(_ error: RadioTransportError) {
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
        cancelPendingWrites()

        controlService = nil
        authenticationService = nil
        controlWriteCharacteristic = nil
        controlNotifyCharacteristic = nil
        authenticationWriteCharacteristic = nil
        authenticationNotifyCharacteristic = nil
        discoveredControlCharacteristics = false
        discoveredAuthenticationCharacteristics = false
        subscriptionStep = .idle
    }

    private func cancelPendingWrites() {
        controlWriteTask?.cancel()
        controlWriteTask = nil
        writeCoordinator.reset()
    }

    private func updateState(
        _ newState: RadioTransportState,
        forceEvent: Bool = false
    ) {
        if state == newState {
            if forceEvent { emit(.stateChanged(newState)) }
            return
        }
        state = newState
        emit(.stateChanged(newState))
    }

    private func emit(_ event: TransportEvent) {
        eventHandler?(event)
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

    static func scanStartDisposition(
        for state: CBManagerState
    ) -> ScanStartDisposition {
        switch state {
        case .poweredOn:
            return .ready
        case .unknown, .resetting, .poweredOff:
            return .waiting
        case .unauthorized:
            return .unavailable(
                reason: description(for: state),
                resumesIfPoweredOn: true
            )
        case .unsupported:
            return .unavailable(
                reason: description(for: state),
                resumesIfPoweredOn: false
            )
        @unknown default:
            return .unavailable(
                reason: description(for: state),
                resumesIfPoweredOn: false
            )
        }
    }
}

extension CoreBluetoothRadioTransport: @preconcurrency CBCentralManagerDelegate {
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
        guard let candidateName = GodoxBluetoothDeviceName.compatibleName(
            from: advertisedName ?? peripheral.name ?? ""
        ) else { return }

        let device = RadioCandidate(
            id: peripheral.identifier,
            name: candidateName,
            rssi: RSSI.intValue
        )
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

        let clientError = RadioTransportError.connectionFailed(
            error?.localizedDescription ?? "unknown error"
        )
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

extension CoreBluetoothRadioTransport: @preconcurrency CBPeripheralDelegate {
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
              writeCoordinator.isControlWriteInFlight else {
            return
        }

        writeCoordinator.completeControlWrite(errorMessage: error?.localizedDescription)
        scheduleNextControlWrite()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard currentPeripheral === peripheral else { return }
        flushDeferredWrites()
    }
}
