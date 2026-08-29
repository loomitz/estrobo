import SwiftUI

@main
struct EstroboAdvertisementProbeApp: App {
    @StateObject private var model = AdvertisementProbeModel()

    var body: some Scene {
        WindowGroup {
            AdvertisementProbeRootView(model: model)
        }
    }
}
