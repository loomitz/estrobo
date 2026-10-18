import AppKit
import Foundation
import SwiftUI

@main @MainActor
enum UpdateCompositionCheck {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        Task { @MainActor in await run(); exit(0) }
        application.run()
    }
    static func run() async {
        let suite = "mx.loo.estrobo.tests.composition.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = MockRadioRuntime.makeController()
        let delegate = PrototypeAppDelegate()
        let installed = InstalledUpdateVersion(build: 4, marketingVersion: "0.1.0", channel: .beta)
        let runtime = MacUpdateRuntime(installed: installed, session: session, appDelegate: delegate,
            preferences: UpdatePreferences(defaults: defaults), clock: CompositionClock(),
            serviceFactory: { _ in CompositionService() })
        expect(delegate.controller === session, "App and delegate must share the existing session")
        expect(!runtime.coordinator.snapshot.automaticChecks && !runtime.coordinator.snapshot.automaticDownloads,
               "Product composition must preserve default opt-out")
        runtime.coordinator.setAutomaticChecks(true)
        runtime.coordinator.setAutomaticDownloads(false)
        let nextDelegate = PrototypeAppDelegate()
        let next = MacUpdateRuntime(installed: installed, session: MockRadioRuntime.makeController(), appDelegate: nextDelegate,
            preferences: UpdatePreferences(defaults: defaults), clock: CompositionClock(), serviceFactory: { _ in CompositionService() })
        expect(next.coordinator.snapshot.automaticChecks && !next.coordinator.snapshot.automaticDownloads,
               "Constructor relaunch must preserve independent preferences")
        expect(session.phase == .idle && session.connectedDeviceName == nil && next.coordinator.snapshot.installed == installed,
               "Composition must retain installed metadata and start disconnected")
        await verifyCloseProtocol()
        await verifyProductionConfiguration()
        print("Update composition verified")
    }
    static func verifyProductionConfiguration() async {
        guard let path = ProcessInfo.processInfo.environment["ESTROBO_TEST_APP_BUNDLE"], let bundle = Bundle(path: path),
              let installed = InstalledUpdateVersion(bundle: bundle) else { expect(false, "The actual product bundle must provide installed metadata"); return }
        expect(bundle.bundleIdentifier == "mx.loo.estrobo" && bundle.object(forInfoDictionaryKey: "SUPublicEDKey") == nil,
               "This development proof requires the actual product identity without a distribution key")
        let session = MockRadioRuntime.makeController()
        let delegate = PrototypeAppDelegate()
        let runtime = MacUpdateRuntime(installed: installed, session: session, appDelegate: delegate, preferences: UpdatePreferences(),
            serviceFactory: { SparkleUpdateService.makeProduction(lifecycle: $0, bundle: bundle) })
        runtime.coordinator.checkManually()
        await settle()
        expect(runtime.coordinator.snapshot.failure?.kind == .configuration && runtime.coordinator.snapshot.stage == .error,
               "The production factory must expose missing trust configuration honestly")
        expect(session.phase == .idle && !runtime.coordinator.snapshot.automaticChecks,
               "Unavailable update configuration must preserve disconnected local control and opt-out")
    }
    static func verifyCloseProtocol() async {
        let session = MockRadioRuntime.makeController()
        let delegate = PrototypeAppDelegate()
        var restored = 0
        delegate.createMainWindow = { restored += 1 }
        var service: CompositionService!
        let runtime = MacUpdateRuntime(installed: .init(build: 4, marketingVersion: "0.1.0", channel: .beta), session: session,
            appDelegate: delegate, preferences: UpdatePreferences(), clock: CompositionClock(), serviceFactory: { lifecycle in
                let value = CompositionService(lifecycle: lifecycle); service = value; return value
            })
        expect(runtime.lifecycle === delegate.updateLifecycle, "The adapter and real delegate must own one lifecycle")
        let edit = session.beginInteractiveEdit()
        expect(delegate.applicationShouldTerminate(NSApp) == .terminateCancel, "Composition must preserve the existing interactive-edit veto")
        await settle()
        expect(restored == 1, "A refused quit must request the existing main-window restoration")
        session.endInteractiveEdit(edit)
        let host = TerminationRecorder(delegate: delegate)
        NSApp.delegate = host
        runtime.coordinator.checkManually()
        await settle()
        runtime.coordinator.download()
        await settle()
        expect(runtime.coordinator.snapshot.stage == .downloaded, "Controlled bytes alone must leave installation unarmed")
        runtime.coordinator.confirmInstall(expectedIdentity: CompositionService.offer.identity)
        await settle()
        expect(runtime.lifecycle.state == .preparing && runtime.coordinator.hasInstallationInProgress,
               "An explicit install must pass through the real AppKit preflight before preparation")
        session.startScanning()
        expect(session.phase == .idle, "Public radio entry points must remain frozen during the acknowledged preparation")
        NSApp.terminate(nil)
        await settle()
        expect(service.cancelRequested && runtime.coordinator.snapshot.isCancellingInstallation && host.allowedQuits == 0,
               "Ordinary quit must invalidate approval and wait for the install cancellation acknowledgement")
        session.startScanning()
        expect(session.phase == .idle, "Cancellation intent must not release radio commands")
        service.acknowledgeCancellation()
        await settle()
        expect(!runtime.coordinator.hasInstallationInProgress && host.allowedQuits == 1,
               "The acknowledged real lifecycle must retry ordinary quit exactly once")
        session.startScanning()
        expect(session.phase == .scanning, "Commands become available only after cancellation acknowledgement")
        session.cancelConnectionAttempt()
        expect(runtime.coordinator.snapshot.installed.build == 4, "Ordinary quit must not replace the installed version")
        NSApp.delegate = nil
    }
    static func settle() async { try? await Task.sleep(for: .milliseconds(200)) }
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}

@MainActor private final class CompositionClock: UpdateClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func schedule(at date: Date, action: @escaping @MainActor () -> Void) -> UpdateScheduleToken { UpdateScheduleToken() }
}
@MainActor private final class CompositionService: UpdateService {
    let lifecycle: UpdateInstallationLifecycle?
    var cancelRequested = false
    var installReply: CheckedContinuation<Void, Error>?
    init(lifecycle: UpdateInstallationLifecycle? = nil) { self.lifecycle = lifecycle }
    func check(for installed: InstalledUpdateVersion) async throws -> [UpdateOffer] { [Self.offer] }
    func download(_ offer: UpdateOffer, progress: @escaping @MainActor (UpdateDownloadProgress) -> Void) async throws -> DownloadedUpdate {
        DownloadedUpdate(offerIdentity: offer.identity, localFile: URL(fileURLWithPath: "/tmp/composition-fixture.dmg"), length: 100, sha256: String(repeating: "a", count: 64))
    }
    func install(_ download: DownloadedUpdate, offer: UpdateOffer, precommit: @escaping @MainActor (UpdateOfferIdentity) -> Bool) async throws {
        guard let lifecycle else { throw UpdateServiceFailure(.configuration) }
        defer { lifecycle.attemptDidFinish() }
        guard await lifecycle.preflight(cancel: { [weak self] in self?.cancel() }), precommit(offer.identity) else { throw UpdateServiceFailure(.unsafeSession) }
        try await withCheckedThrowingContinuation { installReply = $0 }
    }
    func cancel() { cancelRequested = true }
    func acknowledgeCancellation() { installReply?.resume(throwing: UpdateServiceFailure(.cancelled)); installReply = nil }
    static let offer = UpdateOffer(identity: .init(build: 5, archiveURL: URL(string: "https://github.com/loomitz/estrobo/releases/download/v0.1.0-beta.5/estrobo-v0.1.0-beta.5-macos-universal.dmg")!, contentLength: 100, edDSASignature: Data(repeating: 1, count: 64).base64EncodedString()), marketingVersion: "0.1.0", channel: .beta, releaseNotes: "Composition fixture", minimumSystemVersion: "13.0", maximumSystemVersion: nil, hardwareRequirements: [], isCompatibleWithCurrentSystem: true)
}
@MainActor private final class TerminationRecorder: NSObject, NSApplicationDelegate {
    let product: PrototypeAppDelegate
    var allowedQuits = 0
    init(delegate: PrototypeAppDelegate) { product = delegate }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let reply = product.applicationShouldTerminate(sender)
        if reply == .terminateNow { allowedQuits += 1; return .terminateCancel }
        return reply
    }
}
