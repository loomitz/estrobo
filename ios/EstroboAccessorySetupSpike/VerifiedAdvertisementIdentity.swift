import AccessorySetupKit
import CoreBluetooth
import Foundation

/// Advertisement evidence that is strong enough to anchor AccessorySetupKit discovery.
///
/// Callers must obtain these values from repeated physical advertisement samples. A
/// Bluetooth name is optional refinement only and can never create an identity by itself.
@available(iOS 18.0, *)
public struct VerifiedAdvertisementIdentity: Sendable {
    public let advertisedServiceUUIDString: String?
    public let bluetoothCompanyIdentifier: UInt16?
    public let nameSubstring: String?

    public init?(
        verifiedAdvertisedServiceUUID: CBUUID? = nil,
        verifiedBluetoothCompanyIdentifier: UInt16? = nil,
        nameSubstring: String? = nil
    ) {
        guard verifiedAdvertisedServiceUUID != nil ||
                verifiedBluetoothCompanyIdentifier != nil else {
            return nil
        }

        let normalizedName = nameSubstring?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        advertisedServiceUUIDString = verifiedAdvertisedServiceUUID?.uuidString
        bluetoothCompanyIdentifier = verifiedBluetoothCompanyIdentifier
        self.nameSubstring = normalizedName?.isEmpty == false ? normalizedName : nil
    }
}

/// The only construction surface for the spike's AccessorySetupKit descriptor.
@available(iOS 18.0, *)
public enum AccessorySetupDescriptorFactory {
    public static func makeDescriptor(
        from identity: VerifiedAdvertisementIdentity
    ) -> ASDiscoveryDescriptor {
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = identity.advertisedServiceUUIDString.map(CBUUID.init(string:))
        if let companyIdentifier = identity.bluetoothCompanyIdentifier {
            descriptor.bluetoothCompanyIdentifier = ASBluetoothCompanyIdentifier(
                rawValue: companyIdentifier
            )
        }
        descriptor.bluetoothNameSubstring = identity.nameSubstring
        return descriptor
    }
}
