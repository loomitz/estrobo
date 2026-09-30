import AccessorySetupKit
import CoreBluetooth
import Foundation
import OSLog
import UIKit

@MainActor
final class AccessorySetupDiagnosticModel: NSObject, ObservableObject {
    private enum AuthorizationOrigin: Equatable {
        case pickerSelection
        case persisted
        case knownSessionUpdate
    }

    @Published private(set) var sessionStatus = "Not activated"
    @Published private(set) var pickerStatus = "Not presented"
    @Published private(set) var authorizationStatus = "Not authorized"
    @Published private(set) var retrievalStatus = "Not attempted"
    @Published private(set) var removalStatus = "Not requested"
    @Published private(set) var redactedIdentifier = "None"
    @Published private(set) var isSceneActive = false
    @Published private(set) var isSessionActivated = false
    @Published private(set) var isPickerPresented = false
    @Published private(set) var isPickerAllowed = false

    let exactBluetoothName = "GDBH-A681"
    let advertisedServiceUUID = "FFC0"

    private struct SafeError: Sendable {
        let domain: String
        let code: Int

        var summary: String { "\(domain) code \(code)" }
    }

    private let logger = Logger(
        subsystem: "mx.loo.estrobo.accessory-setup-spike",
        category: "ask-diagnostic"
    )
    private var session: ASAccessorySession?
    private var sessionGeneration = UUID()
    private var pickerGeneration = UUID()
    private var discoveredObjectIdentifier: ObjectIdentifier?
    private var discoveredBluetoothIdentifier: UUID?
    private var isPickerUpdatePending = false
    private var hasShownExactMatch = false
    private var centralManager: CBCentralManager?
    private var pendingBluetoothIdentifier: UUID?
    private var resolvedBluetoothIdentifier: UUID?
    private var removalGeneration = UUID()
    private var removalTargetIdentifier: UUID?
    private var isRemovalPending = false
    private var requiresRemovalVerification = false

    var canActivate: Bool {
        isSceneActive && session == nil
    }

    var canShowPicker: Bool {
        isSceneActive && isSessionActivated && isPickerAllowed && !isPickerPresented
    }

    var canRemoveAuthorization: Bool {
        guard isSceneActive,
              isSessionActivated,
              !isPickerPresented,
              !isRemovalPending,
              let session,
              session.accessories.count == 1,
              let authorizedIdentifier = session.accessories[0].bluetoothIdentifier else {
            return false
        }
        return authorizedIdentifier == pendingBluetoothIdentifier &&
            authorizedIdentifier == resolvedBluetoothIdentifier
    }

    func sceneBecameActive() {
        isSceneActive = true
    }

    func sceneBecameInactive() {
        isSceneActive = false
    }

    func sceneEnteredBackground() {
        isSceneActive = false
        if isRemovalPending || requiresRemovalVerification {
            let requestWasPending = isRemovalPending
            requiresRemovalVerification = true
            removalStatus = requestWasPending
                ? "Interrupted; activate to verify"
                : "Verification paused; activate to verify"
            stopSession(
                status: "Removal interrupted; reactivate to verify",
                preserveRemovalVerification: true
            )
        } else {
            stopSession(status: "Stopped in background")
        }
    }

    func activate() {
        guard canActivate else { return }

        sessionStatus = "Activating"
        pickerStatus = "Not presented"
        authorizationStatus = "Not authorized"
        retrievalStatus = "Not attempted"
        removalStatus = requiresRemovalVerification
            ? "Verifying after activation"
            : "Not requested"
        redactedIdentifier = "None"
        discoveredObjectIdentifier = nil
        discoveredBluetoothIdentifier = nil
        isPickerUpdatePending = false
        hasShownExactMatch = false
        pendingBluetoothIdentifier = nil
        resolvedBluetoothIdentifier = nil
        removalGeneration = UUID()
        if !requiresRemovalVerification {
            removalTargetIdentifier = nil
        }
        isRemovalPending = false
        isPickerAllowed = false
        centralManager = nil

        let newSession = ASAccessorySession()
        let settings = ASPickerDisplaySettings.default
        settings.discoveryTimeout = .short
        settings.options = [.filterDiscoveryResults]
        newSession.pickerDisplaySettings = settings

        let generation = UUID()
        sessionGeneration = generation
        session = newSession
        newSession.activate(on: .main) { [weak self] event in
            MainActor.assumeIsolated { [weak self] in
                self?.handle(event, generation: generation)
            }
        }
        logger.info("ASK diagnostic session activation requested")
    }

    func showPicker() {
        guard canShowPicker, let session else { return }
        let generation = sessionGeneration
        resetDiscoveryState()
        let currentPickerGeneration = UUID()
        pickerGeneration = currentPickerGeneration
        guard let identity = VerifiedAdvertisementIdentity(
            verifiedAdvertisedServiceUUID: CBUUID(string: advertisedServiceUUID),
            verifiedExactBluetoothName: exactBluetoothName
        ) else {
            safetyStop("Blocked: verified identity is invalid")
            return
        }
        guard let productImage = UIImage(
            systemName: "antenna.radiowaves.left.and.right"
        ) else {
            safetyStop("Blocked: product image unavailable")
            return
        }

        let descriptor = AccessorySetupDescriptorFactory.makeDescriptor(from: identity)
        let item = ASPickerDisplayItem(
            name: "Godox X3ProS diagnostic",
            productImage: productImage,
            descriptor: descriptor
        )
        item.setupOptions = []
        item.renameOptions = []

        isPickerPresented = true
        pickerStatus = "Presentation requested"
        session.showPicker(for: [item]) { [weak self] error in
            let safeError = Self.safeError(error)
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.sessionGeneration,
                      currentPickerGeneration == self.pickerGeneration,
                      self.session != nil else {
                    return
                }
                if let safeError {
                    self.logger.error(
                        "ASK picker error domain=\(safeError.domain, privacy: .public) code=\(safeError.code)"
                    )
                    self.safetyStop("Blocked: picker presentation failed (\(safeError.summary))")
                }
            }
        }
        logger.info("ASK diagnostic picker presentation requested")
    }

    func removeAuthorization() {
        guard canRemoveAuthorization,
              let session,
              session.accessories.count == 1 else {
            safetyStop("Blocked: removal requires one resolved authorization")
            return
        }
        let accessory = session.accessories[0]
        guard accessory.state == .authorized,
              accessory.descriptor.bluetoothServiceUUID == CBUUID(
                  string: advertisedServiceUUID
              ),
              accessory.descriptor.bluetoothNameSubstring == exactBluetoothName,
              let bluetoothIdentifier = accessory.bluetoothIdentifier,
              bluetoothIdentifier == pendingBluetoothIdentifier,
              bluetoothIdentifier == resolvedBluetoothIdentifier else {
            safetyStop("Blocked: removal target does not match resolved identity")
            return
        }

        let generation = sessionGeneration
        let operationGeneration = UUID()
        removalGeneration = operationGeneration
        removalTargetIdentifier = bluetoothIdentifier
        isRemovalPending = true
        requiresRemovalVerification = false
        removalStatus = "Requested; awaiting system result"
        session.removeAccessory(accessory) { [weak self] error in
            let safeError = Self.safeError(error)
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.sessionGeneration,
                      operationGeneration == self.removalGeneration,
                      self.session != nil else {
                    return
                }
                if let safeError {
                    self.logger.error(
                        "ASK removal error domain=\(safeError.domain, privacy: .public) code=\(safeError.code)"
                    )
                    self.beginRemovalVerification(
                        removalStatus: "Result uncertain; activate to verify",
                        sessionStatus: "Removal result uncertain; reactivate to verify"
                    )
                } else if self.isRemovalPending {
                    self.logger.info("ASK explicit authorization removal accepted")
                    self.beginRemovalVerification(
                        removalStatus: "Accepted; activate to verify",
                        sessionStatus: "Removal accepted; reactivate to verify"
                    )
                }
            }
        }
        logger.info("ASK explicit authorization removal requested")
    }

    private func handle(_ event: ASAccessoryEvent, generation: UUID) {
        guard generation == sessionGeneration, session != nil else { return }

        if let safeError = Self.safeError(event.error) {
            logger.error(
                "ASK event error type=\(event.eventType.rawValue) domain=\(safeError.domain, privacy: .public) code=\(safeError.code)"
            )
        }

        switch event.eventType {
        case .activated:
            isSessionActivated = true
            sessionStatus = "Activated"
            logger.info("ASK diagnostic session activated")
            handlePersistedAccessories()
        case .invalidated:
            let removalWasPending = isRemovalPending
            isSessionActivated = false
            isPickerPresented = false
            isPickerAllowed = false
            centralManager?.delegate = nil
            centralManager = nil
            pendingBluetoothIdentifier = nil
            resolvedBluetoothIdentifier = nil
            removalGeneration = UUID()
            isRemovalPending = false
            if removalWasPending {
                requiresRemovalVerification = true
                removalStatus = "Session invalidated; activate to verify"
                enterRemovalVerificationPresentation()
            } else if !requiresRemovalVerification {
                removalTargetIdentifier = nil
            }
            session = nil
            sessionStatus = "Invalidated"
            logger.info("ASK diagnostic session invalidated")
        case .accessoryDiscovered:
            handleDiscoveredAccessory(
                event.accessory,
                generation: generation,
                pickerGeneration: pickerGeneration
            )
        case .accessoryAdded:
            isPickerAllowed = false
            let origin: AuthorizationOrigin = isKnownAuthorizedIdentifier(event.accessory)
                ? .knownSessionUpdate
                : .pickerSelection
            handleAuthorizedAccessory(event.accessory, origin: origin)
        case .accessoryChanged:
            isPickerAllowed = false
            guard isKnownAuthorizedIdentifier(event.accessory) else {
                safetyStop("Blocked: changed authorization has an unknown identifier")
                return
            }
            handleAuthorizedAccessory(event.accessory, origin: .knownSessionUpdate)
        case .accessoryRemoved:
            guard isRemovalPending,
                  let expectedIdentifier = removalTargetIdentifier,
                  expectedIdentifier == resolvedBluetoothIdentifier,
                  expectedIdentifier == pendingBluetoothIdentifier else {
                safetyStop("Blocked: removal event is not tied to the explicit resolved request")
                return
            }
            if let removedAccessory = event.accessory {
                guard removedAccessory.bluetoothIdentifier == expectedIdentifier,
                      removedAccessory.descriptor.bluetoothServiceUUID == CBUUID(
                          string: advertisedServiceUUID
                      ),
                      removedAccessory.descriptor.bluetoothNameSubstring == exactBluetoothName else {
                    safetyStop("Blocked: removed authorization has an unknown identity")
                    return
                }
            }
            logger.info("ASK accessory authorization removal event received")
            beginRemovalVerification(
                removalStatus: "Accepted; activate to verify",
                sessionStatus: "Removal accepted; reactivate to verify"
            )
        case .pickerDidPresent:
            isPickerPresented = true
            pickerStatus = "Presented"
            logger.info("ASK picker presented")
        case .pickerDidDismiss:
            isPickerPresented = false
            pickerGeneration = UUID()
            resetDiscoveryState()
            pickerStatus = "Dismissed"
            logger.info("ASK picker dismissed")
        case .pickerSetupFailed:
            isPickerPresented = false
            if let safeError = Self.safeError(event.error) {
                safetyStop("Blocked: picker setup failed (\(safeError.summary))")
            } else {
                safetyStop("Blocked: picker setup failed")
            }
        case .pickerSetupBridging:
            safetyStop("Blocked: unexpected transport bridging")
        case .pickerSetupPairing:
            safetyStop("Blocked: unexpected Bluetooth pairing")
        case .pickerSetupRename:
            safetyStop("Blocked: unexpected accessory rename")
        case .migrationComplete:
            safetyStop("Blocked: unexpected migration event")
        case .unknown:
            safetyStop("Blocked: unknown ASK event")
        @unknown default:
            safetyStop("Blocked: unrecognized ASK event")
        }
    }

    private func handlePersistedAccessories() {
        guard let session else { return }
        if requiresRemovalVerification {
            switch session.accessories.count {
            case 0:
                requiresRemovalVerification = false
                removalTargetIdentifier = nil
                removalStatus = "Verified removed"
                authorizationStatus = "Not authorized"
                retrievalStatus = "Not attempted"
                redactedIdentifier = "None"
                isPickerAllowed = true
                pickerStatus = "Ready to present"
                logger.info("ASK authorization removal verified after reactivation")
            case 1:
                guard let removalTargetIdentifier,
                      session.accessories[0].bluetoothIdentifier == removalTargetIdentifier,
                      session.accessories[0].state == .authorized,
                      session.accessories[0].descriptor.bluetoothServiceUUID == CBUUID(
                          string: advertisedServiceUUID
                      ),
                      session.accessories[0].descriptor.bluetoothNameSubstring == exactBluetoothName else {
                    safetyStop("Blocked: removal verification found an unknown authorization")
                    return
                }
                requiresRemovalVerification = false
                self.removalTargetIdentifier = nil
                removalStatus = "Not removed; authorization remains"
                isPickerAllowed = false
                pickerStatus = "Skipped: existing authorization"
                handleAuthorizedAccessory(session.accessories[0], origin: .persisted)
            default:
                safetyStop("Blocked: removal verification found multiple authorizations")
            }
            return
        }
        switch session.accessories.count {
        case 0:
            isPickerAllowed = true
            pickerStatus = "Ready to present"
        case 1:
            isPickerAllowed = false
            pickerStatus = "Skipped: existing authorization"
            handleAuthorizedAccessory(session.accessories[0], origin: .persisted)
        default:
            safetyStop("Blocked: more than one persisted authorization")
        }
    }

    private func handleDiscoveredAccessory(
        _ accessory: ASAccessory?,
        generation: UUID,
        pickerGeneration: UUID
    ) {
        guard isPickerPresented else { return }
        guard let discoveredAccessory = accessory as? ASDiscoveredAccessory else {
            safetyStop("Blocked: discovery event without an accessory")
            return
        }
        guard advertisementMatchesExactly(discoveredAccessory) else {
            return
        }

        let objectIdentifier = ObjectIdentifier(discoveredAccessory)
        let bluetoothIdentifier = discoveredAccessory.bluetoothIdentifier
        if let discoveredBluetoothIdentifier,
           let bluetoothIdentifier,
           discoveredBluetoothIdentifier != bluetoothIdentifier {
                safetyStop("Blocked: more than one exact advertisement match")
                return
        } else if bluetoothIdentifier == nil,
                  let discoveredObjectIdentifier,
                  discoveredObjectIdentifier != objectIdentifier {
                safetyStop("Blocked: ambiguous repeated exact match")
                return
        } else if discoveredBluetoothIdentifier == nil,
                  bluetoothIdentifier != nil,
                  let discoveredObjectIdentifier,
                  discoveredObjectIdentifier != objectIdentifier {
                safetyStop("Blocked: ambiguous exact match identity")
                return
        }
        if discoveredBluetoothIdentifier == nil {
            discoveredBluetoothIdentifier = bluetoothIdentifier
        }
        if discoveredObjectIdentifier == nil {
            discoveredObjectIdentifier = objectIdentifier
        }
        guard discoveredObjectIdentifier == objectIdentifier ||
                discoveredBluetoothIdentifier == bluetoothIdentifier else {
            safetyStop("Blocked: ambiguous exact match identity")
            return
        }
        guard !hasShownExactMatch, !isPickerUpdatePending else {
            return
        }
        guard let session else { return }
        guard let productImage = UIImage(
            systemName: "antenna.radiowaves.left.and.right"
        ) else {
            safetyStop("Blocked: product image unavailable")
            return
        }

        discoveredObjectIdentifier = objectIdentifier
        let displayItem = ASDiscoveredDisplayItem(
            name: "Godox X3ProS diagnostic",
            productImage: productImage,
            accessory: discoveredAccessory
        )
        displayItem.setupOptions = []
        displayItem.renameOptions = []
        isPickerUpdatePending = true
        session.updatePicker(showing: [displayItem]) { [weak self] error in
            let safeError = Self.safeError(error)
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.sessionGeneration,
                      pickerGeneration == self.pickerGeneration,
                      self.isPickerPresented,
                      self.session != nil else {
                    return
                }
                self.isPickerUpdatePending = false
                if let safeError {
                    self.safetyStop("Blocked: picker update failed (\(safeError.summary))")
                } else {
                    self.hasShownExactMatch = true
                    self.pickerStatus = "One exact match shown"
                    self.logger.info("ASK picker updated with one exact advertisement match")
                }
            }
        }
    }

    private func advertisementMatchesExactly(_ accessory: ASDiscoveredAccessory) -> Bool {
        guard let advertisementData = accessory.bluetoothAdvertisementData else {
            return false
        }
        guard advertisementData[CBAdvertisementDataLocalNameKey] as? String == exactBluetoothName else {
            return false
        }
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        return services.contains(CBUUID(string: advertisedServiceUUID))
    }

    private func handleAuthorizedAccessory(
        _ accessory: ASAccessory?,
        origin: AuthorizationOrigin
    ) {
        guard let accessory else {
            safetyStop("Blocked: authorization event without an accessory")
            return
        }
        guard accessory.descriptor.bluetoothServiceUUID == CBUUID(
            string: advertisedServiceUUID
        ), accessory.descriptor.bluetoothNameSubstring == exactBluetoothName else {
            safetyStop("Blocked: authorized descriptor does not match verified identity")
            return
        }
        guard accessory.state == .authorized else {
            safetyStop("Blocked: accessory is not fully authorized")
            return
        }
        guard let bluetoothIdentifier = accessory.bluetoothIdentifier else {
            safetyStop("Blocked: authorized accessory has no Bluetooth identifier")
            return
        }
        switch origin {
        case .pickerSelection:
            guard hasShownExactMatch else {
                safetyStop("Blocked: authorization was not selected from the exact match")
                return
            }
            if let discoveredBluetoothIdentifier,
               discoveredBluetoothIdentifier != bluetoothIdentifier {
                safetyStop("Blocked: selected and authorized identifiers do not match")
                return
            }
        case .persisted:
            authorizationStatus = "Authorized (persisted)"
        case .knownSessionUpdate:
            guard isKnownAuthorizedIdentifier(accessory) else {
                safetyStop("Blocked: authorization update changed identifier")
                return
            }
        }
        if let pendingBluetoothIdentifier,
           pendingBluetoothIdentifier != bluetoothIdentifier {
            safetyStop("Blocked: authorized identifier changed")
            return
        }

        pendingBluetoothIdentifier = bluetoothIdentifier
        redactedIdentifier = Self.redact(bluetoothIdentifier)
        if origin == .pickerSelection {
            authorizationStatus = "Authorized by exact picker match"
        } else if origin == .knownSessionUpdate {
            authorizationStatus = "Authorized"
        }
        if resolvedBluetoothIdentifier == bluetoothIdentifier {
            return
        }
        retrievalStatus = "Waiting for CoreBluetooth"
        logger.info(
            "ASK accessory authorized identifier=\(self.redactedIdentifier, privacy: .public)"
        )

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        } else if centralManager?.state == .poweredOn {
            resolveAuthorizedPeripheral()
        }
    }

    private func isKnownAuthorizedIdentifier(_ accessory: ASAccessory?) -> Bool {
        guard let identifier = accessory?.bluetoothIdentifier else { return false }
        return identifier == pendingBluetoothIdentifier ||
            identifier == resolvedBluetoothIdentifier
    }

    private func resetDiscoveryState() {
        discoveredObjectIdentifier = nil
        discoveredBluetoothIdentifier = nil
        isPickerUpdatePending = false
        hasShownExactMatch = false
    }

    private func resolveAuthorizedPeripheral() {
        guard let centralManager, let pendingBluetoothIdentifier else {
            safetyStop("Blocked: missing authorized identifier")
            return
        }
        guard resolvedBluetoothIdentifier == nil else { return }
        let peripherals = centralManager.retrievePeripherals(
            withIdentifiers: [pendingBluetoothIdentifier]
        )
        guard peripherals.count == 1,
              peripherals[0].identifier == pendingBluetoothIdentifier else {
            safetyStop("Blocked: authorized identifier did not resolve exactly once")
            return
        }

        resolvedBluetoothIdentifier = pendingBluetoothIdentifier
        retrievalStatus = "Resolved exactly once; not connected"
        logger.info(
            "CoreBluetooth resolved authorized identifier once without connecting identifier=\(self.redactedIdentifier, privacy: .public)"
        )
    }

    private func safetyStop(_ status: String) {
        logger.error("ASK diagnostic safety stop: \(status, privacy: .public)")
        let preserveRemovalVerification = (isRemovalPending || requiresRemovalVerification) &&
            removalTargetIdentifier != nil
        if preserveRemovalVerification {
            requiresRemovalVerification = true
            removalStatus = "Blocked; activate to verify"
        }
        stopSession(
            status: status,
            preserveRemovalVerification: preserveRemovalVerification
        )
    }

    private func beginRemovalVerification(
        removalStatus: String,
        sessionStatus: String
    ) {
        guard removalTargetIdentifier != nil else {
            safetyStop("Blocked: removal verification has no target")
            return
        }
        requiresRemovalVerification = true
        self.removalStatus = removalStatus
        logger.info("ASK removal requires verification in a fresh session")
        stopSession(
            status: sessionStatus,
            preserveRemovalVerification: true
        )
    }

    private func stopSession(
        status: String,
        preserveRemovalVerification: Bool = false
    ) {
        let shouldPreserveRemovalVerification = preserveRemovalVerification ||
            ((isRemovalPending || requiresRemovalVerification) &&
                removalTargetIdentifier != nil)
        let previousSession = session
        session = nil
        sessionGeneration = UUID()
        pickerGeneration = UUID()
        isSessionActivated = false
        isPickerPresented = false
        isPickerAllowed = false
        resetDiscoveryState()
        pendingBluetoothIdentifier = nil
        resolvedBluetoothIdentifier = nil
        removalGeneration = UUID()
        isRemovalPending = false
        if shouldPreserveRemovalVerification {
            requiresRemovalVerification = true
            enterRemovalVerificationPresentation()
        } else {
            removalTargetIdentifier = nil
            requiresRemovalVerification = false
        }
        centralManager?.delegate = nil
        centralManager = nil
        sessionStatus = status
        previousSession?.invalidate()
    }

    private func enterRemovalVerificationPresentation() {
        pickerStatus = "Unavailable: verification pending"
        authorizationStatus = "Unknown; fresh activation required"
        retrievalStatus = "Cleared; fresh activation required"
        redactedIdentifier = removalTargetIdentifier.map(Self.redact) ?? "None"
        isPickerPresented = false
        isPickerAllowed = false
    }

    nonisolated private static func safeError(_ error: Error?) -> SafeError? {
        guard let error else { return nil }
        let nsError = error as NSError
        return SafeError(domain: nsError.domain, code: nsError.code)
    }

    nonisolated private static func redact(_ identifier: UUID) -> String {
        "CB-REDACTED-\(identifier.uuidString.suffix(4))"
    }
}

extension AccessorySetupDiagnosticModel: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === centralManager else { return }
        switch central.state {
        case .poweredOn:
            resolveAuthorizedPeripheral()
        case .poweredOff:
            retrievalStatus = "Waiting: Bluetooth is off"
        case .unauthorized:
            retrievalStatus = "Blocked: Bluetooth permission denied"
        case .unsupported:
            safetyStop("Blocked: Bluetooth unsupported")
        case .resetting:
            retrievalStatus = "Waiting: Bluetooth is resetting"
        case .unknown:
            retrievalStatus = "Waiting: Bluetooth state unknown"
        @unknown default:
            safetyStop("Blocked: unrecognized Bluetooth state")
        }
    }
}
