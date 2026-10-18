import Foundation

@MainActor
final class UpdateScheduleToken {
    private var cancellation: (() -> Void)?
    private(set) var isCancelled = false
    init(cancellation: @escaping () -> Void = {}) { self.cancellation = cancellation }
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancellation?()
        cancellation = nil
    }
}

@MainActor
protocol UpdateClock: AnyObject {
    var now: Date { get }
    func schedule(at date: Date, action: @escaping @MainActor () -> Void) -> UpdateScheduleToken
}

@MainActor
final class LiveUpdateClock: UpdateClock {
    var now: Date { Date() }
    func schedule(at date: Date, action: @escaping @MainActor () -> Void) -> UpdateScheduleToken {
        let delay = max(0, date.timeIntervalSince(now))
        let task = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
                try Task.checkCancellation()
                action()
            } catch { /* Cancelled schedules never initiate requests. */ }
        }
        return UpdateScheduleToken { task.cancel() }
    }
}
