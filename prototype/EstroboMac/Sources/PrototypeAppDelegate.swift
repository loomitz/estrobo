import AppKit

#if canImport(EstroboCore)
import EstroboCore
#endif

@MainActor
final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: GodoxSessionController?
    var createMainWindow: (() -> Void)?

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
        guard let controller,
              let blockReason = controller.terminationBlockReason else {
            return .terminateNow
        }
        controller.noteTerminationBlocked(blockReason)
        // A last-window close may still be tearing down its SwiftUI scene.
        // Restore it on the next turn so a refused quit cannot strand the app.
        DispatchQueue.main.async { [self] in showMainWindow() }
        return .terminateCancel
    }
}
