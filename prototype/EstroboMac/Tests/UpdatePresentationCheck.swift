import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@main @MainActor
enum UpdatePresentationCheck {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        Task { @MainActor in await run(); exit(0) }
        app.run()
    }
    static func run() async {
        let session = MockRadioRuntime.makeController()
        let service = PresentationService()
        let coordinator = UpdateCoordinator(installed: .init(build: 4, marketingVersion: "0.1.0", channel: .beta), service: service, session: session, preferences: UpdatePreferences())
        let language = AppLanguageStore(preferences: AppLanguagePreferences(storageKey: "test.language", readString: { _ in "en" }, writeString: { _, _ in }))
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 680, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        var openedURLs: [URL] = []
        window.contentView = NSHostingView(rootView: UpdatesView().environmentObject(coordinator).environmentObject(language)
            .environment(\.openURL, OpenURLAction { url in openedURLs.append(url); return .handled }))
        window.title = "Update UI fixture"
        window.makeKeyAndOrderFront(nil)

        try? await Task.sleep(for: .milliseconds(200))
        expect(press("updates.check", in: window), "The rendered Check for Updates action must be accessible")
        try? await Task.sleep(for: .milliseconds(100))
        expect(service.checks == 1 && coordinator.snapshot.stage == .available, "Manual checking must reach the shared service without enabling automatic checks")
        expect(!coordinator.snapshot.automaticChecks, "Manual action must preserve opt-out")
        expect(press("updates.manual", in: window), "Manual download must remain explicitly requested")
        await settle()
        expect(openedURLs.last == PresentationService.offer.identity.archiveURL, "Manual and assisted installation must use the same exact offered archive")
        expect(press("updates.automaticChecks", in: window), "Background checks must be a native accessible control")
        await settle()
        expect(coordinator.snapshot.automaticChecks && !coordinator.snapshot.automaticDownloads, "Enabling checks alone must preserve independent downloads")
        expect(press("updates.automaticDownloads", in: window), "Background downloads must be a separate accessible control")
        await settle()
        expect(coordinator.snapshot.automaticDownloads, "Download preference must reach the coordinator")
        expect(press("updates.automaticChecks", in: window), "Checks must be switchable off")
        await settle()
        expect(!coordinator.snapshot.automaticChecks && !coordinator.snapshot.automaticDownloads, "Disabling checks must disable automatic download")
        expect(press("updates.download", in: window), "Available updates must expose an explicit download action")
        await settle()
        expect(coordinator.snapshot.stage == .downloading, "Download action must show transfer state")
        expect(press("updates.cancelDownload", in: window), "A transfer must be cancellable from the rendered surface")
        await settle()
        expect(coordinator.snapshot.stage == .available, "Cancelled download must return to the same offer without approval")
        expect(press("updates.download", in: window), "A cancelled transfer must be retryable")
        await settle()
        service.completeDownload()
        await settle()
        expect(coordinator.snapshot.stage == .downloaded && service.installations == 0, "Downloaded bytes must not authorize installation")
        expect(press("updates.install", in: window), "Downloaded update must expose Install and Restart")
        await settle()
        expect(service.installations == 0, "Opening confirmation must not authorize installation")
        expect(press("updates.confirm", in: window), "Confirmation must identify an explicit accessible acceptance action")
        await settle()
        expect(service.installations == 1 && coordinator.snapshot.stage == .installing, "Accepting this offer must reach one installation")
        expect(press("updates.cancelInstall", in: window), "Preparation must remain cancellable")
        await settle()
        expect(coordinator.snapshot.stage == .downloaded, "Acknowledged cancellation must restore downloaded state")
        expect(press("updates.install", in: window), "Cancellation must require a fresh confirmation")
        await settle()
        service.offers = [PresentationService.newerOffer]
        coordinator.checkManually()
        await settle()
        coordinator.download()
        await settle()
        service.completeDownload()
        await settle()
        expect(press("updates.confirm", in: window), "The original displayed confirmation must remain actionable")
        await settle()
        expect(coordinator.snapshot.failure?.kind == .invalidOffer && service.installations == 1,
               "An older dialog must not approve a different downloaded offer")
        let settings = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 500, height: 330), styleMask: [.titled], backing: .buffered, defer: false)
        settings.title = "Update Settings fixture"
        settings.contentView = NSHostingView(rootView: UpdateSettingsSection().environmentObject(coordinator).environmentObject(language).padding(24))
        settings.makeKeyAndOrderFront(nil)
        await settle()
        expect(press("updates.automaticChecks", in: settings), "Settings must expose the same automatic check preference")
        await settle()
        expect(coordinator.snapshot.automaticChecks, "Settings and Updates must share one preference state")
        settings.orderOut(nil)
        service.checkFailure = UpdateServiceFailure(.network)
        coordinator.checkManually()
        await settle()
        expect(hasText("Could not connect", in: window), "A failed check must expose localized recovery, never up to date")
        service.checkFailure = nil
        service.offers = []
        coordinator.checkManually()
        await settle()
        expect(press("updates.manual", in: window), "Without an offer, manual recovery must open the selected-language guide")
        await settle()
        expect(openedURLs.last?.absoluteString == "https://estrobo.app/en/guide/", "English manual recovery must use the actual /en/guide/ route")
        window.orderOut(nil)
        await verifyInvitation()
        await captureBatch()
        print("Update presentation verified")
    }
    static func verifyInvitation() async {
        for enable in [false, true] {
            let preferences = UpdatePreferences()
            preferences.state.postOnboardingLaunches = 1
            let service = PresentationService()
            let coordinator = UpdateCoordinator(installed: .init(build: 4, marketingVersion: "0.1.0", channel: .beta), service: service,
                session: MockRadioRuntime.makeController(), preferences: preferences)
            let language = AppLanguageStore(preferences: AppLanguagePreferences(storageKey: "test.invitation", readString: { _ in "en" }, writeString: { _, _ in }))
            let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 680, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "Invitation fixture"
            window.contentView = NSHostingView(rootView: UpdatesView().environmentObject(coordinator).environmentObject(language))
            window.makeKeyAndOrderFront(nil)
            await settle()
            expect(coordinator.snapshot.showsOptInInvitation && window.attachedSheet == nil, "Second-launch invitation must be nonmodal")
            let field = NSTextField(string: "Workspace typing fixture")
            field.frame = NSRect(x: 24, y: 8, width: 240, height: 22)
            let workspace = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 320, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            workspace.title = "Workspace typing fixture"
            workspace.contentView?.addSubview(field)
            workspace.makeKeyAndOrderFront(nil)
            workspace.makeFirstResponder(field)
            let responder = workspace.firstResponder
            let keyWindow = NSApp.keyWindow
            coordinator.checkManually()
            await settle()
            expect(workspace.firstResponder === responder && NSApp.keyWindow === keyWindow, "Discovery must not steal native keyboard focus")
            expect(press(enable ? "updates.enable" : "updates.skip", in: window), "The nonmodal invitation must offer enable and decline actions")
            await settle()
            expect(!coordinator.snapshot.showsOptInInvitation && coordinator.snapshot.automaticChecks == enable && coordinator.snapshot.automaticDownloads == enable,
                "Invitation choice must preserve explicit preference consent")
            coordinator.setAutomaticChecks(false)
            workspace.orderOut(nil)
            window.orderOut(nil)
        }
    }
    static var screenshots: [[String: Any]] = []
    static func captureBatch() async {
        guard let output = ProcessInfo.processInfo.environment["ESTROBO_UPDATE_UI_EVIDENCE_DIR"] else { return }
        for languageValue in [AppLanguage.en, .es] {
            for dark in [false, true] {
                let language = AppLanguageStore(preferences: AppLanguagePreferences(storageKey: "test.capture", readString: { _ in languageValue.rawValue }, writeString: { _, _ in }))
                let preferences = UpdatePreferences()
                preferences.state.postOnboardingLaunches = 1
                let service = PresentationService()
                let session = MockRadioRuntime.makeController()
                let coordinator = UpdateCoordinator(installed: .init(build: 4, marketingVersion: "0.1.0", channel: .beta), service: service, session: session, preferences: preferences)
                let window = NSWindow(contentRect: NSRect(x: 80, y: 40, width: 680, height: 820), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.title = "Presentation capture \(languageValue.rawValue) \(dark)"
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                var openedURLs: [URL] = []
                window.contentView = NSHostingView(rootView: UpdatesView().environmentObject(coordinator).environmentObject(language).environment(\.locale, languageValue.locale).environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.openURL, OpenURLAction { url in openedURLs.append(url); return .handled }))
                window.makeKeyAndOrderFront(nil)
                await settle()
                let prefix = "\(languageValue.rawValue)-\(dark ? "dark" : "light")"
                capture(window, name: "\(prefix)-invitation", output: output)
                expect(press("updates.skip", in: window), "Captured invitation must retain a usable decline action")
                await settle()
                coordinator.checkManually()
                await settle()
                expect(hasText(languageValue == .es ? "Mejoras del espacio" : "Workspace improvements", in: window), "Release notes must follow the selected app language")
                expect(openedURLs.isEmpty, "Rendering update notes must not request a browser or remote content")
                expect(press("updates.manual", in: window), "Manual download must be user initiated")
                await settle()
                expect(openedURLs.last == PresentationService.offer.identity.archiveURL, "Manual download must use exact offered bytes in both languages")
                capture(window, name: "\(prefix)-available", output: output)
                coordinator.download()
                await settle()
                expect(coordinator.snapshot.progress?.completedBytes == 35, "The native progress surface must receive the service's byte progress")
                // NSProgressIndicator animates a newly inserted determinate bar.
                // Wait for its bounded native presentation before snapshotting.
                try? await Task.sleep(for: .milliseconds(750))
                capture(window, name: "\(prefix)-progress", output: output)
                service.completeDownload()
                await settle()
                capture(window, name: "\(prefix)-downloaded", output: output)
                expect(press("updates.install", in: window), "Captured downloaded surface must open explicit confirmation")
                await settle()
                try? await Task.sleep(for: .milliseconds(500))
                capture(window, name: "\(prefix)-confirmation", output: output)
                for (index, panel) in NSApp.windows.filter({ $0 !== window && $0.isVisible && $0.contentView != nil }).enumerated() {
                    capture(panel, name: "\(prefix)-confirmation-panel-\(index)", output: output)
                }
                postEscape(in: window.attachedSheet ?? window)
                await settle()
                expect(service.installations == 0 && !windowElements(window).contains(where: { attribute($0, kAXIdentifierAttribute) == "updates.confirm" }), "Escape must cancel confirmation without installation")
                session.startScanning()
                await settle()
                expect(coordinator.snapshot.stage == .blocked && hasText(languageValue == .es ? "Espera a que termine" : "Wait for transmitter", in: window), "A real simulated scan must block installation and explain the existing control to use")
                capture(window, name: "\(prefix)-blocked", output: output)
                session.cancelConnectionAttempt()
                await settle()
                service.offers = []
                coordinator.checkManually()
                await settle()
                capture(window, name: "\(prefix)-up-to-date", output: output)
                expect(press("updates.manual", in: window), "Manual recovery must remain user initiated")
                await settle()
                expect(openedURLs.last?.absoluteString == (languageValue == .es ? "https://estrobo.app/guia/" : "https://estrobo.app/en/guide/"), "No-offer recovery must use the real localized guide route")
                expect(press("updates.support", in: window), "Support must open only on request")
                await settle()
                expect(openedURLs.last?.absoluteString == "https://github.com/loomitz/estrobo/issues/new", "Support must use the existing repository issue route")
                service.checkFailure = UpdateServiceFailure(.configuration)
                coordinator.checkManually()
                await settle()
                expect(hasText(languageValue == .es ? "Esta copia no tiene configurada" : "This copy is not configured", in: window), "Missing trust configuration must expose localized recovery")
                capture(window, name: "\(prefix)-configuration", output: output)
                service.checkFailure = UpdateServiceFailure(.signature)
                coordinator.checkManually()
                await settle()
                expect(hasText(languageValue == .es ? "La firma no es válida" : "The signature is invalid", in: window), "Invalid trust must remain a visible error")
                capture(window, name: "\(prefix)-signature-error", output: output)
                window.orderOut(nil)
            }
        }
        let report: [String: Any] = ["passed": true, "fixture": "Native NSHostingView, controlled UpdateService, simulated session and in-memory preferences; no Sparkle install or physical radio", "cases": screenshots]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: output).appendingPathComponent("results.json"))
    }
    static func postEscape(in window: NSWindow) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53) else { preconditionFailure("No Escape event") }
        NSApp.postEvent(event, atStart: false)
    }
    static func capture(_ window: NSWindow, name: String, output: String) {
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let content = window.contentView else { preconditionFailure("No hosted view") }
        let view = window.isSheet ? (content.superview ?? content) : content
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { preconditionFailure("No native bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { preconditionFailure("No PNG") }
        let png = directory.appendingPathComponent(name + ".png")
        try! data.write(to: png)
        let accessibility = windowElements(window).map { element in
            ["role": attribute(element, kAXRoleAttribute) ?? "", "identifier": attribute(element, kAXIdentifierAttribute) ?? "",
             "title": attribute(element, kAXTitleAttribute) ?? "", "description": attribute(element, kAXDescriptionAttribute) ?? "", "value": attribute(element, kAXValueAttribute) ?? ""]
        }
        try! JSONSerialization.data(withJSONObject: accessibility, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent(name + ".json"))
        screenshots.append(["name": name, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh, "captureMethod": "NSView.cacheDisplay", "isSheet": window.isSheet, "windowClass": window.className])
    }

    static func settle() async { try? await Task.sleep(for: .milliseconds(100)) }
    static func elements(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 25 else { return [] }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        return [element] + ((value as? [AXUIElement]) ?? []).flatMap { elements($0, depth: depth + 1) }
    }
    static func attribute(_ element: AXUIElement, _ key: String) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return value as? String
    }
    static func press(_ identifier: String, in window: NSWindow) -> Bool {
        guard let element = windowElements(window).first(where: { attribute($0, kAXIdentifierAttribute) == identifier }) else {
            for element in windowElements(window) {
                fputs("AX: \(attribute(element, kAXIdentifierAttribute) ?? "-") | \(attribute(element, kAXTitleAttribute) ?? attribute(element, kAXDescriptionAttribute) ?? "-")\n", stderr)
            }
            return false
        }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
    static func windowElements(_ window: NSWindow) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(getpid()), kAXWindowsAttribute as CFString, &value)
        guard let root = (value as? [AXUIElement])?.first(where: { attribute($0, kAXTitleAttribute) == window.title }) else { return [] }
        return elements(root)
    }
    static func hasText(_ text: String, in window: NSWindow) -> Bool {
        windowElements(window).contains { element in
            [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains { attribute(element, $0)?.contains(text) == true }
        }
    }
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}

@MainActor private final class PresentationService: UpdateService {
    var checks = 0
    var offers = [PresentationService.offer]
    var checkFailure: UpdateServiceFailure?
    var downloadingOffer: UpdateOffer?
    var installations = 0
    var installReply: CheckedContinuation<Void, Error>?
    var downloadReply: CheckedContinuation<DownloadedUpdate, Error>?
    func check(for installed: InstalledUpdateVersion) async throws -> [UpdateOffer] {
        checks += 1
        if let checkFailure { throw checkFailure }
        return offers
    }
    func download(_ offer: UpdateOffer, progress: @escaping @MainActor (UpdateDownloadProgress) -> Void) async throws -> DownloadedUpdate {
        downloadingOffer = offer
        progress(.init(completedBytes: 35, totalBytes: 100))
        return try await withCheckedThrowingContinuation { downloadReply = $0 }
    }
    func install(_ download: DownloadedUpdate, offer: UpdateOffer, precommit: @escaping @MainActor (UpdateOfferIdentity) -> Bool) async throws {
        installations += 1
        guard precommit(offer.identity) else { throw UpdateServiceFailure(.unsafeSession) }
        try await withCheckedThrowingContinuation { installReply = $0 }
    }
    func cancel() {
        downloadReply?.resume(throwing: UpdateServiceFailure(.cancelled)); downloadReply = nil
        installReply?.resume(throwing: UpdateServiceFailure(.cancelled)); installReply = nil
    }
    func completeDownload() {
        downloadReply?.resume(returning: DownloadedUpdate(offerIdentity: downloadingOffer!.identity,
            localFile: URL(fileURLWithPath: "/tmp/estrobo-update-presentation.dmg"), length: 100, sha256: String(repeating: "a", count: 64)))
        downloadReply = nil
    }
    static var newerOffer: UpdateOffer {
        var identity = offer.identity
        identity = .init(build: 6, archiveURL: URL(string: "https://github.com/loomitz/estrobo/releases/download/v0.1.0-beta.6/estrobo.dmg")!, contentLength: 100, edDSASignature: identity.edDSASignature)
        return UpdateOffer(identity: identity, marketingVersion: "0.1.0", channel: .beta, releaseNotes: "New offer", minimumSystemVersion: "13.0", maximumSystemVersion: nil, hardwareRequirements: [], isCompatibleWithCurrentSystem: true)
    }
    static let offer = UpdateOffer(identity: .init(build: 5, archiveURL: URL(string: "https://github.com/loomitz/estrobo/releases/download/v0.1.0-beta.5/estrobo.dmg")!, contentLength: 100, edDSASignature: Data(repeating: 1, count: 64).base64EncodedString()), marketingVersion: "0.1.0", channel: .beta, releaseNotes: "Fallback notes", minimumSystemVersion: "13.0", maximumSystemVersion: nil, hardwareRequirements: [], isCompatibleWithCurrentSystem: true, localizedReleaseNotes: ["es": "Mejoras del espacio de trabajo.\nSin cambios enviados al transmisor.", "en": "Workspace improvements.\nNo changes sent to the transmitter."])
}
