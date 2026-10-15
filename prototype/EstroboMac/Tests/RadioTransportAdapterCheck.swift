import Foundation

@main
@MainActor
enum RadioTransportAdapterCheck {
    private static let characteristicID = "FFF1"

    static func main() {
        checkBusyTestIsNeverDeferred()
        checkTestTimeoutAndFailureNeverRetry()
        checkControlWritesStaySerial()
        checkAuthenticationPayloadNeverEntersLogsOrErrors()
        print("Radio transport delivery policy, redaction, and serial writes verified")
    }

    private static func checkBusyTestIsNeverDeferred() {
        var events: [TransportEvent] = []
        var deliveries: [Data] = []
        let coordinator = CoreBluetoothWriteCoordinator { events.append($0) }
        let payload = Data("synthetic-test".utf8)

        coordinator.sendTest(
            payload,
            access: writeAccess(canSendWithoutResponse: false),
            characteristicID: characteristicID,
            deliver: { deliveries.append($0) }
        )

        expect(deliveries.isEmpty)
        expect(events.contains {
            guard case .commandFailed(.test, .busy) = $0 else { return false }
            return true
        })

        // A later CoreBluetooth readiness callback only flushes authentication
        // and Sync. It cannot revive the rejected physical Test.
        coordinator.flushDeferred(
            canSendWithoutResponse: { true },
            deliver: { deliveries.append($0) }
        )
        _ = coordinator.beginNextControlWrite { deliveries.append($0) }
        expect(deliveries.isEmpty, "Test ocupado nunca debe entregarse después")
    }

    private static func checkTestTimeoutAndFailureNeverRetry() {
        var deliveries: [Data] = []
        let coordinator = CoreBluetoothWriteCoordinator()
        let payload = Data("single-test".utf8)

        coordinator.sendTest(
            payload,
            access: writeAccess(canSendWithoutResponse: true),
            characteristicID: characteristicID,
            deliver: { deliveries.append($0) }
        )
        expect(deliveries == [payload])

        // A controller timeout or late failure has no Test state to resume.
        // Readiness, control progression, and reset must not deliver it again.
        coordinator.flushDeferred(
            canSendWithoutResponse: { true },
            deliver: { deliveries.append($0) }
        )
        _ = coordinator.beginNextControlWrite { deliveries.append($0) }
        coordinator.reset()
        coordinator.flushDeferred(
            canSendWithoutResponse: { true },
            deliver: { deliveries.append($0) }
        )
        expect(deliveries == [payload], "Test no debe reintentarse tras timeout o fallo")
    }

    private static func checkControlWritesStaySerial() {
        var events: [TransportEvent] = []
        var deliveries: [Data] = []
        let coordinator = CoreBluetoothWriteCoordinator { events.append($0) }
        let first = Data([0xF0, 0xA0])
        let second = Data([0xF0, 0xA1])
        let access = writeAccess(canSendWithoutResponse: false)

        coordinator.enqueueControl(
            first,
            access: access,
            characteristicID: "FEC7"
        )
        coordinator.enqueueControl(
            second,
            access: access,
            characteristicID: "FEC7"
        )

        expect(coordinator.beginNextControlWrite { deliveries.append($0) })
        expect(deliveries == [first])
        expect(
            !coordinator.beginNextControlWrite { deliveries.append($0) },
            "El segundo control no debe iniciar antes del callback GATT"
        )
        expect(deliveries == [first])

        coordinator.completeControlWrite(errorMessage: nil)
        expect(coordinator.beginNextControlWrite { deliveries.append($0) })
        expect(deliveries == [first, second])
        expect(events.filter {
            if case .controlWriteStarted = $0 { return true }
            return false
        }.count == 2)
    }

    private static func checkAuthenticationPayloadNeverEntersLogsOrErrors() {
        let sentinelText = "AUTH-SENTINEL-DO-NOT-LOG"
        let sentinel = Data(sentinelText.utf8)
        let sentinelHex = sentinel.map { String(format: "%02x", $0) }.joined()
        var events: [TransportEvent] = []
        var deliveries: [Data] = []
        let coordinator = CoreBluetoothWriteCoordinator { events.append($0) }

        coordinator.enqueueDeferred(
            sentinel,
            command: .authentication,
            access: writeAccess(
                maximumPayloadLength: sentinel.count,
                canSendWithoutResponse: true
            ),
            characteristicID: characteristicID
        )
        coordinator.flushDeferred(
            canSendWithoutResponse: { true },
            deliver: { deliveries.append($0) }
        )
        expect(deliveries == [sentinel])

        coordinator.enqueueDeferred(
            sentinel,
            command: .authentication,
            access: writeAccess(
                maximumPayloadLength: sentinel.count - 1,
                canSendWithoutResponse: true
            ),
            characteristicID: characteristicID
        )

        for text in diagnosticTexts(from: events) {
            let lowercased = text.lowercased()
            expect(!text.contains(sentinelText), "Un log expuso el payload de autenticación")
            expect(!lowercased.contains(sentinelHex), "Un log expuso bytes de autenticación")
        }
    }

    private static func diagnosticTexts(from events: [TransportEvent]) -> [String] {
        events.compactMap { event in
            switch event {
            case .log(_, let message):
                return message
            case .commandFailed(_, let error), .failed(let error):
                return error.localizedDescription
            case .stateChanged, .discoveryReset, .discovered,
                 .readyForAuthentication, .notification, .commandSent,
                 .controlWriteStarted, .controlWriteCompleted:
                return nil
            }
        }
    }

    private static func writeAccess(
        maximumPayloadLength: Int = 512,
        canSendWithoutResponse: Bool
    ) -> CoreBluetoothWriteAccess {
        CoreBluetoothWriteAccess(
            maximumPayloadLength: maximumPayloadLength,
            supportsWrite: true,
            canSendWithoutResponse: canSendWithoutResponse
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Verificación fallida"
    ) {
        guard condition() else { preconditionFailure(message) }
    }
}
