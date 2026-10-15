import Foundation

@main
@MainActor
enum SimulatedRadioTransportCheck {
    static func main() async throws {
        try await checkNormalScenario()
        await checkAuthenticationRejected()
        await checkSyncTimeout()
        try await checkControlWriteFailure()
        try await checkFEC8Timeout()
        try await checkDisconnectDuringWrite()
        await checkBluetoothDenied()
        print("Simulated radio scenarios verified without CoreBluetooth")
    }

    private static func checkNormalScenario() async throws {
        let fixture = await connectedFixture(.normal)
        fixture.transport.sendAuthentication(Data("redacted-auth".utf8))
        await fixture.waitForEvent("successful authentication") {
            guard case .notification(.authentication, let data) = $0 else { return false }
            return String(data: data, encoding: .utf8)?.hasPrefix("PWOK,") == true
        }
        expect(fixture.events.contains {
            guard case .commandSent(.authentication) = $0 else { return false }
            return true
        })
        expect(fixture.events.contains {
            guard case .notification(.authentication, let data) = $0 else { return false }
            return String(data: data, encoding: .utf8)?.hasPrefix("PWOK,") == true
        })

        fixture.transport.sendSync(Data("synthetic-sync".utf8))
        await fixture.waitForEvent("sync delivery") {
            guard case .commandSent(.sync) = $0 else { return false }
            return true
        }
        expect(fixture.events.contains {
            guard case .commandSent(.sync) = $0 else { return false }
            return true
        })

        fixture.transport.sendControl(try groupFrame())
        await fixture.waitForEvent("FEC8 acknowledgement") {
            guard case .notification(.control, Data([0xF0, 0xA1])) = $0 else { return false }
            return true
        }
        expect(fixture.events.contains {
            guard case .controlWriteStarted = $0 else { return false }
            return true
        })
        expect(fixture.events.contains {
            guard case .controlWriteCompleted = $0 else { return false }
            return true
        })
        expect(fixture.events.contains {
            guard case .notification(.control, Data([0xF0, 0xA1])) = $0 else { return false }
            return true
        })
    }

    private static func checkAuthenticationRejected() async {
        let fixture = await connectedFixture(.authenticationRejected)
        fixture.transport.sendAuthentication(Data("redacted-auth".utf8))
        await fixture.waitForEvent("rejected authentication") {
            guard case .notification(.authentication, let data) = $0 else { return false }
            return data == Data("PWNO".utf8)
        }
        expect(fixture.events.contains {
            guard case .notification(.authentication, let data) = $0 else { return false }
            return data == Data("PWNO".utf8)
        })
    }

    private static func checkSyncTimeout() async {
        let fixture = await connectedFixture(.syncTimeout)
        fixture.transport.sendSync(Data("synthetic-sync".utf8))
        await fixture.observeUnexpectedEvents()
        expect(!fixture.events.contains {
            guard case .commandSent(.sync) = $0 else { return false }
            return true
        })
    }

    private static func checkControlWriteFailure() async throws {
        let fixture = await connectedFixture(.controlWriteFailure)
        fixture.transport.sendControl(try groupFrame())
        await fixture.waitForEvent("control write failure") {
            guard case .commandFailed(.control, .writeFailed) = $0 else { return false }
            return true
        }
        await fixture.observeUnexpectedEvents()
        expect(fixture.events.contains {
            guard case .commandFailed(.control, .writeFailed) = $0 else { return false }
            return true
        })
        expect(!fixture.events.contains {
            guard case .controlWriteCompleted = $0 else { return false }
            return true
        })
    }

    private static func checkFEC8Timeout() async throws {
        let fixture = await connectedFixture(.fec8Timeout)
        fixture.transport.sendControl(try groupFrame())
        await fixture.waitForEvent("GATT acknowledgement without FEC8") {
            guard case .controlWriteCompleted = $0 else { return false }
            return true
        }
        await fixture.observeUnexpectedEvents()
        expect(fixture.events.contains {
            guard case .controlWriteCompleted = $0 else { return false }
            return true
        })
        expect(!fixture.events.contains {
            guard case .notification(.control, _) = $0 else { return false }
            return true
        })
    }

    private static func checkDisconnectDuringWrite() async throws {
        let fixture = await connectedFixture(.disconnectDuringWrite)
        fixture.transport.sendControl(try groupFrame())
        await fixture.waitForEvent("disconnection during write") {
            guard case .failed(.disconnected) = $0 else { return false }
            return true
        }
        expect(fixture.events.contains {
            guard case .failed(.disconnected) = $0 else { return false }
            return true
        })
    }

    private static func checkBluetoothDenied() async {
        let fixture = Fixture(scenario: .bluetoothDenied)
        fixture.transport.startScanning()
        await fixture.waitForEvent("Bluetooth permission denial") {
            guard case .stateChanged(.bluetoothUnavailable("permission denied")) = $0 else {
                return false
            }
            return true
        }
        await fixture.observeUnexpectedEvents()

        expect(fixture.events.contains {
            guard case .stateChanged(.bluetoothUnavailable("permission denied")) = $0 else {
                return false
            }
            return true
        })
        expect(!fixture.events.contains {
            guard case .discovered = $0 else { return false }
            return true
        })
    }

    private static func connectedFixture(
        _ scenario: SimulatedRadioScenario
    ) async -> Fixture {
        let fixture = Fixture(scenario: scenario)
        fixture.transport.connect(to: SimulatedRadioTransport.candidate)
        await fixture.waitForEvent("connection ready for authentication") {
            guard case .readyForAuthentication = $0 else { return false }
            return true
        }
        expect(fixture.events.contains {
            guard case .readyForAuthentication = $0 else { return false }
            return true
        }, "El escenario \(scenario.rawValue) no alcanzó autenticación; eventos: \(fixture.events)")
        expect(fixture.events.compactMap { event -> String? in
            switch event {
            case .stateChanged(.connecting): return "connecting"
            case .stateChanged(.discovering): return "discovering"
            case .stateChanged(.subscribing): return "subscribing"
            case .stateChanged(.ready): return "ready"
            case .readyForAuthentication: return "readyForAuthentication"
            default: return nil
            }
        } == ["connecting", "discovering", "subscribing", "ready", "readyForAuthentication"],
        "Connection milestones must remain serial and ordered")
        return fixture
    }

    private static func groupFrame() throws -> Data {
        guard let power = ManualPower.value(decimal: 27) else {
            preconditionFailure("Falta potencia de prueba")
        }
        return try SafeGodoxProtocol.manualGroupFrame(
            group: .b,
            snapshot: ManualGroupSnapshot(power: power, modeling: .proportional)
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Verificación fallida"
    ) {
        guard condition() else { preconditionFailure(message) }
    }

    @MainActor
    private final class Fixture {
        let transport: SimulatedRadioTransport
        var events: [TransportEvent] = []

        init(scenario: SimulatedRadioScenario) {
            // Scenario semantics must not depend on the runner meeting Demo's
            // wall-clock timings. The adapter retains its serial timelines.
            transport = SimulatedRadioTransport(
                scenario: scenario,
                waitForMilliseconds: { _ in await Task.yield() }
            )
            transport.eventHandler = { [weak self] event in
                self?.events.append(event)
            }
        }

        func waitForEvent(
            _ description: String,
            matching predicate: (TransportEvent) -> Bool
        ) async {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while ContinuousClock.now < deadline {
                if events.contains(where: predicate) { return }
                try? await Task.sleep(for: .milliseconds(1))
            }
            preconditionFailure(
                "Scenario \(transport.scenario.rawValue) did not reach \(description); events: \(events)"
            )
        }

        func observeUnexpectedEvents() async {
            // Keep negative assertions observable after queued tasks run. The
            // injected adapter waits yield immediately, including faulty emits.
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
