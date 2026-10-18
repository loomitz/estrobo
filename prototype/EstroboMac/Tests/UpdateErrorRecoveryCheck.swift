import AppKit
import Sparkle

/// Synthetic public Sparkle callbacks observed through UpdateService.check.
/// This proves classification, not real translocation or system authorization.
@main @MainActor
enum UpdateErrorRecoveryCheck {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        application.run()
    }

    static func run() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let feed = URL(string: CommandLine.arguments[2])!
        let identifier = Bundle.main.bundleIdentifier!
        defer { UserDefaults.standard.removePersistentDomain(forName: identifier) }
        let lifecycle = UpdateInstallationLifecycle(blockReason: { nil }, restoreWindow: {})
        let service = try SparkleUpdateService.testing(bundle: .main, feedURL: feed,
            cacheDirectory: root.appendingPathComponent("cache"), lifecycle: lifecycle)
        let cases: [(String, NSError, UpdateServiceFailure.Kind, Bool)] = [
            ("disk-image", sparkle(.runningFromDiskImageError), .readOnlyLocation, false),
            ("translocated", sparkle(.runningTranslocated), .readOnlyLocation, false),
            ("copy-failure", sparkle(.fileCopyFailure), .installation, false),
            ("authentication-failure", sparkle(.authenticationFailure), .installation, false),
            ("write-permission", sparkle(.installationWriteNoPermissionError), .readOnlyLocation, false),
            ("authorization-cancelled", sparkle(.installationCanceledError), .authorizationCancelled, false),
            ("authorize-later", sparkle(.installationAuthorizeLaterError), .authorizationCancelled, false),
            ("signature", sparkle(.signatureError), .signature, false),
            ("validation", sparkle(.validationError), .signature, false),
            ("underlying-signature", sparkle(.fileCopyFailure, underlying: sparkle(.signatureError)), .signature, false),
            ("underlying-cancel", sparkle(.authenticationFailure, underlying: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)), .authorizationCancelled, false),
            ("cancel-precedence", sparkle(.fileCopyFailure), .cancelled, true),
            ("network", sparkle(.downloadError), .network, false),
        ]
        var failed = false
        for (name, error, expected, cancel) in cases {
            let started = root.appendingPathComponent("started")
            let release = root.appendingPathComponent("release")
            try? FileManager.default.removeItem(at: started)
            try? FileManager.default.removeItem(at: release)
            let task = Task { @MainActor () -> UpdateServiceFailure.Kind? in
                do { _ = try await service.check(for: InstalledUpdateVersion(bundle: .main)!); return nil }
                catch { return (error as? UpdateServiceFailure)?.kind }
            }
            let deadline = Date().addingTimeInterval(10)
            while !FileManager.default.fileExists(atPath: started.path), Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard FileManager.default.fileExists(atPath: started.path) else { throw NSError(domain: "FixtureFeedDidNotStart", code: 1) }
            var acknowledged = false
            service.showUpdaterError(error) { acknowledged = true }
            if cancel { service.cancel() }
            try Data().write(to: release)
            let actual = await task.value
            let passed = acknowledged && actual == expected
            failed = failed || !passed
            print("\(passed ? "PASS" : "FAIL") \(name): expected=\(expected.rawValue) actual=\(actual?.rawValue ?? "success") acknowledged=\(acknowledged)")
        }
        if failed { throw NSError(domain: "PublicCallbackRecoveryMismatch", code: 1) }
        print("13 public callback/service recovery cases verified; synthetic errors only")
    }

    static func sparkle(_ code: SUError, underlying: Error? = nil) -> NSError {
        NSError(domain: SUSparkleErrorDomain, code: Int(code.rawValue),
            userInfo: underlying.map { [NSUnderlyingErrorKey: $0] } ?? [:])
    }
}
