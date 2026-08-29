import SwiftUI
import EstroboCore

/// Temporary app-owned seam until the shared controller exposes foreground
/// lifecycle hooks. Keeping the closures here prevents views from inventing
/// transport behavior. The integration state is visible in Settings.
@MainActor
struct ScenePhaseBridge {
    enum Integration: Equatable {
        case controllerHooksRequired
        case connected
    }

    let integration: Integration
    private let suspend: () -> Void
    private let resume: () -> Void
    private(set) var isSuspended = false

    init(
        integration: Integration,
        suspend: @escaping () -> Void,
        resume: @escaping () -> Void
    ) {
        self.integration = integration
        self.suspend = suspend
        self.resume = resume
    }

    static func pendingControllerHooks() -> ScenePhaseBridge {
        ScenePhaseBridge(
            integration: .controllerHooksRequired,
            suspend: {},
            resume: {}
        )
    }

    static func controller(_ controller: GodoxSessionController) -> ScenePhaseBridge {
        ScenePhaseBridge(
            integration: .connected,
            suspend: { [weak controller] in
                controller?.suspendForInactiveScene()
            },
            resume: { [weak controller] in
                controller?.resumeActiveScene()
            }
        )
    }

    mutating func handle(_ phase: ScenePhase) {
        switch phase {
        case .active where isSuspended:
            isSuspended = false
            resume()
        case .inactive where !isSuspended:
            isSuspended = true
            suspend()
        case .background where !isSuspended:
            isSuspended = true
            suspend()
        default:
            break
        }
    }
}
