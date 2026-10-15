import Darwin
import Foundation

enum RestorationJournalReadResult: Equatable {
    case none
    case data(Data)
    case failed(Int32)
}

enum RestorationJournalMutationResult: Equatable {
    case committed
    case notCommitted
    case indeterminate
}

@MainActor
protocol RestorationJournal: AnyObject {
    func read() -> RestorationJournalReadResult
    func replace(with data: Data) -> RestorationJournalMutationResult
    func clear() -> RestorationJournalMutationResult
}

@MainActor
final class InMemoryRestorationJournal: RestorationJournal {
    var data: Data?
    var nextReadFailure: Int32?
    var nextReplaceResult: RestorationJournalMutationResult?
    var nextClearResult: RestorationJournalMutationResult?

    init(data: Data? = nil) {
        self.data = data
    }

    func read() -> RestorationJournalReadResult {
        if let status = nextReadFailure {
            nextReadFailure = nil
            return .failed(status)
        }
        return data.map(RestorationJournalReadResult.data) ?? .none
    }

    func replace(with newData: Data) -> RestorationJournalMutationResult {
        if let result = nextReplaceResult {
            nextReplaceResult = nil
            if result == .committed { data = newData }
            return result
        }
        data = newData
        return .committed
    }

    func clear() -> RestorationJournalMutationResult {
        if let result = nextClearResult {
            nextClearResult = nil
            if result == .committed { data = nil }
            return result
        }
        data = nil
        return .committed
    }
}

/// Same-directory, crash-durable file replacement for pending radio recovery.
@MainActor
final class AtomicFileRestorationJournal: RestorationJournal {
    enum Operation: Equatable {
        case prepareDirectory
        case openTemporary
        case writeTemporary
        case syncTemporary
        case fullSyncTemporary
        case closeTemporary
        case renameTemporary
        case openDirectory
        case syncDirectory
        case closeDirectory
        case unlink
    }

    static let maximumJournalBytes = 1_048_576

    let fileURL: URL
    private let injectFailure: (Operation) -> Bool

    init(
        fileURL: URL,
        injectFailure: @escaping (Operation) -> Bool = { _ in false }
    ) {
        self.fileURL = fileURL
        self.injectFailure = injectFailure
    }

    func read() -> RestorationJournalReadResult {
        let path = fileURL.path
        var metadata = stat()
        if lstat(path, &metadata) != 0 {
            return errno == ENOENT ? .none : .failed(errno)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG,
              (metadata.st_mode & 0o777) == 0o600,
              metadata.st_size >= 0,
              metadata.st_size <= Self.maximumJournalBytes else {
            return .failed(EINVAL)
        }

        let descriptor = open(path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return .failed(errno) }
        defer { _ = Darwin.close(descriptor) }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return .failed(errno)
            }
            data.append(contentsOf: buffer.prefix(count))
            if data.count > Self.maximumJournalBytes { return .failed(EFBIG) }
        }
        return .data(data)
    }

    func replace(with data: Data) -> RestorationJournalMutationResult {
        guard !data.isEmpty, data.count <= Self.maximumJournalBytes else {
            return .notCommitted
        }
        guard prepareDirectory() else { return .notCommitted }

        let directoryURL = fileURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let temporaryPath = temporaryURL.path
        var descriptor: Int32 = -1
        var renamed = false
        defer {
            if descriptor >= 0 { _ = Darwin.close(descriptor) }
            if !renamed { _ = unlink(temporaryPath) }
        }

        guard !injectFailure(.openTemporary) else { return .notCommitted }
        descriptor = open(
            temporaryPath,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0, fchmod(descriptor, mode_t(0o600)) == 0 else {
            return .notCommitted
        }

        guard !injectFailure(.writeTemporary), writeAll(data, to: descriptor) else {
            return .notCommitted
        }
        guard !injectFailure(.syncTemporary), fsync(descriptor) == 0 else {
            return .notCommitted
        }
        guard !injectFailure(.fullSyncTemporary),
              fcntl(descriptor, F_FULLFSYNC) == 0 else {
            return .notCommitted
        }
        guard !injectFailure(.closeTemporary), Darwin.close(descriptor) == 0 else {
            descriptor = -1
            return .notCommitted
        }
        descriptor = -1

        guard !injectFailure(.renameTemporary),
              rename(temporaryPath, fileURL.path) == 0 else {
            return .notCommitted
        }
        renamed = true

        // Once rename succeeds, failure cannot prove which name is durable.
        guard !injectFailure(.openDirectory) else { return .indeterminate }
        let directoryDescriptor = open(directoryURL.path, O_RDONLY | O_NOFOLLOW)
        guard directoryDescriptor >= 0 else { return .indeterminate }
        guard !injectFailure(.syncDirectory), fsync(directoryDescriptor) == 0 else {
            _ = Darwin.close(directoryDescriptor)
            return .indeterminate
        }
        guard !injectFailure(.closeDirectory), Darwin.close(directoryDescriptor) == 0 else {
            return .indeterminate
        }
        return .committed
    }

    func clear() -> RestorationJournalMutationResult {
        let path = fileURL.path
        if unlink(path) != 0 {
            if errno == ENOENT { return .committed }
            return .notCommitted
        }
        guard !injectFailure(.unlink) else { return .indeterminate }

        let directoryPath = fileURL.deletingLastPathComponent().path
        let descriptor = open(directoryPath, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return .indeterminate }
        guard fsync(descriptor) == 0 else {
            _ = Darwin.close(descriptor)
            return .indeterminate
        }
        return Darwin.close(descriptor) == 0 ? .committed : .indeterminate
    }

    private func prepareDirectory() -> Bool {
        guard !injectFailure(.prepareDirectory) else { return false }
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            return chmod(directoryURL.path, mode_t(0o700)) == 0
        } catch {
            return false
        }
    }

    private func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return false }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }
}

/// Adapter retained for deterministic legacy tests and previews.
@MainActor
final class ClosureRestorationJournal: RestorationJournal {
    private let readObject: () -> Any?
    private let writeData: (Data) -> Bool
    private let removeValue: () -> Bool
    private var lastVerifiedWrite: Data?

    init(
        readObject: @escaping () -> Any?,
        writeData: @escaping (Data) -> Bool,
        removeValue: @escaping () -> Bool
    ) {
        self.readObject = readObject
        self.writeData = writeData
        self.removeValue = removeValue
    }

    func read() -> RestorationJournalReadResult {
        guard let object = readObject() else {
            return lastVerifiedWrite.map(RestorationJournalReadResult.data) ?? .none
        }
        guard let data = object as? Data else { return .failed(EINVAL) }
        return .data(data)
    }

    func replace(with data: Data) -> RestorationJournalMutationResult {
        guard writeData(data) else { return .notCommitted }
        lastVerifiedWrite = data
        return .committed
    }

    func clear() -> RestorationJournalMutationResult {
        guard removeValue() else { return .notCommitted }
        lastVerifiedWrite = nil
        return .committed
    }
}
