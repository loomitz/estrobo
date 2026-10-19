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
struct EstroboApp: App {
    @NSApplicationDelegateAdaptor(PrototypeAppDelegate.self) private var appDelegate
    @StateObject private var controller: GodoxSessionController
    @StateObject private var appearanceStore: AppAppearanceStore
    @StateObject private var languageStore: AppLanguageStore
    @StateObject private var updater: UpdateCoordinator

    init() {
        let sessionController = MockRadioRuntime.makeControllerIfRequested()
            ?? Self.makeLiveController()
        _controller = StateObject(wrappedValue: sessionController)
        _appearanceStore = StateObject(wrappedValue: AppAppearanceStore())
        _languageStore = StateObject(wrappedValue: AppLanguageStore())
        guard let installed = InstalledUpdateVersion(bundle: .main) else {
            preconditionFailure("The macOS bundle must declare a numeric build, version and explicit update channel")
        }
        let updates = MacUpdateRuntime(installed: installed, session: sessionController,
            appDelegate: _appDelegate.wrappedValue, preferences: UpdatePreferences(defaults: .standard))
        _updater = StateObject(wrappedValue: updates.coordinator)
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
        MacAppScenes(controller: controller, updater: updater, appearanceStore: appearanceStore,
                     languageStore: languageStore, appDelegate: appDelegate)
    }
}
