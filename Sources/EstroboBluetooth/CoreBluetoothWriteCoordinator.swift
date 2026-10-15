import Foundation

#if canImport(EstroboCore)
import EstroboCore
#endif

struct CoreBluetoothWriteAccess: Equatable, Sendable {
    let maximumPayloadLength: Int
    let supportsWrite: Bool
    let canSendWithoutResponse: Bool
}

/// Safety-critical write policy used by the CoreBluetooth adapter.
///
/// Authentication and Sync may wait for CoreBluetooth backpressure. Test is
/// intentionally absent from every queue and fails immediately when occupied.
/// Control frames are released one at a time until the GATT callback completes.
@MainActor
final class CoreBluetoothWriteCoordinator {
    private struct DeferredWrite {
        let command: RadioCommand
        let payload: Data
    }

    var eventHandler: ((TransportEvent) -> Void)?

    private var deferredWrites: [DeferredWrite] = []
    private var controlWrites: [Data] = []
    private(set) var isControlWriteInFlight = false

    var hasPendingControlWrite: Bool {
        !controlWrites.isEmpty
    }

    init(eventHandler: ((TransportEvent) -> Void)? = nil) {
        self.eventHandler = eventHandler
    }

    func enqueueDeferred(
        _ payload: Data,
        command: RadioCommand,
        access: CoreBluetoothWriteAccess?,
        characteristicID: String
    ) {
        guard command == .authentication || command == .sync else {
            assertionFailure("Only authentication and Sync may wait for backpressure.")
            reportFailure(command, .busy("The command cannot be deferred."))
            return
        }
        guard validate(
            payload,
            command: command,
            access: access,
            characteristicID: characteristicID
        ) else {
            return
        }
        deferredWrites.append(DeferredWrite(command: command, payload: payload))
    }

    func flushDeferred(
        canSendWithoutResponse: () -> Bool,
        deliver: (Data) -> Void
    ) {
        while canSendWithoutResponse(), !deferredWrites.isEmpty {
            let write = deferredWrites.removeFirst()
            deliver(write.payload)
            eventHandler?(.commandSent(write.command))
            switch write.command {
            case .authentication:
                eventHandler?(.log(.info, "Authentication request sent."))
            case .sync:
                eventHandler?(.log(.info, "Clock synchronization sent."))
            case .test, .control:
                assertionFailure("Only authentication and Sync may be deferred.")
            }
        }
    }

    func sendTest(
        _ payload: Data,
        access: CoreBluetoothWriteAccess?,
        characteristicID: String,
        deliver: (Data) -> Void
    ) {
        guard validate(
            payload,
            command: .test,
            access: access,
            characteristicID: characteristicID
        ) else {
            return
        }
        guard access?.canSendWithoutResponse == true else {
            reportFailure(
                .test,
                .busy("The Bluetooth radio cannot deliver Test right now. Try again.")
            )
            return
        }

        deliver(payload)
        eventHandler?(.log(.info, "Explicit flash test sent."))
        eventHandler?(.commandSent(.test))
    }

    func enqueueControl(
        _ payload: Data,
        access: CoreBluetoothWriteAccess?,
        characteristicID: String
    ) {
        guard validate(
            payload,
            command: .control,
            access: access,
            characteristicID: characteristicID
        ) else {
            return
        }
        controlWrites.append(payload)
    }

    @discardableResult
    func beginNextControlWrite(deliver: (Data) -> Void) -> Bool {
        guard !isControlWriteInFlight, !controlWrites.isEmpty else {
            return false
        }
        let payload = controlWrites.removeFirst()
        isControlWriteInFlight = true
        deliver(payload)
        eventHandler?(.controlWriteStarted)
        return true
    }

    func completeControlWrite(errorMessage: String?) {
        guard isControlWriteInFlight else { return }
        isControlWriteInFlight = false
        if let errorMessage {
            reportFailure(
                .control,
                .writeFailed(command: .control, message: errorMessage)
            )
        } else {
            eventHandler?(.commandSent(.control))
            eventHandler?(.controlWriteCompleted)
            eventHandler?(.log(.info, "Control write acknowledged."))
        }
    }

    func reset() {
        deferredWrites.removeAll()
        controlWrites.removeAll()
        isControlWriteInFlight = false
    }

    private func validate(
        _ payload: Data,
        command: RadioCommand,
        access: CoreBluetoothWriteAccess?,
        characteristicID: String
    ) -> Bool {
        guard let access else {
            reportFailure(command, .notReady)
            return false
        }
        guard payload.count <= access.maximumPayloadLength else {
            reportFailure(
                command,
                .payloadTooLarge(command: command, maximum: access.maximumPayloadLength)
            )
            return false
        }
        guard access.supportsWrite else {
            reportFailure(command, .unsupportedCharacteristic(characteristicID))
            return false
        }
        return true
    }

    private func reportFailure(_ command: RadioCommand, _ error: RadioTransportError) {
        eventHandler?(.commandFailed(command, error))
        eventHandler?(.log(.error, error.localizedDescription))
    }
}
