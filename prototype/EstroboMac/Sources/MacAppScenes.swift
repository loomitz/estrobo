import SwiftUI

/// The productive scene graph, also hosted by the isolated native composition check.
@MainActor
struct MacAppScenes: Scene {
    @ObservedObject var controller: GodoxSessionController
    @ObservedObject var updater: UpdateCoordinator
    @ObservedObject var appearanceStore: AppAppearanceStore
    @ObservedObject var languageStore: AppLanguageStore
    let appDelegate: PrototypeAppDelegate
    let defaults: UserDefaults
    @AppStorage(MenuBarVisibilityPreferences.storageKey)
    private var isMenuBarIconVisible = MenuBarVisibilityPreferences.defaultIsVisible

    init(controller: GodoxSessionController, updater: UpdateCoordinator, appearanceStore: AppAppearanceStore,
         languageStore: AppLanguageStore, appDelegate: PrototypeAppDelegate, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.updater = updater
        self.appearanceStore = appearanceStore
        self.languageStore = languageStore
        self.appDelegate = appDelegate
        self.defaults = defaults
        _isMenuBarIconVisible = AppStorage(wrappedValue: MenuBarVisibilityPreferences.defaultIsVisible,
            MenuBarVisibilityPreferences.storageKey, store: defaults)
    }

    private var menuBarIconInsertionBinding: Binding<Bool> {
        Binding(get: { isMenuBarIconVisible }, set: { newValue in
            guard newValue != isMenuBarIconVisible else { return }
            isMenuBarIconVisible = newValue
        })
    }

    var body: some Scene {
        WindowGroup("estrobo", id: "main") {
            PrototypeRootView(controller: controller, updater: updater,
                              workspaceViewPreferences: WorkspaceViewPreferences(defaults: defaults))
                .background(MainWindowReopenRegistration(appDelegate: appDelegate))
                .environmentObject(appearanceStore)
                .environmentObject(languageStore)
                .environmentObject(updater)
                .environment(\.locale, languageStore.locale)
                .defaultAppStorage(defaults)
                .preferredColorScheme(appearanceStore.appearance.colorScheme)
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .commands { UpdateCommands(updater: updater, languageStore: languageStore) }

        Window(languageStore.language.localized("updates.title"), id: "updates") {
            UpdatesView()
                .environmentObject(updater)
                .environmentObject(appearanceStore)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .preferredColorScheme(appearanceStore.appearance.colorScheme)
        }
        .defaultSize(width: 680, height: 660)
        .windowResizability(.contentMinSize)

        MenuBarExtra(isInserted: menuBarIconInsertionBinding) {
            MenuBarControlView(controller: controller)
                .environmentObject(appearanceStore)
                .environmentObject(languageStore)
                .environmentObject(updater)
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
            appDelegate.createMainWindow = { openWindow(id: "main") }
        }
    }
}
