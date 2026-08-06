import Foundation

enum SessionDeadlineKind: Hashable {
    case scan
    case connectionSetup
    case authentication
    case disconnectRecovery
    case valueSynchronizationSettle
    case automaticApply
    case heartbeat
    case testDelivery

    var duration: Duration {
        switch self {
        case .scan:
            .seconds(10)
        case .connectionSetup:
            .seconds(12)
        case .authentication:
            .seconds(10)
        case .disconnectRecovery:
            .seconds(3)
        case .valueSynchronizationSettle:
            .milliseconds(500)
        case .automaticApply:
            .milliseconds(700)
        case .heartbeat:
            .seconds(5)
        case .testDelivery:
            .seconds(3)
        }
    }
}

@MainActor
final class SessionDeadlineToken {
    private var cancellation: (() -> Void)?
    private(set) var isCancelled = false

    func installCancellation(_ cancellation: @escaping () -> Void) {
        guard !isCancelled else {
            cancellation()
            return
        }
        self.cancellation = cancellation
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        let action = cancellation
        cancellation = nil
        action?()
    }
}

@MainActor
protocol SessionDeadlineScheduling: AnyObject {
    @discardableResult
    func schedule(
        _ kind: SessionDeadlineKind,
        action: @escaping @MainActor () -> Void
    ) -> SessionDeadlineToken
}

@MainActor
final class LiveSessionDeadlineScheduler: SessionDeadlineScheduling {
    func schedule(
        _ kind: SessionDeadlineKind,
        action: @escaping @MainActor () -> Void
    ) -> SessionDeadlineToken {
        let token = SessionDeadlineToken()
        let task = Task { @MainActor [weak token] in
            do {
                try await Task.sleep(for: kind.duration)
            } catch {
                return
            }
            guard let token, !token.isCancelled else { return }
            action()
        }
        token.installCancellation { task.cancel() }
        return token
    }
}
