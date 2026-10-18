import Foundation
import CryptoKit

struct UpdateTransportPolicy: Sendable {
    enum Purpose: Sendable { case feed, archive }
    static let feedURL = URL(string: "https://estrobo.app/updates/macos/appcast.xml")!
    private let loopbackFixture: Bool
    static let production = UpdateTransportPolicy(loopbackFixture: false)
    #if ESTROBO_UPDATER_TESTING
    static let fixture = UpdateTransportPolicy(loopbackFixture: true)
    #endif

    func permits(_ url: URL, purpose: Purpose, initial: Bool) -> Bool {
        guard url.user == nil, url.password == nil, url.fragment == nil else { return false }
        #if ESTROBO_UPDATER_TESTING
        if loopbackFixture {
            if url.scheme == "http" && ["127.0.0.1", "localhost"].contains(url.host ?? "") && url.port != nil { return true }
            if purpose == .feed { return false }
        }
        #endif
        guard url.scheme == "https", url.port == nil || url.port == 443 else { return false }
        if purpose == .feed { return !initial || url == Self.feedURL }
        if initial {
            let path = url.pathComponents
            return url.host == "github.com" && url.query == nil && path.count == 7 &&
                Array(path[1...4]) == ["loomitz", "estrobo", "releases", "download"] &&
                path[5] != "latest" && url.pathExtension.lowercased() == "dmg"
        }
        return ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "")
    }

    func validatesMetadata(_ identity: UpdateOfferIdentity, version: String, channel: InstalledUpdateChannel) -> Bool {
        #if ESTROBO_UPDATER_TESTING
        if loopbackFixture, ["127.0.0.1", "localhost"].contains(identity.archiveURL.host ?? "") {
            let name = identity.build == 2 ? "update.dmg" : "update\(identity.build).dmg"
            return identity.archiveURL.lastPathComponent == name
        }
        #endif
        let path = identity.archiveURL.pathComponents
        guard path.count == 7 else { return false }
        let tags = channel == .beta ? ["v\(version)-beta.\(identity.build)"] : ["v\(version)+build.\(identity.build)", "v\(version)"]
        return tags.contains(path[5]) && path[6] == "estrobo-\(path[5])-macos-universal.dmg"
    }
}

private class UpdateRequestDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    let policy: UpdateTransportPolicy
    let purpose: UpdateTransportPolicy.Purpose
    let maximumBytes: UInt64
    let progress: @MainActor (UpdateDownloadProgress) -> Void
    private let lock = NSLock()
    private var problem: UpdateServiceFailure?
    var failure: UpdateServiceFailure? { lock.lock(); defer { lock.unlock() }; return problem }

    init(policy: UpdateTransportPolicy, purpose: UpdateTransportPolicy.Purpose, maximumBytes: UInt64,
         progress: @escaping @MainActor (UpdateDownloadProgress) -> Void) {
        self.policy = policy; self.purpose = purpose; self.maximumBytes = maximumBytes; self.progress = progress
    }
    fileprivate func fail(_ failure: UpdateServiceFailure, task: URLSessionTask) {
        lock.lock(); problem = failure; lock.unlock(); task.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, policy.permits(url, purpose: purpose, initial: false) else {
            fail(UpdateServiceFailure(.network), task: task)
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let response = downloadTask.response {
            do { try UpdateHTTPClient.validate(response) }
            catch { fail(UpdateHTTPClient.map(error), task: downloadTask); return }
        }
        guard totalBytesWritten >= 0, UInt64(totalBytesWritten) <= maximumBytes,
              totalBytesExpectedToWrite <= 0 || UInt64(totalBytesExpectedToWrite) <= maximumBytes else {
            fail(UpdateServiceFailure(.archive), task: downloadTask); return
        }
        let value = UpdateDownloadProgress(completedBytes: UInt64(totalBytesWritten), totalBytes: maximumBytes)
        Task { @MainActor [progress] in progress(value) }
    }
}

/// A real download-task delegate receives incremental bytes on its serial
/// background queue. Foundation's async convenience download did not forward
/// progress on the tested host, so it cannot enforce the streaming byte cap.
private final class UpdateDownloadTransfer: UpdateRequestDelegate, @unchecked Sendable {
    private let identity: UpdateOfferIdentity
    private let destination: URL
    private let transferLock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<DownloadedUpdate, Error>?
    private var cancelled = false
    private var result: DownloadedUpdate?
    private var fileFailure: UpdateServiceFailure?

    init(identity: UpdateOfferIdentity, destination: URL, policy: UpdateTransportPolicy,
         progress: @escaping @MainActor (UpdateDownloadProgress) -> Void) {
        self.identity = identity; self.destination = destination
        super.init(policy: policy, purpose: .archive, maximumBytes: identity.contentLength, progress: progress)
    }

    func start() async throws -> DownloadedUpdate {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { reply in
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: updateSessionConfiguration(), delegate: self, delegateQueue: queue)
                var request = URLRequest(url: identity.archiveURL)
                request.setValue("Estrobo Updater", forHTTPHeaderField: "User-Agent")
                let task = session.downloadTask(with: request)
                transferLock.lock()
                continuation = reply
                self.session = session; self.task = task
                let wasCancelled = cancelled
                transferLock.unlock()
                task.resume()
                if wasCancelled { task.cancel() }
            }
        }, onCancel: { self.cancel() })
    }

    func cancel() {
        transferLock.lock(); cancelled = true; let task = task; transferLock.unlock()
        task?.cancel()
    }

    override func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let partial = destination.appendingPathExtension("partial")
        do {
            if let failure { throw failure }
            guard let response = downloadTask.response else { throw UpdateServiceFailure(.network) }
            try UpdateHTTPClient.validate(response)
            let info = try UpdateHTTPClient.inspect(location, maximumBytes: identity.contentLength)
            guard info.length == identity.contentLength else { throw UpdateServiceFailure(.archive) }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.moveItem(at: location, to: partial)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: partial.path)
            try FileManager.default.moveItem(at: partial, to: destination)
            result = DownloadedUpdate(offerIdentity: identity, localFile: destination, length: info.length, sha256: info.sha256)
        } catch {
            fileFailure = UpdateHTTPClient.map(error)
            try? FileManager.default.removeItem(at: partial)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        transferLock.lock()
        let reply = continuation
        continuation = nil
        let wasCancelled = cancelled
        transferLock.unlock()
        let problem = failure ?? fileFailure ?? (error.map { UpdateHTTPClient.map($0) })
        if let problem {
            try? FileManager.default.removeItem(at: destination)
            reply?.resume(throwing: problem)
        } else if wasCancelled {
            try? FileManager.default.removeItem(at: destination)
            reply?.resume(throwing: UpdateServiceFailure(.cancelled))
        } else if let result { reply?.resume(returning: result) }
        else { reply?.resume(throwing: UpdateServiceFailure(.archive)) }
        session.finishTasksAndInvalidate()
        transferLock.lock(); self.session = nil; self.task = nil; transferLock.unlock()
    }
}

private func updateSessionConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 300
    return configuration
}

/// Estrobo's own bounded HEAD/download transport, separate from Sparkle's feed session.
/// Cookies, credentials and persistent URL caching are deliberately absent.
@MainActor
final class UpdateHTTPClient {
    static let maximumArchiveBytes: UInt64 = 64 * 1024 * 1024
    private let policy: UpdateTransportPolicy
    private var session: URLSession
    private var transfer: UpdateDownloadTransfer?
    init(policy: UpdateTransportPolicy) {
        self.policy = policy
        session = URLSession(configuration: updateSessionConfiguration())
    }
    func cancel() {
        transfer?.cancel()
        session.invalidateAndCancel()
        session = URLSession(configuration: updateSessionConfiguration())
    }

    func preflight(_ url: URL) async throws {
        guard policy.permits(url, purpose: .feed, initial: true) else { throw UpdateServiceFailure(.configuration) }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Estrobo Updater", forHTTPHeaderField: "User-Agent")
        let delegate = UpdateRequestDelegate(policy: policy, purpose: .feed, maximumBytes: 0, progress: { _ in })
        do {
            let (_, response) = try await session.data(for: request, delegate: delegate)
            if let failure = delegate.failure { throw failure }
            try Self.validate(response)
        } catch { throw delegate.failure ?? Self.map(error) }
    }

    func download(_ identity: UpdateOfferIdentity, to destination: URL,
                  progress: @escaping @MainActor (UpdateDownloadProgress) -> Void) async throws -> DownloadedUpdate {
        guard policy.permits(identity.archiveURL, purpose: .archive, initial: true),
              identity.contentLength > 0, identity.contentLength <= Self.maximumArchiveBytes else {
            throw UpdateServiceFailure(.invalidOffer)
        }
        let transfer = UpdateDownloadTransfer(identity: identity, destination: destination, policy: policy, progress: progress)
        self.transfer = transfer
        defer { self.transfer = nil }
        let result = try await transfer.start()
        progress(UpdateDownloadProgress(completedBytes: result.length, totalBytes: result.length))
        return result
    }

    nonisolated static func inspect(_ url: URL, maximumBytes: UInt64) throws -> (length: UInt64, sha256: String) {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        var length: UInt64 = 0
        while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty {
            length += UInt64(bytes.count)
            guard length <= maximumBytes else { throw UpdateServiceFailure(.archive) }
            hash.update(data: bytes)
        }
        return (length, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }

    nonisolated static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw UpdateServiceFailure(.network) }
        guard (200...299).contains(response.statusCode) else {
            let retry = retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: Date())
            throw UpdateServiceFailure(response.statusCode == 429 ? .rateLimit : .network, retryAfter: retry, httpStatus: response.statusCode)
        }
    }
    nonisolated static func retryAfter(_ raw: String?, now: Date) -> Date? {
        guard let raw else { return nil }
        if let seconds = Double(raw.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds >= 0 {
            return min(.distantFuture, now.addingTimeInterval(seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: raw)
    }
    nonisolated static func map(_ error: Error) -> UpdateServiceFailure {
        if let failure = error as? UpdateServiceFailure { return failure }
        let error = error as NSError
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return UpdateServiceFailure(.cancelled) }
        if error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC) { return UpdateServiceFailure(.diskSpace) }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError { return UpdateServiceFailure(.diskSpace) }
        if error.domain == NSPOSIXErrorDomain && error.code == Int(EROFS) { return UpdateServiceFailure(.readOnlyLocation) }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError { return UpdateServiceFailure(.readOnlyLocation) }
        return UpdateServiceFailure(.network)
    }
}
