import Foundation

/// The app's composition boundary. Product and native checks use the same
/// coordinator/service/lifecycle; only the existing service port is replaceable.
@MainActor
final class MacUpdateRuntime {
    let coordinator: UpdateCoordinator
    let lifecycle: UpdateInstallationLifecycle

    init(installed: InstalledUpdateVersion, session: GodoxSessionController,
         appDelegate: PrototypeAppDelegate, preferences: UpdatePreferences,
         clock: (any UpdateClock)? = nil,
         serviceFactory: @MainActor (UpdateInstallationLifecycle) -> any UpdateService = {
             SparkleUpdateService.makeProduction(lifecycle: $0)
         }) {
        appDelegate.controller = session
        lifecycle = appDelegate.updateLifecycle
        coordinator = UpdateCoordinator(installed: installed, service: serviceFactory(lifecycle),
            session: session, preferences: preferences, clock: clock)
        lifecycle.ordinaryQuitRequested = { [weak coordinator] in coordinator?.ordinaryQuitRequested() }
    }
}
