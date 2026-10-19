import Foundation

enum InstalledUpdateChannel: String, Codable, Sendable {
    case stable, beta
}

struct InstalledUpdateVersion: Equatable, Sendable {
    let build: UInt64
    let marketingVersion: String
    let channel: InstalledUpdateChannel

    init(build: UInt64, marketingVersion: String, channel: InstalledUpdateChannel) {
        self.build = build
        self.marketingVersion = marketingVersion
        self.channel = channel
    }

    init?(bundle: Bundle = .main) {
        guard let raw = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let build = UInt64(raw), build > 0, String(build) == raw,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let channelName = bundle.object(forInfoDictionaryKey: "EstroboUpdateChannel") as? String,
              let channel = InstalledUpdateChannel(rawValue: channelName) else { return nil }
        self.init(build: build, marketingVersion: version, channel: channel)
    }
}

struct UpdateOfferIdentity: Equatable, Hashable, Codable, Sendable {
    let build: UInt64
    let archiveURL: URL
    let contentLength: UInt64
    let edDSASignature: String
}

struct UpdateOffer: Equatable, Sendable {
    let identity: UpdateOfferIdentity
    let marketingVersion: String
    let channel: InstalledUpdateChannel
    let releaseNotes: String
    let minimumSystemVersion: String?
    let maximumSystemVersion: String?
    let hardwareRequirements: Set<String>
    let isCompatibleWithCurrentSystem: Bool
    let localizedReleaseNotes: [String: String]

    init(identity: UpdateOfferIdentity, marketingVersion: String,
         channel: InstalledUpdateChannel, releaseNotes: String,
         minimumSystemVersion: String?, maximumSystemVersion: String?,
         hardwareRequirements: Set<String>, isCompatibleWithCurrentSystem: Bool,
         localizedReleaseNotes: [String: String] = [:]) {
        self.identity = identity
        self.marketingVersion = marketingVersion
        self.channel = channel
        self.releaseNotes = releaseNotes
        self.minimumSystemVersion = minimumSystemVersion
        self.maximumSystemVersion = maximumSystemVersion
        self.hardwareRequirements = hardwareRequirements
        self.isCompatibleWithCurrentSystem = isCompatibleWithCurrentSystem
        self.localizedReleaseNotes = localizedReleaseNotes
    }
}

struct DownloadedUpdate: Equatable, Codable, Sendable {
    let offerIdentity: UpdateOfferIdentity
    let localFile: URL
    let length: UInt64
    /// Evidence of byte identity, never a replacement for signature validation.
    let sha256: String
}

struct UpdateDownloadProgress: Equatable, Sendable {
    let completedBytes: UInt64
    let totalBytes: UInt64

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
}

struct UpdateServiceFailure: Error, Equatable, Sendable {
    enum Kind: String, Sendable {
        case configuration, network, rateLimit, signature, invalidOffer
        case archive, installation, cancelled, unsafeSession
        case readOnlyLocation, authorizationCancelled, diskSpace
    }
    let kind: Kind
    let retryAfter: Date?
    let httpStatus: Int?

    init(_ kind: Kind, retryAfter: Date? = nil, httpStatus: Int? = nil) {
        self.kind = kind
        self.retryAfter = retryAfter
        self.httpStatus = httpStatus
    }
}

/// One boundary for real Sparkle/HTTP and the controlled test service.
/// A successful check returns candidates from a verified fresh signed feed.
/// Installation revalidates that feed and exact downloaded identity, then calls
/// precommit synchronously on MainActor immediately before archive preparation
/// and again before committing installation. A false reply MUST cancel without
/// consuming installer approval. cancel() requests cancellation synchronously;
/// the async install operation returns only after preparation has stopped, so the
/// coordinator can safely release its session suspension when that task finishes.
@MainActor
protocol UpdateService: AnyObject {
    func check(for installed: InstalledUpdateVersion) async throws -> [UpdateOffer]
    func download(_ offer: UpdateOffer,
                  progress: @escaping @MainActor (UpdateDownloadProgress) -> Void) async throws -> DownloadedUpdate
    func install(_ download: DownloadedUpdate, offer: UpdateOffer,
                 precommit: @escaping @MainActor (UpdateOfferIdentity) -> Bool) async throws
    func cancel()
}
