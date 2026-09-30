import SwiftUI

@main
@MainActor
struct EstroboIOSApp: App {
    @StateObject private var coordinator: AppSessionCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _coordinator = StateObject(
            wrappedValue: AppSessionCoordinator(
                restoreRememberedLiveRuntime: true
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            EstroboRootView(coordinator: coordinator)
                .environment(\.locale, coordinator.locale)
                .modifier(
                    UITestSizeClassModifier(
                        override: coordinator.uiTestConfiguration.layoutOverride
                    )
                )
                .preferredColorScheme(coordinator.appearance.colorScheme)
                .tint(EstroboTheme.interactiveAccent)
                .alert(item: $coordinator.launchConnectionOffer) { offer in
                    Alert(
                        title: Text(coordinator.text("launch.connection.title")),
                        message: Text(
                            coordinator.text(
                                "launch.connection.message",
                                offer.name
                            )
                        ),
                        primaryButton: .default(
                            Text(coordinator.text("launch.connection.connect")),
                            action: {
                                // SwiftUI may clear the alert binding before
                                // invoking this action. Capture the presented
                                // radio so the connection cannot be lost with
                                // the dismissal transaction.
                                coordinator.connectLaunchOffer(offer)
                            }
                        ),
                        secondaryButton: .cancel(
                            Text(coordinator.text("launch.connection.not-now")),
                            action: coordinator.dismissLaunchConnectionOffer
                        )
                    )
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    coordinator.handleScenePhase(phase)
                }
        }
        .commands {
            CommandMenu(coordinator.text("commands.navigation")) {
                Button(coordinator.text("tab.groups")) {
                    coordinator.navigate(to: .groups)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button(coordinator.text("tab.presets")) {
                    coordinator.navigate(to: .presets)
                }
                .keyboardShortcut("2", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button(coordinator.text("tab.settings")) {
                    coordinator.navigate(to: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

private struct UITestSizeClassModifier: ViewModifier {
    let override: UITestConfiguration.LayoutOverride?

    @ViewBuilder
    func body(content: Content) -> some View {
        switch override {
        case .compact:
            content.environment(\.horizontalSizeClass, .compact)
        case .regular:
            content.environment(\.horizontalSizeClass, .regular)
        case nil:
            content
        }
    }
}
