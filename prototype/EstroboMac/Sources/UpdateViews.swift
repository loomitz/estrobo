import SwiftUI

/// Receives the single app-owned coordinator. It never owns an installer or radio session.
@MainActor
struct UpdatesView: View {
    @EnvironmentObject private var updater: UpdateCoordinator
    @EnvironmentObject private var languageStore: AppLanguageStore

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var confirmationOffer: UpdateOffer?
    @State private var showsConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(languageStore.language.localized("updates.title"))
                    .font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 6) {
                    Text(languageStore.language.localized("updates.installed"))
                        .font(.callout.weight(.semibold))
                    Text(verbatim: UpdateCopy.version(updater.snapshot.installed, language: languageStore.language))
                        .font(.callout)
                    Text(verbatim: UpdateCopy.lastCheck(updater.snapshot, language: languageStore.language))
                        .font(.caption)
                        .foregroundStyle(UpdatePalette.secondaryText)
                }
                Divider()
                if updater.snapshot.showsOptInInvitation {
                    UpdateInvitation()
                    Divider()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(languageStore.language.localized("updates.status.\(updater.snapshot.stage.rawValue)"))
                        .font(.headline)
                        .accessibilityIdentifier("updates.status")
                    if updater.snapshot.isCancellingInstallation {
                        Text(languageStore.language.localized("updates.cancelling"))
                            .font(.callout)
                    }
                    if let failure = updater.snapshot.failure {
                        Text(languageStore.language.localized("updates.error.\(failure.kind.rawValue)"))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("updates.failure")
                        if updater.snapshot.automaticChecks, let date = updater.snapshot.nextAutomaticAttempt {
                            Text(languageStore.language.localizedFormat("updates.retryAt", date.formatted(.dateTime.locale(languageStore.locale).month().day().hour().minute())))
                                .font(.caption)
                                .foregroundStyle(UpdatePalette.secondaryText)
                        }
                    }
                    if updater.snapshot.downloadedIdentity != nil, let blocker = updater.snapshot.installationBlocker {
                        UpdateBlockerExplanation(blocker: blocker)
                    }
                    if let offer = updater.snapshot.offer {
                        Text(verbatim: UpdateCopy.version(offer, language: languageStore.language))
                            .font(.callout.weight(.semibold))
                        if !offer.releaseNotes.isEmpty || !offer.localizedReleaseNotes.isEmpty {
                            Text(languageStore.language.localized("updates.notes"))
                                .font(.callout.weight(.semibold))
                            Text(verbatim: offer.localizedReleaseNotes[languageStore.language.rawValue] ?? offer.releaseNotes)
                                .font(.callout)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("updates.notes")
                        }
                    }
                    if let progress = updater.snapshot.progress {
                        ProgressView(value: progress.fraction)
                            .accessibilityLabel(languageStore.language.localized("updates.status.downloading"))
                            .accessibilityValue(UpdateCopy.progress(progress, language: languageStore.language))
                            .accessibilityIdentifier("updates.progress")
                        Text(verbatim: UpdateCopy.progress(progress, language: languageStore.language))
                            .font(.caption)
                    }
                    HStack(spacing: 10) {
                        Button(languageStore.language.localized("updates.check")) { updater.checkManually() }
                            .disabled([.checking, .downloading, .installing].contains(updater.snapshot.stage))
                            .accessibilityIdentifier("updates.check")
                        if updater.snapshot.offer != nil && updater.snapshot.downloadedIdentity == nil && [.available, .error].contains(updater.snapshot.stage) {
                            Button(languageStore.language.localized("updates.download")) { updater.download() }
                                .accessibilityIdentifier("updates.download")
                        }
                        if updater.snapshot.stage == .downloading {
                            Button(languageStore.language.localized("updates.cancelDownload")) { updater.cancelDownload() }
                                .accessibilityIdentifier("updates.cancelDownload")
                        }
                        if updater.snapshot.downloadedIdentity != nil && [.downloaded, .blocked, .error].contains(updater.snapshot.stage) {
                            Button(languageStore.language.localized("updates.install")) {
                                confirmationOffer = updater.snapshot.offer
                                showsConfirmation = confirmationOffer != nil
                            }
                            .disabled(updater.snapshot.installationBlocker != nil)
                            .accessibilityIdentifier("updates.install")
                        }
                        if updater.snapshot.stage == .installing {
                            Button(languageStore.language.localized("updates.cancelInstall")) { updater.cancelInstall() }
                                .disabled(updater.snapshot.isCancellingInstallation || !updater.hasInstallationInProgress)
                                .accessibilityIdentifier("updates.cancelInstall")
                        }
                    }
                    if updater.snapshot.offer != nil && ![.downloading, .installing].contains(updater.snapshot.stage) {
                        Button(languageStore.language.localized("updates.postpone")) {
                            updater.postpone()
                            dismiss()
                        }
                        .accessibilityIdentifier("updates.postpone")
                    }
                }
                Divider()
                UpdatePreferencesControls()
                if !updater.snapshot.showsOptInInvitation {
                    Text(languageStore.language.localized("updates.privacy"))
                        .font(.caption)
                        .foregroundStyle(UpdatePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 16) {
                    Button(languageStore.language.localized("updates.support")) {
                        openURL(URL(string: "https://github.com/loomitz/estrobo/issues/new")!)
                    }
                    .accessibilityIdentifier("updates.support")
                    Button(languageStore.language.localized("updates.manual")) {
                        openURL(updater.snapshot.offer?.identity.archiveURL ?? URL(string: languageStore.language == .es ? "https://estrobo.app/guia/" : "https://estrobo.app/en/guide/")!)
                    }
                    .accessibilityIdentifier("updates.manual")
                }
                .buttonStyle(.link)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(PrototypePalette.primaryText)
        .background(PrototypePalette.windowBackground)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 660)
        .confirmationDialog(confirmationTitle, isPresented: $showsConfirmation, titleVisibility: .visible,
                            presenting: confirmationOffer) { capturedOffer in
            Button(languageStore.language.localized("updates.confirmInstall")) {
                updater.confirmInstall(expectedIdentity: capturedOffer.identity)
                confirmationOffer = nil
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("updates.confirm")
            Button(languageStore.language.localized("updates.cancel"), role: .cancel) {
                confirmationOffer = nil
                updater.postpone()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("updates.cancelConfirmation")
        } message: { _ in
            Text(languageStore.language.localized("updates.confirm.detail"))
        }
    }

    private var confirmationTitle: String {
        guard let offer = confirmationOffer else { return languageStore.language.localized("updates.install") }
        return languageStore.language.localizedFormat("updates.confirm.title", offer.marketingVersion, String(offer.identity.build))
    }
}

@MainActor
struct UpdatePreferencesControls: View {
    @EnvironmentObject private var updater: UpdateCoordinator
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(languageStore.language.localized("updates.automaticChecks"), isOn: Binding(
                get: { updater.snapshot.automaticChecks }, set: { updater.setAutomaticChecks($0) }))
                .accessibilityIdentifier("updates.automaticChecks")
            Toggle(languageStore.language.localized("updates.automaticDownloads"), isOn: Binding(
                get: { updater.snapshot.automaticDownloads }, set: { updater.setAutomaticDownloads($0) }))
                .disabled(!updater.snapshot.automaticChecks)
                .accessibilityIdentifier("updates.automaticDownloads")
            Text(languageStore.language.localized("updates.automaticHelp"))
                .font(.caption)
                .foregroundStyle(UpdatePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !updater.snapshot.automaticChecks {
                Text(languageStore.language.localized("updates.downloadRequiresChecks"))
                    .font(.caption)
                    .foregroundStyle(UpdatePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }
}

@MainActor
enum UpdateCopy {
    static func version(_ version: InstalledUpdateVersion, language: AppLanguage) -> String {
        language.localizedFormat("updates.version", version.marketingVersion, String(version.build),
                                 language.localized("updates.channel.\(version.channel.rawValue)"))
    }
    static func version(_ offer: UpdateOffer, language: AppLanguage) -> String {
        version(.init(build: offer.identity.build, marketingVersion: offer.marketingVersion, channel: offer.channel), language: language)
    }
    static func lastCheck(_ snapshot: UpdateSnapshot, language: AppLanguage) -> String {
        guard let date = snapshot.lastSuccessfulCheck else { return language.localized("updates.never") }
        return language.localizedFormat("updates.lastCheck", date.formatted(.dateTime.locale(language.locale).year().month().day().hour().minute()))
    }
    static func progress(_ progress: UpdateDownloadProgress, language: AppLanguage) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return language.localizedFormat("updates.progress", formatter.string(fromByteCount: Int64(clamping: progress.completedBytes)),
            formatter.string(fromByteCount: Int64(clamping: progress.totalBytes)), Int(progress.fraction * 100))
    }
}

/// Fits the incumbent SettingsRow; the details window receives the same environment object.
@MainActor
struct UpdateSettingsSection: View {
    @EnvironmentObject private var updater: UpdateCoordinator
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: UpdateCopy.version(updater.snapshot.installed, language: languageStore.language))
                .font(.callout.weight(.medium))
            Text(languageStore.language.localized("updates.status.\(updater.snapshot.stage.rawValue)"))
                .font(.caption)
                .foregroundStyle(UpdatePalette.secondaryText)
            UpdatePreferencesControls()
            HStack(spacing: 10) {
                Button(languageStore.language.localized("updates.check")) {
                    openWindow(id: "updates")
                    updater.checkManually()
                }
                .disabled([.checking, .downloading, .installing].contains(updater.snapshot.stage))
                .accessibilityIdentifier("updates.check")
                Button(languageStore.language.localized("updates.details")) { openWindow(id: "updates") }
                    .accessibilityIdentifier("updates.details")
            }
        }
    }
}

@MainActor
struct UpdateCommands: Commands {
    @ObservedObject var updater: UpdateCoordinator
    @ObservedObject var languageStore: AppLanguageStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(languageStore.language.localized("updates.check")) {
                openWindow(id: "updates")
                updater.checkManually()
            }
            .disabled([.checking, .downloading, .installing].contains(updater.snapshot.stage))
            .accessibilityIdentifier("updates.menuCheck")
        }
    }
}

@MainActor
struct UpdateBlockerExplanation: View {
    let blocker: UpdateInstallationBlocker
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .session(let reason) = blocker {
                Text(verbatim: languageStore.language.localizedMessage(reason))
                    .font(.callout.weight(.medium))
            }
            Text(languageStore.language.localized(guidanceKey))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("updates.blocker")
            Button(languageStore.language.localized("updates.workspace")) { openWindow(id: "main") }
                .accessibilityIdentifier("updates.workspace")
        }
    }
    private var guidanceKey: String {
        switch blocker {
        case .transmitterConnected: "updates.blocker.transmitterConnected"
        case .connectionInProgress: "updates.blocker.connectionInProgress"
        case .session: "updates.blocker.session"
        case .recovery: "updates.blocker.recovery"
        }
    }
}

/// App-owned consent state decides whether this inline invitation is present.
/// It neither opens a window nor requests keyboard focus.
@MainActor
struct UpdateInvitation: View {
    @EnvironmentObject private var updater: UpdateCoordinator
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        if updater.snapshot.showsOptInInvitation {
            VStack(alignment: .leading, spacing: 10) {
                Text(languageStore.language.localized("updates.invitation.title"))
                    .font(.headline)
                    .accessibilityIdentifier("updates.invitation")
                Text(languageStore.language.localized("updates.invitation.detail"))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text(languageStore.language.localized("updates.privacy"))
                    .font(.caption)
                    .foregroundStyle(UpdatePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(languageStore.language.localized("updates.enable")) { updater.enableAutomaticUpdates() }
                        .accessibilityIdentifier("updates.enable")
                    Button(languageStore.language.localized("updates.skip")) { updater.dismissOptInInvitation() }
                        .accessibilityIdentifier("updates.skip")
                }
            }
            .foregroundStyle(PrototypePalette.primaryText)
        }
    }
}

@MainActor
struct UpdateStatusIndicator: View {
    @EnvironmentObject private var updater: UpdateCoordinator
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if updater.snapshot.offer != nil && [.available, .downloading, .downloaded, .blocked].contains(updater.snapshot.stage) {
            Button { openWindow(id: "updates") } label: {
                Label(languageStore.language.localized("updates.indicator"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("updates.indicator")
        }
    }
}

/// The incumbent palette uses calibrated RGB. Use explicit sRGB for this small
/// text so its resolved light appearance retains at least 4.5:1 contrast.
private enum UpdatePalette {
    static let secondaryText = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 181.0 / 255, green: 183.0 / 255, blue: 187.0 / 255, alpha: 1)
        }
        return NSColor(srgbRed: 96.0 / 255, green: 112.0 / 255, blue: 131.0 / 255, alpha: 1)
    })
}
