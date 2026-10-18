import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@main @MainActor
struct UpdateSceneCompositionCheck: App {
    @NSApplicationDelegateAdaptor(PrototypeAppDelegate.self) private var delegate
    @StateObject private var fixture: SceneFixture
    init() {
        let value = SceneFixture(delegate: _delegate.wrappedValue)
        _fixture = StateObject(wrappedValue: value)
    }
    var body: some Scene {
        MacAppScenes(controller: fixture.session, updater: fixture.runtime.coordinator,
            appearanceStore: fixture.appearance, languageStore: fixture.language, appDelegate: delegate, defaults: fixture.defaults)
    }
}

@MainActor private final class SceneFixture: ObservableObject {
    let session = MockRadioRuntime.makeController()
    let runtime: MacUpdateRuntime
    let service: SceneService
    let delegate: PrototypeAppDelegate
    let defaults: UserDefaults
    let appearance: AppAppearanceStore
    let language: AppLanguageStore
    let suite = "mx.loo.estrobo.tests.scenes.\(UUID())"
    init(delegate: PrototypeAppDelegate) {
        self.delegate = delegate
        let service = SceneService()
        self.service = service
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: MenuBarVisibilityPreferences.storageKey)
        appearance = AppAppearanceStore(defaults: defaults, arguments: ["--theme=light"])
        language = AppLanguageStore(preferences: AppLanguagePreferences(defaults: defaults))
        language.select(.es)
        let preferences = UpdatePreferences(defaults: defaults)
        preferences.state.postOnboardingLaunches = 1
        runtime = MacUpdateRuntime(installed: .init(build: 4, marketingVersion: "0.1.0", channel: .beta), session: session,
            appDelegate: delegate, preferences: preferences, serviceFactory: { _ in service })
        Task { @MainActor [self] in
            await verify()
            defaults.removePersistentDomain(forName: suite)
            print("Product update scenes verified")
            exit(0)
        }
    }
    func verify() async {
        let deadline = Date().addingTimeInterval(8)
        while !NSApp.windows.contains(where: { $0.title.lowercased() == "estrobo" }), Date() < deadline { await settle() }
        guard let main = NSApp.windows.first(where: { $0.title.lowercased() == "estrobo" }) else { fail("The productive main scene must appear") }
        await settle()
        expect(runtime.coordinator.snapshot.showsOptInInvitation, "The composed main window must receive the invitation snapshot")
        expect(main.contentLayoutRect.height <= 821, "The invitation must fit the habitual 820-point main content height")
        expect(findMenu(NSApp.mainMenu, title: "Buscar actualizaciones…") != nil, "The real Estrobo app menu must expose localized manual checking")
        if let directory = ProcessInfo.processInfo.environment["ESTROBO_UPDATE_COMPOSITION_EVIDENCE_DIR"], let view = main.contentView {
            try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("main-invitation-es-light.png"))
        }
        guard let item = findMenu(NSApp.mainMenu, title: "Buscar actualizaciones…"), let menu = item.menu else { fail("No manual command") }
        menu.performActionForItem(at: menu.index(of: item))
        menu.performActionForItem(at: menu.index(of: item))
        await settle()
        expect(service.checks == 1 && runtime.coordinator.snapshot.stage == .checking, "The real app menu must deduplicate one shared manual check")
        guard let updates = NSApp.windows.first(where: { $0.title == "Actualizaciones" }) else { fail("Manual command must open the one productive Updates window") }
        expect(NSApp.windows.filter { $0.title == "Actualizaciones" }.count == 1, "Repeated menu use must retain one Updates window")
        updates.makeKeyAndOrderFront(nil)
        await settle()
        expect(findMenu(NSApp.mainMenu, title: "Buscar actualizaciones…") != nil, "Manual checking must remain in the app menu while Updates is active")
        delegate.showMainWindow()
        expect(press(in: main, label: "Configuración"), "The real workspace must expose its Settings sheet")
        await settle()
        expect(press(in: main, identifier: "updates.automaticChecks"), "The productive Settings sheet must receive the coordinator")
        await settle()
        expect(runtime.coordinator.snapshot.automaticChecks && !runtime.coordinator.snapshot.automaticDownloads && service.checks == 1,
               "Settings and app menu must share independent preferences and the in-flight check")
        expect(press(in: main, label: "Cerrar"), "Settings must retain its native close action")
        await settle()
        service.finishCheck()
        await settle()
        expect(runtime.coordinator.snapshot.stage == .available, "A completed shared check must reach the Updates surface")
        expect(press(in: updates, identifier: "updates.download"), "The real Updates scene must expose manual download")
        await settle()
        expect(runtime.coordinator.snapshot.progress?.completedBytes == 0, "Initial byte progress must remain observable")
        expect(hasText("0 bytes", in: updates) && !hasText("Zero", in: updates), "Spanish initial progress must use the selected locale even on an English system")
        expect(press(in: updates, identifier: "updates.cancelDownload"), "The composed transfer must remain cancellable")
        await settle()
        expect(runtime.coordinator.snapshot.stage == .available && session.phase == .idle, "Cancelling an update must preserve the disconnected radio session")
        if let directory = ProcessInfo.processInfo.environment["ESTROBO_UPDATE_COMPOSITION_EVIDENCE_DIR"] {
            let report: [String: Any] = ["passed": true, "fixture": "Product MacAppScenes, PrototypeAppDelegate, coordinator and controlled service; simulated radio; isolated defaults",
                "mainContentWidth": main.contentLayoutRect.width, "mainContentHeight": main.contentLayoutRect.height,
                "selectedLanguage": language.language.rawValue, "systemLocale": Locale.current.identifier,
                "manualRequests": service.checks, "updatesWindows": NSApp.windows.filter { $0.title == "Actualizaciones" }.count,
                "zeroProgressLocalized": true, "disconnected": session.phase == .idle]
            try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: directory).appendingPathComponent("results.json"))
        }
    }
    func findMenu(_ menu: NSMenu?, title: String) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.title == title { return item }
            if let child = findMenu(item.submenu, title: title) { return child }
        }
        return nil
    }
    func elements(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 24 else { return [] }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        return [element] + ((value as? [AXUIElement]) ?? []).flatMap { elements($0, depth: depth + 1) }
    }
    func attribute(_ element: AXUIElement, _ key: String) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return value as? String
    }
    func windowElements(_ window: NSWindow) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(getpid()), kAXWindowsAttribute as CFString, &value)
        guard let element = (value as? [AXUIElement])?.first(where: { attribute($0, kAXTitleAttribute) == window.title }) else { return [] }
        return elements(element)
    }
    func press(in window: NSWindow, identifier: String? = nil, label: String? = nil) -> Bool {
        guard let element = windowElements(window).first(where: { element in
            if let identifier { return attribute(element, kAXIdentifierAttribute) == identifier }
            return attribute(element, kAXTitleAttribute) == label || attribute(element, kAXDescriptionAttribute) == label
        }) else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
    func hasText(_ text: String, in window: NSWindow) -> Bool {
        windowElements(window).contains { element in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].contains { attribute(element, $0)?.contains(text) == true } }
    }
    func settle() async { try? await Task.sleep(for: .milliseconds(250)) }
    func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fail(message) } }
    func fail(_ message: String) -> Never { defaults.removePersistentDomain(forName: suite); fputs("FAIL: \(message)\n", stderr); exit(1) }
}
@MainActor private final class SceneService: UpdateService {
    var checks = 0
    var checkReply: CheckedContinuation<[UpdateOffer], Error>?
    var downloadReply: CheckedContinuation<DownloadedUpdate, Error>?
    func check(for installed: InstalledUpdateVersion) async throws -> [UpdateOffer] {
        checks += 1
        return try await withCheckedThrowingContinuation { checkReply = $0 }
    }
    func finishCheck() { checkReply?.resume(returning: [Self.offer]); checkReply = nil }
    func download(_ offer: UpdateOffer, progress: @escaping @MainActor (UpdateDownloadProgress) -> Void) async throws -> DownloadedUpdate {
        progress(.init(completedBytes: 0, totalBytes: 100))
        return try await withCheckedThrowingContinuation { downloadReply = $0 }
    }
    func install(_ download: DownloadedUpdate, offer: UpdateOffer, precommit: @escaping @MainActor (UpdateOfferIdentity) -> Bool) async throws { throw UpdateServiceFailure(.cancelled) }
    func cancel() { downloadReply?.resume(throwing: UpdateServiceFailure(.cancelled)); downloadReply = nil }
    static let offer = UpdateOffer(identity: .init(build: 5, archiveURL: URL(string: "https://github.com/loomitz/estrobo/releases/download/v0.1.0-beta.5/estrobo-v0.1.0-beta.5-macos-universal.dmg")!, contentLength: 100, edDSASignature: Data(repeating: 1, count: 64).base64EncodedString()), marketingVersion: "0.1.0", channel: .beta, releaseNotes: "Notas locales", minimumSystemVersion: "13.0", maximumSystemVersion: nil, hardwareRequirements: [], isCompatibleWithCurrentSystem: true)
}
