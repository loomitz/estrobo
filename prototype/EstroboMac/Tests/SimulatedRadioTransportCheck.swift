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
        await wait(milliseconds: 90)
        expect(fixture.events.contains {
            guard case .commandSent(.authentication) = $0 else { return false }
            return true
        })
        expect(fixture.events.contains {
            guard case .notification(.authentication, let data) = $0 else { return false }
            return String(data: data, encoding: .utf8)?.hasPrefix("PWOK,") == true
        })

        fixture.transport.sendSync(Data("synthetic-sync".utf8))
        await wait(milliseconds: 70)
        expect(fixture.events.contains {
            guard case .commandSent(.sync) = $0 else { return false }
            return true
        })

        fixture.transport.sendControl(try groupFrame())
        await wait(milliseconds: 110)
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
        await wait(milliseconds: 90)
        expect(fixture.events.contains {
            guard case .notification(.authentication, let data) = $0 else { return false }
            return data == Data("PWNO".utf8)
        })
    }

    private static func checkSyncTimeout() async {
        let fixture = await connectedFixture(.syncTimeout)
        fixture.transport.sendSync(Data("synthetic-sync".utf8))
        await wait(milliseconds: 50)
        expect(!fixture.events.contains {
            guard case .commandSent(.sync) = $0 else { return false }
            return true
        })
    }

    private static func checkControlWriteFailure() async throws {
        let fixture = await connectedFixture(.controlWriteFailure)
        fixture.transport.sendControl(try groupFrame())
        await wait(milliseconds: 80)
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
        await wait(milliseconds: 110)
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
        await wait(milliseconds: 80)
        expect(fixture.events.contains {
            guard case .failed(.disconnected) = $0 else { return false }
            return true
        })
    }

    private static func checkBluetoothDenied() async {
        var events: [TransportEvent] = []
        let transport = SimulatedRadioTransport(scenario: .bluetoothDenied)
        transport.eventHandler = { events.append($0) }
        transport.startScanning()
        await wait(milliseconds: 45)

        expect(events.contains {
            guard case .stateChanged(.bluetoothUnavailable("permission denied")) = $0 else {
                return false
            }
            return true
        })
        expect(!events.contains {
            guard case .discovered = $0 else { return false }
            return true
        })
    }

    private static func connectedFixture(
        _ scenario: SimulatedRadioScenario
    ) async -> Fixture {
        let fixture = Fixture(scenario: scenario)
        fixture.transport.connect(to: SimulatedRadioTransport.candidate)
        await wait(milliseconds: 180)
        expect(fixture.events.contains {
            guard case .readyForAuthentication = $0 else { return false }
            return true
        }, "El escenario \(scenario.rawValue) no alcanzó autenticación; eventos: \(fixture.events)")
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

    private static func wait(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
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
            transport = SimulatedRadioTransport(scenario: scenario)
            transport.eventHandler = { [weak self] event in
                self?.events.append(event)
            }
        }
    }
}
