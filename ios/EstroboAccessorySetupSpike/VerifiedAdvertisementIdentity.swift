import AccessorySetupKit
import CoreBluetooth
import Foundation

/// Advertisement evidence that is strong enough to anchor the diagnostic picker.
///
/// Every value must come from repeated physical advertisement samples. The exact
/// Bluetooth name refines a service or company anchor; it never creates an identity alone.
@available(iOS 26.1, *)
struct VerifiedAdvertisementIdentity: Sendable {
    public let advertisedServiceUUIDString: String?
    public let bluetoothCompanyIdentifier: UInt16?
    public let exactBluetoothName: String

    init?(
        verifiedAdvertisedServiceUUID: CBUUID? = nil,
        verifiedBluetoothCompanyIdentifier: UInt16? = nil,
        verifiedExactBluetoothName: String
    ) {
        guard verifiedAdvertisedServiceUUID != nil ||
                verifiedBluetoothCompanyIdentifier != nil else {
            return nil
        }

        let normalizedName = verifiedExactBluetoothName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }

        advertisedServiceUUIDString = verifiedAdvertisedServiceUUID?.uuidString
        bluetoothCompanyIdentifier = verifiedBluetoothCompanyIdentifier
        exactBluetoothName = normalizedName
    }
}

/// The only construction surface for the spike's AccessorySetupKit descriptor.
@available(iOS 26.1, *)
enum AccessorySetupDescriptorFactory {
    static func makeDescriptor(
        from identity: VerifiedAdvertisementIdentity
    ) -> ASDiscoveryDescriptor {
        let descriptor = ASDiscoveryDescriptor()
        descriptor.supportedOptions = []
        descriptor.bluetoothServiceUUID = identity.advertisedServiceUUIDString.map(CBUUID.init(string:))
        if let companyIdentifier = identity.bluetoothCompanyIdentifier {
            descriptor.bluetoothCompanyIdentifier = ASBluetoothCompanyIdentifier(
                rawValue: companyIdentifier
            )
        }
        descriptor.bluetoothNameSubstring = identity.exactBluetoothName
        descriptor.bluetoothNameSubstringCompareOptions = [.literal]
        return descriptor
    }
}
