import Foundation

/// Six decimal digits used by the transmitter handshake.
///
/// Deliberately does not expose its contents through textual descriptions. Code
/// that must build a protocol frame can opt in through `unsafePlaintext`; that
/// spelling is intentional so a secret cannot drift into interpolation unnoticed.
public struct RadioCode: Equatable, Hashable, CustomStringConvertible,
    CustomDebugStringConvertible, Sendable {
    private let value: String

    public init?(_ value: String) {
        guard value.utf8.count == 6,
              value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            return nil
        }
        self.value = value
    }

    public var unsafePlaintext: String { value }
    public var description: String { "<redacted>" }
    public var debugDescription: String { "RadioCode(<redacted>)" }
}

/// A remembered transmitter. Its credential remains redacted and is persisted
/// only through a secure vault adapter.
public struct SavedRadio: Equatable, Identifiable, Sendable {
    public let deviceID: UUID
    public let name: String
    private let code: RadioCode

    public var id: UUID { deviceID }
    /// Explicitly unwraps the credential for the authentication boundary.
    /// Keep the unsafe spelling so accidental interpolation remains conspicuous.
    public var unsafeRadioCodePlaintext: String { code.unsafePlaintext }
    public var secureRadioCode: RadioCode { code }

    public init?(deviceID: UUID, name: String, radioCode: String) {
        guard let code = RadioCode(radioCode) else { return nil }
        self.init(deviceID: deviceID, name: name, code: code)
    }

    public init?(deviceID: UUID, name: String, code: RadioCode) {
        guard let normalizedName = GodoxBluetoothDeviceName.canonicalName(from: name) else {
            return nil
        }
        self.deviceID = deviceID
        self.name = normalizedName
        self.code = code
    }

    public static func isValidRadioCode(_ radioCode: String) -> Bool {
        RadioCode(radioCode) != nil
    }
}
