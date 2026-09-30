import Foundation

#if canImport(EstroboBluetooth)
import EstroboBluetooth
#endif
#if canImport(EstroboCore)
import EstroboCore
#endif
#if canImport(EstroboPersistence)
import EstroboPersistence
#endif

/// Mac launch-mode composition for the shared simulated radio adapter.
///
/// Every preference that could identify a radio or retain physical restoration
/// state is replaced with an isolated in-memory adapter.
@MainActor
enum MockRadioRuntime {
    static let launchArgument = "--mock-radio"
    static let onboardingLaunchArgument = "--show-onboarding"
    static let scenarioArgumentPrefix = "--mock-radio-scenario="

    static func isRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(launchArgument)
    }

    static func makeControllerIfRequested(
        arguments: [String] = CommandLine.arguments
    ) -> GodoxSessionController? {
        guard isRequested(arguments: arguments) else { return nil }
        return makeController(
            showOnboarding: arguments.contains(onboardingLaunchArgument),
            scenario: requestedScenario(arguments: arguments)
        )
    }

    static func makeController(
        showOnboarding: Bool = false,
        scenario: SimulatedRadioScenario = .normal
    ) -> GodoxSessionController {
        let persistence = PersistenceServicesFactory.inMemory()
        let controller = GodoxSessionController(
            transport: RadioTransportFactory.simulated(scenario: scenario),
            deadlineScheduler: LiveSessionDeadlineScheduler(),
            visibilityPreferences: persistence.groupVisibility,
            restorationStore: persistence.restorations,
            savedRadioStore: persistence.savedRadios,
            changeDeliveryPreferences: persistence.changeDelivery,
            transmitterProfilePreferences: persistence.transmitterProfiles,
            studioLibraryStore: persistence.studioLibrary
        )
        // Keep the synthetic B reference on a valid 1/3-EV scale so the
        // relationship-preserving global control is immediately exercisable.
        controller.setFlashModel("ad600", assigned: false, to: .b)
        if !showOnboarding {
            _ = controller.completeWorkspaceConfiguration(
                profileID: controller.transmitterProfile.id,
                selectedGroups: [.b, .c],
                assignedFlashModelIDs: [
                    .b: ["ad600pro-ii"],
                    .c: ["ad400pro"],
                ]
            )
        }
        controller.rememberSelectedRadio = false
        return controller
    }

    private static func requestedScenario(
        arguments: [String]
    ) -> SimulatedRadioScenario {
        guard let value = arguments.first(where: {
            $0.hasPrefix(scenarioArgumentPrefix)
        })?.dropFirst(scenarioArgumentPrefix.count),
        let scenario = SimulatedRadioScenario(rawValue: String(value)) else {
            return .normal
        }
        return scenario
    }
}
