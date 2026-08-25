import Foundation

/// Deterministic, in-process radio used by the interactive `--mock-radio` mode.
///
/// This transport only emits the same domain events as `BluetoothClient`; it
/// never creates a CoreBluetooth central manager or talks to physical hardware.
@MainActor
final class MockGodoxSessionTransport: GodoxSessionTransport {
    static let device = BluetoothClient.Device(
        id: UUID(uuidString: "E5700B00-0000-4000-8000-000000000001")!,
        name: "ESTROBO MOCK",
        rssi: -36
    )

    weak var delegate: (any BluetoothClientDelegate)?
    let isSimulation = true

    private let waitForMilliseconds: @MainActor (Int) async throws -> Void
    private var connectedDevice: BluetoothClient.Device?
    private var generation: UInt = 0
    private var scheduledEvents: [UUID: Task<Void, Never>] = [:]

    init(
        waitForMilliseconds: @escaping @MainActor (Int) async throws -> Void = { milliseconds in
            try await Task.sleep(for: .milliseconds(milliseconds))
        }
    ) {
        self.waitForMilliseconds = waitForMilliseconds
    }

    func startScanning() {
        beginNewSequence()
        let activeGeneration = generation
        emitSequence(
            [
                (10, .stateChanged(.scanning)),
                (70, .discovered(Self.device)),
            ],
            generation: activeGeneration
        )
    }

    func stopScanning() {
        beginNewSequence()
        emit(.stateChanged(.idle), after: 10, generation: generation)
    }

    func connect(to device: BluetoothClient.Device) {
        beginNewSequence()
        guard device.id == Self.device.id else {
            emit(.failed(.unknownDevice(device.id)), after: 10, generation: generation)
            return
        }

        connectedDevice = Self.device
        let activeGeneration = generation
        emitSequence(
            [
                (10, .stateChanged(.connecting(Self.device))),
                (35, .stateChanged(.discovering(Self.device))),
                (60, .stateChanged(.subscribing(Self.device))),
                (85, .stateChanged(.ready(Self.device))),
                (110, .readyForAuthentication),
            ],
            generation: activeGeneration
        )
    }

    func disconnect() {
        beginNewSequence()
        let activeGeneration = generation
        let device = connectedDevice ?? Self.device
        schedule(after: 5, generation: activeGeneration) { transport in
            transport.delegate?.bluetoothClient(
                didReceive: .stateChanged(.disconnecting(device))
            )
            transport.schedule(after: 35, generation: activeGeneration) { transport in
                transport.connectedDevice = nil
                transport.delegate?.bluetoothClient(didReceive: .discoveryReset)
                transport.delegate?.bluetoothClient(didReceive: .stateChanged(.idle))
            }
        }
    }

    func forceResetConnection() {
        beginNewSequence()
        connectedDevice = nil
        delegate?.bluetoothClient(didReceive: .discoveryReset)
        delegate?.bluetoothClient(didReceive: .stateChanged(.idle))
    }

    func sendAuthentication(_ payload: Data) {
        guard connectedDevice != nil else {
            emitCommandFailure(.authentication)
            return
        }

        let activeGeneration = generation
        emitSequence(
            [
                (10, .commandSent(.authentication)),
                (45, .notification(
                    .authentication,
                    Self.validAuthenticationResponse()
                )),
            ],
            generation: activeGeneration
        )
    }

    func sendSync(_ payload: Data) {
        guard connectedDevice != nil else {
            emitCommandFailure(.sync)
            return
        }
        emit(.commandSent(.sync), after: 30, generation: generation)
    }

    func sendTest(_ payload: Data) {
        guard connectedDevice != nil else {
            emitCommandFailure(.test)
            return
        }
        emit(.commandSent(.test), after: 20, generation: generation)
    }

    func sendControl(_ payload: Data) {
        guard connectedDevice != nil else {
            emitCommandFailure(.control)
            return
        }

        let activeGeneration = generation
        var timeline: [(Int, BluetoothClient.Event)] = [
            (10, .controlWriteStarted),
            (35, .controlWriteCompleted),
        ]
        // A0 termina con el acuse de escritura GATT. Sólo A1 recibe después
        // la confirmación FEC8 que compromete el estado del grupo.
        if SafeGodoxProtocol.groupSnapshot(from: payload) != nil {
            timeline.append(
                (60, .notification(.control, Data([0xF0, 0xA1])))
            )
        }
        emitSequence(timeline, generation: activeGeneration)
    }

    private func emitCommandFailure(_ kind: BluetoothClient.CommandKind) {
        emit(.commandFailed(kind, .notReady), after: 10, generation: generation)
    }

    private func beginNewSequence() {
        generation &+= 1
        scheduledEvents.values.forEach { $0.cancel() }
        scheduledEvents.removeAll()
    }

    private func emit(
        _ event: BluetoothClient.Event,
        after milliseconds: Int,
        generation: UInt
    ) {
        schedule(after: milliseconds, generation: generation) { transport in
            transport.delegate?.bluetoothClient(didReceive: event)
        }
    }

    /// Keeps protocol milestones ordered even when a loaded executor wakes
    /// several elapsed deadlines together. Offsets are measured from the
    /// beginning of the simulated operation, matching the prior timings.
    private func emitSequence(
        _ timeline: [(offsetMilliseconds: Int, event: BluetoothClient.Event)],
        generation expectedGeneration: UInt
    ) {
        let eventID = UUID()
        scheduledEvents[eventID] = Task { @MainActor [weak self] in
            defer { self?.scheduledEvents[eventID] = nil }
            var elapsedMilliseconds = 0
            for milestone in timeline {
                precondition(
                    milestone.offsetMilliseconds >= elapsedMilliseconds,
                    "Mock event timelines must use nondecreasing offsets"
                )
                guard let self else { return }
                do {
                    try await self.waitForMilliseconds(
                        milestone.offsetMilliseconds - elapsedMilliseconds
                    )
                } catch {
                    return
                }
                guard self.generation == expectedGeneration else { return }
                self.delegate?.bluetoothClient(didReceive: milestone.event)
                elapsedMilliseconds = milestone.offsetMilliseconds
            }
        }
    }

    private func schedule(
        after milliseconds: Int,
        generation expectedGeneration: UInt,
        action: @escaping @MainActor (MockGodoxSessionTransport) -> Void
    ) {
        let eventID = UUID()
        scheduledEvents[eventID] = Task { @MainActor [weak self] in
            defer { self?.scheduledEvents[eventID] = nil }
            do {
                guard let self else { return }
                try await self.waitForMilliseconds(milliseconds)
            } catch {
                return
            }
            guard let self, self.generation == expectedGeneration else { return }
            action(self)
        }
    }

    /// Builds a fresh PWOK response from the current clock. It contains no
    /// radio code and is accepted by the same clean-room decoder as a real radio.
    private static func validAuthenticationResponse(now: Date = Date()) -> Data {
        let unixSeconds = Int64(now.timeIntervalSince1970.rounded(.towardZero))
        let secondsSuffix = unixSeconds % 10_000
        let decodedTime = Int((10_000 - secondsSuffix) % 10_000)
        let decodedDigits = String(format: "%04d", decodedTime)

        // Selector 99 yields decoder offset key[9] + key[9] = 6.
        let encodedDigits = decodedDigits.compactMap { character -> Character? in
            guard let digit = character.wholeNumberValue,
                  let scalar = UnicodeScalar(54 + digit) else {
                return nil
            }
            return Character(scalar)
        }
        guard encodedDigits.count == 4 else { return Data() }
        return Data("PWOK,;\(String(encodedDigits))".utf8)
    }
}

/// Launch-mode helper for the app entry point.
///
/// The mock controller uses no-op, in-memory adapters for every preference that
/// can identify a radio or record a pending physical restoration. Consequently,
/// a mock session cannot read, overwrite, or clear real session safety state.
@MainActor
enum MockRadioRuntime {
    static let launchArgument = "--mock-radio"
    static let onboardingLaunchArgument = "--show-onboarding"

    static func isRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(launchArgument)
    }

    static func makeControllerIfRequested(
        arguments: [String] = CommandLine.arguments
    ) -> GodoxSessionController? {
        guard isRequested(arguments: arguments) else { return nil }
        return makeController(
            showOnboarding: arguments.contains(onboardingLaunchArgument)
        )
    }

    static func makeController(showOnboarding: Bool = false) -> GodoxSessionController {
        var studioLibraryData: Data?
        var transmitterProfilePreferenceData: Data?
        let controller = GodoxSessionController(
            transport: MockGodoxSessionTransport(),
            deadlineScheduler: LiveSessionDeadlineScheduler(),
            visibilityPreferences: LocalGroupPreferences(
                storageKey: "Estrobo.mock.visibleGroups",
                readArray: { _ in nil },
                writeIntegers: { _, _ in }
            ),
            restorationStore: PendingRestorationStore(
                storageKey: "Estrobo.mock.pendingRestoration",
                readObject: { _ in nil },
                writeData: { _, _ in true },
                removeValue: { _ in true }
            ),
            savedRadioStore: SavedRadioStore(
                storageKey: "Estrobo.mock.savedRadio",
                readObject: { _ in nil },
                writeData: { _, _ in true },
                removeValue: { _ in true }
            ),
            changeDeliveryPreferences: ChangeDeliveryPreferences(
                storageKey: "Estrobo.mock.changeDeliveryMode",
                readString: { _ in nil },
                writeString: { _, _ in }
            ),
            transmitterProfilePreferences: TransmitterProfilePreferences(
                storageKey: "Estrobo.mock.transmitterProfiles",
                readObject: { _ in transmitterProfilePreferenceData },
                writeData: { data, _ in
                    transmitterProfilePreferenceData = data
                    return true
                }
            ),
            studioLibraryStore: StudioLibraryStore(
                storageKey: "Estrobo.mock.studioLibrary",
                readObject: { _ in studioLibraryData },
                writeData: { data, _ in
                    studioLibraryData = data
                    return true
                }
            )
        )
        // Keep the synthetic B reference on a valid 1/3-EV scale so the
        // relationship-preserving global control is immediately exercisable.
        // This changes only the isolated mock capability, never real hardware.
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
}
