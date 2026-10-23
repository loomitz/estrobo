import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

/// Experimental façade only. Real controller, real simulator, in-memory test ports.
@MainActor
public final class ExperimentRuntime {
    private let controller: GodoxSessionController
    private let transport: SimulatedRadioTransport
    private var phaseSubscription: AnyCancellable?

    public init() {
        transport = SimulatedRadioTransport()
        controller = GodoxSessionController(
            transport: transport,
            deadlineScheduler: LiveSessionDeadlineScheduler(),
            visibilityPreferences: MemoryGroupVisibilityPreferences(),
            restorationStore: MemoryRestorationRepository(),
            savedRadioStore: EmptySavedRadioRepository(),
            changeDeliveryPreferences: MemoryChangeDeliveryPreferences(),
            radioConnectionPreferences: MemoryRadioConnectionPreferences(),
            transmitterProfilePreferences: MemoryTransmitterProfilePreferences(),
            studioLibraryStore: MemoryStudioLibraryRepository()
        )
        precondition(controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b, .c],
            assignedFlashModelIDs: [.b: ["ad600pro-ii"], .c: ["ad400pro"]]
        ))
        phaseSubscription = controller.$phase.sink { [weak self] phase in
            self?.emit(["event": "phase", "phase": String(describing: phase)])
        }
    }

    public func hello() {
        emit(["event": "hello", "protocol": 1, "engine": "real GodoxSessionController", "transport": "real SimulatedRadioTransport"])
    }

    public func handle(_ line: String) async -> Bool {
        guard let data = line.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = request["id"] as? Int,
              let command = request["command"] as? String else {
            emit(["event": "error", "message": "invalid request"])
            return true
        }
        do {
            switch command {
            case "start":
                controller.startScanning()
                try await waitUntil { !self.controller.devices.isEmpty }
                controller.selectedDeviceID = SimulatedRadioTransport.candidate.id
                controller.radioCode = "111111" // synthetic simulator fixture
                controller.connectSelectedDevice()
                try await waitUntil { self.controller.phase == .ready }
                emit(["event": "result", "id": id, "ok": true, "phase": "ready"])
            case "adjust":
                guard controller.phase == .ready else { throw ExperimentError.notReady }
                let index = min(controller.powerIndex(for: .c) + 1, controller.allowedPowers(for: .c).count - 1)
                controller.setDraftPowerIndex(index, for: .c)
                guard controller.canApply else { throw ExperimentError.notReady }
                controller.applyPendingChanges()
                try await waitUntil { self.controller.phase == .ready && self.controller.pendingCount == 0 }
                emit(["event": "result", "id": id, "ok": true, "phase": "ready", "pending": controller.pendingCount])
            case "shutdown":
                controller.suspendForInactiveScene()
                transport.forceResetConnection()
                emit(["event": "result", "id": id, "ok": true, "phase": "shutdown"])
                return false
            default:
                emit(["event": "result", "id": id, "ok": false, "error": "unknown command"])
            }
        } catch {
            emit(["event": "result", "id": id, "ok": false, "error": String(describing: error)])
        }
        return true
    }

    public func close() {
        controller.suspendForInactiveScene()
        transport.forceResetConnection()
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ExperimentError.deadline
    }

    private func emit(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        FileHandle.standardOutput.write(data + Data([10]))
    }

    private enum ExperimentError: Error { case deadline, notReady }
}
