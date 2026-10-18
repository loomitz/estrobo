import AppKit

#if canImport(EstroboCore)
import EstroboCore
#endif

@MainActor
final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: GodoxSessionController?
    var createMainWindow: (() -> Void)?
    lazy var updateLifecycle = UpdateInstallationLifecycle(blockReason: { [weak self] in
        guard let controller = self?.controller, let reason = controller.terminationBlockReason else { return nil }
        controller.noteTerminationBlocked(reason)
        return reason
    }, restoreWindow: { [weak self] in self?.showMainWindow() })

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showMainWindow()
        return false
    }

    func showMainWindow() {
        let application = NSApplication.shared
        if let window = application.windows.first(where: {
            !($0 is NSPanel) && $0.title.lowercased() == "estrobo"
        }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            createMainWindow?()
        }
        application.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        updateLifecycle.applicationShouldTerminate(sender)
    }
}
