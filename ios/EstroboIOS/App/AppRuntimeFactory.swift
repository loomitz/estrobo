import Foundation
import EstroboBluetooth
import EstroboCore
import EstroboPersistence

@MainActor
struct AppRuntime {
    enum Mode: Equatable {
        case live
        case demo
    }

    enum Isolation: Equatable {
        case livePersistent
        case inMemoryOnly
    }

    let controller: GodoxSessionController
    let mode: Mode
    let isolation: Isolation
    let demoScenario: SimulatedRadioScenario?
}

@MainActor
enum AppRuntimeFactory {
    enum DemoSeed: Equatable {
        case empty
        case workspace
        case recoveryWrongUUID
        case savedRadios
    }

    static func makeDemo(
        scenario: SimulatedRadioScenario = .normal,
        seed: DemoSeed = .empty
    ) -> AppRuntime {
        let persistence = PersistenceServicesFactory.inMemory()

        if seed == .savedRadios {
            let primary = SavedRadio(
                deviceID: RadioTransportFactory.simulatedCandidate.id,
                name: RadioTransportFactory.simulatedCandidate.name,
                radioCode: "123456"
            )!
            let reserve = SavedRadio(
                deviceID: UUID(uuidString: "E5700B00-0000-4000-8000-000000000002")!,
                name: "X3Pro Reserva",
                radioCode: "654321"
            )!
            _ = persistence.savedRadios.upsert(primary)
            _ = persistence.savedRadios.upsert(reserve)
            _ = persistence.radioConnectionPreferences.save(
                RadioConnectionPreferenceState(
                    lastConnectedRadioID: primary.deviceID,
                    automaticConnectionRadioID: nil
                )
            )
        }

        if seed == .recoveryWrongUUID {
            let point = GroupRestorationPoint(
                deviceID: UUID(uuidString: "E5700B00-0000-4000-8000-00000000DEAD")!,
                snapshot: ManualGroupSnapshot(
                    power: ManualPower.value(decimal: 30)!,
                    modeling: .off
                )
            )
            _ = persistence.restorations.save(group: .b, point: point)
        }

        let controller = GodoxSessionController(
            transport: RadioTransportFactory.simulated(scenario: scenario),
            deadlineScheduler: LiveSessionDeadlineScheduler(),
            visibilityPreferences: persistence.groupVisibility,
            restorationStore: persistence.restorations,
            savedRadioStore: persistence.savedRadios,
            changeDeliveryPreferences: persistence.changeDelivery,
            radioConnectionPreferences: persistence.radioConnectionPreferences,
            transmitterProfilePreferences: persistence.transmitterProfiles,
            studioLibraryStore: persistence.studioLibrary
        )

        if seed != .empty {
            configureDefaultWorkspace(controller)
            controller.setChangeDeliveryMode(.manual)
        }

        return AppRuntime(
            controller: controller,
            mode: .demo,
            isolation: .inMemoryOnly,
            demoScenario: scenario
        )
    }

    /// This is the only live composition root. Calling it constructs
    /// CoreBluetooth and persistent adapters, so the coordinator invokes it
    /// only after the education screen is acknowledged.
    static func makeLive() -> AppRuntime {
        makeLive(persistence: PersistenceServicesFactory.live())
    }

    /// Restores the live shell only when a transmitter credential is already
    /// remembered. First-run users still see the Bluetooth explanation before
    /// CoreBluetooth is constructed.
    static func makeLiveRestoringRememberedRadio() -> AppRuntime? {
        let persistence = PersistenceServicesFactory.live()
        guard case .records(let radios) = persistence.savedRadios.load(),
              !radios.isEmpty else {
            return nil
        }
        return makeLive(persistence: persistence)
    }

    private static func makeLive(persistence: PersistenceServices) -> AppRuntime {
        let controller = GodoxSessionController(
            transport: RadioTransportFactory.live(),
            deadlineScheduler: LiveSessionDeadlineScheduler(),
            visibilityPreferences: persistence.groupVisibility,
            restorationStore: persistence.restorations,
            savedRadioStore: persistence.savedRadios,
            changeDeliveryPreferences: persistence.changeDelivery,
            radioConnectionPreferences: persistence.radioConnectionPreferences,
            transmitterProfilePreferences: persistence.transmitterProfiles,
            studioLibraryStore: persistence.studioLibrary,
            requiresExplicitInitialValueSynchronizationConfirmation: false,
            stagesNewWorkingGroupsAtSafeMinimum: true
        )
        return AppRuntime(
            controller: controller,
            mode: .live,
            isolation: .livePersistent,
            demoScenario: nil
        )
    }

    @discardableResult
    static func configureDefaultWorkspace(_ controller: GodoxSessionController) -> Bool {
        let profile = TransmitterProfile.observedGDBH
        let groups: Set<GodoxGroup> = [.b, .c]
        let assignments = Dictionary(uniqueKeysWithValues: groups.map {
            ($0, Set(["ad400pro-ii"]))
        })
        return controller.completeWorkspaceConfiguration(
            profileID: profile.id,
            selectedGroups: groups,
            assignedFlashModelIDs: assignments
        )
    }
}
