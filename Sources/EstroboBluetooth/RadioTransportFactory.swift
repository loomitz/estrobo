import Foundation

#if canImport(EstroboCore)
import EstroboCore
#endif

/// Public construction surface for the production and deterministic radio adapters.
@MainActor
public enum RadioTransportFactory {
    public static var simulatedCandidate: RadioCandidate {
        SimulatedRadioTransport.candidate
    }

    public static func live() -> any RadioTransport {
        CoreBluetoothRadioTransport()
    }

    public static func simulated(
        scenario: SimulatedRadioScenario = .normal
    ) -> any RadioTransport {
        SimulatedRadioTransport(scenario: scenario)
    }
}
