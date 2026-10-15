import Foundation
import Security

#if canImport(EstroboCore)
import EstroboCore
#endif

enum RadioCodeVaultReadResult: Equatable {
    case value(RadioCode)
    case missing
    case failed(Int32)
}

enum RadioCodeVaultMutationResult: Equatable {
    case succeeded
    case failed(Int32)
}

@MainActor
protocol RadioCodeVault: AnyObject {
    func read(deviceID: UUID) -> RadioCodeVaultReadResult
    func store(_ code: RadioCode, deviceID: UUID) -> RadioCodeVaultMutationResult
    func remove(deviceID: UUID) -> RadioCodeVaultMutationResult
}

/// Deterministic vault for previews, simulator fixtures and unit tests.
@MainActor
final class InMemoryRadioCodeVault: RadioCodeVault {
    private(set) var values: [UUID: RadioCode]
    var nextReadFailure: Int32?
    var nextStoreFailure: Int32?
    var nextRemoveFailure: Int32?

    init(values: [UUID: RadioCode] = [:]) {
        self.values = values
    }

    func read(deviceID: UUID) -> RadioCodeVaultReadResult {
        if let status = nextReadFailure {
            nextReadFailure = nil
            return .failed(status)
        }
        return values[deviceID].map(RadioCodeVaultReadResult.value) ?? .missing
    }

    func store(_ code: RadioCode, deviceID: UUID) -> RadioCodeVaultMutationResult {
        if let status = nextStoreFailure {
            nextStoreFailure = nil
            return .failed(status)
        }
        values[deviceID] = code
        return .succeeded
    }

    func remove(deviceID: UUID) -> RadioCodeVaultMutationResult {
        if let status = nextRemoveFailure {
            nextRemoveFailure = nil
            return .failed(status)
        }
        values[deviceID] = nil
        return .succeeded
    }
}

/// Keychain-backed vault used by the live composition root.
///
/// Accounts are stable CoreBluetooth UUIDs. Items are device-only, available
/// only while unlocked and explicitly excluded from Keychain synchronization.
@MainActor
final class KeychainRadioCodeVault: RadioCodeVault {
    nonisolated static let defaultService = "mx.loo.estrobo.radio-code"

    private let service: String

    init(service: String = KeychainRadioCodeVault.defaultService) {
        self.service = service
    }

    func read(deviceID: UUID) -> RadioCodeVaultReadResult {
        var query = baseQuery(deviceID: deviceID)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8),
              let code = RadioCode(text) else {
            return .failed(status == errSecSuccess ? errSecDecode : status)
        }
        return .value(code)
    }

    func store(_ code: RadioCode, deviceID: UUID) -> RadioCodeVaultMutationResult {
        let data = Data(code.unsafePlaintext.utf8)
        var add = baseQuery(deviceID: deviceID)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { return .succeeded }
        guard status == errSecDuplicateItem else { return .failed(status) }

        let updateStatus = SecItemUpdate(
            baseQuery(deviceID: deviceID) as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ] as CFDictionary
        )
        return updateStatus == errSecSuccess ? .succeeded : .failed(updateStatus)
    }

    func remove(deviceID: UUID) -> RadioCodeVaultMutationResult {
        let status = SecItemDelete(baseQuery(deviceID: deviceID) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
            ? .succeeded
            : .failed(status)
    }

    private func baseQuery(deviceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}
