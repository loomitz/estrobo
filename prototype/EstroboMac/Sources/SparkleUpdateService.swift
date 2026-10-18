import AppKit
import CryptoKit
import Sparkle

@MainActor
private final class UnavailableUpdateService: UpdateService {
    func check(for installed: InstalledUpdateVersion) async throws -> [UpdateOffer] { throw UpdateServiceFailure(.configuration) }
    func download(_ offer: UpdateOffer, progress: @escaping @MainActor (UpdateDownloadProgress) -> Void) async throws -> DownloadedUpdate { throw UpdateServiceFailure(.configuration) }
    func install(_ download: DownloadedUpdate, offer: UpdateOffer, precommit: @escaping @MainActor (UpdateOfferIdentity) -> Bool) async throws { throw UpdateServiceFailure(.configuration) }
    func cancel() {}
}

/// Real app-local adapter: Sparkle owns signed-feed/EdDSA/installer verification;
/// Estrobo owns scheduling, durable full archives and its own constrained HTTP.
@MainActor
final class SparkleUpdateService: NSObject, UpdateService, SPUUpdaterDelegate, SPUUserDriver {
    private enum Operation { case check, download, install }
    private let installed: InstalledUpdateVersion
    private let feedURL: URL
    private let policy: UpdateTransportPolicy
    private let cacheDirectory: URL
    private let lifecycle: UpdateInstallationLifecycle
    private let http: UpdateHTTPClient
    private let archiveCache: URLCache
    private let event: (String) -> Void
    private var updater: SPUUpdater!
    private var operation: Operation?
    private var cancellationRequested = false
    private var cycleReply: CheckedContinuation<Void, Error>?
    private var cycleFailure: UpdateServiceFailure?
    private var feedValidated = false
    private var selectedItem: SUAppcastItem?
    private var selectedOffer: UpdateOffer?
    private var knownOffers: [UpdateOfferIdentity: UpdateOffer] = [:]
    private var approvedOffer: UpdateOffer?
    private var precommit: ((UpdateOfferIdentity) -> Bool)?
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var checkCancellation: (() -> Void)?
    private var downloadCancellation: (() -> Void)?

    static func makeProduction(lifecycle: UpdateInstallationLifecycle, bundle: Bundle = .main) -> any UpdateService {
        guard bundle.bundleIdentifier == "mx.loo.estrobo",
              let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return UnavailableUpdateService()
        }
        return (try? SparkleUpdateService(bundle: bundle, feedURL: UpdateTransportPolicy.feedURL,
            cacheDirectory: directory.appendingPathComponent("EstroboAssistedUpdates", isDirectory: true),
            policy: .production, lifecycle: lifecycle, event: { _ in })) ?? UnavailableUpdateService()
    }

    #if ESTROBO_UPDATER_TESTING
    static func testing(bundle: Bundle, feedURL: URL, cacheDirectory: URL,
                        lifecycle: UpdateInstallationLifecycle, event: @escaping (String) -> Void = { _ in }) throws -> SparkleUpdateService {
        guard ["127.0.0.1", "localhost"].contains(feedURL.host ?? ""), feedURL.port != nil else { throw UpdateServiceFailure(.configuration) }
        return try SparkleUpdateService(bundle: bundle, feedURL: feedURL, cacheDirectory: cacheDirectory,
            policy: .fixture, lifecycle: lifecycle, event: event)
    }
    #endif

    private init(bundle: Bundle, feedURL: URL, cacheDirectory: URL, policy: UpdateTransportPolicy,
                 lifecycle: UpdateInstallationLifecycle, event: @escaping (String) -> Void) throws {
        guard let installed = InstalledUpdateVersion(bundle: bundle),
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let keyBytes = Data(base64Encoded: key), keyBytes.count == 32, keyBytes.base64EncodedString() == key,
              bundle.object(forInfoDictionaryKey: "SUEnableDownloaderService") as? Bool != true,
              bundle.object(forInfoDictionaryKey: "NSAppTransportSecurity") == nil ||
                (bundle.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any])?.isEmpty == true,
              bundle.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool == true,
              bundle.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true,
              (bundle.object(forInfoDictionaryKey: "SUSignedFeedFailureExpirationInterval") as? NSNumber)?.doubleValue == 0,
              policy.permits(feedURL, purpose: .feed, initial: true),
              Bundle(for: SPUUpdater.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "2.10.0" else {
            throw UpdateServiceFailure(.configuration)
        }
        self.installed = installed; self.feedURL = feedURL; self.cacheDirectory = cacheDirectory
        self.policy = policy; self.lifecycle = lifecycle; self.event = event
        http = UpdateHTTPClient(policy: policy)
        // One archive <=64 MiB; capacity is a virtual cache admission envelope,
        // not a 2 GiB allocation. No unrelated app traffic uses this private cache.
        archiveCache = URLCache(memoryCapacity: 2 * 1024 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        super.init()
        URLCache.shared = archiveCache
        updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: self, delegate: self)
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        updater.sendsSystemProfile = false
        updater.httpHeaders = ["Cache-Control": "no-cache", "Pragma": "no-cache"]
        try updater.start()
    }

    func check(for installed: InstalledUpdateVersion) async throws -> [UpdateOffer] {
        guard self.installed == installed else { throw UpdateServiceFailure(.configuration) }
        try begin(.check)
        defer { end() }
        try await http.preflight(feedURL)
        try checkNotCancelled()
        try await runCycle()
        knownOffers = selectedOffer.map { [$0.identity: $0] } ?? [:]
        return selectedOffer.map { [$0] } ?? []
    }

    func download(_ offer: UpdateOffer, progress: @escaping @MainActor (UpdateDownloadProgress) -> Void) async throws -> DownloadedUpdate {
        guard knownOffers[offer.identity] == offer else { throw UpdateServiceFailure(.invalidOffer) }
        try begin(.download)
        defer { end() }
        let descriptorURL = cacheDirectory.appendingPathComponent("download.json")
        let stored = await readDescriptor(descriptorURL)
        let previous: DownloadedUpdate?
        if let stored, (try? await validatedBytes(stored)) != nil { previous = stored } else { previous = nil }
        let previousFiles = Set(previous.map { [$0.localFile] } ?? [])
        try await pruneCache(keeping: previousFiles)
        if let cached = previous, cached.offerIdentity == offer.identity {
            try checkNotCancelled()
            progress(UpdateDownloadProgress(completedBytes: cached.length, totalBytes: cached.length))
            return cached
        }
        let file = cacheDirectory.appendingPathComponent("archive-\(UUID()).dmg")
        var descriptorCommitted = false
        do {
            let result = try await http.download(offer.identity, to: file, progress: progress)
            try checkNotCancelled()
            try await Task.detached {
                try JSONEncoder().encode(result).write(to: descriptorURL, options: .atomic)
                // The containing directory is already private. A metadata-mode
                // failure after atomic replacement must not roll back/delete the
                // newly referenced archive while its valid descriptor is current.
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: descriptorURL.path)
            }.value
            descriptorCommitted = true
            try await pruneCache(keeping: [file])
            return result
        } catch {
            // Preserve the old valid descriptor until atomic replacement succeeds.
            // Only strictly named, regular, app-owned files can be removed.
            try? await pruneCache(keeping: descriptorCommitted ? [file] : previousFiles)
            throw error
        }
    }

    func install(_ download: DownloadedUpdate, offer: UpdateOffer,
                 precommit: @escaping @MainActor (UpdateOfferIdentity) -> Bool) async throws {
        guard download.offerIdentity == offer.identity, knownOffers[offer.identity] == offer else { throw UpdateServiceFailure(.invalidOffer) }
        try begin(.install)
        approvedOffer = offer
        self.precommit = precommit
        var committed = false
        defer { if !committed { lifecycle.attemptDidFinish() }; end() }
        let bytes = try await validatedBytes(download)
        try checkNotCancelled()
        guard await lifecycle.preflight(cancel: { [weak self] in self?.cancel() }) else { throw UpdateServiceFailure(.unsafeSession) }
        try checkNotCancelled()
        try await http.preflight(feedURL)
        try checkNotCancelled()
        archiveCache.removeAllCachedResponses()
        let response = HTTPURLResponse(url: offer.identity.archiveURL, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(bytes.count)", "Content-Type": "application/octet-stream",
                          "Cache-Control": "private, max-age=3600", "Content-Disposition": "attachment; filename=update.dmg"])!
        archiveCache.storeCachedResponse(CachedURLResponse(response: response, data: bytes), for: URLRequest(url: offer.identity.archiveURL))
        guard archiveCache.cachedResponse(for: URLRequest(url: offer.identity.archiveURL)) != nil else { throw UpdateServiceFailure(.archive) }
        try await runCycle()
        committed = lifecycle.isCommitting
    }

    func cancel() {
        guard operation != nil, !lifecycle.isCommitting else { return }
        cancellationRequested = true
        http.cancel()
        if let readyReply {
            self.readyReply = nil
            readyReply(.skip)
        } else if let downloadCancellation { downloadCancellation() }
        else { checkCancellation?() }
        // Extraction may currently expose no cancellation block. The eventual
        // ready callback consumes .skip, and only finished-cycle resolves install.
    }

    private func begin(_ operation: Operation) throws {
        guard self.operation == nil, !updater.sessionInProgress else { throw UpdateServiceFailure(.configuration) }
        self.operation = operation
        cancellationRequested = false
        cycleFailure = nil
        feedValidated = false
        selectedItem = nil
        selectedOffer = nil
    }
    private func end() {
        operation = nil; approvedOffer = nil; precommit = nil; readyReply = nil
        checkCancellation = nil; downloadCancellation = nil
        archiveCache.removeAllCachedResponses()
    }
    private func checkNotCancelled() throws {
        if cancellationRequested || Task.isCancelled { throw UpdateServiceFailure(.cancelled) }
    }
    private func runCycle() async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { reply in
                cycleReply = reply
                updater.checkForUpdates()
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
    }

    private func validatedBytes(_ download: DownloadedUpdate) async throws -> Data {
        let directory = cacheDirectory.standardizedFileURL.path + "/"
        guard download.localFile.isFileURL, download.localFile.standardizedFileURL.path.hasPrefix(directory),
              download.length > 0, download.length <= UpdateHTTPClient.maximumArchiveBytes,
              download.length == download.offerIdentity.contentLength else { throw UpdateServiceFailure(.archive) }
        return try await Task.detached {
            let values = try download.localFile.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  values.fileSize == Int(download.length) else { throw UpdateServiceFailure(.archive) }
            let data = try Data(contentsOf: download.localFile, options: .mappedIfSafe)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard data.count == Int(download.length), digest == download.sha256 else { throw UpdateServiceFailure(.archive) }
            return data
        }.value
    }

    private func readDescriptor(_ url: URL) async -> DownloadedUpdate? {
        await Task.detached {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 8193) <= 8192,
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(DownloadedUpdate.self, from: data)
        }.value
    }

    private func pruneCache(keeping files: Set<URL>) async throws {
        let directory = cacheDirectory
        try await Task.detached {
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw UpdateServiceFailure(.archive) }
            let keep = Set(files.map { $0.standardizedFileURL })
            for file in try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                var name = file.lastPathComponent
                if name.hasSuffix(".partial") { name = String(name.dropLast(8)) }
                guard name.hasPrefix("archive-"), name.hasSuffix(".dmg"),
                      UUID(uuidString: String(name.dropFirst(8).dropLast(4))) != nil,
                      !keep.contains(file.standardizedFileURL) else { continue }
                let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if properties.isRegularFile == true, properties.isSymbolicLink != true { try FileManager.default.removeItem(at: file) }
            }
        }.value
    }

    private func mapOffer(_ item: SUAppcastItem) throws -> UpdateOffer {
        guard feedValidated, item.signingValidationStatus == .succeeded,
              let build = UInt64(item.versionString), build > 0, String(build) == item.versionString,
              let url = item.fileURL, policy.permits(url, purpose: .archive, initial: true),
              !item.isDeltaUpdate, item.deltaUpdates?.isEmpty != false, !item.isInformationOnlyUpdate,
              item.isMacOsUpdate, item.installationType == "application", item.contentLength > 0,
              item.contentLength <= UpdateHTTPClient.maximumArchiveBytes,
              let enclosure = item.propertiesDictionary["enclosure"] as? [String: Any],
              let signature = enclosure["sparkle:edSignature"] as? String,
              Data(base64Encoded: signature)?.count == 64 else { throw UpdateServiceFailure(.invalidOffer) }
        let channel: InstalledUpdateChannel
        switch item.channel { case nil, "": channel = .stable; case "beta": channel = .beta; default: throw UpdateServiceFailure(.invalidOffer) }
        let version = item.displayVersionString
        let pieces = version.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && ($0 == "0" || $0.first != "0") &&
            $0.utf8.allSatisfy { (48...57).contains($0) } }) else { throw UpdateServiceFailure(.invalidOffer) }
        let identity = UpdateOfferIdentity(build: build, archiveURL: url, contentLength: item.contentLength, edDSASignature: signature)
        guard policy.validatesMetadata(identity, version: version, channel: channel) else { throw UpdateServiceFailure(.invalidOffer) }
        var notes: [String: String] = [:]
        for (language, key) in [("en", "estrobo:releaseNotesEn"), ("es", "estrobo:releaseNotesEs")] {
            guard let text = item.propertiesDictionary[key] as? String, !text.isEmpty, text.utf8.count <= 16_384 else { throw UpdateServiceFailure(.invalidOffer) }
            notes[language] = text
        }
        return UpdateOffer(identity: identity,
            marketingVersion: version, channel: channel, releaseNotes: notes["en"]!,
            minimumSystemVersion: item.minimumSystemVersion, maximumSystemVersion: item.maximumSystemVersion,
            hardwareRequirements: item.hardwareRequirements,
            isCompatibleWithCurrentSystem: item.minimumOperatingSystemVersionIsOK && item.maximumOperatingSystemVersionIsOK &&
                item.minimumUpdateVersionIsOK && item.arm64HardwareRequirementIsOK, localizedReleaseNotes: notes)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> { installed.channel == .beta ? ["beta"] : [] }
    func feedURLString(for updater: SPUUpdater) -> String? { feedURL.absoluteString }
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
    func feedParameters(for updater: SPUUpdater, sendingSystemProfile: Bool) -> [[String: String]] { [] }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard operation == .check || operation == .install else { throw UpdateServiceFailure(.cancelled) }
        try checkNotCancelled()
    }
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        guard appcast.signingValidationStatus == .succeeded else { cycleFailure = UpdateServiceFailure(.signature); checkCancellation?(); return }
        feedValidated = true
        event("signed-feed-validated")
        do {
            var builds: [UInt64: UpdateOffer] = [:]
            let candidates = try appcast.items.map { item -> (SUAppcastItem, UpdateOffer) in
                let offer = try mapOffer(item)
                if let previous = builds[offer.identity.build], previous != offer { throw UpdateServiceFailure(.invalidOffer) }
                builds[offer.identity.build] = offer
                return (item, offer)
            }
            let eligible = candidates.filter { $0.1.identity.build > installed.build && $0.1.isCompatibleWithCurrentSystem &&
                (installed.channel == .beta || $0.1.channel == .stable) }
            let selected = eligible.max { $0.1.identity.build < $1.1.identity.build }
            selectedItem = selected?.0
            selectedOffer = selected?.1
        } catch { cycleFailure = error as? UpdateServiceFailure ?? UpdateServiceFailure(.invalidOffer); checkCancellation?() }
    }
    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? { selectedItem ?? SUAppcastItem.empty() }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        try checkNotCancelled()
        if let cycleFailure { throw cycleFailure }
        let candidate = try mapOffer(item)
        if operation == .install, candidate.identity != approvedOffer?.identity { throw UpdateServiceFailure(.invalidOffer) }
    }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool { false }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        request.cachePolicy = .returnCacheDataDontLoad
        guard operation == .install, !cancellationRequested, item.fileURL == approvedOffer?.identity.archiveURL else {
            cycleFailure = UpdateServiceFailure(.invalidOffer); cancel(); return
        }
        let cached = archiveCache.cachedResponse(for: request as URLRequest) != nil
        if !cached { cycleFailure = UpdateServiceFailure(.archive) }
        event("cache-only lookup=\(cached)")
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        trace(error)
        if successfulNoUpdate(error) { return }
        if cycleFailure == nil { cycleFailure = Self.mapSparkle(error) }
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        let reply = cycleReply
        cycleReply = nil
        checkCancellation = nil; downloadCancellation = nil
        event("sparkle-cycle-finished")
        if cancellationRequested { reply?.resume(throwing: UpdateServiceFailure(.cancelled)) }
        else if let cycleFailure { reply?.resume(throwing: cycleFailure) }
        else if let error, !successfulNoUpdate(error) {
            reply?.resume(throwing: Self.mapSparkle(error))
        } else if !feedValidated { reply?.resume(throwing: UpdateServiceFailure(.signature)) }
        else if operation == .install, !lifecycle.isCommitting { reply?.resume(throwing: UpdateServiceFailure(.invalidOffer)) }
        else { reply?.resume() }
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)) }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { checkCancellation = cancellation; if cancellationRequested { cancellation() } }
    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard state.stage == .notDownloaded, !cancellationRequested, cycleFailure == nil else {
            cycleFailure = cycleFailure ?? UpdateServiceFailure(.cancelled); reply(.skip); return
        }
        if operation == .check { reply(.dismiss); return }
        guard operation == .install, let offer = approvedOffer, selectedOffer?.identity == offer.identity,
              precommit?(offer.identity) == true else {
            cycleFailure = UpdateServiceFailure(.invalidOffer); reply(.skip); return
        }
        reply(.install)
    }
    func showUpdateReleaseNotes(with data: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if operation == .install { cycleFailure = UpdateServiceFailure(.invalidOffer) }
        else if !successfulNoUpdate(error) { cycleFailure = Self.mapSparkle(error) }
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { trace(error); if cycleFailure == nil { cycleFailure = Self.mapSparkle(error) }; acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { downloadCancellation = cancellation; if cancellationRequested { cancellation() } }
    func showDownloadDidReceiveExpectedContentLength(_ length: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { downloadCancellation = nil; event("sparkle-extracting") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard operation == .install, !cancellationRequested, let offer = approvedOffer else { reply(.skip); return }
        readyReply = reply
        event("sparkle-prepared")
        lifecycle.prepared(validate: { [weak self] in
            guard let self, !self.cancellationRequested else { return false }
            return self.precommit?(offer.identity) == true
        }, commit: { [weak self] in
            guard let self, let readyReply = self.readyReply else { return }
            self.readyReply = nil
            readyReply(.install)
        })
    }
    func showInstallingUpdate(withApplicationTerminated terminated: Bool, retryTerminatingApplication: @escaping () -> Void) { event("sparkle-installing"); lifecycle.installerWillTerminateApplication() }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() { readyReply = nil; event("sparkle-dismissed") }
    func showUpdateInFocus() {}

    private func successfulNoUpdate(_ error: Error) -> Bool {
        let value = error as NSError
        return operation == .check && feedValidated && selectedOffer == nil && cycleFailure == nil &&
            value.domain == SUSparkleErrorDomain && value.code == Int(SUError.noUpdateError.rawValue)
    }

    private func trace(_ error: Error, depth: Int = 0) {
        guard depth < 8 else { return }
        let value = error as NSError
        event("sparkle-result domain=\(value.domain) code=\(value.code)")
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error { trace(underlying, depth: depth + 1) }
    }

    private static func mapSparkle(_ error: Error, depth: Int = 0) -> UpdateServiceFailure {
        if let failure = error as? UpdateServiceFailure { return failure }
        let value = error as NSError
        if depth < 8, let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error {
            let mapped = mapSparkle(underlying, depth: depth + 1)
            if [.signature, .diskSpace, .readOnlyLocation, .authorizationCancelled].contains(mapped.kind) { return mapped }
        }
        if value.domain == SUSparkleErrorDomain {
            switch value.code {
            case Int(SUError.noUpdateError.rawValue): return UpdateServiceFailure(.invalidOffer)
            case Int(SUError.signatureError.rawValue), Int(SUError.validationError.rawValue):
                return UpdateServiceFailure(.signature)
            case Int(SUError.runningFromDiskImageError.rawValue), Int(SUError.runningTranslocated.rawValue),
                 Int(SUError.installationWriteNoPermissionError.rawValue):
                return UpdateServiceFailure(.readOnlyLocation)
            case Int(SUError.installationCanceledError.rawValue), Int(SUError.installationAuthorizeLaterError.rawValue):
                return UpdateServiceFailure(.authorizationCancelled)
            case Int(SUError.temporaryDirectoryError.rawValue), Int(SUError.unarchivingError.rawValue),
                 Int(SUError.fileCopyFailure.rawValue), Int(SUError.authenticationFailure.rawValue),
                 Int(SUError.missingUpdateError.rawValue), Int(SUError.missingInstallerToolError.rawValue),
                 Int(SUError.relaunchError.rawValue), Int(SUError.installationError.rawValue),
                 Int(SUError.downgradeError.rawValue), Int(SUError.notValidUpdateError.rawValue),
                 Int(SUError.agentInvalidationError.rawValue):
                return UpdateServiceFailure(.installation)
            default: return UpdateServiceFailure(.network)
            }
        }
        if value.domain == NSPOSIXErrorDomain && value.code == Int(EROFS) { return UpdateServiceFailure(.readOnlyLocation) }
        if value.domain == NSCocoaErrorDomain && value.code == NSFileWriteNoPermissionError { return UpdateServiceFailure(.readOnlyLocation) }
        if value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError { return UpdateServiceFailure(.authorizationCancelled) }
        return UpdateHTTPClient.map(error)
    }
}
