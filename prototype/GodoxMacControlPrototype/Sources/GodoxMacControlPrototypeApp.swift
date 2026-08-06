import SwiftUI
import AppKit

// Aplicación macOS para controlar grupos, potencia y modelado junto al
// tethering. Las tres vistas comparten una sola sesión y los mismos borradores.

@main
@MainActor
struct GodoxMacControlPrototypeApp: App {
    @NSApplicationDelegateAdaptor(PrototypeAppDelegate.self) private var appDelegate
    @StateObject private var controller: GodoxSessionController
    @StateObject private var appearanceStore: AppAppearanceStore

    init() {
        _controller = StateObject(
            wrappedValue: MockRadioRuntime.makeControllerIfRequested()
                ?? GodoxSessionController()
        )
        _appearanceStore = StateObject(wrappedValue: AppAppearanceStore())
    }

    var body: some Scene {
        WindowGroup("estrobo") {
            PrototypeRootView(controller: controller)
                .environmentObject(appearanceStore)
                .preferredColorScheme(appearanceStore.appearance.colorScheme)
                .onAppear { appDelegate.controller = controller }
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: GodoxSessionController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller, !controller.restorationPoints.isEmpty else {
            return .terminateNow
        }
        controller.noteTerminationBlockedForRestoration()
        NSApplication.shared.activate(ignoringOtherApps: true)
        return .terminateCancel
    }
}
