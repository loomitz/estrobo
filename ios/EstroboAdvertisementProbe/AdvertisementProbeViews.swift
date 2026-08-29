import SwiftUI

struct AdvertisementProbeRootView: View {
    @ObservedObject var model: AdvertisementProbeModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("Probe status") {
                    LabeledContent("Bluetooth", value: model.bluetoothState)
                    LabeledContent("Scan", value: model.isScanning ? "Running" : "Stopped")
                    LabeledContent("Accessories", value: "\(model.observations.count)")
                }

                Section("Advertisement metadata") {
                    if model.observations.isEmpty {
                        ContentUnavailableView(
                            "No advertisements",
                            systemImage: "antenna.radiowaves.left.and.right",
                            description: Text("Start the probe near the physical accessory.")
                        )
                    } else {
                        ForEach(model.observations) { observation in
                            NavigationLink {
                                AdvertisementDetailView(observation: observation)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(observation.title)
                                    Text(observation.id.uuidString)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text("RSSI \(observation.rssi) · \(observation.sampleCount) samples")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Advertisement Probe")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Clear", action: model.clear)
                    Button(model.isScanning ? "Stop" : "Scan") {
                        model.isScanning ? model.stopScanning() : model.startScanning()
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                model.stopScanning()
            }
        }
    }
}

private struct AdvertisementDetailView: View {
    let observation: AdvertisementObservation

    var body: some View {
        List {
            value("Peripheral UUID", observation.id.uuidString)
            value("Peripheral name", observation.peripheralName ?? "None")
            value("Local name", observation.localName ?? "None")
            value("RSSI", "\(observation.rssi)")
            value("Connectable", observation.isConnectable.map(String.init) ?? "Unknown")
            value("Samples", "\(observation.sampleCount)")

            Section("Advertised service UUIDs") {
                if observation.serviceUUIDs.isEmpty {
                    Text("None")
                } else {
                    ForEach(observation.serviceUUIDs, id: \.self) { Text($0) }
                }
            }

            Section("Overflow service UUIDs") {
                if observation.overflowServiceUUIDs.isEmpty {
                    Text("None")
                } else {
                    ForEach(observation.overflowServiceUUIDs, id: \.self) { Text($0) }
                }
            }

            Section("Solicited service UUIDs") {
                if observation.solicitedServiceUUIDs.isEmpty {
                    Text("None")
                } else {
                    ForEach(observation.solicitedServiceUUIDs, id: \.self) { Text($0) }
                }
            }

            Section("Manufacturer metadata") {
                value(
                    "Company ID",
                    observation.manufacturerCompanyIdentifier.map {
                        String(format: "0x%04X", $0)
                    } ?? "None"
                )
                value(
                    "Data length",
                    observation.manufacturerDataLength.map(String.init) ?? "None"
                )
            }

            Section("Service-data metadata") {
                if observation.serviceData.isEmpty {
                    Text("None")
                } else {
                    ForEach(observation.serviceData, id: \.key) { item in
                        LabeledContent(item.key, value: "\(item.length) bytes")
                    }
                }
            }
        }
        .navigationTitle(observation.title)
    }

    @ViewBuilder
    private func value(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }
}
