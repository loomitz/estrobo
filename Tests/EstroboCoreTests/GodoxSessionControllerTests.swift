import Foundation
import XCTest
@testable import EstroboCore

@MainActor
final class GodoxSessionControllerTests: XCTestCase {
    private let device = RadioCandidate(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        name: "GDBH-XCTest",
        rssi: -42
    )

    func testPWOKAndSyncStartA0BeforeSerialA1Delivery() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)

        try await connectAndSynchronizeTransport(fixture)

        XCTAssertEqual(fixture.transport.sentCommands.prefix(2), [.authentication, .sync])
        XCTAssertEqual(fixture.controller.phase, .synchronizing)
        XCTAssertTrue(fixture.scheduler.fire(.valueSynchronizationSettle))
        XCTAssertEqual(fixture.transport.controlPayloads.count, 1)
        XCTAssertNotNil(
            SafeGodoxProtocol.globalSnapshot(from: fixture.transport.controlPayloads[0]),
            "The connection synchronization must start with one complete A0 frame."
        )
        XCTAssertEqual(Set(fixture.restorations.points?.keys.map { $0 } ?? []), [.b, .c])

        acknowledgeGATTWrite(fixture.transport)
        XCTAssertEqual(fixture.transport.controlPayloads.count, 2)
        XCTAssertEqual(decodedGroup(fixture.transport.controlPayloads[1]), .b)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        XCTAssertEqual(
            fixture.transport.controlPayloads.count,
            2,
            "C must not be submitted until B has both its GATT receipt and FEC8 response."
        )

        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        XCTAssertEqual(fixture.transport.controlPayloads.count, 3)
        XCTAssertEqual(decodedGroup(fixture.transport.controlPayloads[2]), .c)

        acknowledgeGroupWrite(fixture.transport)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertNil(fixture.restorations.points)
        XCTAssertEqual(fixture.restorations.clearCount, 1)
    }

    func testJournalFailurePreventsA0AndStartedA0RemainsRecoverable() async throws {
        let rejectedJournal = MemoryRestorationRepository()
        rejectedJournal.acceptsSave = false
        let rejected = makeFixture(restorations: rejectedJournal)
        try await connectAndSynchronizeTransport(rejected)
        XCTAssertEqual(rejected.controller.phase, .ready)

        rejected.controller.setGlobalStandby(true)

        XCTAssertEqual(rejectedJournal.saveCount, 1)
        XCTAssertTrue(rejected.transport.controlPayloads.isEmpty)
        XCTAssertFalse(rejected.controller.isGlobalStandbyEnabled)
        XCTAssertTrue(rejected.controller.restorationPoints.isEmpty)

        let durableJournal = MemoryRestorationRepository()
        let uncertain = makeFixture(restorations: durableJournal)
        try await connectAndSynchronizeTransport(uncertain)
        uncertain.controller.setGlobalStandby(true)

        XCTAssertEqual(uncertain.transport.controlPayloads.count, 1)
        XCTAssertNotNil(SafeGodoxProtocol.globalSnapshot(from: uncertain.transport.controlPayloads[0]))
        XCTAssertEqual(Set(durableJournal.points?.keys.map { $0 } ?? []), [.b, .c])

        uncertain.transport.emit(.controlWriteStarted)
        uncertain.controller.suspendForInactiveScene()
        uncertain.controller.resumeActiveScene()

        XCTAssertEqual(uncertain.transport.controlPayloads.count, 1)
        XCTAssertEqual(durableJournal.clearCount, 0)
        XCTAssertEqual(Set(durableJournal.points?.keys.map { $0 } ?? []), [.b, .c])
        XCTAssertEqual(
            uncertain.controller.foregroundSessionRequirement,
            .recover(deviceID: device.id)
        )
        XCTAssertEqual(
            uncertain.controller.foregroundSessionState,
            .actionRequired(.recover(deviceID: device.id))
        )
    }

    func testInactiveSceneCancelsPendingTestWithoutRetry() async throws {
        let fixture = makeFixture()
        try await connectAndSynchronizeTransport(fixture)

        fixture.controller.sendTestFlash()
        XCTAssertEqual(fixture.transport.testWriteCount, 1)
        XCTAssertTrue(fixture.controller.isTestPending)
        XCTAssertEqual(fixture.scheduler.activeCount(.testDelivery), 1)

        fixture.controller.suspendForInactiveScene()
        fixture.transport.emit(.commandSent(.test))
        fixture.controller.resumeActiveScene()

        XCTAssertFalse(fixture.controller.isTestPending)
        XCTAssertFalse(fixture.scheduler.fire(.testDelivery))
        XCTAssertEqual(fixture.transport.testWriteCount, 1)
        XCTAssertEqual(fixture.transport.disconnectCount, 1)
        XCTAssertEqual(fixture.transport.forceResetCount, 1)
        XCTAssertEqual(
            fixture.controller.foregroundSessionState,
            .actionRequired(.reconnectAndSynchronize)
        )
    }

    func testContinuousEditSendsOnlyTheFinalValueAfterGestureEnds() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        let writesBeforeGesture = fixture.transport.controlPayloads.count
        fixture.controller.setChangeDeliveryMode(.automatic)
        let token = fixture.controller.beginInteractiveEdit()

        for decimal in [30, 33, 37] {
            fixture.controller.setDraftPower(
                .c,
                power: try XCTUnwrap(ManualPower.value(decimal: decimal))
            )
        }

        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeGesture)
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 0)
        XCTAssertTrue(fixture.controller.isInteractiveEditActive)

        fixture.controller.endInteractiveEdit(token)
        XCTAssertFalse(fixture.controller.isInteractiveEditActive)
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 1)
        XCTAssertTrue(fixture.scheduler.fire(.automaticApply))

        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeGesture + 1)
        let finalPayload = fixture.transport.controlPayloads[writesBeforeGesture]
        let decoded = try XCTUnwrap(SafeGodoxProtocol.groupSnapshot(from: finalPayload))
        XCTAssertEqual(decoded.0, .c)
        XCTAssertEqual(decoded.1.power, ManualPower.value(decimal: 37))
        XCTAssertFalse(
            fixture.transport.controlPayloads.dropFirst(writesBeforeGesture).contains { payload in
                guard let snapshot = SafeGodoxProtocol.groupSnapshot(from: payload)?.1 else {
                    return false
                }
                return snapshot.power == ManualPower.value(decimal: 30) ||
                    snapshot.power == ManualPower.value(decimal: 33)
            }
        )
    }

    func testTestCommandFailsFastAndIsNeverRetried() async throws {
        let fixture = makeFixture()
        try await connectAndSynchronizeTransport(fixture)
        fixture.transport.failTestSynchronously = true

        fixture.controller.sendTestFlash()

        XCTAssertEqual(fixture.transport.testWriteCount, 1)
        XCTAssertFalse(fixture.controller.isTestPending)
        XCTAssertEqual(fixture.scheduler.activeCount(.testDelivery), 0)
        XCTAssertFalse(fixture.scheduler.fire(.testDelivery))
        XCTAssertEqual(fixture.transport.testWriteCount, 1)
        XCTAssertTrue(
            fixture.controller.activity.last?.message.contains("Test no enviado") == true
        )
    }

    private func makeFixture(
        restorations: MemoryRestorationRepository = MemoryRestorationRepository()
    ) -> Fixture {
        let transport = RecordingRadioTransport()
        let scheduler = ManualDeadlineScheduler()
        let changeDelivery = MemoryChangeDeliveryPreferences()
        let studioLibrary = MemoryStudioLibraryRepository()
        let controller = GodoxSessionController(
            transport: transport,
            deadlineScheduler: scheduler,
            visibilityPreferences: MemoryGroupVisibilityPreferences(),
            restorationStore: restorations,
            savedRadioStore: EmptySavedRadioRepository(),
            changeDeliveryPreferences: changeDelivery,
            transmitterProfilePreferences: MemoryTransmitterProfilePreferences(),
            studioLibraryStore: studioLibrary
        )
        return Fixture(
            controller: controller,
            transport: transport,
            scheduler: scheduler,
            restorations: restorations,
            changeDelivery: changeDelivery,
            studioLibrary: studioLibrary
        )
    }

    private func completeWorkspace(_ controller: GodoxSessionController) {
        XCTAssertTrue(controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b, .c],
            assignedFlashModelIDs: [
                .b: ["ad600pro-ii"],
                .c: ["ad400pro"],
            ]
        ))
    }

    private func connectAndSynchronizeTransport(_ fixture: Fixture) async throws {
        fixture.controller.startScanning()
        fixture.transport.emit(.discovered(device))
        fixture.controller.radioCode = "111111"
        fixture.controller.connectSelectedDevice()
        fixture.transport.emit(.stateChanged(.ready(device)))
        fixture.transport.emit(.readyForAuthentication)
        fixture.transport.emit(.notification(
            .authentication,
            validAuthenticationResponse()
        ))

        for _ in 0..<30 where !fixture.transport.sentCommands.contains(.sync) {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(
            fixture.transport.sentCommands.contains(.sync),
            "PWOK must lead to one delivered Sync command."
        )
    }

    private func finishInitialValueSynchronization(_ fixture: Fixture) {
        XCTAssertTrue(fixture.scheduler.fire(.valueSynchronizationSettle))
        acknowledgeGATTWrite(fixture.transport)
        for _ in fixture.controller.workingGroups {
            acknowledgeGroupWrite(fixture.transport)
        }
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertTrue(fixture.controller.restorationPoints.isEmpty)
    }

    private func acknowledgeGATTWrite(_ transport: RecordingRadioTransport) {
        transport.emit(.controlWriteStarted)
        transport.emit(.controlWriteCompleted)
    }

    private func acknowledgeGroupWrite(_ transport: RecordingRadioTransport) {
        acknowledgeGATTWrite(transport)
        transport.emit(.notification(.control, Data([0xF0, 0xA1])))
    }

    private func decodedGroup(_ payload: Data) -> GodoxGroup? {
        SafeGodoxProtocol.groupSnapshot(from: payload)?.0
    }

    private func validAuthenticationResponse(now: Date = Date()) -> Data {
        let unixSeconds = Int64(now.timeIntervalSince1970.rounded(.towardZero))
        let decodedTime = Int((10_000 - (unixSeconds % 10_000)) % 10_000)
        let decodedDigits = String(format: "%04d", decodedTime)
        let encodedDigits = decodedDigits.map { character -> Character in
            let digit = character.wholeNumberValue!
            return Character(UnicodeScalar(54 + digit)!)
        }
        return Data("PWOK,;\(String(encodedDigits))".utf8)
    }
}

@MainActor
private struct Fixture {
    let controller: GodoxSessionController
    let transport: RecordingRadioTransport
    let scheduler: ManualDeadlineScheduler
    let restorations: MemoryRestorationRepository
    let changeDelivery: MemoryChangeDeliveryPreferences
    let studioLibrary: MemoryStudioLibraryRepository
}

@MainActor
private final class ManualDeadlineScheduler: SessionDeadlineScheduling {
    private struct Entry {
        let token: SessionDeadlineToken
        let action: @MainActor () -> Void
    }

    private var entries: [SessionDeadlineKind: [Entry]] = [:]

    func schedule(
        _ kind: SessionDeadlineKind,
        action: @escaping @MainActor () -> Void
    ) -> SessionDeadlineToken {
        let token = SessionDeadlineToken()
        entries[kind, default: []].append(Entry(token: token, action: action))
        return token
    }

    func activeCount(_ kind: SessionDeadlineKind) -> Int {
        entries[kind, default: []].filter { !$0.token.isCancelled }.count
    }

    @discardableResult
    func fire(_ kind: SessionDeadlineKind) -> Bool {
        while var pending = entries[kind], !pending.isEmpty {
            let entry = pending.removeFirst()
            entries[kind] = pending
            guard !entry.token.isCancelled else { continue }
            entry.action()
            return true
        }
        return false
    }
}

@MainActor
private final class RecordingRadioTransport: RadioTransport {
    enum SentCommand: Equatable {
        case authentication
        case sync
        case test
        case control
    }

    var eventHandler: ((TransportEvent) -> Void)?
    private(set) var sentCommands: [SentCommand] = []
    private(set) var controlPayloads: [Data] = []
    private(set) var testWriteCount = 0
    private(set) var disconnectCount = 0
    private(set) var forceResetCount = 0
    var failTestSynchronously = false

    func startScanning() {}
    func stopScanning() {}
    func connect(to candidate: RadioCandidate) {}

    func disconnect() {
        disconnectCount += 1
    }

    func forceResetConnection() {
        forceResetCount += 1
    }

    func sendAuthentication(_ payload: Data) {
        sentCommands.append(.authentication)
        eventHandler?(.commandSent(.authentication))
    }

    func sendSync(_ payload: Data) {
        sentCommands.append(.sync)
        eventHandler?(.commandSent(.sync))
    }

    func sendTest(_ payload: Data) {
        sentCommands.append(.test)
        testWriteCount += 1
        if failTestSynchronously {
            eventHandler?(.commandFailed(
                .test,
                .writeFailed(command: .test, message: "synthetic fail-fast")
            ))
        }
    }

    func sendControl(_ payload: Data) {
        sentCommands.append(.control)
        controlPayloads.append(payload)
    }

    func emit(_ event: TransportEvent) {
        eventHandler?(event)
    }
}

@MainActor
private final class MemoryRestorationRepository: RestorationRepository {
    var points: [GodoxGroup: GroupRestorationPoint]?
    var acceptsSave = true
    var acceptsClear = true
    private(set) var saveCount = 0
    private(set) var clearCount = 0

    func load() -> RestorationLoadResult {
        points.map(RestorationLoadResult.batch(points:)) ?? .none
    }

    func save(points: [GodoxGroup: GroupRestorationPoint]) -> Bool {
        saveCount += 1
        guard acceptsSave else { return false }
        self.points = points
        return true
    }

    func clear() -> Bool {
        clearCount += 1
        guard acceptsClear else { return false }
        points = nil
        return true
    }
}

@MainActor
private final class EmptySavedRadioRepository: SavedRadioRepository {
    func load() -> SavedRadioLoadResult { .none }
    func upsert(_ radio: SavedRadio) -> Bool { true }
    func remove(deviceID: UUID) -> Bool { true }
    func clear() -> Bool { true }
}

@MainActor
private final class MemoryStudioLibraryRepository: StudioLibraryRepository {
    private(set) var library: StudioLibrary?

    func load() -> StudioLibraryLoadResult {
        library.map(StudioLibraryLoadResult.record) ?? .none
    }

    func save(_ library: StudioLibrary) -> Bool {
        self.library = library
        return true
    }
}

@MainActor
private final class MemoryGroupVisibilityPreferences: GroupVisibilityPreferencesStore {
    func loadVisibleGroups(
        supportedGroups: [GodoxGroup],
        defaultVisibleGroups: [GodoxGroup]?
    ) -> [GodoxGroup] {
        let requested = defaultVisibleGroups ?? supportedGroups
        return supportedGroups.filter(requested.contains)
    }

    func saveVisibleGroups(
        _ visibleGroups: [GodoxGroup],
        supportedGroups: [GodoxGroup]
    ) -> [GodoxGroup] {
        supportedGroups.filter(visibleGroups.contains)
    }
}

@MainActor
private final class MemoryChangeDeliveryPreferences: ChangeDeliveryPreferencesStore {
    private(set) var mode: ChangeDeliveryMode = .manual

    func load() -> ChangeDeliveryMode { mode }

    func save(_ mode: ChangeDeliveryMode) {
        self.mode = mode
    }
}

@MainActor
private final class MemoryTransmitterProfilePreferences: TransmitterProfilePreferencesStore {
    func load(
        builtInProfileIDs: [String],
        fallbackDefaultProfileID: String
    ) -> TransmitterProfilePreferenceState {
        TransmitterProfilePreferenceState(
            availableProfileIDs: builtInProfileIDs,
            defaultProfileID: fallbackDefaultProfileID
        )
    }

    func save(
        _ state: TransmitterProfilePreferenceState,
        builtInProfileIDs: [String],
        fallbackDefaultProfileID: String
    ) -> Bool {
        true
    }
}
