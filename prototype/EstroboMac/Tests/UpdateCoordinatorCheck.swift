import Foundation

@MainActor
private final class ControlledUpdateService: UpdateService {
    var checks = 0
    var offers: [UpdateOffer] = []
    var checkFailure: UpdateServiceFailure?
    var downloads = 0
    var holdChecks = false
    var holdDownloads = false
    var checkReply: CheckedContinuation<[UpdateOffer], Error>?
    var downloadReply: CheckedContinuation<DownloadedUpdate, Error>?
    var cancelRequested = false
    var installations = 0
    var installedBuild: UInt64 = 4
    var holdInstallation = false
    var beforeCommit: (() -> Void)?
    var freshIdentity: UpdateOfferIdentity?
    var installationFailure: UpdateServiceFailure?
    var failureAfterCommit: UpdateServiceFailure?
    var installReply: CheckedContinuation<Void, Error>?
    var downloadOverride: DownloadedUpdate?
    var finalPrecommit: (@MainActor (UpdateOfferIdentity) -> Bool)?
    func check(for installed: InstalledUpdateVersion) async throws -> [UpdateOffer] {
        checks += 1
        if let checkFailure { throw checkFailure }
        if holdChecks { return try await withCheckedThrowingContinuation { checkReply = $0 } }
        return offers
    }
    func download(_ offer: UpdateOffer, progress: @escaping @MainActor (UpdateDownloadProgress) -> Void) async throws -> DownloadedUpdate {
        downloads += 1
        progress(UpdateDownloadProgress(completedBytes: 25, totalBytes: 100))
        if holdDownloads { return try await withCheckedThrowingContinuation { downloadReply = $0 } }
        return downloadOverride ?? Self.downloaded(offer)
    }
    func install(_ download: DownloadedUpdate, offer: UpdateOffer,
                 precommit: @escaping @MainActor (UpdateOfferIdentity) -> Bool) async throws {
        installations += 1
        finalPrecommit = precommit
        if let installationFailure { throw installationFailure }
        beforeCommit?()
        guard precommit(freshIdentity ?? offer.identity) else { throw UpdateServiceFailure(.unsafeSession) }
        if let failureAfterCommit { throw failureAfterCommit }
        if holdInstallation { try await withCheckedThrowingContinuation { installReply = $0 } }
        try Task.checkCancellation()
        installedBuild = offer.identity.build
    }
    func cancel() { cancelRequested = true }
    static func downloaded(_ offer: UpdateOffer) -> DownloadedUpdate {
        DownloadedUpdate(offerIdentity: offer.identity, localFile: URL(fileURLWithPath: "/tmp/update-fixture.dmg"),
                         length: offer.identity.contentLength, sha256: String(repeating: "a", count: 64))
    }
}

@MainActor
private final class ControlledUpdateClock: UpdateClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var entries: [(Date, UpdateScheduleToken, @MainActor () -> Void)] = []
    func schedule(at date: Date, action: @escaping @MainActor () -> Void) -> UpdateScheduleToken {
        let token = UpdateScheduleToken()
        entries.append((date, token, action))
        return token
    }
    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        let due = entries.filter { $0.0 <= now }
        entries.removeAll { $0.0 <= now }
        for entry in due where !entry.1.isCancelled { entry.2() }
    }
}

// The existing session/transport seam, without CoreBluetooth or physical writes.
@MainActor
private final class UpdateRadioTransport: RadioTransport {
    var eventHandler: ((TransportEvent) -> Void)?
    var scans = 0
    var controlWrites = 0
    var disconnects = 0
    var testWrites = 0
    var lastControl: Data?
    static let candidate = RadioCandidate(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, name: "GDBH-UPDATE", rssi: -40)
    func emit(_ event: TransportEvent) { eventHandler?(event) }
    func startScanning() { scans += 1; emit(.stateChanged(.scanning)) }
    func stopScanning() { emit(.stateChanged(.idle)) }
    func connect(to device: RadioCandidate) { emit(.stateChanged(.connecting(device))) }
    func disconnect() { disconnects += 1; emit(.stateChanged(.disconnecting(Self.candidate))) }
    func forceResetConnection() { emit(.discoveryReset); emit(.stateChanged(.idle)) }
    func sendAuthentication(_ payload: Data) { emit(.commandSent(.authentication)) }
    func sendSync(_ payload: Data) { emit(.commandSent(.sync)) }
    func sendTest(_ payload: Data) { testWrites += 1 }
    func sendControl(_ payload: Data) { controlWrites += 1; lastControl = payload }
}

@MainActor
private final class UpdateSessionScheduler: SessionDeadlineScheduling {
    var entries: [SessionDeadlineKind: [(SessionDeadlineToken, @MainActor () -> Void)]] = [:]
    func schedule(_ kind: SessionDeadlineKind, action: @escaping @MainActor () -> Void) -> SessionDeadlineToken {
        let token = SessionDeadlineToken()
        entries[kind, default: []].append((token, action))
        return token
    }
    func fire(_ kind: SessionDeadlineKind) {
        let pending = entries.removeValue(forKey: kind) ?? []
        for entry in pending where !entry.0.isCancelled { entry.1(); return }
        preconditionFailure("No live deadline for \(kind)")
    }
}

@MainActor
private final class UpdateSessionFixture {
    let transport = UpdateRadioTransport()
    let scheduler = UpdateSessionScheduler()
    let session: GodoxSessionController
    let persistence: PersistenceServices

    init(persistence: PersistenceServices? = nil, restoration: (any RestorationRepository)? = nil) {
        let persistence = persistence ?? PersistenceServicesFactory.inMemory()
        self.persistence = persistence
        session = GodoxSessionController(transport: transport, deadlineScheduler: scheduler,
            visibilityPreferences: persistence.groupVisibility,
            restorationStore: restoration ?? persistence.restorations, savedRadioStore: persistence.savedRadios,
            changeDeliveryPreferences: persistence.changeDelivery,
            transmitterProfilePreferences: persistence.transmitterProfiles, studioLibraryStore: persistence.studioLibrary)
        if !session.hasStoredWorkspaceConfiguration, session.recoveryBlockReason == nil {
            precondition(session.completeWorkspaceConfiguration(profileID: TransmitterProfile.observedGDBH.id,
                selectedGroups: [.b, .c], assignedFlashModelIDs: [.b: ["ad600pro-ii"], .c: ["ad400pro"]]))
        }
    }

    func connect() {
        session.startScanning()
        transport.emit(.discovered(UpdateRadioTransport.candidate))
        session.radioCode = "111111"
        session.connectSelectedDevice()
    }

    func authenticate() {
        transport.emit(.stateChanged(.ready(UpdateRadioTransport.candidate)))
        transport.emit(.readyForAuthentication)
        let seconds = Int64(Date().timeIntervalSince1970.rounded(.towardZero)) % 10_000
        let digits = String(format: "%04d", Int((10_000 - seconds) % 10_000))
        let encoded = digits.map { Character(UnicodeScalar(48 + 6 + $0.wholeNumberValue!)!) }
        transport.emit(.notification(.authentication, Data("PWOK,;\(String(encoded))".utf8)))
        transport.emit(.commandSent(.sync))
    }

    func ready() {
        connect()
        authenticate()
        scheduler.fire(.valueSynchronizationSettle)
        for _ in session.workingGroups { confirmControl() }
        precondition(session.phase == .ready && session.pendingCount == 0)
    }

    func confirmControl() {
        if session.isGlobalControlPending, transport.lastControl.flatMap({ SafeGodoxProtocol.globalSnapshot(from: $0) }) != nil {
            transport.emit(.controlWriteStarted)
            transport.emit(.controlWriteCompleted)
        }
        transport.emit(.controlWriteStarted)
        transport.emit(.controlWriteCompleted)
        transport.emit(.notification(.control, Data([0xF0, 0xA1])))
    }
}

@main
@MainActor
enum UpdateCoordinatorCheck {
    static func main() async {
        await checkManualLookupDoesNotEnableAutomation()
        await checkDailyChecksAndBackoffSurviveRelaunch()
        await checkSecondLaunchInvitationAndPersistentOptOut()
        await checkChannelBuildAndCompatibilitySelection()
        await checkOneTransferAndDisablingOnlyAutomaticWork()
        await checkIdentityBoundConsentAndCancellationAcknowledgement()
        await checkSafetyAgainImmediatelyBeforeCommit()
        await checkExistingSessionSafetyClasses()
        await checkPersistedUnresolvableDraftDoesNotTrapUpdate()
        await checkOpaqueFailuresAndCancellationKeepNetworkPolicy()
        await checkOfferWithdrawalAndFreshIdentityMismatch()
        await checkOrdinaryQuitAndInstallerFailureReleaseConsent()
        await checkDownloadLeavesRadioResponsive()
        await checkNewTransportStateRemainsObservableDuringCommit()
        print("UpdateCoordinatorCheck passed")
    }

    private static func checkNewTransportStateRemainsObservableDuringCommit() async {
        let fixture = UpdateSessionFixture()
        let service = ControlledUpdateService()
        service.offers = [makeOffer()]
        service.holdInstallation = true
        let coordinator = UpdateCoordinator(installed: installed, service: service,
            session: fixture.session, preferences: UpdatePreferences())
        coordinator.checkManually(); await settle(); coordinator.download(); await settle()
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        await settle()
        // Transport status remains a real input even while new commands are gated.
        fixture.transport.emit(.stateChanged(.connecting(UpdateRadioTransport.candidate)))
        await settle()
        expect(coordinator.snapshot.installationBlocker == .connectionInProgress && service.cancelRequested,
               "A new unsafe transport state invalidates consent rather than being hidden by command suspension")
        service.installReply?.resume(throwing: UpdateServiceFailure(.cancelled))
        service.installReply = nil
        await settle()
        expect(fixture.session.operationSuspensionCount == 0 && service.installedBuild == 4,
               "Unsafe state cancellation releases suspension after acknowledgement")
    }

    private static func checkOrdinaryQuitAndInstallerFailureReleaseConsent() async {
        let service = ControlledUpdateService()
        service.offers = [makeOffer()]
        service.holdInstallation = true
        let session = MockRadioRuntime.makeController()
        let coordinator = UpdateCoordinator(installed: installed, service: service,
            session: session, preferences: UpdatePreferences())
        coordinator.checkManually(); await settle(); coordinator.download(); await settle()
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        await settle()
        coordinator.ordinaryQuitRequested()
        expect(coordinator.hasInstallationInProgress && coordinator.snapshot.isCancellingInstallation,
               "Ordinary quit waits for the prepared installer to be cancelled")
        service.installReply?.resume(throwing: UpdateServiceFailure(.cancelled))
        service.installReply = nil
        await settle()
        expect(!coordinator.hasInstallationInProgress && session.operationSuspensionCount == 0,
               "Only acknowledged cancellation permits a later ordinary quit")
        service.holdInstallation = false
        service.failureAfterCommit = UpdateServiceFailure(.installation)
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        await settle()
        expect(coordinator.snapshot.failure?.kind == .installation && session.operationSuspensionCount == 0,
               "Installer failure releases the command suspension and leaves current app usable")
        service.failureAfterCommit = nil
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        await settle()
        expect(service.installedBuild == 5 && service.installations == 3,
               "Retry needs fresh explicit consent after ordinary quit or installation failure")
    }

    private static func checkDownloadLeavesRadioResponsive() async {
        let fixture = UpdateSessionFixture()
        fixture.ready()
        let service = ControlledUpdateService()
        service.offers = [makeOffer()]
        service.holdDownloads = true
        let coordinator = UpdateCoordinator(installed: installed, service: service,
            session: fixture.session, preferences: UpdatePreferences())
        coordinator.checkManually(); await settle(); coordinator.download(); await settle()
        fixture.session.sendTestFlash()
        expect(fixture.transport.testWrites == 1 && coordinator.snapshot.stage == .downloading,
               "A background transfer leaves real radio command entrypoints responsive")
        fixture.transport.emit(.commandSent(.test))
        service.downloadReply?.resume(returning: ControlledUpdateService.downloaded(makeOffer()))
        service.downloadReply = nil
        await settle()
        expect(coordinator.snapshot.stage == .blocked && fixture.session.phase == .ready,
               "A completed download preserves the connected session and requires explicit disconnect")
    }

    private static func checkOpaqueFailuresAndCancellationKeepNetworkPolicy() async {
        let clock = ControlledUpdateClock()
        let service = ControlledUpdateService()
        service.holdChecks = true
        let coordinator = UpdateCoordinator(installed: installed, service: service,
            session: MockRadioRuntime.makeController(), preferences: UpdatePreferences(), clock: clock)
        coordinator.enableAutomaticUpdates()
        clock.advance(0)
        await settle()
        coordinator.setAutomaticChecks(false)
        expect(service.cancelRequested, "Opting out stops an in-flight automatic check")
        service.checkReply?.resume(returning: [makeOffer()])
        service.checkReply = nil
        await settle()
        expect(coordinator.snapshot.offer == nil && service.downloads == 0,
               "A late successful callback cannot resurrect disabled automatic work")
        service.holdChecks = false
        service.checkFailure = UpdateServiceFailure(.network)
        coordinator.checkManually()
        await settle()
        expect(coordinator.snapshot.stage == .error && coordinator.snapshot.lastSuccessfulCheck == nil,
               "Opaque transport failure never invents a successful check")
        expect(coordinator.snapshot.nextAutomaticAttempt == Date(timeIntervalSince1970: 1_800_086_400),
               "Missing transport metadata uses a conservative 24-hour retry deadline")
        service.checkFailure = nil
        coordinator.checkManually()
        await settle()
        expect(coordinator.snapshot.stage == .upToDate && !coordinator.snapshot.automaticChecks,
               "Manual retry succeeds without re-enabling automatic connections")
    }

    private static func checkOfferWithdrawalAndFreshIdentityMismatch() async {
        let service = ControlledUpdateService()
        service.offers = [makeOffer()]
        let session = MockRadioRuntime.makeController()
        let coordinator = UpdateCoordinator(installed: installed, service: service,
            session: session, preferences: UpdatePreferences())
        coordinator.checkManually(); await settle(); coordinator.download(); await settle()
        service.freshIdentity = makeOffer(build: 6).identity
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        await settle()
        expect(service.installedBuild == 4 && coordinator.snapshot.failure?.kind == .invalidOffer,
               "Fresh feed changing the confirmed build cannot authorize cached installation")
        expect(session.operationSuspensionCount == 0, "Rejected fresh identity does not retain a command lock")
        service.freshIdentity = nil
        service.installationFailure = UpdateServiceFailure(.network, httpStatus: 403)
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        await settle()
        expect(service.installedBuild == 4 && coordinator.snapshot.failure?.httpStatus == 403,
               "Offline or failed fresh validation retains the current installed app")
        service.offers = []
        coordinator.checkManually(); await settle()
        expect(coordinator.snapshot.downloadedIdentity == nil && coordinator.snapshot.stage == .upToDate,
               "A withdrawn offer loses its cached installation action")
        let attempts = service.installations
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        await settle()
        expect(service.installations == attempts, "Old confirmation cannot install a withdrawn offer")

        service.offers = [makeOffer()]
        service.downloadOverride = ControlledUpdateService.downloaded(makeOffer(build: 6))
        coordinator.checkManually(); await settle(); coordinator.download(); await settle()
        expect(coordinator.snapshot.failure?.kind == .archive && coordinator.snapshot.downloadedIdentity == nil,
               "A different download payload identity is never shown as ready")
    }

    private static func checkPersistedUnresolvableDraftDoesNotTrapUpdate() async {
        let fixture = UpdateSessionFixture()
        fixture.session.setChangeDeliveryMode(.manual)
        fixture.ready()
        fixture.session.setGlobalMultiFlashEnabled(true)
        fixture.session.setMultiFlashPower(ManualPower.value(decimal: 80)!)
        fixture.session.setMultiFlashHertz(100)
        fixture.session.setMultiFlashCount(100)
        fixture.session.applyPendingChanges()
        for _ in fixture.session.workingGroups { fixture.confirmControl() }
        fixture.session.setFlashModel("ad400pro-ii", assigned: true, to: .b)
        expect(fixture.session.multiFlashDraft.count == 2 && fixture.session.multiFlashBaseline.count == 100,
               "Model change creates the existing persisted derived Multi draft")
        expect(fixture.session.canApply && !fixture.session.canDiscardPendingChanges,
               "Connected derived draft has Apply as its only resolution")
        let suspension = fixture.session.suspendOperations()
        expect(!fixture.session.canApply && fixture.session.terminationBlockReason != nil,
               "Command suspension cannot turn a resolvable draft into the close exception")
        fixture.session.resumeActiveScene()
        fixture.session.applyPendingChanges()
        expect(fixture.session.phase == .ready, "Suspension gates the real Apply entrypoint")
        fixture.session.resumeOperations(suspension)
        fixture.session.disconnect()
        fixture.scheduler.fire(.disconnectRecovery)
        expect(fixture.session.phase == .idle && fixture.session.terminationBlockReason == nil,
               "Persisted derived draft with no legal Apply/Discard does not trap close")
        let relaunched = UpdateSessionFixture(persistence: fixture.persistence)
        expect(relaunched.session.pendingCount == 0 && relaunched.session.multiFlashDraft.count == 2,
               "The saved workspace reopens with the derived value intact")
        let service = ControlledUpdateService()
        service.offers = [makeOffer(channel: .stable)]
        let coordinator = UpdateCoordinator(installed: installed, service: service,
            session: fixture.session, preferences: UpdatePreferences())
        coordinator.checkManually(); await settle(); coordinator.download(); await settle()
        coordinator.confirmInstall(expectedIdentity: makeOffer(channel: .stable).identity)
        await settle()
        expect(service.installedBuild == 5 && coordinator.snapshot.stage == .installing,
               "Explicit installation can commit with the persisted unresolvable exception")
        coordinator.confirmInstall(expectedIdentity: makeOffer(channel: .stable).identity)
        coordinator.checkManually()
        await settle()
        expect(service.installations == 1 && coordinator.snapshot.stage == .installing,
               "Completed approval remains committed and cannot start another operation")
    }

    private static func checkExistingSessionSafetyClasses() async {
        let fixture = UpdateSessionFixture()
        let service = ControlledUpdateService()
        service.offers = [makeOffer()]
        let coordinator = UpdateCoordinator(installed: installed, service: service,
            session: fixture.session, preferences: UpdatePreferences())
        coordinator.checkManually()
        await settle()
        coordinator.download()
        await settle()
        fixture.session.startScanning()
        await expectBlocked(coordinator, service: service, label: "scanning")
        fixture.transport.emit(.discovered(UpdateRadioTransport.candidate))
        fixture.session.radioCode = "111111"
        fixture.session.connectSelectedDevice()
        await expectBlocked(coordinator, service: service, label: "connecting")
        fixture.transport.emit(.stateChanged(.discovering(UpdateRadioTransport.candidate)))
        await expectBlocked(coordinator, service: service, label: "discovering")
        fixture.transport.emit(.stateChanged(.ready(UpdateRadioTransport.candidate)))
        fixture.transport.emit(.readyForAuthentication)
        await expectBlocked(coordinator, service: service, label: "authenticating")
        fixture.authenticate()
        await expectBlocked(coordinator, service: service, label: "synchronizing")
        fixture.scheduler.fire(.valueSynchronizationSettle)
        for _ in fixture.session.workingGroups { fixture.confirmControl() }
        expect(fixture.session.phase == .ready, "Fixture traverses real authentication and synchronization")
        await expectBlocked(coordinator, service: service, label: "connected idle")
        let edit = fixture.session.beginInteractiveEdit()
        await expectBlocked(coordinator, service: service, label: "interactive edit")
        fixture.session.endInteractiveEdit(edit)
        fixture.session.sendTestFlash()
        expect(fixture.session.isTestPending, "A real Test delivery is pending")
        await expectBlocked(coordinator, service: service, label: "Test delivery")
        fixture.transport.emit(.commandSent(.test))
        fixture.session.setChangeDeliveryMode(.automatic)
        fixture.session.adjust(.b, direction: 1)
        expect(fixture.session.isAutomaticApplyScheduled, "A real automatic send is scheduled")
        await expectBlocked(coordinator, service: service, label: "automatic send")
        fixture.session.setChangeDeliveryMode(.manual)
        await expectBlocked(coordinator, service: service, label: "resolvable draft")
        fixture.session.applyPendingChanges()
        expect(fixture.session.phase == .applying, "A real write batch is in progress")
        await expectBlocked(coordinator, service: service, label: "applying")
        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.commandFailed(.control, .writeFailed(command: .control, message: "fixture interrupted write")))
        expect(!fixture.session.restorationPoints.isEmpty, "Interrupted physical delivery retains recovery")
        let recoveryDisconnects = fixture.transport.disconnects
        await expectBlocked(coordinator, service: service, label: "recovery")
        expect(fixture.transport.disconnects == recoveryDisconnects, "Updater never disconnects to make its gate pass")

        let disconnecting = UpdateSessionFixture()
        disconnecting.ready()
        let otherService = ControlledUpdateService()
        otherService.offers = [makeOffer()]
        let other = UpdateCoordinator(installed: installed, service: otherService,
            session: disconnecting.session, preferences: UpdatePreferences())
        other.checkManually(); await settle(); other.download(); await settle()
        disconnecting.session.disconnect()
        await expectBlocked(other, service: otherService, label: "disconnecting")

        let invalidJournal = PendingRestorationStore(storageKey: "invalid-fixture", readObject: { _ in Data([1,2,3]) },
            writeData: { _, _ in true }, removeValue: { _ in true })
        let uncertain = UpdateSessionFixture(restoration: invalidJournal)
        expect(uncertain.session.recoveryBlockReason != nil, "Invalid persisted recovery is uncertain")
        let uncertainService = ControlledUpdateService()
        uncertainService.offers = [makeOffer()]
        let recovery = UpdateCoordinator(installed: installed, service: uncertainService,
            session: uncertain.session, preferences: UpdatePreferences())
        recovery.checkManually(); await settle(); recovery.download(); await settle()
        await expectBlocked(recovery, service: uncertainService, label: "uncertain recovery journal")
    }

    private static func expectBlocked(_ coordinator: UpdateCoordinator, service: ControlledUpdateService, label: String) async {
        await settle()
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        await settle()
        expect(coordinator.snapshot.installationBlocker != nil && service.installations == 0,
               "Installation is blocked during \(label)")
    }

    private static func checkIdentityBoundConsentAndCancellationAcknowledgement() async {
        let service = ControlledUpdateService()
        service.offers = [makeOffer()]
        service.holdInstallation = true
        let session = MockRadioRuntime.makeController()
        let coordinator = UpdateCoordinator(installed: installed, service: service,
            session: session, preferences: UpdatePreferences())
        coordinator.checkManually()
        await settle()
        coordinator.download()
        await settle()
        expect(service.installations == 0, "Completed download and postponement do not authorize installation")
        coordinator.postpone()
        coordinator.confirmInstall(expectedIdentity: makeOffer(build: 99).identity)
        await settle()
        expect(service.installations == 0, "An obsolete confirmation dialog cannot approve a changed offer")
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        await settle()
        expect(service.installations == 1 && coordinator.snapshot.stage == .installing,
               "Exact confirmation starts a single install attempt")
        session.startScanning()
        session.resumeActiveScene()
        session.startScanning()
        expect(session.phase == .idle, "The synchronous commit suspension blocks real scan entrypoints")
        coordinator.cancelInstall()
        expect(service.cancelRequested, "Cancellation reaches the service")
        expect(service.finalPrecommit?(makeOffer().identity) == false,
               "Cancellation invalidates approval even if a late commit callback arrives")
        session.startScanning()
        expect(session.phase == .idle, "Cancellation intent does not release the lock before installer acknowledgement")
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        expect(service.installations == 1, "No competing install while cancellation is pending")
        service.installReply?.resume(throwing: UpdateServiceFailure(.cancelled))
        service.installReply = nil
        await settle()
        expect(coordinator.snapshot.stage == .downloaded && coordinator.snapshot.failure == nil && service.installedBuild == 4,
               "Acknowledged cancellation retains the prior installed app and cached offer")
        session.startScanning()
        expect(session.phase == .scanning, "Failed/cancelled attempts release operation suspension")
    }

    private static func checkSafetyAgainImmediatelyBeforeCommit() async {
        let service = ControlledUpdateService()
        service.offers = [makeOffer()]
        let session = MockRadioRuntime.makeController()
        let coordinator = UpdateCoordinator(installed: installed, service: service,
            session: session, preferences: UpdatePreferences())
        coordinator.checkManually()
        await settle()
        coordinator.download()
        await settle()
        service.beforeCommit = { session.startScanning() }
        coordinator.confirmInstall(expectedIdentity: makeOffer().identity)
        await settle()
        expect(service.installedBuild == 4 && coordinator.snapshot.installationBlocker != nil,
               "A scan begun during fresh-feed validation vetoes installation atomically")
    }

    private static func checkOneTransferAndDisablingOnlyAutomaticWork() async {
        let service = ControlledUpdateService()
        service.offers = [makeOffer()]
        service.holdDownloads = true
        let coordinator = UpdateCoordinator(installed: installed, service: service,
            session: MockRadioRuntime.makeController(), preferences: UpdatePreferences())
        coordinator.checkManually()
        coordinator.checkManually()
        await settle()
        expect(service.checks == 1, "Two surfaces share one in-flight lookup")
        coordinator.download()
        coordinator.download()
        await settle()
        expect(service.downloads == 1 && coordinator.snapshot.stage == .downloading,
               "Repeated actions start only one transfer")
        expect(coordinator.snapshot.progress?.fraction == 0.25, "Progress is visible without blocking session")
        coordinator.setAutomaticChecks(false)
        expect(!service.cancelRequested, "Disabling automatic checks preserves an explicit manual transfer")
        service.downloadReply?.resume(returning: ControlledUpdateService.downloaded(makeOffer()))
        service.downloadReply = nil
        await settle()
        expect(coordinator.snapshot.stage == .downloaded, "Manual download completes while automations are off")

        let clock = ControlledUpdateClock()
        let automaticService = ControlledUpdateService()
        automaticService.offers = [makeOffer()]
        automaticService.holdDownloads = true
        let automatic = UpdateCoordinator(installed: installed, service: automaticService,
            session: MockRadioRuntime.makeController(), preferences: UpdatePreferences(), clock: clock)
        automatic.enableAutomaticUpdates()
        clock.advance(0)
        await settle()
        expect(automaticService.downloads == 1, "Opt-in permits background discovery and download")
        automatic.setAutomaticDownloads(false)
        expect(automaticService.cancelRequested, "Disabling downloads cancels only automatic transfer")
        automaticService.downloadReply?.resume(throwing: UpdateServiceFailure(.cancelled))
        automaticService.downloadReply = nil
        await settle()
        expect(automatic.snapshot.stage == .available && automatic.snapshot.failure == nil,
               "Cancellation leaves the offered version available for a manual retry")
    }

    private static func checkChannelBuildAndCompatibilitySelection() async {
        let service = ControlledUpdateService()
        service.offers = [makeOffer(build: 8, channel: .stable, compatible: false),
                          makeOffer(build: 7, channel: .beta),
                          makeOffer(build: 6, channel: .stable), makeOffer(build: 4)]
        let beta = UpdateCoordinator(installed: installed, service: service,
            session: MockRadioRuntime.makeController(), preferences: UpdatePreferences())
        beta.checkManually()
        await settle()
        expect(beta.snapshot.offer?.identity.build == 7,
               "Beta selects highest compatible build even with the same marketing version")
        let stable = UpdateCoordinator(
            installed: InstalledUpdateVersion(build: 5, marketingVersion: "0.1.0", channel: .stable),
            service: service, session: MockRadioRuntime.makeController(), preferences: UpdatePreferences())
        stable.checkManually()
        await settle()
        expect(stable.snapshot.offer?.identity.build == 6, "Stable ignores beta and incompatible newer builds")
        service.offers = [makeOffer(build: 4), makeOffer(build: 3)]
        beta.checkManually()
        await settle()
        expect(beta.snapshot.stage == .upToDate && beta.snapshot.offer == nil, "Equal/lower builds are never offers")
        service.offers = [makeOffer(build: 6, archive: "https://github.com/loomitz/estrobo/releases/latest/download/update.dmg")]
        stable.checkManually()
        await settle()
        expect(stable.snapshot.failure?.kind == .invalidOffer, "Latest aliases cannot identify immutable bytes")
    }

    private static func makeOffer(build: UInt64 = 5, channel: InstalledUpdateChannel = .beta,
                                  compatible: Bool = true, archive: String? = nil) -> UpdateOffer {
        UpdateOffer(identity: UpdateOfferIdentity(build: build,
            archiveURL: URL(string: archive ?? "https://github.com/loomitz/estrobo/releases/download/v0.1.0-beta.\(build)/update.dmg")!,
            contentLength: 100, edDSASignature: Data(repeating: 1, count: 64).base64EncodedString()),
            marketingVersion: "0.1.0", channel: channel, releaseNotes: "Signed fixture notes",
            minimumSystemVersion: "13.0", maximumSystemVersion: nil, hardwareRequirements: [],
            isCompatibleWithCurrentSystem: compatible)
    }

    private static func checkSecondLaunchInvitationAndPersistentOptOut() async {
        let name = "UpdateCoordinatorCheck.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = MockRadioRuntime.makeController()
        let first = UpdateCoordinator(installed: installed,
            service: ControlledUpdateService(), session: session,
            preferences: UpdatePreferences(defaults: defaults))
        expect(!first.snapshot.showsOptInInvitation, "The first configured launch remains quiet")
        let second = UpdateCoordinator(installed: installed,
            service: ControlledUpdateService(), session: session,
            preferences: UpdatePreferences(defaults: defaults))
        expect(second.snapshot.showsOptInInvitation, "Second post-onboarding launch offers nonmodal opt-in")
        second.dismissOptInInvitation()
        let third = UpdateCoordinator(installed: installed,
            service: ControlledUpdateService(), session: session,
            preferences: UpdatePreferences(defaults: defaults))
        expect(!third.snapshot.showsOptInInvitation && !third.snapshot.automaticChecks,
               "Dismissal persists without enabling network")
        third.setAutomaticDownloads(true)
        expect(!third.snapshot.automaticDownloads, "Download automation requires check automation")
    }

    private static var installed: InstalledUpdateVersion {
        InstalledUpdateVersion(build: 4, marketingVersion: "0.1.0", channel: .beta)
    }

    private static func checkDailyChecksAndBackoffSurviveRelaunch() async {
        let clock = ControlledUpdateClock()
        let name = "UpdateCoordinatorBackoff.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UpdatePreferences(defaults: defaults)
        let service = ControlledUpdateService()
        let session = MockRadioRuntime.makeController()
        var coordinator: UpdateCoordinator? = UpdateCoordinator(
            installed: InstalledUpdateVersion(build: 4, marketingVersion: "0.1.0", channel: .beta),
            service: service, session: session, preferences: preferences, clock: clock)
        coordinator?.enableAutomaticUpdates()
        clock.advance(0)
        await settle()
        expect(service.checks == 1, "Consent allows the initial automatic check")
        clock.advance(86_399)
        await settle()
        expect(service.checks == 1, "No automatic request before 24 hours")
        let serverDeadline = clock.now.addingTimeInterval(259_200)
        service.checkFailure = UpdateServiceFailure(.rateLimit, retryAfter: serverDeadline, httpStatus: 429)
        clock.advance(1)
        await settle()
        expect(coordinator?.snapshot.stage == .error, "A failed check is never up to date")
        expect(coordinator?.snapshot.nextAutomaticAttempt == serverDeadline, "Known Retry-After is respected")
        coordinator?.setAutomaticChecks(false)
        coordinator = nil
        let relaunched = UpdateCoordinator(
            installed: InstalledUpdateVersion(build: 4, marketingVersion: "0.1.0", channel: .beta),
            service: service, session: session, preferences: UpdatePreferences(defaults: defaults), clock: clock)
        relaunched.setAutomaticChecks(true)
        clock.advance(86_400)
        await settle()
        expect(service.checks == 2, "Relaunch and preference toggles cannot shorten server backoff")
        service.checkFailure = nil
        relaunched.checkManually()
        await settle()
        expect(service.checks == 3 && relaunched.snapshot.stage == .upToDate,
               "Manual retry remains available during automatic backoff")
        expect(relaunched.snapshot.nextAutomaticAttempt == serverDeadline,
               "Manual success preserves the known future deadline")
    }

    private static func checkManualLookupDoesNotEnableAutomation() async {
        let session = MockRadioRuntime.makeController()
        let service = ControlledUpdateService()
        let coordinator = UpdateCoordinator(
            installed: InstalledUpdateVersion(build: 4, marketingVersion: "0.1.0", channel: .beta),
            service: service, session: session, preferences: UpdatePreferences())
        expect(!coordinator.snapshot.automaticChecks && !coordinator.snapshot.automaticDownloads,
               "Background network starts disabled")
        coordinator.checkManually()
        await settle()
        expect(coordinator.snapshot.stage == .upToDate, "Successful empty feed reports up to date")
        expect(service.checks == 1 && !coordinator.snapshot.automaticChecks,
               "Manual lookup does not imply background consent")
    }

    private static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
