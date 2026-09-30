import Foundation

#if canImport(EstroboCore)
import EstroboCore
#endif

public enum SimulatedRadioScenario: String, CaseIterable, Sendable {
    case normal
    case delayedSuccess = "delayed-success"
    case authenticationRejected
    case syncTimeout
    case controlWriteFailure
    case fec8Timeout
    case disconnectDuringWrite
    case bluetoothDenied

    /// Keep the deterministic UI-test timing seam out of the user-facing Demo Lab.
    public static let allCases: [SimulatedRadioScenario] = [
        .normal,
        .authenticationRejected,
        .syncTimeout,
        .controlWriteFailure,
        .fec8Timeout,
        .disconnectDuringWrite,
        .bluetoothDenied,
    ]
}

/// Deterministic, in-process adapter for Demo mode and automated tests.
///
/// It never creates a CoreBluetooth central manager or talks to physical
/// hardware. Protocol frames still come from `SafeGodoxProtocol`; the adapter
/// only reproduces delivery timing and transport failures.
@MainActor
final class SimulatedRadioTransport: RadioTransport {
    static let candidate = RadioCandidate(
        id: UUID(uuidString: "E5700B00-0000-4000-8000-000000000001")!,
        name: "ESTROBO SIMULADO",
        rssi: -36
    )

    var eventHandler: ((TransportEvent) -> Void)?
    let isSimulation = true
    let scenario: SimulatedRadioScenario

    private let waitForMilliseconds: @MainActor (Int) async throws -> Void
    private var connectedCandidate: RadioCandidate?
    private var generation: UInt = 0
    private var scheduledEvents: [UUID: Task<Void, Never>] = [:]
    private var controlWriteQueue: [Data] = []
    private var controlWriteInFlight = false

    init(
        scenario: SimulatedRadioScenario = .normal,
        waitForMilliseconds: @escaping @MainActor (Int) async throws -> Void = { milliseconds in
            try await Task.sleep(for: .milliseconds(milliseconds))
        }
    ) {
        self.scenario = scenario
        self.waitForMilliseconds = waitForMilliseconds
    }

    func startScanning() {
        beginNewSequence()
        let activeGeneration = generation
        if scenario == .bluetoothDenied {
            emit(
                .stateChanged(.bluetoothUnavailable("permission denied")),
                after: 10,
                generation: activeGeneration
            )
            return
        }
        emitSequence(
            [
                (10, .stateChanged(.scanning)),
                (70, .discovered(Self.candidate)),
            ],
            generation: activeGeneration
        )
    }

    func stopScanning() {
        beginNewSequence()
        emit(.stateChanged(.idle), after: 10, generation: generation)
    }

    func connect(to candidate: RadioCandidate) {
        beginNewSequence()
        guard scenario != .bluetoothDenied else {
            emit(
                .failed(.bluetoothUnavailable("permission denied")),
                after: 10,
                generation: generation
            )
            return
        }
        guard candidate.id == Self.candidate.id else {
            emit(.failed(.unknownDevice(candidate.id)), after: 10, generation: generation)
            return
        }

        connectedCandidate = Self.candidate
        let activeGeneration = generation
        emitSequence(
            [
                (10, .stateChanged(.connecting(Self.candidate))),
                (35, .stateChanged(.discovering(Self.candidate))),
                (60, .stateChanged(.subscribing(Self.candidate))),
                (85, .stateChanged(.ready(Self.candidate))),
                (110, .readyForAuthentication),
            ],
            generation: activeGeneration
        )
    }

    func disconnect() {
        beginNewSequence()
        let activeGeneration = generation
        let candidate = connectedCandidate ?? Self.candidate
        schedule(after: 5, generation: activeGeneration) { transport in
            transport.eventHandler?(.stateChanged(.disconnecting(candidate)))
            transport.schedule(after: 35, generation: activeGeneration) { transport in
                transport.connectedCandidate = nil
                transport.eventHandler?(.discoveryReset)
                transport.eventHandler?(.stateChanged(.idle))
            }
        }
    }

    func forceResetConnection() {
        beginNewSequence()
        connectedCandidate = nil
        eventHandler?(.discoveryReset)
        eventHandler?(.stateChanged(.idle))
    }

    func sendAuthentication(_ payload: Data) {
        guard connectedCandidate != nil else {
            emitCommandFailure(.authentication)
            return
        }

        let activeGeneration = generation
        let response = scenario == .authenticationRejected
            ? Data("PWNO".utf8)
            : Self.validAuthenticationResponse()
        emitSequence(
            [
                (10, .commandSent(.authentication)),
                (45, .notification(.authentication, response)),
            ],
            generation: activeGeneration
        )
    }

    func sendSync(_ payload: Data) {
        guard connectedCandidate != nil else {
            emitCommandFailure(.sync)
            return
        }
        guard scenario != .syncTimeout else { return }
        emit(.commandSent(.sync), after: 30, generation: generation)
    }

    /// Test remains immediate and is never retained for later delivery.
    func sendTest(_ payload: Data) {
        guard connectedCandidate != nil else {
            emitCommandFailure(.test)
            return
        }
        emit(.commandSent(.test), after: 20, generation: generation)
    }

    func sendControl(_ payload: Data) {
        guard connectedCandidate != nil else {
            emitCommandFailure(.control)
            return
        }
        controlWriteQueue.append(payload)
        scheduleNextControlWrite()
    }

    private func scheduleNextControlWrite() {
        guard !controlWriteInFlight,
              connectedCandidate != nil,
              !controlWriteQueue.isEmpty else {
            return
        }

        controlWriteInFlight = true
        let payload = controlWriteQueue.removeFirst()
        let activeGeneration = generation
        scheduleControlTimeline(
            payload: payload,
            generation: activeGeneration
        )
    }

    private func finishControlWrite() {
        controlWriteInFlight = false
        scheduleNextControlWrite()
    }

    private func emitCommandFailure(_ command: RadioCommand) {
        emit(.commandFailed(command, .notReady), after: 10, generation: generation)
    }

    private func beginNewSequence() {
        generation &+= 1
        scheduledEvents.values.forEach { $0.cancel() }
        scheduledEvents.removeAll()
        controlWriteQueue.removeAll()
        controlWriteInFlight = false
    }

    private func emit(
        _ event: TransportEvent,
        after milliseconds: Int,
        generation: UInt
    ) {
        schedule(after: milliseconds, generation: generation) { transport in
            transport.eventHandler?(event)
        }
    }

    /// Keeps protocol milestones ordered even when a loaded executor wakes
    /// several elapsed deadlines together. Offsets are measured from the
    /// beginning of the simulated operation, preserving the original timings.
    private func emitSequence(
        _ timeline: [(offsetMilliseconds: Int, event: TransportEvent)],
        generation expectedGeneration: UInt
    ) {
        let eventID = UUID()
        scheduledEvents[eventID] = Task { @MainActor [weak self] in
            defer { self?.scheduledEvents[eventID] = nil }
            var elapsedMilliseconds = 0
            for milestone in timeline {
                precondition(
                    milestone.offsetMilliseconds >= elapsedMilliseconds,
                    "Simulated event timelines must use nondecreasing offsets"
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
                self.eventHandler?(milestone.event)
                elapsedMilliseconds = milestone.offsetMilliseconds
            }
        }
    }

    /// Serializes each simulated GATT acknowledgement timeline while retaining
    /// the adapter's queue and failure scenarios.
    private func scheduleControlTimeline(
        payload: Data,
        generation expectedGeneration: UInt
    ) {
        let eventID = UUID()
        scheduledEvents[eventID] = Task { @MainActor [weak self] in
            defer { self?.scheduledEvents[eventID] = nil }
            guard let self else { return }
            do {
                try await self.waitForMilliseconds(10)
            } catch {
                return
            }
            guard self.generation == expectedGeneration else { return }
            self.eventHandler?(.controlWriteStarted)

            do {
                try await self.waitForMilliseconds(
                    self.scenario == .delayedSuccess ? 1_200 : 25
                )
            } catch {
                return
            }
            guard self.generation == expectedGeneration else { return }
            switch self.scenario {
            case .controlWriteFailure:
                self.eventHandler?(.commandFailed(
                    .control,
                    .writeFailed(command: .control, message: "simulated write failure")
                ))
                self.finishControlWrite()
                return

            case .disconnectDuringWrite:
                self.connectedCandidate = nil
                self.controlWriteQueue.removeAll()
                self.controlWriteInFlight = false
                self.eventHandler?(.failed(
                    .disconnected("simulated disconnect during write")
                ))
                return

            case .normal, .delayedSuccess, .authenticationRejected, .syncTimeout,
                 .fec8Timeout, .bluetoothDenied:
                self.eventHandler?(.commandSent(.control))
                self.eventHandler?(.controlWriteCompleted)
                self.finishControlWrite()
            }

            guard self.scenario != .fec8Timeout,
                  SafeGodoxProtocol.groupSnapshot(from: payload) != nil else {
                return
            }
            do {
                try await self.waitForMilliseconds(25)
            } catch {
                return
            }
            guard self.generation == expectedGeneration else { return }
            self.eventHandler?(.notification(.control, Data([0xF0, 0xA1])))
        }
    }

    private func schedule(
        after milliseconds: Int,
        generation expectedGeneration: UInt,
        action: @escaping @MainActor (SimulatedRadioTransport) -> Void
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

    /// Builds a fresh PWOK response without retaining or exposing a radio code.
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
