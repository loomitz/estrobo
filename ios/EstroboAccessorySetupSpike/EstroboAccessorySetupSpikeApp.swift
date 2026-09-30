import SwiftUI

@main
struct EstroboAccessorySetupSpikeApp: App {
    @StateObject private var model = AccessorySetupDiagnosticModel()

    var body: some Scene {
        WindowGroup {
            AccessorySetupDiagnosticRootView(model: model)
        }
    }
}
