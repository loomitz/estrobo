import SwiftUI

struct AccessorySetupDiagnosticRootView: View {
    @ObservedObject var model: AccessorySetupDiagnosticModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRemovalConfirmationPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("Verified advertisement identity") {
                    LabeledContent("Exact local name", value: model.exactBluetoothName)
                    LabeledContent("Advertised service", value: model.advertisedServiceUUID)
                }

                Section("Diagnostic status") {
                    LabeledContent("Session", value: model.sessionStatus)
                    LabeledContent("Picker", value: model.pickerStatus)
                    LabeledContent("Authorization", value: model.authorizationStatus)
                    LabeledContent("CoreBluetooth", value: model.retrievalStatus)
                    LabeledContent("Removal", value: model.removalStatus)
                    LabeledContent("Identifier", value: model.redactedIdentifier)
                }

                Section("Controls") {
                    Button("1. Activate diagnostic", action: model.activate)
                        .disabled(!model.canActivate)
                    Button("2. Show system picker", action: model.showPicker)
                        .disabled(!model.canShowPicker)
                    Button("3. Remove diagnostic authorization", role: .destructive) {
                        isRemovalConfirmationPresented = true
                    }
                    .disabled(!model.canRemoveAuthorization)
                }

                Section("Safety boundary") {
                    Text(
                        "Selecting the accessory authorizes it for this diagnostic app. " +
                        "The app only resolves that authorized identifier locally."
                    )
                    Text(
                        "No direct CoreBluetooth scan, GATT connection, service discovery, " +
                        "command, write, Test, or Multi is implemented."
                    )
                    Text("Cancel if more than one transmitter could match GDBH-A681.")
                }
            }
            .navigationTitle("ASK Diagnostic")
            .alert(
                "Remove diagnostic authorization?",
                isPresented: $isRemovalConfirmationPresented
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Remove authorization", role: .destructive) {
                    model.removeAuthorization()
                }
            } message: {
                Text(
                    "This requests system removal of this diagnostic authorization. " +
                    "It does not connect to or write to the transmitter."
                )
            }
        }
        .onAppear {
            if scenePhase == .active {
                model.sceneBecameActive()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                model.sceneBecameActive()
            case .inactive:
                model.sceneBecameInactive()
            case .background:
                model.sceneEnteredBackground()
            @unknown default:
                model.sceneEnteredBackground()
            }
        }
    }
}
