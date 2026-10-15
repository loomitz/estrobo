import Foundation

/// A radio discovered by a transport adapter.
///
/// The identifier is local to the current Apple device. Callers must not assume
/// that macOS and iOS assign the same identifier to the same physical radio.
public struct RadioCandidate: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int

    public init(id: UUID, name: String, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

/// Commands accepted by a radio transport.
///
/// The concrete adapter owns their delivery policy: Test is fail-fast and is
/// never queued or retried, while control writes are serialized.
public enum RadioCommand: Equatable, Sendable {
    case authentication
    case sync
    case test
    case control

    fileprivate var label: String {
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

public enum RadioTransportState: Equatable, Sendable {
    case idle
    case waitingForBluetooth
    case bluetoothUnavailable(String)
    case scanning
    case connecting(RadioCandidate)
    case discovering(RadioCandidate)
    case subscribing(RadioCandidate)
    case ready(RadioCandidate)
    case disconnecting(RadioCandidate)
    case failed(String)
}

public enum RadioNotificationSource: Equatable, Sendable {
    case authentication
    case control
}

public enum RadioTransportLogLevel: Equatable, Sendable {
    case debug
    case info
    case warning
    case error
}

public enum RadioTransportError: LocalizedError, Equatable, Sendable {
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
    case payloadTooLarge(command: RadioCommand, maximum: Int)
    case writeFailed(command: RadioCommand, message: String)

    public var errorDescription: String? {
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

public enum TransportEvent: Equatable, Sendable {
    case stateChanged(RadioTransportState)
    case discoveryReset
    case discovered(RadioCandidate)
    case log(RadioTransportLogLevel, String)
    case readyForAuthentication
    case notification(RadioNotificationSource, Data)
    case commandSent(RadioCommand)
    case controlWriteStarted
    case controlWriteCompleted
    case commandFailed(RadioCommand, RadioTransportError)
    case failed(RadioTransportError)
}

/// Platform-independent seam between session behavior and radio I/O.
///
/// Adapters deliver events on the main actor. Payloads may cross the seam for
/// protocol decoding, but adapters must never include them in log events.
@MainActor
public protocol RadioTransport: AnyObject {
    var eventHandler: ((TransportEvent) -> Void)? { get set }
    var isSimulation: Bool { get }

    func startScanning()
    func stopScanning()
    func connect(to candidate: RadioCandidate)
    func disconnect()
    func forceResetConnection()
    func sendAuthentication(_ payload: Data)
    func sendSync(_ payload: Data)
    func sendTest(_ payload: Data)
    func sendControl(_ payload: Data)
}

extension RadioTransport {
    public var isSimulation: Bool { false }
}
