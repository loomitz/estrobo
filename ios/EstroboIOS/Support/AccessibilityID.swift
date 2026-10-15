import Foundation
import EstroboBluetooth

/// Stable, non-localized identifiers shared by the app and its UI-test target.
enum EstroboAccessibilityID {
    static let appRoot = "estrobo.app.root"
    static let onboardingRoot = "estrobo.onboarding.root"
    static let runtimeDemo = "estrobo.onboarding.runtime.demo"
    static let runtimeLiveEducation = "estrobo.onboarding.runtime.live-education"
    static let runtimeLiveAcknowledge = "estrobo.onboarding.runtime.live-acknowledge"
    static let runtimeLiveStart = "estrobo.onboarding.runtime.live-start"
    static let workspaceSetup = "estrobo.onboarding.workspace"
    static let workspaceProfile = "estrobo.onboarding.profile"
    static let workspaceContinue = "estrobo.onboarding.workspace.continue"
    static let demoBanner = "estrobo.demo.banner"
    static let demoLab = "estrobo.demo.lab"
    static let demoRestart = "estrobo.demo.restart"
    static let demoExit = "estrobo.demo.exit"

    static let workspaceRoot = "estrobo.workspace.root"
    static let phoneLayout = "estrobo.layout.phone"
    static let tabletLayout = "estrobo.layout.tablet"
    static let tabletMatrix = "estrobo.layout.tablet.matrix"
    static let sessionStatus = "estrobo.session.status"
    static let connectionSheet = "estrobo.connection.sheet"
    static let connectionScan = "estrobo.connection.scan"
    static let connectionRadioCode = "estrobo.connection.radio-code"
    static let connectionRemember = "estrobo.connection.remember"
    static let connectionConnect = "estrobo.connection.connect"
    static let connectionPWOK = "estrobo.connection.pwok"
    static let connectionSync = "estrobo.connection.sync"
    static let connectionSyncCancel = "estrobo.connection.sync.cancel"
    static let connectionPermissionDenied = "estrobo.connection.permission-denied"
    static let connectionDismiss = "estrobo.connection.dismiss"
    static let recoveryGate = "estrobo.recovery.gate"
    static let recoveryWrongDevice = "estrobo.recovery.wrong-device"
    static let recoveryRequiredDevice = "estrobo.recovery.required-device"
    static let recoveryPrepare = "estrobo.recovery.prepare"
    static let recoveryApply = "estrobo.recovery.apply"

    static let tabGroups = "estrobo.tab.groups"
    static let tabGlobal = "estrobo.tab.global"
    static let tabPresets = "estrobo.tab.presets"
    static let tabSettings = "estrobo.tab.settings"
    static let sidebarConnection = "estrobo.sidebar.connection"
    static let sidebarGroups = "estrobo.sidebar.groups"
    static let sidebarGlobal = "estrobo.sidebar.global"
    static let sidebarPresets = "estrobo.sidebar.presets"
    static let sidebarSavedRadios = "estrobo.sidebar.saved-radios"
    static let sidebarSettings = "estrobo.sidebar.settings"
    static let sidebarDemo = "estrobo.sidebar.demo"
    static let groupsList = "estrobo.groups.list"
    static let globalScreen = "estrobo.global.root"
    static let presetsScreen = "estrobo.presets.root"
    static let settingsScreen = "estrobo.settings.root"
    static let apply = "estrobo.changes.apply"
    static let discard = "estrobo.changes.discard"
    static let pendingStatus = "estrobo.changes.pending"
    static let deliveryMode = "estrobo.changes.delivery-mode"
    static let deliveryAutomaticFeedback = "estrobo.changes.delivery.automatic-feedback"

    static let globalBeep = "estrobo.global.beep"
    static let globalModeling = "estrobo.global.modeling"
    static let globalStandby = "estrobo.global.standby"
    static let globalPowerDecrease = "estrobo.global.power.decrease"
    static let globalPowerIncrease = "estrobo.global.power.increase"
    static let globalPowerSlider = "estrobo.global.power.slider"
    static let globalPowerStatus = "estrobo.global.power.status"
    static let testSend = "estrobo.test.send"
    static let testOpenConfirmation = "estrobo.test.open-confirmation"
    static let testConfirmation = "estrobo.test.confirmation"
    static let testConfirm = "estrobo.test.confirm"
    static let testCancel = "estrobo.test.cancel"
    static let testPending = "estrobo.test.pending"
    static let testSent = "estrobo.test.sent"
    static let testFailed = "estrobo.test.failed"
    static let multiToggle = "estrobo.multi.toggle"
    static let multiEnabled = "estrobo.multi.enabled"
    static let multiPower = "estrobo.multi.power"
    static let multiCount = "estrobo.multi.count"
    static let multiHertz = "estrobo.multi.hertz"
    static let multiLimit = "estrobo.multi.limit"

    static let presetName = "estrobo.preset.name"
    static let presetSave = "estrobo.preset.save"
    static let presetEmpty = "estrobo.preset.empty"
    static let presetDeleteConfirmation = "estrobo.preset.delete.confirmation"
    static let presetDeleteConfirm = "estrobo.preset.delete.confirm"
    static let presetDeleteCancel = "estrobo.preset.delete.cancel"
    static let savedRadios = "estrobo.settings.saved-radios"
    static let savedRadioEmpty = "estrobo.saved-radio.empty"
    static let savedRadioForgetConfirmation = "estrobo.saved-radio.forget.confirmation"
    static let savedRadioForgetConfirm = "estrobo.saved-radio.forget.confirm"
    static let savedRadioForgetCancel = "estrobo.saved-radio.forget.cancel"
    static let compatibility = "estrobo.settings.compatibility"
    static let compatibilityEdit = "estrobo.settings.compatibility.edit"
    static let compatibilitySave = "estrobo.settings.compatibility.save"
    static let compatibilityConnection = "estrobo.settings.compatibility.connection"
    static let compatibilityProfile = "estrobo.settings.compatibility.profile"
    static let compatibilityGroupsSummary = "estrobo.settings.compatibility.groups-summary"
    static let compatibilityAddGroups = "estrobo.settings.compatibility.add-groups"
    static let compatibilityAddGroupsSheet = "estrobo.settings.compatibility.add-groups.sheet"
    static let compatibilityAddGroupsConfirm = "estrobo.settings.compatibility.add-groups.confirm"
    static let language = "estrobo.settings.language"
    static let appearance = "estrobo.settings.appearance"
    static let sceneSafety = "estrobo.settings.scene-safety"
    static let privacyPolicy = "estrobo.settings.privacy-policy"
    static let support = "estrobo.settings.support"

    static func workspaceGroup(_ group: String) -> String {
        "estrobo.onboarding.group.\(group.lowercased())"
    }

    static func workspaceModel(_ group: String) -> String {
        "estrobo.onboarding.model.\(group.lowercased())"
    }

    static func workspaceCapability(_ group: String, model: String) -> String {
        "estrobo.onboarding.capability.\(group.lowercased()).\(model.lowercased())"
    }

    static func candidate(_ identifier: UUID) -> String {
        "estrobo.connection.candidate.\(redactedPeripheralToken(identifier))"
    }

    static func groupRow(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).row"
    }

    static func groupDetail(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).detail"
    }

    static func groupDetailOpen(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).detail.open"
    }

    static func groupMode(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).mode"
    }

    static func groupPower(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).power"
    }

    static func groupPowerSlider(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).power.slider"
    }

    static func groupDetailPower(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).detail.power"
    }

    static func groupDetailPowerSlider(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).detail.power.slider"
    }

    static func groupPowerIncrease(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).power.increase"
    }

    static func groupPowerDecrease(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).power.decrease"
    }

    static func groupModeling(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).modeling"
    }

    static func groupModelingManualSlider(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).modeling.manual.slider"
    }

    static func groupStandbyOverlay(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).standby-overlay"
    }

    static func groupBeep(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).beep"
    }

    static func groupConfirmation(_ group: String) -> String {
        "estrobo.group.\(group.lowercased()).confirmation"
    }

    static func multiParticipant(_ group: String) -> String {
        "estrobo.multi.participant.\(group.lowercased())"
    }

    static func preset(_ identifier: UUID) -> String {
        "estrobo.preset.\(identifier.uuidString.lowercased())"
    }

    static func presetLoadLocal(_ identifier: UUID) -> String {
        "\(preset(identifier)).load-local"
    }

    static func presetSync(_ identifier: UUID) -> String {
        "\(preset(identifier)).sync"
    }

    static func presetDelete(_ identifier: UUID) -> String {
        "\(preset(identifier)).delete"
    }

    static func savedRadio(_ identifier: UUID) -> String {
        "estrobo.saved-radio.\(redactedPeripheralToken(identifier))"
    }

    static func savedRadioForget(_ identifier: UUID) -> String {
        "\(savedRadio(identifier)).forget"
    }

    static func savedRadioAutoConnect(_ identifier: UUID) -> String {
        "\(savedRadio(identifier)).auto-connect"
    }

    static func demoScenario(_ scenario: SimulatedRadioScenario) -> String {
        "estrobo.demo.scenario.\(scenario.rawValue)"
    }

    static func compatibilityGroup(_ group: String) -> String {
        "estrobo.settings.compatibility.group.\(group.lowercased())"
    }

    static func compatibilityGroupRow(_ group: String) -> String {
        "\(compatibilityGroup(group)).row"
    }

    static func compatibilityGroupChoice(_ group: String) -> String {
        "\(compatibilityGroup(group)).choice"
    }

    static func compatibilityModels(_ group: String) -> String {
        "\(compatibilityGroup(group)).models"
    }

    static func compatibilityModelCount(_ group: String) -> String {
        "\(compatibilityModels(group)).selected-count"
    }

    static func compatibilityModel(_ group: String, model: String) -> String {
        "\(compatibilityModels(group)).\(model.lowercased())"
    }

    private static func redactedPeripheralToken(_ identifier: UUID) -> String {
        "redacted-\(identifier.uuidString.suffix(4).lowercased())"
    }
}
