import AppKit
import Sparkle

@MainActor final class Probe: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, SPUUserDriver {
    var updater: SPUUpdater!
    var errors: [NSError] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do { try updater.start(); updater.checkForUpdates() }
        catch { finish(error) }
    }
    func finish(_ error: Error?) {
        func errorObject(_ error: NSError) -> [String: Any] {
            var result: [String: Any] = ["domain": error.domain, "code": error.code, "description": error.localizedDescription]
            if let nested = error.userInfo[NSUnderlyingErrorKey] as? NSError { result["underlying"] = errorObject(nested) }
            return result
        }
        if let error { errors.append(error as NSError) }
        let record: [String:Any] = ["feed": Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") ?? "", "atsDictionaryPresent": Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") != nil, "errors": errors.map(errorObject)]
        let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        fflush(stdout)
        DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) { finish(error) }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse)->Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)) }
    func showUserInitiatedUpdateCheck(cancellation: @escaping ()->Void) {}
    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice)->Void) { reply(.skip) }
    func showUpdateReleaseNotes(with data: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping ()->Void) { errors.append(error as NSError); acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping ()->Void) { errors.append(error as NSError); acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping ()->Void) { cancellation() }
    func showDownloadDidReceiveExpectedContentLength(_ length: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice)->Void) { reply(.skip) }
    func showInstallingUpdate(withApplicationTerminated terminated: Bool, retryTerminatingApplication: @escaping ()->Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping ()->Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem)->Bool { false }
}
@main @MainActor enum Host {
    static func main() { let app=NSApplication.shared; let probe=Probe(); app.delegate=probe; app.setActivationPolicy(.prohibited); app.run(); withExtendedLifetime(probe) {} }
}
