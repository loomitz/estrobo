import Foundation
import Combine

enum UpdateStage: String, Equatable, Sendable {
    case idle, checking, upToDate, available, downloading, downloaded, blocked, installing, error
}

enum UpdateInstallationBlocker: Equatable, Sendable {
    case session(String)
    case recovery(String)
    case transmitterConnected
    case connectionInProgress
}

struct UpdateSnapshot: Equatable, Sendable {
    let installed: InstalledUpdateVersion
    let stage: UpdateStage
    let offer: UpdateOffer?
    let progress: UpdateDownloadProgress?
    let lastSuccessfulCheck: Date?
    let nextAutomaticAttempt: Date?
    let automaticChecks: Bool
    let automaticDownloads: Bool
    let showsOptInInvitation: Bool
    let installationBlocker: UpdateInstallationBlocker?
    let failure: UpdateServiceFailure?
    let downloadedIdentity: UpdateOfferIdentity?
    let isCancellingInstallation: Bool
}

@MainActor
final class UpdateCoordinator: ObservableObject {
    @Published private(set) var snapshot: UpdateSnapshot
    private let installed: InstalledUpdateVersion
    private let service: any UpdateService
    private let session: GodoxSessionController
    private let preferences: UpdatePreferences
    private let clock: any UpdateClock
    private var schedule: UpdateScheduleToken?
    private var isAutomaticWork = false
    private var work: Task<Void, Never>?
    private var stage: UpdateStage = .idle
    private var offer: UpdateOffer?
    private var failure: UpdateServiceFailure?
    private var downloaded: DownloadedUpdate?
    private var progress: UpdateDownloadProgress?
    private var operationID: UUID?
    private var sessionObservation: AnyCancellable?
    private var installationAuthorization: UUID?
    private var operationSuspension: UUID?
    private var isCancellingInstallation = false
    private var completedInstallation = false

    var hasInstallationInProgress: Bool { stage == .installing && work != nil }

    init(installed: InstalledUpdateVersion, service: any UpdateService,
         session: GodoxSessionController, preferences: UpdatePreferences,
         clock: (any UpdateClock)? = nil) {
        self.installed = installed
        self.service = service
        self.session = session
        self.preferences = preferences
        self.clock = clock ?? LiveUpdateClock()
        snapshot = UpdateSnapshot(installed: installed, stage: .idle, offer: nil, progress: nil,
                                  lastSuccessfulCheck: preferences.state.lastSuccessfulCheck,
                                  nextAutomaticAttempt: preferences.state.nextAutomaticAttempt,
                                  automaticChecks: preferences.state.automaticChecks,
                                  automaticDownloads: preferences.state.automaticDownloads,
                                  showsOptInInvitation: false, installationBlocker: nil, failure: nil,
                                  downloadedIdentity: nil, isCancellingInstallation: false)
        if session.hasStoredWorkspaceConfiguration {
            preferences.state.postOnboardingLaunches = min(2, preferences.state.postOnboardingLaunches + 1)
        }
        sessionObservation = session.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.sessionDidChange() }
        }
        publish()
        scheduleAutomaticCheck()
    }

    func checkManually() {
        check(automatically: false)
    }

    func enableAutomaticUpdates() {
        preferences.state.automaticChecks = true
        preferences.state.automaticDownloads = true
        preferences.state.invitationDismissed = true
        publish()
        scheduleAutomaticCheck()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        preferences.state.automaticChecks = enabled
        if !enabled {
            preferences.state.automaticDownloads = false
            schedule?.cancel()
            if isAutomaticWork { work?.cancel(); service.cancel() }
        }
        publish()
        scheduleAutomaticCheck()
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        preferences.state.automaticDownloads = enabled && preferences.state.automaticChecks
        if !preferences.state.automaticDownloads, isAutomaticWork, stage == .downloading {
            cancelDownload()
        }
        publish()
    }

    func download() { download(automatically: false) }

    /// The caller captures this exact identity when presenting confirmation.
    /// A later catalog change cannot reuse an earlier dialog's approval.
    func confirmInstall(expectedIdentity: UpdateOfferIdentity) {
        guard work == nil, !completedInstallation, let offer, let downloaded else { return }
        guard expectedIdentity == offer.identity, downloaded.offerIdentity == expectedIdentity else {
            failure = UpdateServiceFailure(.invalidOffer)
            stage = .error
            publish()
            return
        }
        guard installationBlocker == nil else {
            stage = .blocked
            publish()
            return
        }
        let id = UUID()
        installationAuthorization = id
        operationID = id
        isCancellingInstallation = false
        failure = nil
        stage = .installing
        schedule?.cancel()
        publish()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.install(downloaded, offer: offer) { [weak self] identity in
                    guard let self else { return false }
                    guard self.installationAuthorization == id, self.work?.isCancelled != true,
                          self.offer?.identity == expectedIdentity, identity == expectedIdentity else {
                        self.failure = UpdateServiceFailure(.invalidOffer)
                        return false
                    }
                    guard self.installationBlocker == nil else {
                        self.failure = UpdateServiceFailure(.unsafeSession)
                        return false
                    }
                    if self.operationSuspension == nil {
                        self.operationSuspension = self.session.suspendOperations()
                    }
                    return true
                }
                try Task.checkCancellation()
                completedInstallation = true
                // Successful replacement terminates this process. Keep commands
                // suspended until then; no second install can reuse approval.
                stage = .installing
            } catch {
                let problem = failure ?? (error as? UpdateServiceFailure)
                handleFailure(problem ?? error)
                if let operationSuspension { session.resumeOperations(operationSuspension) }
                operationSuspension = nil
                if installationBlocker != nil, downloaded.offerIdentity == self.downloaded?.offerIdentity {
                    stage = .blocked
                }
            }
            installationAuthorization = nil
            operationID = nil
            isCancellingInstallation = false
            work = nil
            publish()
            if !completedInstallation { scheduleAutomaticCheck() }
        }
    }

    func cancelInstall() {
        guard hasInstallationInProgress, !isCancellingInstallation else { return }
        installationAuthorization = nil
        isCancellingInstallation = true
        work?.cancel()
        service.cancel()
        // Service completion, not cancellation intent, releases the suspension.
        publish()
    }

    func postpone() {
        if hasInstallationInProgress { cancelInstall(); return }
        guard work == nil, !completedInstallation else { return }
        installationAuthorization = nil
        failure = nil
        stage = restingStage
        publish()
    }

    /// Ordinary quit is never installation approval. AppKit's owner waits for
    /// hasInstallationInProgress to become false before asking to terminate again.
    func ordinaryQuitRequested() { cancelInstall() }

    private func sessionDidChange() {
        if installationAuthorization != nil, installationBlocker != nil { cancelInstall() }
        if stage == .blocked, work == nil, installationBlocker == nil {
            stage = restingStage
            if failure?.kind == .unsafeSession { failure = nil }
        }
        publish()
    }

    func cancelDownload() {
        guard stage == .downloading, work != nil else { return }
        work?.cancel()
        service.cancel()
    }

    private func download(automatically: Bool) {
        guard work == nil, !completedInstallation, let offer else { return }
        isAutomaticWork = automatically
        let id = UUID()
        operationID = id
        stage = .downloading
        progress = UpdateDownloadProgress(completedBytes: 0, totalBytes: offer.identity.contentLength)
        downloaded = nil
        failure = nil
        schedule?.cancel()
        publish()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.download(offer) { [weak self] value in
                    guard let self, self.operationID == id, self.work?.isCancelled != true else { return }
                    self.progress = value
                    self.publish()
                }
                try Task.checkCancellation()
                guard result.offerIdentity == offer.identity,
                      result.length == offer.identity.contentLength, result.localFile.isFileURL,
                      result.sha256.count == 64, result.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                    throw UpdateServiceFailure(.archive)
                }
                downloaded = result
                stage = .downloaded
            } catch {
                handleFailure(error)
            }
            work = nil
            operationID = nil
            progress = nil
            isAutomaticWork = false
            publish()
            scheduleAutomaticCheck()
        }
    }

    func dismissOptInInvitation() {
        preferences.state.invitationDismissed = true
        publish()
    }

    private var installationBlocker: UpdateInstallationBlocker? {
        if let reason = session.recoveryBlockReason { return .recovery(reason) }
        if let reason = session.terminationBlockReason { return .session(reason) }
        if session.phase.isBusy || session.pendingSavedRadioConnectionID != nil { return .connectionInProgress }
        if session.connectedDeviceName != nil || session.phase == .ready { return .transmitterConnected }
        return nil
    }

    private func check(automatically: Bool) {
        guard work == nil, !completedInstallation else { return }
        isAutomaticWork = automatically
        schedule?.cancel()
        stage = .checking
        failure = nil
        publish()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let offers = try await service.check(for: installed)
                try Task.checkCancellation()
                offer = try selectOffer(from: offers)
                if downloaded?.offerIdentity != offer?.identity { downloaded = nil }
                stage = offer == nil ? .upToDate : restingStage
                preferences.state.lastSuccessfulCheck = clock.now
                preferences.state.nextAutomaticAttempt = max(
                    preferences.state.nextAutomaticAttempt ?? .distantPast,
                    clock.now.addingTimeInterval(86_400))
            } catch {
                handleFailure(error)
            }
            work = nil
            isAutomaticWork = false
            publish()
            scheduleAutomaticCheck()
            if automatically, preferences.state.automaticChecks, preferences.state.automaticDownloads,
               failure == nil, !Task.isCancelled, offer != nil, downloaded == nil {
                download(automatically: true)
            }
        }
    }

    private var restingStage: UpdateStage {
        downloaded != nil ? .downloaded : (offer == nil ? .idle : .available)
    }

    private func handleFailure(_ error: Error) {
        if Task.isCancelled || (error as? UpdateServiceFailure)?.kind == .cancelled {
            failure = nil
            stage = restingStage
            return
        }
        let problem = error as? UpdateServiceFailure ?? UpdateServiceFailure(.network)
        failure = problem
        stage = .error
        preferences.state.nextAutomaticAttempt = max(
            preferences.state.nextAutomaticAttempt ?? .distantPast,
            max(clock.now.addingTimeInterval(86_400), problem.retryAfter ?? .distantPast))
    }

    private func scheduleAutomaticCheck() {
        schedule?.cancel()
        guard preferences.state.automaticChecks, work == nil, !completedInstallation else { return }
        schedule = clock.schedule(at: preferences.state.nextAutomaticAttempt ?? clock.now) { [weak self] in
            self?.check(automatically: true)
        }
    }

    private func selectOffer(from candidates: [UpdateOffer]) throws -> UpdateOffer? {
        var builds: [UInt64: UpdateOffer] = [:]
        for candidate in candidates {
            let identity = candidate.identity
            let url = identity.archiveURL
            let path = url.pathComponents
            let version = candidate.marketingVersion.split(separator: ".", omittingEmptySubsequences: false)
            guard identity.build > 0, identity.contentLength > 0,
                  Data(base64Encoded: identity.edDSASignature)?.count == 64,
                  version.count == 3, version.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
                  url.scheme == "https", url.host == "github.com", url.port == nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  path.count == 7, Array(path[1...4]) == ["loomitz", "estrobo", "releases", "download"],
                  path[5] != "latest", url.pathExtension.lowercased() == "dmg",
                  builds[identity.build] == nil || builds[identity.build] == candidate else {
                throw UpdateServiceFailure(.invalidOffer)
            }
            builds[identity.build] = candidate
        }
        return candidates.filter {
            $0.identity.build > installed.build && $0.isCompatibleWithCurrentSystem &&
            (installed.channel == .beta || $0.channel == .stable)
        }.max { $0.identity.build < $1.identity.build }
    }

    private func publish() {
        snapshot = UpdateSnapshot(installed: installed,
                                  stage: stage == .downloaded && installationBlocker != nil ? .blocked : stage,
                                  offer: offer, progress: progress,
                                  lastSuccessfulCheck: preferences.state.lastSuccessfulCheck,
                                  nextAutomaticAttempt: preferences.state.nextAutomaticAttempt,
                                  automaticChecks: preferences.state.automaticChecks,
                                  automaticDownloads: preferences.state.automaticDownloads,
                                  showsOptInInvitation: preferences.state.postOnboardingLaunches >= 2 &&
                                    !preferences.state.invitationDismissed && !preferences.state.automaticChecks &&
                                    session.hasStoredWorkspaceConfiguration && installationBlocker == nil,
                                  installationBlocker: installationBlocker, failure: failure,
                                  downloadedIdentity: downloaded?.offerIdentity,
                                  isCancellingInstallation: isCancellingInstallation)
    }
}
