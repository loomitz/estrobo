import SwiftUI
import AppKit

#if canImport(EstroboBluetooth)
import EstroboBluetooth
#endif
#if canImport(EstroboCore)
import EstroboCore
#endif
#if canImport(EstroboPersistence)
import EstroboPersistence
#endif

// Aplicación macOS para controlar grupos, potencia y modelado junto al
// tethering. Las tres vistas comparten una sola sesión y los mismos borradores.

@main
@MainActor
struct GodoxMacControlPrototypeApp: App {
    @NSApplicationDelegateAdaptor(PrototypeAppDelegate.self) private var appDelegate
    @StateObject private var controller: GodoxSessionController
    @StateObject private var appearanceStore: AppAppearanceStore
    @StateObject private var languageStore: AppLanguageStore
    @AppStorage(MenuBarVisibilityPreferences.storageKey)
    private var isMenuBarIconVisible = MenuBarVisibilityPreferences.defaultIsVisible

    init() {
        let sessionController = MockRadioRuntime.makeControllerIfRequested()
            ?? Self.makeLiveController()
        _controller = StateObject(wrappedValue: sessionController)
        _appearanceStore = StateObject(wrappedValue: AppAppearanceStore())
        _languageStore = StateObject(wrappedValue: AppLanguageStore())
        appDelegate.controller = sessionController
    }

    private var menuBarIconInsertionBinding: Binding<Bool> {
        Binding(
            get: { isMenuBarIconVisible },
            set: { newValue in
                guard newValue != isMenuBarIconVisible else { return }
                isMenuBarIconVisible = newValue
            }
        )
    }

    private static func makeLiveController() -> GodoxSessionController {
        let persistence = PersistenceServicesFactory.live()
        return GodoxSessionController(
            transport: RadioTransportFactory.live(),
            deadlineScheduler: LiveSessionDeadlineScheduler(),
            visibilityPreferences: persistence.groupVisibility,
            restorationStore: persistence.restorations,
            savedRadioStore: persistence.savedRadios,
            changeDeliveryPreferences: persistence.changeDelivery,
            transmitterProfilePreferences: persistence.transmitterProfiles,
            studioLibraryStore: persistence.studioLibrary
        )
    }

    var body: some Scene {
        WindowGroup("estrobo", id: "main") {
            PrototypeRootView(controller: controller)
                .environmentObject(appearanceStore)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .preferredColorScheme(appearanceStore.appearance.colorScheme)
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)

        MenuBarExtra(isInserted: menuBarIconInsertionBinding) {
            MenuBarControlView(controller: controller)
                .environmentObject(appearanceStore)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .preferredColorScheme(appearanceStore.appearance.colorScheme)
        } label: {
            MenuBarStatusLabel(controller: controller)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: GodoxSessionController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller,
              let blockReason = controller.terminationBlockReason else {
            return .terminateNow
        }
        controller.noteTerminationBlocked(blockReason)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first(where: { !($0 is NSPanel) })?
            .makeKeyAndOrderFront(nil)
        return .terminateCancel
    }
}
