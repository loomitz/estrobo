import SwiftUI
import AppKit

// Aplicación macOS para controlar grupos, potencia y modelado junto al
// tethering. Las tres vistas comparten una sola sesión y los mismos borradores.

@main
@MainActor
struct EstroboApp: App {
    @NSApplicationDelegateAdaptor(PrototypeAppDelegate.self) private var appDelegate
    @StateObject private var controller: EstroboSessionController
    @StateObject private var appearanceStore: AppAppearanceStore
    @StateObject private var languageStore: AppLanguageStore
    @AppStorage(MenuBarVisibilityPreferences.storageKey)
    private var isMenuBarIconVisible = MenuBarVisibilityPreferences.defaultIsVisible

    init() {
        let sessionController = MockRadioRuntime.makeControllerIfRequested()
            ?? EstroboSessionController()
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

    var body: some Scene {
        WindowGroup("estrobo", id: "main") {
            PrototypeRootView(controller: controller)
                .background(MainWindowReopenRegistration(appDelegate: appDelegate))
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

private struct MainWindowReopenRegistration: View {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: PrototypeAppDelegate

    var body: some View {
        Color.clear.onAppear {
            // Retain the scene action even if its last window has been closed.
            appDelegate.createMainWindow = { openWindow(id: "main") }
        }
    }
}
