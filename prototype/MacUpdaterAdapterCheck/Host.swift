import AppKit
import Combine

@MainActor
final class AdapterHost: NSObject, NSApplicationDelegate {
    let root: URL
    var window: NSWindow!
    var buttons: [String: NSButton] = [:]
    var status: NSTextField!
    var bridge: UpdateInstallationLifecycle!
    var service: (any UpdateService)!
    var offer: UpdateOffer?
    var downloaded: DownloadedUpdate?
    var blocked = false
    var veto = false
    var timer: Timer?
    var lastCommand: String?
    var observation: AnyCancellable?
    var snapshotNumber = 0
    var evictBeforeCopy = false

    init(root: URL) { self.root = root }
    func log(_ message: String) {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let line = "\(Date()) pid=\(ProcessInfo.processInfo.processIdentifier) build=\(build) \(message)\n"
        if let file = try? FileHandle(forWritingTo: root.appendingPathComponent("events.log")) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data(line.utf8))
        }
    }

    func present(_ message: String) {
        status.stringValue = message
        log(message)
        snapshotNumber += 1
        let directory = root.appendingPathComponent("ui")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot: [String: Any] = ["status": message, "pid": ProcessInfo.processInfo.processIdentifier,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            "buttons": buttons.mapValues { ["title": $0.title, "enabled": $0.isEnabled] }]
        let stem = "pid\(ProcessInfo.processInfo.processIdentifier)-" + String(format: "%03d", snapshotNumber)
        try? JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent(stem + ".json"))
        window.displayIfNeeded()
        if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(stem + ".png"))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 650, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Real Estrobo adapter fixture"
        window.appearance = NSAppearance(named: .aqua)
        status = NSTextField(wrappingLabelWithString: "Starting")
        status.frame = NSRect(x: 20, y: 265, width: 610, height: 70)
        window.contentView?.addSubview(status)
        let actions = [("check", "Check"), ("cancel", "Cancel"), ("download", "Download"),
                       ("install", "Install and restart"), ("pause", "Install (pause)"), ("continue", "Continue"),
                       ("block", "Unsafe work"), ("unblock", "Resolve"), ("veto", "Veto close"),
                       ("quit", "Quit"), ("evict", "Evict cache"),
                       ("install-queued", "Queue preflight"), ("queue-commit", "Queue final commit"),
                       ("install-evict", "Install (evict)")]
        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.1, target: self, action: #selector(clicked(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(action.0)
            button.setAccessibilityIdentifier(action.0)
            button.frame = NSRect(x: 20 + (index % 3) * 205, y: 210 - (index / 3) * 48, width: 195, height: 34)
            window.contentView?.addSubview(button)
            buttons[action.0] = button
        }
        let menu = NSMenu()
        let appMenu = NSMenu()
        let top = NSMenuItem()
        top.submenu = appMenu
        menu.addItem(top)
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        bridge = UpdateInstallationLifecycle(blockReason: { [weak self] in
            self?.blocked == true || self?.veto == true ? "Fixture close veto" : nil
        }, restoreWindow: { [weak self] in self?.window.makeKeyAndOrderFront(nil) })
        bridge.ordinaryQuitRequested = { [weak self] in self?.log("ordinary-quit-invalidates-consent") }
        observation = bridge.$state.sink { [weak self] value in self?.present("lifecycle-\(value.rawValue)") }
        do {
            service = try SparkleUpdateService.testing(bundle: .main,
                feedURL: URL(string: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as! String)!,
                cacheDirectory: root.appendingPathComponent("cache"), lifecycle: bridge,
                event: { [weak self] message in self?.log(message) })
        } catch { present("configuration-error \(error)") }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        lastCommand = try? String(contentsOf: root.appendingPathComponent("command"), encoding: .utf8)
        timer = Timer(timeInterval: 0.03, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        present("launched")
    }

    @objc func clicked(_ button: NSButton) {
        let action = button.identifier!.rawValue
        log("ui-action \(action)")
        if action == "check" {
            Task { [self] in
                do {
                    let offers = try await service.check(for: InstalledUpdateVersion(bundle: .main)!)
                    offer = offers.max { $0.identity.build < $1.identity.build }
                    present("checked builds=\(offers.map { $0.identity.build }) notes-es=\(offer?.localizedReleaseNotes["es"] ?? "missing")")
                } catch { presentFailure(error, operation: "check") }
            }
        }
        if action == "download", let offer {
            Task { [self] in
                do {
                    downloaded = try await service.download(offer) { [weak self] progress in self?.log("progress \(progress.completedBytes)/\(progress.totalBytes)") }
                    present("downloaded sha256=\(downloaded!.sha256) length=\(downloaded!.length)")
                } catch { presentFailure(error, operation: "download") }
            }
        }
        if ["install", "pause", "install-queued", "install-evict"].contains(action), let offer, let downloaded {
            bridge.pauseBeforeFinalCommit = action == "pause"
            bridge.pauseQueuedTermination = action == "install-queued"
            evictBeforeCopy = action == "install-evict"
            Task { [self] in
                do {
                    try await service.install(downloaded, offer: offer) { [weak self] identity in
                        self?.log("precommit build=\(identity.build)")
                        if self?.evictBeforeCopy == true {
                            URLCache.shared.removeAllCachedResponses()
                            self?.evictBeforeCopy = false
                            self?.log("cache-evicted-at-public-precommit")
                        }
                        return self?.blocked == false && identity == offer.identity
                    }
                    present("install-completed")
                } catch { presentFailure(error, operation: "install") }
            }
        }
        if action == "cancel" { service.cancel() }
        if action == "continue" { bridge.continuePreparedInstallation() }
        if action == "queue-commit" { bridge.pauseQueuedTermination = true; bridge.continuePreparedInstallation(); present("final-request-queued") }
        if action == "block" { blocked = true; service.cancel(); present("blocked") }
        if action == "unblock" { blocked = false; veto = false; present("unblocked") }
        if action == "veto" { veto = true; present("veto-armed") }
        if action == "quit" { NSApp.terminate(nil) }
        if action == "evict" { URLCache.shared.removeAllCachedResponses(); present("cache-evicted") }
    }

    func presentFailure(_ error: Error, operation: String) {
        if let failure = error as? UpdateServiceFailure {
            present("\(operation)-failed kind=\(failure.kind.rawValue) status=\(failure.httpStatus ?? 0) retry=\(failure.retryAfter?.timeIntervalSince1970 ?? 0)")
        } else { present("\(operation)-failed unexpected=\(error)") }
    }

    @objc func poll() {
        guard let command = try? String(contentsOf: root.appendingPathComponent("command"), encoding: .utf8), command != lastCommand else { return }
        lastCommand = command
        let action = command.split(separator: " ").last.map(String.init) ?? ""
        if action.hasPrefix("mouse:") {
            let name = String(action.dropFirst(6))
            let button = name == "window-close" ? window.standardWindowButton(.closeButton) : buttons[name]
            guard let button, button.isEnabled else { log("unavailable \(name)"); return }
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                NSApp.postEvent(event, atStart: false)
            }
            log("queued-mouse \(name)")
        } else if action == "key:quit" {
            NSApp.postEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!, atStart: false)
            log("queued-command-q")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let result = bridge.applicationShouldTerminate(sender)
        log("appkit-close-decision \(result.rawValue)")
        return result
    }
}

@main
enum AdapterMain {
    static func main() {
        let root = CommandLine.arguments.dropFirst().first ?? Bundle.main.object(forInfoDictionaryKey: "ConsentSpikeRoot") as! String
        let application = NSApplication.shared
        let host = AdapterHost(root: URL(fileURLWithPath: root))
        application.delegate = host
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(host) {}
    }
}
