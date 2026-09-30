import Foundation
import EstroboBluetooth

struct UITestConfiguration: Equatable {
    enum LayoutOverride: String {
        case compact
        case regular
    }

    enum Fixture: String {
        case onboarding
        case workspace
        case connected
        case recoveryWrongUUID = "recovery-wrong-uuid"
        case permissionDenied = "permission-denied"
        case savedRadios = "saved-radios"
    }

    let isEnabled: Bool
    let fixture: Fixture
    let scenario: SimulatedRadioScenario
    let language: EstroboLanguage?
    let appearance: EstroboAppearance?
    let layoutOverride: LayoutOverride?

    init(
        isEnabled: Bool,
        fixture: Fixture,
        scenario: SimulatedRadioScenario,
        language: EstroboLanguage?,
        appearance: EstroboAppearance?,
        layoutOverride: LayoutOverride? = nil
    ) {
        self.isEnabled = isEnabled
        self.fixture = fixture
        self.scenario = scenario
        self.language = language
        self.appearance = appearance
        self.layoutOverride = layoutOverride
    }

    static func current(processInfo: ProcessInfo = .processInfo) -> UITestConfiguration {
        parse(arguments: processInfo.arguments)
    }

    static func parse(arguments: [String]) -> UITestConfiguration {
        guard arguments.contains("--ui-testing") else {
            return UITestConfiguration(
                isEnabled: false,
                fixture: .onboarding,
                scenario: .normal,
                language: nil,
                appearance: nil,
                layoutOverride: nil
            )
        }

        let fixture = value(after: "--fixture", in: arguments)
            .flatMap(Fixture.init(rawValue:)) ?? .onboarding
        let requestedScenario = value(after: "--scenario", in: arguments)
            .flatMap(SimulatedRadioScenario.init(rawValue:)) ?? .normal
        let scenario: SimulatedRadioScenario = fixture == .permissionDenied
            ? .bluetoothDenied
            : requestedScenario

        return UITestConfiguration(
            isEnabled: true,
            fixture: fixture,
            scenario: scenario,
            language: value(after: "--language", in: arguments)
                .flatMap(EstroboLanguage.init(rawValue:)),
            appearance: value(after: "--appearance", in: arguments)
                .flatMap(EstroboAppearance.init(rawValue:)),
            layoutOverride: value(after: "--layout", in: arguments)
                .flatMap(LayoutOverride.init(rawValue:))
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        if let index = arguments.firstIndex(of: flag),
           arguments.indices.contains(index + 1) {
            return arguments[index + 1]
        }
        return arguments.first(where: { $0.hasPrefix("\(flag)=") })
            .map { String($0.dropFirst(flag.count + 1)) }
    }
}
