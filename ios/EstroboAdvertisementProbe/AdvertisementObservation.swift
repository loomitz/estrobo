import CoreBluetooth
import Foundation

struct AdvertisementObservation: Identifiable, Equatable, Sendable {
    struct ServiceDataMetadata: Equatable, Sendable {
        let key: String
        let length: Int
    }

    let id: UUID
    let peripheralName: String?
    let localName: String?
    let serviceUUIDs: [String]
    let overflowServiceUUIDs: [String]
    let solicitedServiceUUIDs: [String]
    let manufacturerCompanyIdentifier: UInt16?
    let manufacturerDataLength: Int?
    let serviceData: [ServiceDataMetadata]
    let isConnectable: Bool?
    let rssi: Int
    let sampleCount: Int
    let lastSeenAt: Date

    var title: String {
        localName ?? peripheralName ?? "Unnamed advertisement"
    }

    var logSummary: String {
        let company = manufacturerCompanyIdentifier.map {
            String(format: "0x%04X", $0)
        } ?? "none"
        let manufacturerLength = manufacturerDataLength.map(String.init) ?? "none"
        let serviceList = serviceUUIDs.isEmpty ? "none" : serviceUUIDs.joined(separator: ",")
        let overflowServiceList = overflowServiceUUIDs.isEmpty
            ? "none"
            : overflowServiceUUIDs.joined(separator: ",")
        let solicitedServiceList = solicitedServiceUUIDs.isEmpty
            ? "none"
            : solicitedServiceUUIDs.joined(separator: ",")
        let serviceDataList = serviceData.isEmpty
            ? "none"
            : serviceData.map { "\($0.key):\($0.length)" }.joined(separator: ",")
        let connectable = isConnectable.map(String.init) ?? "unknown"

        return [
            "peripheral=\(id.uuidString)",
            "name=\(peripheralName ?? "none")",
            "localName=\(localName ?? "none")",
            "serviceUUIDs=\(serviceList)",
            "overflowServiceUUIDs=\(overflowServiceList)",
            "solicitedServiceUUIDs=\(solicitedServiceList)",
            "manufacturerCompanyID=\(company)",
            "manufacturerLength=\(manufacturerLength)",
            "serviceData=\(serviceDataList)",
            "connectable=\(connectable)",
            "rssi=\(rssi)",
            "samples=\(sampleCount)",
        ].joined(separator: " ")
    }

    static func make(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber,
        previousSampleCount: Int
    ) -> AdvertisementObservation {
        let manufacturerData = advertisementData[
            CBAdvertisementDataManufacturerDataKey
        ] as? Data
        let companyIdentifier = manufacturerData.flatMap { data -> UInt16? in
            guard data.count >= 2 else { return nil }
            return UInt16(data[data.startIndex]) |
                (UInt16(data[data.index(after: data.startIndex)]) << 8)
        }
        let advertisedServiceUUIDs = (
            advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        ) ?? []
        let overflowServiceUUIDs = (
            advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]
        ) ?? []
        let solicitedServiceUUIDs = (
            advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]
        ) ?? []
        let advertisedServiceData = (
            advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        ) ?? [:]
        let connectableNumber = advertisementData[
            CBAdvertisementDataIsConnectable
        ] as? NSNumber

        return AdvertisementObservation(
            id: peripheral.identifier,
            peripheralName: peripheral.name,
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            serviceUUIDs: advertisedServiceUUIDs
                .map(\.uuidString)
                .sorted(),
            overflowServiceUUIDs: overflowServiceUUIDs
                .map(\.uuidString)
                .sorted(),
            solicitedServiceUUIDs: solicitedServiceUUIDs
                .map(\.uuidString)
                .sorted(),
            manufacturerCompanyIdentifier: companyIdentifier,
            manufacturerDataLength: manufacturerData?.count,
            serviceData: advertisedServiceData
                .map { ServiceDataMetadata(key: $0.key.uuidString, length: $0.value.count) }
                .sorted { $0.key < $1.key },
            isConnectable: connectableNumber?.boolValue,
            rssi: rssi.intValue,
            sampleCount: previousSampleCount + 1,
            lastSeenAt: Date()
        )
    }
}
