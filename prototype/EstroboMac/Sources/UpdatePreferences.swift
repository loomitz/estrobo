import Foundation

struct UpdatePreferenceState: Codable, Equatable {
    var automaticChecks = false
    var automaticDownloads = false
    var lastSuccessfulCheck: Date?
    var nextAutomaticAttempt: Date?
    var postOnboardingLaunches = 0
    var invitationDismissed = false
}

/// App-local persistence, independent from radio data and beta enrollment.
@MainActor
final class UpdatePreferences {
    private let defaults: UserDefaults?
    private let key = "macOS.assistedUpdates.preferences.v1"
    var state: UpdatePreferenceState {
        didSet {
            if let data = try? JSONEncoder().encode(state) { defaults?.set(data, forKey: key) }
        }
    }

    /// nil defaults provides isolated in-memory preferences for behavior tests.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        state = defaults?.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(UpdatePreferenceState.self, from: $0) }
            ?? UpdatePreferenceState()
        if !state.automaticChecks { state.automaticDownloads = false }
    }
}
