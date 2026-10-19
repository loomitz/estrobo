import AppKit
import Combine

/// The product and real-adapter fixture forward the same AppKit close protocol.
/// No Sparkle continuation or installer type escapes into the app delegate/UI.
@MainActor
final class UpdateInstallationLifecycle: ObservableObject {
    enum State: String { case idle, preflighting, preparing, ready, committing }
    @Published private(set) var state: State = .idle
    var ordinaryQuitRequested: (() -> Void)?
    private let blockReason: () -> String?
    private let restoreWindow: () -> Void
    private var preflightReply: CheckedContinuation<Bool, Never>?
    private var validateCommit: (() -> Bool)?
    private var commit: (() -> Void)?
    private var cancelAttempt: (() -> Void)?
    private var ordinaryQuitPending = false
    private var commitRequested = false
    private enum TerminationIntent { case preflight, commit, ordinaryRetry }
    private var internalTerminationIntent: TerminationIntent?
    private var terminationRequestID = UUID()

    #if ESTROBO_UPDATER_TESTING
    var pauseBeforeFinalCommit = false
    var pauseQueuedTermination = false
    private var heldTerminationRequest: (@MainActor @Sendable () -> Void)?
    #endif

    init(blockReason: @escaping () -> String?, restoreWindow: @escaping () -> Void) {
        self.blockReason = blockReason
        self.restoreWindow = restoreWindow
    }

    var isCommitting: Bool { state == .committing }

    func preflight(cancel: @escaping () -> Void) async -> Bool {
        guard state == .idle else { return false }
        cancelAttempt = cancel
        state = .preflighting
        return await withCheckedContinuation { reply in
            preflightReply = reply
            requestTermination(.preflight)
        }
    }

    func prepared(validate: @escaping () -> Bool, commit: @escaping () -> Void) {
        guard state == .preparing else { cancelAttempt?(); return }
        validateCommit = validate
        self.commit = commit
        state = .ready
        #if ESTROBO_UPDATER_TESTING
        if pauseBeforeFinalCommit { return }
        #endif
        continuePreparedInstallation()
    }

    func continuePreparedInstallation() {
        guard state == .ready, commit != nil else { return }
        commitRequested = true
        requestTermination(.commit)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if blockReason() != nil {
            let reply = preflightReply
            preflightReply = nil
            reply?.resume(returning: false)
            cancelAttempt?()
            restoreAfterRejectedQuit()
            return .terminateCancel
        }
        if state == .preflighting, internalTerminationIntent == .preflight {
            state = .preparing
            let reply = preflightReply
            preflightReply = nil
            reply?.resume(returning: true)
            // A real AppKit gate was consulted, but preparation keeps normal input.
            return .terminateCancel
        }
        if commitRequested, state == .ready, internalTerminationIntent == .commit {
            commitRequested = false
            guard validateCommit?() == true, let commit else {
                cancelAttempt?()
                restoreAfterRejectedQuit()
                return .terminateCancel
            }
            self.commit = nil
            state = .committing
            DispatchQueue.main.async { commit() }
            return .terminateLater
        }
        if state == .committing { return .terminateLater }
        if state != .idle {
            terminationRequestID = UUID()
            let preflight = preflightReply
            preflightReply = nil
            preflight?.resume(returning: false)
            ordinaryQuitPending = true
            ordinaryQuitRequested?()
            cancelAttempt?()
            return .terminateCancel
        }
        return .terminateNow
    }

    func installerWillTerminateApplication() {
        guard state == .committing else { return }
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    /// Called after the real public cycle has finished cancelling, never on intent.
    func attemptDidFinish() {
        let wasCommitting = state == .committing
        let preflight = preflightReply
        preflightReply = nil
        preflight?.resume(returning: false)
        validateCommit = nil
        commit = nil
        cancelAttempt = nil
        commitRequested = false
        terminationRequestID = UUID()
        #if ESTROBO_UPDATER_TESTING
        heldTerminationRequest = nil
        #endif
        state = .idle
        if wasCommitting { NSApp.reply(toApplicationShouldTerminate: false) }
        if ordinaryQuitPending {
            ordinaryQuitPending = false
            requestTermination(.ordinaryRetry)
        }
    }

    private func restoreAfterRejectedQuit() {
        RunLoop.main.perform { [restoreWindow] in restoreWindow() }
    }

    private func requestTermination(_ intent: TerminationIntent) {
        // A queued AppKit run-loop action avoids nested termination from Sparkle's
        // main dispatch callbacks, which would prevent its next callbacks running.
        let id = UUID()
        terminationRequestID = id
        let request: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.terminationRequestID == id else { return }
            self.internalTerminationIntent = intent
            defer { self.internalTerminationIntent = nil }
            NSApp.terminate(nil)
        }
        #if ESTROBO_UPDATER_TESTING
        if pauseQueuedTermination, intent != .ordinaryRetry { heldTerminationRequest = request; return }
        #endif
        RunLoop.main.perform(inModes: [.default, .eventTracking, .modalPanel]) {
            MainActor.assumeIsolated { request() }
        }
    }
}
