import Foundation
import Combine
import XCTest
@testable import EstroboCore

@MainActor
final class GodoxSessionControllerTests: XCTestCase {
    private let device = RadioCandidate(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        name: "GDBH-XCTest",
        rssi: -42
    )

    func testPWOKAndSyncStartA0BeforeSerialA1Delivery() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)

        try await connectAndSynchronizeTransport(fixture)

        XCTAssertEqual(fixture.transport.sentCommands.prefix(2), [.authentication, .sync])
        XCTAssertEqual(fixture.controller.phase, .synchronizing)
        XCTAssertTrue(fixture.scheduler.fire(.valueSynchronizationSettle))
        XCTAssertEqual(fixture.transport.controlPayloads.count, 1)
        XCTAssertNotNil(
            SafeGodoxProtocol.globalSnapshot(from: fixture.transport.controlPayloads[0]),
            "The connection synchronization must start with one complete A0 frame."
        )
        XCTAssertEqual(Set(fixture.restorations.points?.keys.map { $0 } ?? []), [.b, .c])

        acknowledgeGATTWrite(fixture.transport)
        XCTAssertEqual(fixture.transport.controlPayloads.count, 2)
        XCTAssertEqual(decodedGroup(fixture.transport.controlPayloads[1]), .b)

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.controlWriteCompleted)
        XCTAssertEqual(
            fixture.transport.controlPayloads.count,
            2,
            "C must not be submitted until B has both its GATT receipt and FEC8 response."
        )

        fixture.transport.emit(.notification(.control, Data([0xF0, 0xA1])))
        XCTAssertEqual(fixture.transport.controlPayloads.count, 3)
        XCTAssertEqual(decodedGroup(fixture.transport.controlPayloads[2]), .c)

        acknowledgeGroupWrite(fixture.transport)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertNil(fixture.restorations.points)
        XCTAssertEqual(fixture.restorations.clearCount, 1)
    }

    func testAutomaticInitialValueSynchronizationDefersHeartbeatUntilReady() async throws {
        let fixture = makeFixture(
            stagesNewWorkingGroupsAtSafeMinimum: true
        )
        XCTAssertTrue(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b],
            assignedFlashModelIDs: [.b: ["ad400pro-ii"]]
        ))

        try await connectAndSynchronizeTransport(fixture)

        XCTAssertFalse(fixture.controller.isInitialValueSynchronizationAwaitingConfirmation)
        XCTAssertFalse(fixture.controller.canConfirmInitialValueSynchronization)
        XCTAssertEqual(
            fixture.controller.initialValueSynchronizationPreview,
            ["B · M · 1/512 +0.0"]
        )
        XCTAssertTrue(fixture.controller.isSynchronizingValues)
        XCTAssertTrue(fixture.transport.controlPayloads.isEmpty)
        XCTAssertEqual(fixture.scheduler.activeCount(.valueSynchronizationSettle), 1)

        fixture.transport.emit(.notification(
            .control,
            Data([0xF0, 0xE0, 0x00, 0x00, 0x00, 0x00])
        ))
        XCTAssertTrue(
            fixture.transport.controlPayloads.isEmpty,
            "A heartbeat must be deferred while connection synchronization owns the control channel."
        )

        XCTAssertTrue(fixture.scheduler.fire(.valueSynchronizationSettle))
        XCTAssertEqual(fixture.transport.controlPayloads.count, 1)
        XCTAssertNotNil(
            SafeGodoxProtocol.globalSnapshot(from: fixture.transport.controlPayloads[0])
        )

        acknowledgeGATTWrite(fixture.transport)
        XCTAssertEqual(fixture.transport.controlPayloads.count, 2)
        let groupWrite = try XCTUnwrap(
            SafeGodoxProtocol.groupSnapshot(from: fixture.transport.controlPayloads[1])
        )
        XCTAssertEqual(groupWrite.0, .b)
        XCTAssertEqual(groupWrite.1.operatingMode, .manual)
        XCTAssertEqual(groupWrite.1.power, ManualPower.value(decimal: 10))
        XCTAssertEqual(groupWrite.1.modelingState.value, .off)

        acknowledgeGroupWrite(fixture.transport)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertEqual(
            fixture.transport.controlPayloads.last,
            Data([0xF0, 0xE0]),
            "The one deferred heartbeat may be released only after Ready."
        )
    }

    func testInactiveSceneDropsUnconfirmedInitialValueSynchronization() async throws {
        let fixture = makeFixture(
            requiresExplicitInitialValueSynchronizationConfirmation: true
        )
        completeWorkspace(fixture.controller)

        try await connectAndSynchronizeTransport(fixture)
        XCTAssertTrue(fixture.controller.isInitialValueSynchronizationAwaitingConfirmation)

        fixture.controller.suspendForInactiveScene()
        fixture.controller.resumeActiveScene()
        fixture.controller.confirmInitialValueSynchronization()

        XCTAssertFalse(fixture.controller.isInitialValueSynchronizationAwaitingConfirmation)
        XCTAssertFalse(fixture.controller.canConfirmInitialValueSynchronization)
        XCTAssertFalse(fixture.scheduler.fire(.valueSynchronizationSettle))
        XCTAssertTrue(fixture.transport.controlPayloads.isEmpty)
        XCTAssertEqual(fixture.transport.disconnectCount, 1)
        XCTAssertEqual(fixture.transport.forceResetCount, 1)
    }

    func testCancelDropsUnconfirmedInitialValueSynchronization() async throws {
        let fixture = makeFixture(
            requiresExplicitInitialValueSynchronizationConfirmation: true
        )
        completeWorkspace(fixture.controller)

        try await connectAndSynchronizeTransport(fixture)
        XCTAssertTrue(fixture.controller.isInitialValueSynchronizationAwaitingConfirmation)

        fixture.controller.cancelConnectionAttempt()
        fixture.controller.confirmInitialValueSynchronization()

        XCTAssertEqual(fixture.controller.phase, .disconnecting)
        XCTAssertFalse(fixture.controller.isInitialValueSynchronizationAwaitingConfirmation)
        XCTAssertFalse(fixture.scheduler.fire(.valueSynchronizationSettle))
        XCTAssertTrue(fixture.transport.controlPayloads.isEmpty)
        XCTAssertEqual(fixture.transport.disconnectCount, 1)
    }

    func testNewWorkingGroupIsStagedOffAtItsCommonMinimum() async throws {
        let fixture = makeFixture(
            requiresExplicitInitialValueSynchronizationConfirmation: true,
            stagesNewWorkingGroupsAtSafeMinimum: true
        )
        let profileID = TransmitterProfile.observedGDBH.id

        XCTAssertTrue(fixture.controller.completeWorkspaceConfiguration(
            profileID: profileID,
            selectedGroups: [.b],
            assignedFlashModelIDs: [.b: ["ad400pro-ii"]]
        ))
        try await connectAndSynchronizeTransport(fixture)
        fixture.controller.confirmInitialValueSynchronization()
        XCTAssertTrue(fixture.scheduler.fire(.valueSynchronizationSettle))
        acknowledgeGATTWrite(fixture.transport)
        acknowledgeGroupWrite(fixture.transport)
        XCTAssertEqual(fixture.controller.phase, .ready)

        fixture.controller.disconnect()
        fixture.transport.emit(.stateChanged(.idle))
        XCTAssertEqual(fixture.controller.phase, .idle)
        fixture.controller.beginWorkspaceConfiguration()
        XCTAssertTrue(fixture.controller.isReconfiguringWorkspace)
        XCTAssertTrue(fixture.controller.completeWorkspaceConfiguration(
            profileID: profileID,
            selectedGroups: [.b, .c],
            assignedFlashModelIDs: [
                .b: ["ad400pro-ii"],
                .c: ["ad400pro-ii"],
            ]
        ))

        let staged = fixture.controller.groupDraft(.c).draft
        XCTAssertEqual(staged.operatingMode, .off)
        XCTAssertEqual(staged.power, ManualPower.value(decimal: 10))
        XCTAssertEqual(staged.modelingState.value, .off)
        XCTAssertFalse(staged.beepEnabled)
        XCTAssertEqual(staged.compensationByte, 0)

        let writesBeforeSecondConnection = fixture.transport.controlPayloads.count
        try await connectAndSynchronizeTransport(fixture)
        XCTAssertEqual(
            fixture.controller.initialValueSynchronizationPreview,
            ["B · M · 1/512 +0.0", "C · OFF · 1/512 +0.0"]
        )
        fixture.controller.confirmInitialValueSynchronization()
        guard fixture.scheduler.fire(.valueSynchronizationSettle) else {
            XCTFail("The confirmed second connection must schedule value synchronization.")
            return
        }
        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeSecondConnection + 1)

        acknowledgeGATTWrite(fixture.transport)
        let secondConnectionBPayload = try XCTUnwrap(
            fixture.transport.controlPayloads.dropFirst(writesBeforeSecondConnection + 1).first
        )
        let secondConnectionB = try XCTUnwrap(
            SafeGodoxProtocol.groupSnapshot(from: secondConnectionBPayload)
        )
        XCTAssertEqual(secondConnectionB.0, .b)
        XCTAssertEqual(secondConnectionB.1.power, ManualPower.value(decimal: 10))

        acknowledgeGroupWrite(fixture.transport)
        let secondConnectionCPayload = try XCTUnwrap(
            fixture.transport.controlPayloads.dropFirst(writesBeforeSecondConnection + 2).first
        )
        let secondConnectionC = try XCTUnwrap(
            SafeGodoxProtocol.groupSnapshot(from: secondConnectionCPayload)
        )
        XCTAssertEqual(secondConnectionC.0, .c)
        XCTAssertEqual(secondConnectionC.1.operatingMode, .off)
        XCTAssertEqual(secondConnectionC.1.power, ManualPower.value(decimal: 10))
        XCTAssertEqual(secondConnectionC.1.modelingState.value, .off)

        acknowledgeGroupWrite(fixture.transport)
        XCTAssertEqual(fixture.controller.phase, .ready)
    }

    func testReadyWorkspaceCanAddACompatibleGroupWithoutDisconnecting() async throws {
        let fixture = makeFixture(stagesNewWorkingGroupsAtSafeMinimum: true)
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        let writesBeforeReconfiguration = fixture.transport.controlPayloads.count
        fixture.controller.beginWorkspaceConfiguration()

        XCTAssertTrue(fixture.controller.isReconfiguringWorkspace)
        XCTAssertFalse(fixture.controller.hasCompletedOnboarding)
        XCTAssertTrue(fixture.controller.canConfigureWorkspace)
        XCTAssertFalse(fixture.controller.canConfigureHardwareProfile)
        XCTAssertTrue(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b, .c, .d],
            assignedFlashModelIDs: [
                .b: ["ad600pro-ii"],
                .c: ["ad400pro"],
                .d: ["ad400pro-ii"],
            ]
        ))

        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertFalse(fixture.controller.isReconfiguringWorkspace)
        XCTAssertTrue(fixture.controller.hasCompletedOnboarding)
        XCTAssertEqual(fixture.controller.workingGroups, [.b, .c, .d])
        XCTAssertEqual(
            fixture.controller.groupConfiguration(.d).assignedFlashModelIDs,
            ["ad400pro-ii"]
        )
        let staged = fixture.controller.groupDraft(.d).draft
        XCTAssertEqual(staged.operatingMode, .off)
        XCTAssertEqual(staged.power, ManualPower.value(decimal: 10))
        XCTAssertEqual(staged.modelingState.value, .off)
        XCTAssertFalse(staged.beepEnabled)
        XCTAssertEqual(
            fixture.transport.controlPayloads.count,
            writesBeforeReconfiguration,
            "Editing compatibility while Ready must remain local until an explicit apply."
        )
    }

    func testReadyWorkspaceCancelPreservesConfigurationAndRejectsProfileChanges() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        let profileBefore = fixture.controller.transmitterProfile
        let groupsBefore = fixture.controller.workingGroups
        let configurationsBefore = Dictionary(uniqueKeysWithValues:
            groupsBefore.map { group in
                (group, fixture.controller.groupConfiguration(group))
            }
        )
        let writesBeforeReconfiguration = fixture.transport.controlPayloads.count

        fixture.controller.beginWorkspaceConfiguration()
        XCTAssertFalse(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.classicLetters.id,
            selectedGroups: [.b, .c],
            assignedFlashModelIDs: [
                .b: ["ad600pro-ii"],
                .c: ["ad400pro"],
            ]
        ))
        fixture.controller.cancelWorkspaceConfiguration()

        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertFalse(fixture.controller.isReconfiguringWorkspace)
        XCTAssertTrue(fixture.controller.hasCompletedOnboarding)
        XCTAssertEqual(fixture.controller.transmitterProfile, profileBefore)
        XCTAssertEqual(fixture.controller.workingGroups, groupsBefore)
        for group in groupsBefore {
            XCTAssertEqual(
                fixture.controller.groupConfiguration(group),
                configurationsBefore[group]
            )
        }
        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeReconfiguration)
    }

    func testJournalFailurePreventsA0AndStartedA0RemainsRecoverable() async throws {
        let rejectedJournal = MemoryRestorationRepository()
        rejectedJournal.acceptsSave = false
        let rejected = makeFixture(restorations: rejectedJournal)
        try await connectAndSynchronizeTransport(rejected)
        XCTAssertEqual(rejected.controller.phase, .ready)

        rejected.controller.setGlobalStandby(true)

        XCTAssertEqual(rejectedJournal.saveCount, 1)
        XCTAssertTrue(rejected.transport.controlPayloads.isEmpty)
        XCTAssertFalse(rejected.controller.isGlobalStandbyEnabled)
        XCTAssertFalse(rejected.controller.isDirectGlobalActionPending)
        XCTAssertTrue(rejected.controller.restorationPoints.isEmpty)

        let durableJournal = MemoryRestorationRepository()
        let uncertain = makeFixture(restorations: durableJournal)
        try await connectAndSynchronizeTransport(uncertain)
        uncertain.controller.setGlobalStandby(true)

        XCTAssertEqual(uncertain.transport.controlPayloads.count, 1)
        XCTAssertNotNil(SafeGodoxProtocol.globalSnapshot(from: uncertain.transport.controlPayloads[0]))
        XCTAssertEqual(Set(durableJournal.points?.keys.map { $0 } ?? []), [.b, .c])

        uncertain.transport.emit(.controlWriteStarted)
        uncertain.controller.suspendForInactiveScene()
        uncertain.controller.resumeActiveScene()

        XCTAssertEqual(uncertain.transport.controlPayloads.count, 1)
        XCTAssertEqual(durableJournal.clearCount, 0)
        XCTAssertEqual(Set(durableJournal.points?.keys.map { $0 } ?? []), [.b, .c])
        XCTAssertEqual(
            uncertain.controller.foregroundSessionRequirement,
            .recover(deviceID: device.id)
        )
        XCTAssertEqual(
            uncertain.controller.foregroundSessionState,
            .actionRequired(.recover(deviceID: device.id))
        )
    }

    func testDirectBeepActionRemainsPendingThroughA0AndEveryA1Followup() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        var pendingStateObservedWithBeepDraft = false
        let observation = fixture.controller.$groups.dropFirst().sink { groups in
            guard groups.values.contains(where: { $0.draft.beepEnabled }) else { return }
            pendingStateObservedWithBeepDraft =
                fixture.controller.isDirectGlobalActionPending
        }
        defer { withExtendedLifetime(observation) {} }

        fixture.controller.setGlobalBeep(true)

        XCTAssertTrue(pendingStateObservedWithBeepDraft)
        XCTAssertTrue(fixture.controller.isDirectGlobalActionPending)
        XCTAssertFalse(fixture.controller.restorationPoints.isEmpty)
        XCTAssertFalse(fixture.controller.requiresPhysicalRecovery)
        acknowledgeGATTWrite(fixture.transport)
        XCTAssertTrue(
            fixture.controller.isDirectGlobalActionPending,
            "The direct Beep action must remain pending after A0 while A1 followups run."
        )
        XCTAssertFalse(fixture.controller.restorationPoints.isEmpty)
        XCTAssertFalse(fixture.controller.requiresPhysicalRecovery)

        for index in fixture.controller.workingGroups.indices {
            acknowledgeGroupWrite(fixture.transport)
            XCTAssertEqual(
                fixture.controller.isDirectGlobalActionPending,
                index < fixture.controller.workingGroups.count - 1
            )
        }

        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertFalse(fixture.controller.isDirectGlobalActionPending)
        XCTAssertTrue(fixture.controller.restorationPoints.isEmpty)
        XCTAssertFalse(fixture.controller.requiresPhysicalRecovery)
    }

    func testGlobalModelingMasterRollsBackWhenJournalRejectsA0() async throws {
        let rejectedJournal = MemoryRestorationRepository()
        rejectedJournal.acceptsSave = false
        let fixture = makeFixture(restorations: rejectedJournal)
        try await connectAndSynchronizeTransport(fixture)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertTrue(fixture.controller.isGlobalModelingLightEnabled)

        fixture.controller.setGlobalModelingLightEnabled(false)

        XCTAssertEqual(rejectedJournal.saveCount, 1)
        XCTAssertTrue(fixture.transport.controlPayloads.isEmpty)
        XCTAssertTrue(
            fixture.controller.isGlobalModelingLightEnabled,
            "A rejected journal must restore the modeling master before any A0 is sent."
        )
        XCTAssertFalse(fixture.controller.isDirectGlobalActionPending)
        XCTAssertTrue(fixture.controller.restorationPoints.isEmpty)
        XCTAssertEqual(fixture.controller.phase, .ready)
    }

    func testDirectGlobalModelingMasterWritesOnlyA0AndPreservesGroupModelingDrafts() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        XCTAssertTrue(fixture.controller.isGlobalModelingLightEnabled)
        XCTAssertTrue(fixture.controller.canToggleGlobalModelingLight)
        let modelingBefore = Dictionary(uniqueKeysWithValues:
            fixture.controller.workingGroups.map { group in
                (group, fixture.controller.groupDraft(group).draft.modeling)
            }
        )
        let writesBefore = fixture.transport.controlPayloads.count

        fixture.controller.setGlobalModelingLightEnabled(false)

        XCTAssertTrue(fixture.controller.isDirectGlobalActionPending)
        XCTAssertFalse(fixture.controller.restorationPoints.isEmpty)
        XCTAssertFalse(fixture.controller.requiresPhysicalRecovery)
        XCTAssertFalse(fixture.controller.isGlobalModelingLightEnabled)
        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBefore + 1)
        let disabledSnapshot = try XCTUnwrap(
            SafeGodoxProtocol.globalSnapshot(
                from: fixture.transport.controlPayloads[writesBefore]
            )
        )
        XCTAssertFalse(disabledSnapshot.modelingLightEnabled)
        for group in fixture.controller.workingGroups {
            XCTAssertEqual(
                fixture.controller.groupDraft(group).draft.modeling,
                try XCTUnwrap(modelingBefore[group])
            )
        }

        acknowledgeGATTWrite(fixture.transport)

        XCTAssertFalse(fixture.controller.isDirectGlobalActionPending)
        XCTAssertTrue(fixture.controller.restorationPoints.isEmpty)
        XCTAssertFalse(fixture.controller.requiresPhysicalRecovery)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertEqual(
            fixture.transport.controlPayloads.count,
            writesBefore + 1,
            "The modeling master must not emit A1 followups."
        )

        fixture.controller.setGlobalModelingLightEnabled(true)
        let enabledSnapshot = try XCTUnwrap(
            SafeGodoxProtocol.globalSnapshot(
                from: fixture.transport.controlPayloads[writesBefore + 1]
            )
        )
        XCTAssertTrue(enabledSnapshot.modelingLightEnabled)
        acknowledgeGATTWrite(fixture.transport)
        XCTAssertTrue(fixture.controller.isGlobalModelingLightEnabled)
    }

    func testUncertainGlobalModelingA0KeepsDesiredStateAndRecoveryJournal() async throws {
        let durableJournal = MemoryRestorationRepository()
        let fixture = makeFixture(restorations: durableJournal)
        try await connectAndSynchronizeTransport(fixture)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertTrue(fixture.controller.isGlobalModelingLightEnabled)

        fixture.controller.setGlobalModelingLightEnabled(false)

        XCTAssertEqual(fixture.transport.controlPayloads.count, 1)
        let attemptedSnapshot = try XCTUnwrap(
            SafeGodoxProtocol.globalSnapshot(
                from: fixture.transport.controlPayloads[0]
            )
        )
        XCTAssertFalse(attemptedSnapshot.modelingLightEnabled)
        XCTAssertEqual(
            Set(durableJournal.points?.keys.map { $0 } ?? []),
            [.b, .c]
        )
        XCTAssertFalse(fixture.controller.requiresPhysicalRecovery)
        XCTAssertTrue(
            durableJournal.points?.values.allSatisfy {
                $0.globalSnapshot?.modelingLightEnabled == true
            } == true,
            "Recovery must retain the previously confirmed global modeling master."
        )

        fixture.transport.emit(.controlWriteStarted)
        fixture.transport.emit(.commandFailed(
            .control,
            .writeFailed(
                command: .control,
                message: "synthetic uncertain modeling A0"
            )
        ))

        XCTAssertFalse(fixture.controller.isDirectGlobalActionPending)
        XCTAssertFalse(
            fixture.controller.isGlobalModelingLightEnabled,
            "The desired master remains off so a later exact synchronization can retry it."
        )
        XCTAssertEqual(fixture.controller.phase, .disconnecting)
        XCTAssertEqual(fixture.transport.disconnectCount, 1)
        XCTAssertEqual(durableJournal.clearCount, 0)
        XCTAssertEqual(
            Set(durableJournal.points?.keys.map { $0 } ?? []),
            [.b, .c]
        )
        XCTAssertEqual(Set(fixture.controller.restorationPoints.keys), [.b, .c])
        XCTAssertTrue(fixture.controller.requiresPhysicalRecovery)
        XCTAssertFalse(fixture.controller.canToggleGlobalModelingLight)
    }

    func testUnrelatedApplyDoesNotReenableDisabledGlobalModelingMaster() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.setGlobalModelingLightEnabled(false)
        acknowledgeGATTWrite(fixture.transport)
        XCTAssertFalse(fixture.controller.isGlobalModelingLightEnabled)

        let group = try XCTUnwrap(fixture.controller.workingGroups.first)
        let currentPower = fixture.controller.groupDraft(group).draft.power
        let alternatePower = try XCTUnwrap(
            fixture.controller.allowedPowers(for: group).first { $0 != currentPower }
        )
        fixture.controller.setDraftPower(group, power: alternatePower)
        let writesBeforeApply = fixture.transport.controlPayloads.count

        fixture.controller.applyPendingChanges()

        XCTAssertFalse(fixture.controller.isGlobalModelingLightEnabled)
        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeApply + 1)
        XCTAssertNil(
            SafeGodoxProtocol.globalSnapshot(
                from: fixture.transport.controlPayloads[writesBeforeApply]
            ),
            "A power-only Apply must not rebuild A0 from per-group modeling modes."
        )
        acknowledgeGroupWrite(fixture.transport)
        XCTAssertEqual(fixture.controller.phase, .ready)
    }

    func testIndividualModelingEditReenablesGlobalModelingMaster() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.setGlobalModelingLightEnabled(false)
        acknowledgeGATTWrite(fixture.transport)
        XCTAssertFalse(fixture.controller.isGlobalModelingLightEnabled)

        fixture.controller.setDraftModeling(.c, modeling: .fixed(percent: 25))

        XCTAssertTrue(fixture.controller.isGlobalModelingLightEnabled)
        XCTAssertEqual(
            fixture.controller.groupDraft(.c).draft.modeling,
            .fixed(percent: 25)
        )
    }

    func testDirectStandbyActionIsPendingUntilItsA0OnlyCompletion() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.setGlobalStandby(true)

        XCTAssertTrue(fixture.controller.isDirectGlobalActionPending)
        XCTAssertFalse(fixture.controller.restorationPoints.isEmpty)
        XCTAssertFalse(fixture.controller.requiresPhysicalRecovery)
        XCTAssertTrue(fixture.controller.isGlobalStandbyEnabled)

        acknowledgeGATTWrite(fixture.transport)

        XCTAssertFalse(fixture.controller.isDirectGlobalActionPending)
        XCTAssertTrue(fixture.controller.restorationPoints.isEmpty)
        XCTAssertFalse(fixture.controller.requiresPhysicalRecovery)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertTrue(fixture.controller.isGlobalStandbyEnabled)
    }

    func testManualMultiApplyNeverPublishesDirectGlobalActionPending() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.setGlobalMultiFlashEnabled(true)
        XCTAssertFalse(fixture.controller.isDirectGlobalActionPending)

        fixture.controller.applyPendingChanges()
        XCTAssertFalse(fixture.controller.isDirectGlobalActionPending)

        acknowledgeGATTWrite(fixture.transport)
        XCTAssertFalse(fixture.controller.isDirectGlobalActionPending)
        for _ in fixture.controller.workingGroups {
            acknowledgeGroupWrite(fixture.transport)
            XCTAssertFalse(fixture.controller.isDirectGlobalActionPending)
        }
    }

    func testDirectGlobalActionPendingClearsOnFailureAndBackgroundCancellation() async throws {
        let failed = makeFixture()
        completeWorkspace(failed.controller)
        try await connectAndSynchronizeTransport(failed)
        finishInitialValueSynchronization(failed)

        failed.controller.setGlobalStandby(true)
        XCTAssertTrue(failed.controller.isDirectGlobalActionPending)
        failed.transport.emit(.commandFailed(
            .control,
            .writeFailed(command: .control, message: "synthetic direct failure")
        ))

        XCTAssertFalse(failed.controller.isDirectGlobalActionPending)
        XCTAssertEqual(failed.controller.phase, .disconnecting)

        let followupFailed = makeFixture()
        completeWorkspace(followupFailed.controller)
        try await connectAndSynchronizeTransport(followupFailed)
        finishInitialValueSynchronization(followupFailed)

        followupFailed.controller.setGlobalBeep(true)
        acknowledgeGATTWrite(followupFailed.transport)
        XCTAssertTrue(followupFailed.controller.isDirectGlobalActionPending)
        followupFailed.transport.emit(.commandFailed(
            .control,
            .writeFailed(command: .control, message: "synthetic Beep A1 failure")
        ))

        XCTAssertFalse(followupFailed.controller.isDirectGlobalActionPending)
        XCTAssertEqual(followupFailed.controller.phase, .disconnecting)

        let backgrounded = makeFixture()
        completeWorkspace(backgrounded.controller)
        try await connectAndSynchronizeTransport(backgrounded)
        finishInitialValueSynchronization(backgrounded)

        backgrounded.controller.setGlobalBeep(true)
        XCTAssertTrue(backgrounded.controller.isDirectGlobalActionPending)
        backgrounded.controller.suspendForInactiveScene()

        XCTAssertFalse(backgrounded.controller.isDirectGlobalActionPending)
        XCTAssertFalse(backgrounded.controller.isSceneActive)
    }

    func testInactiveSceneCancelsPendingTestWithoutRetryAndPreservesLink() async throws {
        let fixture = makeFixture()
        try await connectAndSynchronizeTransport(fixture)

        XCTAssertNil(fixture.controller.testDeliveryResult)
        fixture.controller.sendTestFlash()
        XCTAssertEqual(fixture.transport.testWriteCount, 1)
        XCTAssertTrue(fixture.controller.isTestPending)
        XCTAssertNil(fixture.controller.testDeliveryResult)
        XCTAssertEqual(fixture.scheduler.activeCount(.testDelivery), 1)

        fixture.controller.suspendForInactiveScene()
        fixture.transport.emit(.commandSent(.test))
        fixture.controller.resumeActiveScene()

        XCTAssertFalse(fixture.controller.isTestPending)
        XCTAssertNil(fixture.controller.testDeliveryResult)
        XCTAssertFalse(fixture.scheduler.fire(.testDelivery))
        XCTAssertEqual(fixture.transport.testWriteCount, 1)
        XCTAssertEqual(fixture.transport.disconnectCount, 0)
        XCTAssertEqual(fixture.transport.forceResetCount, 0)
        XCTAssertEqual(
            fixture.controller.foregroundSessionState,
            .active
        )
        XCTAssertEqual(fixture.controller.phase, .ready)

        fixture.controller.setGlobalStandby(true)
        acknowledgeGATTWrite(fixture.transport)

        XCTAssertNil(
            fixture.controller.testDeliveryResult,
            "A later successful control operation must not be presented as a Test result."
        )
    }

    func testInactiveReadyScenePreservesTransportSessionAndReturnsReadyWithoutHandshake() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        let commandsBeforeSuspension = fixture.transport.sentCommands
        let controlPayloadsBeforeSuspension = fixture.transport.controlPayloads

        fixture.controller.suspendForInactiveScene()

        XCTAssertFalse(fixture.controller.isSceneActive)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertEqual(fixture.transport.disconnectCount, 0)
        XCTAssertEqual(fixture.transport.forceResetCount, 0)

        fixture.controller.resumeActiveScene()

        XCTAssertTrue(fixture.controller.isSceneActive)
        XCTAssertEqual(fixture.controller.foregroundSessionState, .active)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertEqual(fixture.transport.sentCommands, commandsBeforeSuspension)
        XCTAssertEqual(
            fixture.transport.controlPayloads,
            controlPayloadsBeforeSuspension,
            "Returning to the app must not repeat Sync or A0/A1 delivery."
        )
    }

    func testPhysicalDisconnectionWhileInactiveAllowsOneExactReconnectOnReturn() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.suspendForInactiveScene()
        fixture.transport.emit(.stateChanged(.idle))
        XCTAssertFalse(fixture.controller.reconnectInterruptedSessionIfPossible())
        fixture.controller.resumeActiveScene()

        XCTAssertTrue(fixture.controller.isSceneActive)
        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertEqual(
            fixture.controller.foregroundSessionState,
            .actionRequired(.reconnectAndSynchronize)
        )
        XCTAssertEqual(fixture.transport.disconnectCount, 0)
        XCTAssertEqual(fixture.transport.forceResetCount, 0)
        XCTAssertTrue(fixture.controller.reconnectInterruptedSessionIfPossible())
        XCTAssertFalse(fixture.controller.reconnectInterruptedSessionIfPossible())
        XCTAssertEqual(fixture.controller.phase, .scanning)
        XCTAssertEqual(fixture.transport.scanCount, 2)
    }

    func testPhysicalDisconnectionDeliveredAfterResumeStartsOneExactReconnect() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.suspendForInactiveScene()
        fixture.controller.resumeActiveScene()
        fixture.transport.emit(.stateChanged(.idle))

        XCTAssertTrue(fixture.controller.isSceneActive)
        XCTAssertEqual(fixture.controller.phase, .scanning)
        XCTAssertEqual(
            fixture.controller.foregroundSessionState,
            .actionRequired(.reconnectAndSynchronize)
        )
        XCTAssertFalse(fixture.controller.reconnectInterruptedSessionIfPossible())
        XCTAssertEqual(fixture.transport.scanCount, 2)
        XCTAssertEqual(fixture.transport.disconnectCount, 0)
        XCTAssertEqual(fixture.transport.forceResetCount, 0)
    }

    func testPhysicalFailureDeliveredAfterResumeStartsOneExactReconnect() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.suspendForInactiveScene()
        fixture.controller.resumeActiveScene()
        fixture.transport.emit(.failed(.disconnected("link lost")))

        XCTAssertTrue(fixture.controller.isSceneActive)
        XCTAssertEqual(fixture.controller.phase, .scanning)
        XCTAssertEqual(
            fixture.controller.foregroundSessionState,
            .actionRequired(.reconnectAndSynchronize)
        )
        XCTAssertFalse(fixture.controller.reconnectInterruptedSessionIfPossible())
        XCTAssertEqual(fixture.transport.scanCount, 2)
        XCTAssertEqual(fixture.transport.disconnectCount, 0)
        XCTAssertEqual(fixture.transport.forceResetCount, 0)
    }

    func testReadyDisconnectDoubleFailureSignalKeepsOneExactReconnectScan() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        let failure = RadioTransportError.disconnected("synthetic link loss")
        fixture.transport.emit(.stateChanged(.failed(failure.localizedDescription)))
        fixture.transport.emit(.failed(failure))

        XCTAssertEqual(fixture.controller.phase, .scanning)
        XCTAssertEqual(
            fixture.controller.foregroundSessionState,
            .actionRequired(.reconnectAndSynchronize)
        )
        XCTAssertEqual(fixture.transport.scanCount, 2)
        XCTAssertEqual(fixture.scheduler.activeCount(.scan), 1)
        XCTAssertFalse(fixture.controller.reconnectInterruptedSessionIfPossible())
    }

    func testForegroundReconnectIgnoresAnotherIdentifierAndUsesSessionCredential() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)
        XCTAssertTrue(fixture.controller.radioCode.isEmpty)
        XCTAssertFalse(fixture.controller.rememberSelectedRadio)

        fixture.controller.suspendForInactiveScene()
        fixture.transport.emit(.stateChanged(.idle))
        fixture.controller.resumeActiveScene()
        XCTAssertTrue(fixture.controller.reconnectInterruptedSessionIfPossible())

        let other = RadioCandidate(
            id: UUID(),
            name: device.name,
            rssi: -20
        )
        fixture.transport.emit(.discovered(other))
        XCTAssertEqual(fixture.transport.connectedCandidates, [device])

        fixture.transport.emit(.discovered(device))
        XCTAssertEqual(fixture.transport.connectedCandidates, [device, device])
        XCTAssertEqual(fixture.controller.phase, .connecting)
        XCTAssertTrue(fixture.controller.isRadioCodeValid)
        XCTAssertFalse(fixture.controller.rememberSelectedRadio)
        XCTAssertFalse(fixture.controller.reconnectInterruptedSessionIfPossible())
    }

    func testSecondInactiveTransitionDuringReconnectScanPreservesExactTarget() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.suspendForInactiveScene()
        fixture.transport.emit(.stateChanged(.idle))
        fixture.controller.resumeActiveScene()
        XCTAssertTrue(fixture.controller.reconnectInterruptedSessionIfPossible())
        XCTAssertEqual(fixture.controller.phase, .scanning)
        XCTAssertEqual(fixture.transport.scanCount, 2)

        fixture.controller.suspendForInactiveScene()
        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertEqual(
            fixture.controller.foregroundSessionState,
            .inactive(requirement: .reconnectAndSynchronize)
        )

        fixture.controller.resumeActiveScene()
        XCTAssertTrue(fixture.controller.reconnectInterruptedSessionIfPossible())
        XCTAssertFalse(fixture.controller.reconnectInterruptedSessionIfPossible())
        XCTAssertEqual(fixture.controller.phase, .scanning)
        XCTAssertEqual(fixture.transport.scanCount, 3)
    }

    func testExplicitReconnectCancellationDoesNotRetryOnTheNextForeground() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.suspendForInactiveScene()
        fixture.transport.emit(.stateChanged(.idle))
        fixture.controller.resumeActiveScene()
        XCTAssertTrue(fixture.controller.reconnectInterruptedSessionIfPossible())
        XCTAssertEqual(fixture.controller.phase, .scanning)

        fixture.controller.cancelConnectionAttempt()
        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertEqual(fixture.controller.foregroundSessionState, .active)
        XCTAssertTrue(fixture.controller.radioCode.isEmpty)
        let scanCountAfterCancellation = fixture.transport.scanCount

        fixture.controller.suspendForInactiveScene()
        fixture.controller.resumeActiveScene()
        XCTAssertFalse(fixture.controller.reconnectInterruptedSessionIfPossible())
        XCTAssertEqual(fixture.transport.scanCount, scanCountAfterCancellation)
    }

    func testExplicitDisconnectDoesNotCreateAForegroundReconnect() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)
        let scanCountBeforeDisconnect = fixture.transport.scanCount

        fixture.controller.disconnect()
        fixture.transport.emit(.stateChanged(.idle))
        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertEqual(fixture.controller.foregroundSessionState, .active)

        fixture.controller.suspendForInactiveScene()
        fixture.controller.resumeActiveScene()
        XCTAssertFalse(fixture.controller.reconnectInterruptedSessionIfPossible())
        XCTAssertEqual(fixture.transport.scanCount, scanCountBeforeDisconnect)
    }

    func testReadyForegroundResumeRearmsOnePendingAutomaticApply() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)
        fixture.controller.setChangeDeliveryMode(.automatic)
        fixture.controller.adjust(.b, direction: 1)
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 1)
        let payloadCountBeforeSuspension = fixture.transport.controlPayloads.count

        fixture.controller.suspendForInactiveScene()
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 0)

        fixture.controller.resumeActiveScene()
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 1)
        fixture.controller.resumeActiveScene()
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 1)

        XCTAssertTrue(fixture.scheduler.fire(.automaticApply))
        XCTAssertEqual(
            fixture.transport.controlPayloads.count,
            payloadCountBeforeSuspension + 1
        )
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 0)
    }

    func testSavedRadioSearchConnectsOnlyTheExactRememberedIdentifierOnce() throws {
        let saved = try XCTUnwrap(SavedRadio(
            deviceID: device.id,
            name: device.name,
            radioCode: "111111"
        ))
        let preferences = MemoryRadioConnectionPreferences(
            state: RadioConnectionPreferenceState(
                lastConnectedRadioID: device.id,
                automaticConnectionRadioID: device.id
            )
        )
        let fixture = makeFixture(
            savedRadioStore: MemorySavedRadioRepository(radios: [saved]),
            connectionPreferences: preferences
        )
        let other = RadioCandidate(
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            name: "GDBH-Other",
            rssi: -30
        )

        fixture.controller.connectSavedRadioWhenDiscovered(device.id)
        XCTAssertEqual(fixture.transport.scanCount, 1)
        XCTAssertEqual(fixture.controller.pendingSavedRadioConnectionID, device.id)

        fixture.transport.emit(.discovered(other))
        XCTAssertTrue(fixture.transport.connectedCandidates.isEmpty)

        fixture.transport.emit(.discovered(device))
        fixture.transport.emit(.discovered(device))

        XCTAssertEqual(fixture.transport.connectedCandidates, [device])
        XCTAssertNil(fixture.controller.pendingSavedRadioConnectionID)
        XCTAssertEqual(fixture.controller.phase, .connecting)
    }

    func testScanCompletionPreservesSelectionAndCodeForEitherIdleCallbackTiming() {
        for emitsIdleSynchronously in [true, false] {
            let fixture = makeFixture()
            fixture.transport.emitsIdleWhenStoppingScan = emitsIdleSynchronously
            fixture.controller.startScanning()
            fixture.transport.emit(.discovered(device))
            fixture.controller.selectDevice(device.id)
            fixture.controller.radioCode = "111111"
            fixture.controller.rememberSelectedRadio = true

            XCTAssertTrue(fixture.scheduler.fire(.scan))
            XCTAssertEqual(fixture.transport.stopScanCount, 1)
            XCTAssertEqual(fixture.controller.phase, .idle)
            if !emitsIdleSynchronously {
                // Demo's stopScanning delivers this callback after the deadline
                // has already moved the controller from scanning to idle.
                fixture.transport.emit(.stateChanged(.idle))
            }

            XCTAssertEqual(fixture.controller.selectedDeviceID, device.id)
            XCTAssertEqual(fixture.controller.radioCode, "111111")
            XCTAssertTrue(fixture.controller.rememberSelectedRadio)
            XCTAssertTrue(fixture.controller.isRadioCodeValid)
            XCTAssertEqual(fixture.scheduler.activeCount(.scan), 0)

            fixture.controller.connectSelectedDevice()

            XCTAssertEqual(fixture.controller.phase, .connecting)
            XCTAssertEqual(fixture.transport.connectedCandidates, [device])
        }
    }

    func testIdleAfterConnectingFromCompletedScanStillClearsCode() {
        let fixture = makeFixture()
        fixture.controller.startScanning()
        fixture.transport.emit(.discovered(device))
        fixture.controller.radioCode = "111111"
        XCTAssertTrue(fixture.scheduler.fire(.scan))
        fixture.transport.emit(.stateChanged(.idle))
        fixture.controller.connectSelectedDevice()
        XCTAssertEqual(fixture.controller.phase, .connecting)

        fixture.transport.emit(.stateChanged(.idle))

        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertTrue(fixture.controller.radioCode.isEmpty)
        XCTAssertNil(fixture.controller.connectedDeviceName)
        XCTAssertEqual(fixture.scheduler.activeCount(.connectionSetup), 0)
    }

    func testExplicitScanCancellationClearsCodeBeforeDeferredIdle() {
        let fixture = makeFixture()
        fixture.controller.startScanning()
        fixture.transport.emit(.discovered(device))
        fixture.controller.radioCode = "111111"

        fixture.controller.cancelConnectionAttempt()

        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertTrue(fixture.controller.radioCode.isEmpty)
        XCTAssertEqual(fixture.transport.stopScanCount, 1)
        XCTAssertFalse(fixture.scheduler.fire(.scan))
        fixture.transport.emit(.stateChanged(.idle))
        XCTAssertTrue(fixture.controller.radioCode.isEmpty)
        fixture.controller.connectSelectedDevice()
        XCTAssertTrue(fixture.transport.connectedCandidates.isEmpty)
    }

    func testInactiveScanClearsCodeBeforeDeferredIdle() {
        let fixture = makeFixture()
        fixture.controller.startScanning()
        fixture.transport.emit(.discovered(device))
        fixture.controller.radioCode = "111111"

        fixture.controller.suspendForInactiveScene()
        fixture.transport.emit(.stateChanged(.idle))
        fixture.controller.resumeActiveScene()

        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertTrue(fixture.controller.radioCode.isEmpty)
        XCTAssertFalse(fixture.scheduler.fire(.scan))
        fixture.controller.connectSelectedDevice()
        XCTAssertTrue(fixture.transport.connectedCandidates.isEmpty)
    }

    func testScanFailuresStillClearSelectedRadioCode() {
        let failures: [TransportEvent] = [
            .stateChanged(.bluetoothUnavailable("powered off")),
            .failed(.disconnected("synthetic scan failure")),
        ]
        for failure in failures {
            let fixture = makeFixture()
            fixture.controller.startScanning()
            fixture.transport.emit(.discovered(device))
            fixture.controller.radioCode = "111111"

            fixture.transport.emit(failure)

            XCTAssertTrue(fixture.controller.radioCode.isEmpty)
            fixture.controller.connectSelectedDevice()
            XCTAssertTrue(fixture.transport.connectedCandidates.isEmpty)
        }
    }

    func testSavedRadioSearchArmsExactTargetBeforeSynchronousDiscovery() throws {
        let saved = try XCTUnwrap(SavedRadio(
            deviceID: device.id,
            name: device.name,
            radioCode: "111111"
        ))
        let fixture = makeFixture(
            savedRadioStore: MemorySavedRadioRepository(radios: [saved])
        )
        fixture.transport.discoveryOnScan = device

        XCTAssertTrue(
            fixture.controller.connectSavedRadioWhenDiscovered(device.id)
        )

        XCTAssertEqual(fixture.transport.scanCount, 1)
        XCTAssertEqual(fixture.transport.connectedCandidates, [device])
        XCTAssertNil(fixture.controller.pendingSavedRadioConnectionID)
        XCTAssertEqual(fixture.controller.phase, .connecting)
    }

    func testSavedRadioSearchWaitsThroughBluetoothUnavailableAndRearmsTimeout() throws {
        let saved = try XCTUnwrap(SavedRadio(
            deviceID: device.id,
            name: device.name,
            radioCode: "111111"
        ))
        let fixture = makeFixture(
            savedRadioStore: MemorySavedRadioRepository(radios: [saved])
        )

        XCTAssertTrue(
            fixture.controller.connectSavedRadioWhenDiscovered(device.id)
        )
        XCTAssertEqual(fixture.scheduler.activeCount(.scan), 1)

        fixture.transport.emit(.stateChanged(.bluetoothUnavailable("powered off")))

        XCTAssertEqual(fixture.controller.phase, .unavailable("powered off"))
        XCTAssertEqual(fixture.controller.pendingSavedRadioConnectionID, device.id)
        XCTAssertEqual(fixture.scheduler.activeCount(.scan), 0)

        fixture.transport.emit(.stateChanged(.scanning))

        XCTAssertEqual(fixture.controller.phase, .scanning)
        XCTAssertEqual(fixture.scheduler.activeCount(.scan), 1)
        fixture.transport.emit(.discovered(device))
        XCTAssertEqual(fixture.transport.connectedCandidates, [device])
        XCTAssertNil(fixture.controller.pendingSavedRadioConnectionID)
    }

    func testSavedRadioSearchPausesTimeoutWhileWaitingForBluetooth() throws {
        let saved = try XCTUnwrap(SavedRadio(
            deviceID: device.id,
            name: device.name,
            radioCode: "111111"
        ))
        let fixture = makeFixture(
            savedRadioStore: MemorySavedRadioRepository(radios: [saved])
        )

        XCTAssertTrue(
            fixture.controller.connectSavedRadioWhenDiscovered(device.id)
        )
        XCTAssertEqual(fixture.scheduler.activeCount(.scan), 1)

        fixture.transport.emit(.stateChanged(.waitingForBluetooth))

        XCTAssertEqual(fixture.controller.phase, .scanning)
        XCTAssertEqual(fixture.controller.pendingSavedRadioConnectionID, device.id)
        XCTAssertEqual(fixture.scheduler.activeCount(.scan), 0)

        fixture.transport.emit(.stateChanged(.scanning))

        XCTAssertEqual(fixture.scheduler.activeCount(.scan), 1)
        XCTAssertEqual(fixture.controller.pendingSavedRadioConnectionID, device.id)
    }

    func testSuccessfulSavedRadioSyncRecordsItAsLastConnected() async throws {
        let saved = try XCTUnwrap(SavedRadio(
            deviceID: device.id,
            name: device.name,
            radioCode: "111111"
        ))
        let preferences = MemoryRadioConnectionPreferences()
        let fixture = makeFixture(
            savedRadioStore: MemorySavedRadioRepository(radios: [saved]),
            connectionPreferences: preferences
        )

        try await connectAndSynchronizeTransport(fixture)

        XCTAssertEqual(fixture.controller.lastConnectedRadioID, device.id)
        XCTAssertEqual(preferences.state.lastConnectedRadioID, device.id)
        XCTAssertNil(preferences.state.automaticConnectionRadioID)
    }

    func testAutomaticConnectionPreferenceIsExclusiveAndForgettingClearsIt() throws {
        let saved = try XCTUnwrap(SavedRadio(
            deviceID: device.id,
            name: device.name,
            radioCode: "111111"
        ))
        let reserveID = UUID(
            uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
        )!
        let reserve = try XCTUnwrap(SavedRadio(
            deviceID: reserveID,
            name: "GDBH-Reserve",
            radioCode: "222222"
        ))
        let repository = MemorySavedRadioRepository(radios: [saved, reserve])
        let preferences = MemoryRadioConnectionPreferences(
            state: RadioConnectionPreferenceState(
                lastConnectedRadioID: device.id,
                automaticConnectionRadioID: nil
            )
        )
        let fixture = makeFixture(
            savedRadioStore: repository,
            connectionPreferences: preferences
        )

        fixture.controller.setAutomaticConnectionEnabled(true, for: device.id)
        XCTAssertTrue(fixture.controller.isAutomaticConnectionEnabled(for: device.id))
        XCTAssertEqual(preferences.state.automaticConnectionRadioID, device.id)

        fixture.controller.setAutomaticConnectionEnabled(true, for: reserveID)
        XCTAssertFalse(fixture.controller.isAutomaticConnectionEnabled(for: device.id))
        XCTAssertTrue(fixture.controller.isAutomaticConnectionEnabled(for: reserveID))
        XCTAssertEqual(preferences.state.automaticConnectionRadioID, reserveID)

        let restored = makeFixture(
            savedRadioStore: repository,
            connectionPreferences: preferences
        )
        XCTAssertFalse(restored.controller.isAutomaticConnectionEnabled(for: device.id))
        XCTAssertTrue(restored.controller.isAutomaticConnectionEnabled(for: reserveID))

        restored.controller.forgetSavedRadio(reserveID)

        XCTAssertEqual(repository.radios, [saved])
        XCTAssertEqual(restored.controller.lastConnectedRadioID, device.id)
        XCTAssertNil(restored.controller.automaticConnectionRadioID)
        XCTAssertEqual(
            preferences.state,
            RadioConnectionPreferenceState(
                lastConnectedRadioID: device.id,
                automaticConnectionRadioID: nil
            )
        )
    }

    func testInvalidSavedRadioLoadDoesNotEraseConnectionPreferences() {
        let rememberedID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!
        let preferences = MemoryRadioConnectionPreferences(
            state: RadioConnectionPreferenceState(
                lastConnectedRadioID: rememberedID,
                automaticConnectionRadioID: rememberedID
            )
        )

        let fixture = makeFixture(
            savedRadioStore: InvalidSavedRadioRepository(),
            connectionPreferences: preferences
        )

        XCTAssertTrue(fixture.controller.savedRadios.isEmpty)
        XCTAssertNil(fixture.controller.lastConnectedRadioID)
        XCTAssertNil(fixture.controller.automaticConnectionRadioID)
        XCTAssertEqual(preferences.saveCount, 0)
        XCTAssertEqual(
            preferences.state,
            RadioConnectionPreferenceState(
                lastConnectedRadioID: rememberedID,
                automaticConnectionRadioID: rememberedID
            )
        )
    }

    func testTestCommandIsSingleFlightUntilTransportReportsDelivery() async throws {
        let fixture = makeFixture()
        try await connectAndSynchronizeTransport(fixture)

        XCTAssertTrue(fixture.controller.canSendTest)
        XCTAssertNil(fixture.controller.testDeliveryResult)

        fixture.controller.sendTestFlash()

        XCTAssertEqual(fixture.transport.testWriteCount, 1)
        XCTAssertTrue(fixture.controller.isTestPending)
        XCTAssertFalse(fixture.controller.canSendTest)
        XCTAssertNil(fixture.controller.testDeliveryResult)

        fixture.controller.sendTestFlash()

        XCTAssertEqual(
            fixture.transport.testWriteCount,
            1,
            "A pending Test must not enqueue a second delivery."
        )

        fixture.transport.emit(.commandSent(.test))

        XCTAssertFalse(fixture.controller.isTestPending)
        XCTAssertTrue(fixture.controller.canSendTest)
        XCTAssertFalse(fixture.scheduler.fire(.testDelivery))
        let firstResult = try XCTUnwrap(fixture.controller.testDeliveryResult)
        XCTAssertEqual(firstResult.outcome, .delivered)

        fixture.controller.sendTestFlash()

        XCTAssertNil(
            fixture.controller.testDeliveryResult,
            "Starting a new Test must clear the previous correlated result."
        )
        fixture.transport.emit(.commandSent(.test))
        let secondResult = try XCTUnwrap(fixture.controller.testDeliveryResult)
        XCTAssertEqual(secondResult.outcome, .delivered)
        XCTAssertNotEqual(secondResult.attemptID, firstResult.attemptID)
    }

    func testGroupPowerAdjustmentAvailabilityTracksDirectionBoundsAndOffMode() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        let minimum = try XCTUnwrap(fixture.controller.allowedPowers(for: .b).first)
        let next = try XCTUnwrap(fixture.controller.allowedPowers(for: .b).dropFirst().first)
        let maximum = try XCTUnwrap(fixture.controller.allowedPowers(for: .b).last)

        XCTAssertEqual(fixture.controller.groupDraft(.b).draft.power, minimum)
        XCTAssertFalse(fixture.controller.canAdjustPower(.b, direction: -1))
        XCTAssertTrue(fixture.controller.canAdjustPower(.b, direction: 1))

        fixture.controller.adjust(.b, direction: 1)

        XCTAssertEqual(fixture.controller.groupDraft(.b).draft.power, next)
        XCTAssertTrue(fixture.controller.canAdjustPower(.b, direction: -1))

        fixture.controller.setDraftPower(.b, power: maximum)

        XCTAssertTrue(fixture.controller.canAdjustPower(.b, direction: -1))
        XCTAssertFalse(fixture.controller.canAdjustPower(.b, direction: 1))

        let groupCMinimum = try XCTUnwrap(
            fixture.controller.allowedPowers(for: .c).first
        )
        fixture.controller.setDraftPower(.c, power: groupCMinimum)
        fixture.controller.setDraftRadioEnabled(.c, enabled: false)

        XCTAssertEqual(fixture.controller.groupDraft(.c).draft.operatingMode, .off)
        XCTAssertEqual(fixture.controller.groupDraft(.c).draft.power, groupCMinimum)
        XCTAssertFalse(fixture.controller.canAdjustPower(.c, direction: -1))
        XCTAssertFalse(fixture.controller.canAdjustPower(.c, direction: 1))
    }

    func testAtomicGlobalPowerOffsetPersistsAndSchedulesAllEligibleGroupsOnce() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)
        fixture.controller.setChangeDeliveryMode(.automatic)

        let eligibleGroups: [GodoxGroup] = [.b, .c]
        let initialIndices = Dictionary(uniqueKeysWithValues: eligibleGroups.map {
            ($0, fixture.controller.powerIndex(for: $0))
        })
        let writesBeforeAdjustment = fixture.transport.controlPayloads.count
        let savesBeforeAdjustment = fixture.studioLibrary.saveCount

        let outcome = fixture.controller.adjustGlobalPower(offsetSteps: 3)

        XCTAssertEqual(outcome, .applied(offsetSteps: 3))
        for group in eligibleGroups {
            let allowed = fixture.controller.allowedPowers(for: group)
            let initialIndex = try XCTUnwrap(initialIndices[group])
            XCTAssertEqual(
                fixture.controller.groupDraft(group).draft.power,
                allowed[initialIndex + 3]
            )
        }
        XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeAdjustment + 1)
        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeAdjustment)
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 1)

        XCTAssertTrue(fixture.scheduler.fire(.automaticApply))
        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeAdjustment + 1)
        let firstFinalWrite = try XCTUnwrap(
            SafeGodoxProtocol.groupSnapshot(
                from: fixture.transport.controlPayloads[writesBeforeAdjustment]
            )
        )
        XCTAssertEqual(firstFinalWrite.0, .b)
        XCTAssertEqual(
            firstFinalWrite.1.power,
            fixture.controller.groupDraft(.b).draft.power
        )
    }

    func testAtomicGlobalPowerOffsetClampsAndLeavesDisabledGroupsUntouched() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        let allowedB = fixture.controller.allowedPowers(for: .b)
        let nearMaximumBIndex = allowedB.index(
            before: allowedB.index(before: allowedB.endIndex)
        )
        let nearMaximumB = allowedB[nearMaximumBIndex]
        fixture.controller.setDraftPower(.b, power: nearMaximumB)
        fixture.controller.setDraftRadioEnabled(.c, enabled: false)
        let disabledC = fixture.controller.groupDraft(.c).draft

        fixture.controller.applyPendingChanges()
        let setupWriteCount = try XCTUnwrap(fixture.controller.applySequenceStatus?.totalCount)
        for _ in 0..<setupWriteCount {
            acknowledgeGroupWrite(fixture.transport)
        }
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertEqual(fixture.controller.pendingCount, 0)

        fixture.controller.setChangeDeliveryMode(.automatic)
        let writesBeforeAdjustment = fixture.transport.controlPayloads.count
        let savesBeforeAdjustment = fixture.studioLibrary.saveCount

        let outcome = fixture.controller.adjustGlobalPower(offsetSteps: 9)

        XCTAssertEqual(outcome, .limited(offsetSteps: 1, cause: .groups([.b])))
        XCTAssertEqual(fixture.controller.groupDraft(.b).draft.power, allowedB.last)
        XCTAssertEqual(fixture.controller.groupDraft(.c).draft, disabledC)
        XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeAdjustment + 1)
        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeAdjustment)
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 1)
    }

    func testContinuousEditPersistsAndSendsOnlyTheFinalValueAfterGestureEnds() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        let writesBeforeGesture = fixture.transport.controlPayloads.count
        let savesBeforeGesture = fixture.studioLibrary.saveCount
        fixture.controller.setChangeDeliveryMode(.automatic)
        let firstToken = fixture.controller.beginInteractiveEdit()
        let finalToken = fixture.controller.beginInteractiveEdit()

        for decimal in [30, 33, 37] {
            let requestedPower = try XCTUnwrap(ManualPower.value(decimal: decimal))
            let requestedIndex = try XCTUnwrap(
                fixture.controller.allowedPowers(for: .c).firstIndex(of: requestedPower)
            )
            fixture.controller.setDraftPowerIndex(requestedIndex, for: .c)
            XCTAssertEqual(
                fixture.controller.groupDraft(.c).draft.power,
                requestedPower,
                "Every interactive step must update the live draft before release."
            )
            XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeGesture)
        }

        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeGesture)
        XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeGesture)
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 0)
        XCTAssertTrue(fixture.controller.isInteractiveEditActive)

        fixture.controller.endInteractiveEdit(firstToken)
        XCTAssertTrue(fixture.controller.isInteractiveEditActive)
        XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeGesture)
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 0)

        fixture.controller.endInteractiveEdit(finalToken)
        XCTAssertFalse(fixture.controller.isInteractiveEditActive)
        XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeGesture + 1)
        XCTAssertEqual(
            fixture.studioLibrary.library?
                .workspace.groupConfigurations[.c]?.snapshot.power,
            ManualPower.value(decimal: 37)
        )
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 1)
        XCTAssertTrue(fixture.scheduler.fire(.automaticApply))

        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeGesture + 1)
        let finalPayload = fixture.transport.controlPayloads[writesBeforeGesture]
        let decoded = try XCTUnwrap(SafeGodoxProtocol.groupSnapshot(from: finalPayload))
        XCTAssertEqual(decoded.0, .c)
        XCTAssertEqual(decoded.1.power, ManualPower.value(decimal: 37))
        XCTAssertFalse(
            fixture.transport.controlPayloads.dropFirst(writesBeforeGesture).contains { payload in
                guard let snapshot = SafeGodoxProtocol.groupSnapshot(from: payload)?.1 else {
                    return false
                }
                return snapshot.power == ManualPower.value(decimal: 30) ||
                    snapshot.power == ManualPower.value(decimal: 33)
            }
        )
    }

    func testMultiHertzAbovePublishedProfileRangeIsUnverifiedAndEncodesC7() async throws {
        let fixture = makeFixture()
        XCTAssertTrue(fixture.controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b],
            assignedFlashModelIDs: [.b: ["ad400pro-ii"]]
        ))
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.setGlobalMultiFlashEnabled(true)
        fixture.controller.applyPendingChanges()
        acknowledgeGATTWrite(fixture.transport)
        acknowledgeGroupWrite(fixture.transport)
        XCTAssertEqual(fixture.controller.phase, .ready)

        fixture.controller.setMultiFlashHertz(199)
        fixture.controller.setMultiFlashHertz(200)

        XCTAssertEqual(fixture.controller.multiFlashDraft.hertz, 199)
        XCTAssertEqual(fixture.controller.multiFlashDraft.hertzByte, 0xC7)
        XCTAssertNil(
            MultiFlashLimitProfile.ad400ProII.maximumFlashCount(
                power: fixture.controller.multiFlashDraft.power,
                hertz: 199
            )
        )
        XCTAssertFalse(fixture.controller.hasVerifiedMultiFlashCountLimit)
        XCTAssertFalse(fixture.controller.hasConservativeMultiFlashCountLimit)
        XCTAssertTrue(fixture.controller.hasUnverifiedMultiFlashCountLimit)
        XCTAssertEqual(
            fixture.controller.multiFlashMaximumCount,
            MultiFlashSettings.countRange.upperBound
        )

        let writesBeforeApply = fixture.transport.controlPayloads.count
        fixture.controller.applyPendingChanges()

        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeApply + 1)
        let global = try XCTUnwrap(
            SafeGodoxProtocol.globalSnapshot(
                from: fixture.transport.controlPayloads[writesBeforeApply]
            )
        )
        XCTAssertEqual(global.multiHertz, 0xC7)

        acknowledgeGATTWrite(fixture.transport)
        XCTAssertEqual(fixture.controller.multiFlashBaseline.hertz, 199)
        XCTAssertEqual(fixture.controller.phase, .ready)
    }

    func testGlobalMultiToggleIsBlockedDuringInteractiveMultiScrub() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.setGlobalMultiFlashEnabled(true)
        fixture.controller.applyPendingChanges()
        acknowledgeGATTWrite(fixture.transport)
        for _ in fixture.controller.workingGroups {
            acknowledgeGroupWrite(fixture.transport)
        }
        XCTAssertEqual(fixture.controller.phase, .ready)

        let token = fixture.controller.beginInteractiveEdit()
        XCTAssertTrue(fixture.controller.isInteractiveEditActive)
        XCTAssertTrue(
            fixture.controller.canEditMultiFlashSettings,
            "The active Multi scrub must remain allowed while its own token is live."
        )
        XCTAssertFalse(fixture.controller.canSetGlobalMultiFlashEnabled(false))

        let previousCount = fixture.controller.multiFlashDraft.count
        fixture.controller.setMultiFlashCount(previousCount + 1)
        XCTAssertEqual(fixture.controller.multiFlashDraft.count, previousCount + 1)

        fixture.controller.setGlobalMultiFlashEnabled(false)
        XCTAssertFalse(
            fixture.controller.multiFlashGroups.isEmpty,
            "A global mode toggle must not run underneath an active scrub."
        )

        fixture.controller.cancelInteractiveEdit(token)
    }

    func testGlobalMultiTransitionPendingTracksOnlyModeToggle() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        XCTAssertNil(fixture.controller.pendingGlobalMultiFlashTransition)

        fixture.controller.setGlobalMultiFlashEnabled(true)

        XCTAssertEqual(fixture.controller.pendingGlobalMultiFlashTransition, .enabling)
        XCTAssertGreaterThan(fixture.controller.pendingCount, 0)

        let alternatePower = try XCTUnwrap(
            fixture.controller.allowedMultiFlashPowers.first {
                $0 != fixture.controller.multiFlashDraft.power
            }
        )
        fixture.controller.setMultiFlashPower(alternatePower)

        XCTAssertNil(
            fixture.controller.pendingGlobalMultiFlashTransition,
            "A Multi power edit is not a global mode transition."
        )
        fixture.controller.discardPendingChanges()

        fixture.controller.setGlobalMultiFlashEnabled(true)
        XCTAssertEqual(fixture.controller.pendingGlobalMultiFlashTransition, .enabling)

        fixture.controller.setMultiFlashCount(fixture.controller.multiFlashDraft.count + 1)

        XCTAssertNil(
            fixture.controller.pendingGlobalMultiFlashTransition,
            "A Multi count edit is not a global mode transition."
        )
        XCTAssertGreaterThan(fixture.controller.pendingCount, 0)

        fixture.controller.discardPendingChanges()

        fixture.controller.setGlobalMultiFlashEnabled(true)
        XCTAssertEqual(fixture.controller.pendingGlobalMultiFlashTransition, .enabling)
        fixture.controller.setMultiFlashHertz(fixture.controller.multiFlashDraft.hertz + 1)

        XCTAssertNil(
            fixture.controller.pendingGlobalMultiFlashTransition,
            "A Multi Hz edit is not a global mode transition."
        )
        XCTAssertGreaterThan(fixture.controller.pendingCount, 0)

        fixture.controller.discardPendingChanges()

        XCTAssertNil(fixture.controller.pendingGlobalMultiFlashTransition)
        XCTAssertEqual(fixture.controller.pendingCount, 0)

        fixture.controller.setGlobalMultiFlashEnabled(true)
        XCTAssertEqual(fixture.controller.pendingGlobalMultiFlashTransition, .enabling)
        fixture.controller.applyPendingChanges()
        acknowledgeGATTWrite(fixture.transport)
        for _ in fixture.controller.workingGroups {
            acknowledgeGroupWrite(fixture.transport)
        }

        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertEqual(fixture.controller.pendingCount, 0)
        XCTAssertNil(fixture.controller.pendingGlobalMultiFlashTransition)

        fixture.controller.setGlobalMultiFlashEnabled(false)
        XCTAssertEqual(fixture.controller.pendingGlobalMultiFlashTransition, .disabling)
        fixture.controller.disconnect()
        fixture.transport.emit(.stateChanged(.idle))

        XCTAssertNil(fixture.controller.pendingGlobalMultiFlashTransition)
    }

    func testContinuousMultiEditPersistsAndSchedulesOnlyItsFinalSettings() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        fixture.controller.setGlobalMultiFlashEnabled(true)
        XCTAssertTrue(fixture.controller.canApply)
        fixture.controller.applyPendingChanges()
        acknowledgeGATTWrite(fixture.transport)
        for _ in fixture.controller.workingGroups {
            acknowledgeGroupWrite(fixture.transport)
        }
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertEqual(fixture.controller.pendingCount, 0)

        fixture.controller.setChangeDeliveryMode(.automatic)
        let writesBeforeGesture = fixture.transport.controlPayloads.count
        let savesBeforeGesture = fixture.studioLibrary.saveCount
        let token = fixture.controller.beginInteractiveEdit()

        fixture.controller.setMultiFlashCount(9)
        fixture.controller.setMultiFlashHertz(12)
        fixture.controller.setMultiFlashCount(8)
        fixture.controller.setMultiFlashHertz(14)

        XCTAssertEqual(fixture.controller.multiFlashDraft.count, 8)
        XCTAssertEqual(fixture.controller.multiFlashDraft.hertz, 14)
        XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeGesture)
        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeGesture)
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 0)

        fixture.controller.endInteractiveEdit(token)

        XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeGesture + 1)
        XCTAssertEqual(
            fixture.studioLibrary.library?.workspace.multiFlashSettings,
            fixture.controller.multiFlashDraft
        )
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 1)
        XCTAssertTrue(fixture.scheduler.fire(.automaticApply))
        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeGesture + 1)
    }

    func testCancelledContinuousEditPersistsFinalValueWithoutAutomaticDelivery() async throws {
        let fixture = makeFixture()
        completeWorkspace(fixture.controller)
        try await connectAndSynchronizeTransport(fixture)
        finishInitialValueSynchronization(fixture)

        let writesBeforeGesture = fixture.transport.controlPayloads.count
        let savesBeforeGesture = fixture.studioLibrary.saveCount
        fixture.controller.setChangeDeliveryMode(.automatic)
        let firstToken = fixture.controller.beginInteractiveEdit()
        let finalToken = fixture.controller.beginInteractiveEdit()
        let nextIndex = min(
            fixture.controller.powerIndex(for: .c) + 1,
            fixture.controller.allowedPowers(for: .c).count - 1
        )
        fixture.controller.setDraftPowerIndex(nextIndex, for: .c)

        XCTAssertTrue(fixture.controller.isInteractiveEditActive)
        XCTAssertGreaterThan(fixture.controller.pendingCount, 0)
        XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeGesture)
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 0)

        fixture.controller.endInteractiveEdit(firstToken)
        XCTAssertTrue(fixture.controller.isInteractiveEditActive)
        XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeGesture)
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 0)

        let finalPower = fixture.controller.groupDraft(.c).draft.power
        fixture.controller.cancelInteractiveEdit(finalToken)

        XCTAssertFalse(fixture.controller.isInteractiveEditActive)
        XCTAssertEqual(fixture.studioLibrary.saveCount, savesBeforeGesture + 1)
        XCTAssertEqual(
            fixture.studioLibrary.library?
                .workspace.groupConfigurations[.c]?.snapshot.power,
            finalPower
        )
        XCTAssertEqual(fixture.scheduler.activeCount(.automaticApply), 0)
        XCTAssertFalse(fixture.scheduler.fire(.automaticApply))
        XCTAssertEqual(fixture.transport.controlPayloads.count, writesBeforeGesture)
    }

    func testTestCommandFailsFastAndIsNeverRetried() async throws {
        let fixture = makeFixture()
        try await connectAndSynchronizeTransport(fixture)
        fixture.transport.failTestSynchronously = true

        fixture.controller.sendTestFlash()

        XCTAssertEqual(fixture.transport.testWriteCount, 1)
        XCTAssertFalse(fixture.controller.isTestPending)
        XCTAssertEqual(fixture.scheduler.activeCount(.testDelivery), 0)
        XCTAssertFalse(fixture.scheduler.fire(.testDelivery))
        XCTAssertEqual(fixture.transport.testWriteCount, 1)
        XCTAssertEqual(fixture.controller.testDeliveryResult?.outcome, .failed)
        XCTAssertTrue(
            fixture.controller.activity.last?.message.contains("Test no enviado") == true
        )
    }

    func testSimulatedTestPublishesItsOwnCorrelatedOutcome() async throws {
        let fixture = makeFixture()
        fixture.transport.isSimulation = true
        try await connectAndSynchronizeTransport(fixture)

        fixture.controller.sendTestFlash()
        fixture.transport.emit(.commandSent(.test))

        let result = try XCTUnwrap(fixture.controller.testDeliveryResult)
        XCTAssertEqual(result.outcome, .simulated)
        XCTAssertFalse(fixture.controller.isTestPending)
    }

    func testTestTimeoutPublishesFailureUntilSessionResetClearsIt() async throws {
        let fixture = makeFixture()
        try await connectAndSynchronizeTransport(fixture)

        fixture.controller.sendTestFlash()

        XCTAssertTrue(fixture.scheduler.fire(.testDelivery))
        XCTAssertEqual(fixture.controller.testDeliveryResult?.outcome, .failed)
        XCTAssertEqual(fixture.controller.phase, .disconnecting)

        fixture.transport.emit(.stateChanged(.idle))

        XCTAssertNil(fixture.controller.testDeliveryResult)
        XCTAssertFalse(fixture.controller.isTestPending)
    }

    private func makeFixture(
        restorations: MemoryRestorationRepository = MemoryRestorationRepository(),
        savedRadioStore: any SavedRadioRepository = EmptySavedRadioRepository(),
        connectionPreferences: MemoryRadioConnectionPreferences = MemoryRadioConnectionPreferences(),
        requiresExplicitInitialValueSynchronizationConfirmation: Bool = false,
        stagesNewWorkingGroupsAtSafeMinimum: Bool = false
    ) -> Fixture {
        let transport = RecordingRadioTransport()
        let scheduler = ManualDeadlineScheduler()
        let changeDelivery = MemoryChangeDeliveryPreferences()
        let studioLibrary = MemoryStudioLibraryRepository()
        let controller = GodoxSessionController(
            transport: transport,
            deadlineScheduler: scheduler,
            visibilityPreferences: MemoryGroupVisibilityPreferences(),
            restorationStore: restorations,
            savedRadioStore: savedRadioStore,
            changeDeliveryPreferences: changeDelivery,
            radioConnectionPreferences: connectionPreferences,
            transmitterProfilePreferences: MemoryTransmitterProfilePreferences(),
            studioLibraryStore: studioLibrary,
            requiresExplicitInitialValueSynchronizationConfirmation:
                requiresExplicitInitialValueSynchronizationConfirmation,
            stagesNewWorkingGroupsAtSafeMinimum: stagesNewWorkingGroupsAtSafeMinimum
        )
        return Fixture(
            controller: controller,
            transport: transport,
            scheduler: scheduler,
            restorations: restorations,
            changeDelivery: changeDelivery,
            connectionPreferences: connectionPreferences,
            studioLibrary: studioLibrary
        )
    }

    private func completeWorkspace(_ controller: GodoxSessionController) {
        XCTAssertTrue(controller.completeWorkspaceConfiguration(
            profileID: TransmitterProfile.observedGDBH.id,
            selectedGroups: [.b, .c],
            assignedFlashModelIDs: [
                .b: ["ad600pro-ii"],
                .c: ["ad400pro"],
            ]
        ))
    }

    private func connectAndSynchronizeTransport(_ fixture: Fixture) async throws {
        let syncCountBeforeConnection = fixture.transport.sentCommands.filter {
            $0 == .sync
        }.count
        fixture.controller.startScanning()
        fixture.transport.emit(.discovered(device))
        fixture.controller.radioCode = "111111"
        fixture.controller.connectSelectedDevice()
        fixture.transport.emit(.stateChanged(.ready(device)))
        fixture.transport.emit(.readyForAuthentication)
        fixture.transport.emit(.notification(
            .authentication,
            validAuthenticationResponse()
        ))

        for _ in 0..<30 where fixture.transport.sentCommands.filter({
            $0 == .sync
        }).count == syncCountBeforeConnection {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(
            fixture.transport.sentCommands.filter { $0 == .sync }.count,
            syncCountBeforeConnection + 1,
            "PWOK must lead to one delivered Sync command."
        )
    }

    private func finishInitialValueSynchronization(_ fixture: Fixture) {
        XCTAssertTrue(fixture.scheduler.fire(.valueSynchronizationSettle))
        acknowledgeGATTWrite(fixture.transport)
        for _ in fixture.controller.workingGroups {
            acknowledgeGroupWrite(fixture.transport)
        }
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertTrue(fixture.controller.restorationPoints.isEmpty)
    }

    private func acknowledgeGATTWrite(_ transport: RecordingRadioTransport) {
        transport.emit(.controlWriteStarted)
        transport.emit(.controlWriteCompleted)
    }

    private func acknowledgeGroupWrite(_ transport: RecordingRadioTransport) {
        acknowledgeGATTWrite(transport)
        transport.emit(.notification(.control, Data([0xF0, 0xA1])))
    }

    private func decodedGroup(_ payload: Data) -> GodoxGroup? {
        SafeGodoxProtocol.groupSnapshot(from: payload)?.0
    }

    private func validAuthenticationResponse(now: Date = Date()) -> Data {
        let unixSeconds = Int64(now.timeIntervalSince1970.rounded(.towardZero))
        let decodedTime = Int((10_000 - (unixSeconds % 10_000)) % 10_000)
        let decodedDigits = String(format: "%04d", decodedTime)
        let encodedDigits = decodedDigits.map { character -> Character in
            let digit = character.wholeNumberValue!
            return Character(UnicodeScalar(54 + digit)!)
        }
        return Data("PWOK,;\(String(encodedDigits))".utf8)
    }
}

@MainActor
private struct Fixture {
    let controller: GodoxSessionController
    let transport: RecordingRadioTransport
    let scheduler: ManualDeadlineScheduler
    let restorations: MemoryRestorationRepository
    let changeDelivery: MemoryChangeDeliveryPreferences
    let connectionPreferences: MemoryRadioConnectionPreferences
    let studioLibrary: MemoryStudioLibraryRepository
}

@MainActor
private final class ManualDeadlineScheduler: SessionDeadlineScheduling {
    private struct Entry {
        let token: SessionDeadlineToken
        let action: @MainActor () -> Void
    }

    private var entries: [SessionDeadlineKind: [Entry]] = [:]

    func schedule(
        _ kind: SessionDeadlineKind,
        action: @escaping @MainActor () -> Void
    ) -> SessionDeadlineToken {
        let token = SessionDeadlineToken()
        entries[kind, default: []].append(Entry(token: token, action: action))
        return token
    }

    func activeCount(_ kind: SessionDeadlineKind) -> Int {
        entries[kind, default: []].filter { !$0.token.isCancelled }.count
    }

    @discardableResult
    func fire(_ kind: SessionDeadlineKind) -> Bool {
        while var pending = entries[kind], !pending.isEmpty {
            let entry = pending.removeFirst()
            entries[kind] = pending
            guard !entry.token.isCancelled else { continue }
            entry.action()
            return true
        }
        return false
    }
}

@MainActor
private final class RecordingRadioTransport: RadioTransport {
    enum SentCommand: Equatable {
        case authentication
        case sync
        case test
        case control
    }

    var eventHandler: ((TransportEvent) -> Void)?
    private(set) var sentCommands: [SentCommand] = []
    private(set) var controlPayloads: [Data] = []
    private(set) var testWriteCount = 0
    private(set) var scanCount = 0
    private(set) var stopScanCount = 0
    private(set) var connectedCandidates: [RadioCandidate] = []
    private(set) var disconnectCount = 0
    private(set) var forceResetCount = 0
    var isSimulation = false
    var failTestSynchronously = false
    var discoveryOnScan: RadioCandidate?
    var emitsIdleWhenStoppingScan = false

    func startScanning() {
        scanCount += 1
        if let discoveryOnScan {
            eventHandler?(.discovered(discoveryOnScan))
        }
    }
    func stopScanning() {
        stopScanCount += 1
        if emitsIdleWhenStoppingScan {
            eventHandler?(.stateChanged(.idle))
        }
    }
    func connect(to candidate: RadioCandidate) {
        connectedCandidates.append(candidate)
    }

    func disconnect() {
        disconnectCount += 1
    }

    func forceResetConnection() {
        forceResetCount += 1
    }

    func sendAuthentication(_ payload: Data) {
        sentCommands.append(.authentication)
        eventHandler?(.commandSent(.authentication))
    }

    func sendSync(_ payload: Data) {
        sentCommands.append(.sync)
        eventHandler?(.commandSent(.sync))
    }

    func sendTest(_ payload: Data) {
        sentCommands.append(.test)
        testWriteCount += 1
        if failTestSynchronously {
            eventHandler?(.commandFailed(
                .test,
                .writeFailed(command: .test, message: "synthetic fail-fast")
            ))
        }
    }

    func sendControl(_ payload: Data) {
        sentCommands.append(.control)
        controlPayloads.append(payload)
    }

    func emit(_ event: TransportEvent) {
        eventHandler?(event)
    }
}

@MainActor
private final class MemoryRestorationRepository: RestorationRepository {
    var points: [GodoxGroup: GroupRestorationPoint]?
    var acceptsSave = true
    var acceptsClear = true
    private(set) var saveCount = 0
    private(set) var clearCount = 0

    func load() -> RestorationLoadResult {
        points.map(RestorationLoadResult.batch(points:)) ?? .none
    }

    func save(points: [GodoxGroup: GroupRestorationPoint]) -> Bool {
        saveCount += 1
        guard acceptsSave else { return false }
        self.points = points
        return true
    }

    func clear() -> Bool {
        clearCount += 1
        guard acceptsClear else { return false }
        points = nil
        return true
    }
}

@MainActor
private final class EmptySavedRadioRepository: SavedRadioRepository {
    func load() -> SavedRadioLoadResult { .none }
    func upsert(_ radio: SavedRadio) -> Bool { true }
    func remove(deviceID: UUID) -> Bool { true }
    func clear() -> Bool { true }
}

@MainActor
private final class InvalidSavedRadioRepository: SavedRadioRepository {
    func load() -> SavedRadioLoadResult { .invalid }
    func upsert(_ radio: SavedRadio) -> Bool { false }
    func remove(deviceID: UUID) -> Bool { false }
    func clear() -> Bool { false }
}

@MainActor
private final class MemorySavedRadioRepository: SavedRadioRepository {
    private(set) var radios: [SavedRadio]

    init(radios: [SavedRadio]) {
        self.radios = radios
    }

    func load() -> SavedRadioLoadResult {
        radios.isEmpty ? .none : .records(radios)
    }

    func upsert(_ radio: SavedRadio) -> Bool {
        if let index = radios.firstIndex(where: { $0.deviceID == radio.deviceID }) {
            radios[index] = radio
        } else {
            radios.append(radio)
        }
        return true
    }

    func remove(deviceID: UUID) -> Bool {
        radios.removeAll { $0.deviceID == deviceID }
        return true
    }

    func clear() -> Bool {
        radios.removeAll()
        return true
    }
}

@MainActor
private final class MemoryRadioConnectionPreferences:
    RadioConnectionPreferencesStore {
    private(set) var state: RadioConnectionPreferenceState
    private(set) var saveCount = 0
    var acceptsSave = true

    init(
        state: RadioConnectionPreferenceState = RadioConnectionPreferenceState(
            lastConnectedRadioID: nil,
            automaticConnectionRadioID: nil
        )
    ) {
        self.state = state
    }

    func load() -> RadioConnectionPreferenceState { state }

    func save(_ state: RadioConnectionPreferenceState) -> Bool {
        saveCount += 1
        guard acceptsSave else { return false }
        self.state = state
        return true
    }
}

@MainActor
private final class MemoryStudioLibraryRepository: StudioLibraryRepository {
    private(set) var library: StudioLibrary?
    private(set) var saveCount = 0

    func load() -> StudioLibraryLoadResult {
        library.map(StudioLibraryLoadResult.record) ?? .none
    }

    func save(_ library: StudioLibrary) -> Bool {
        saveCount += 1
        self.library = library
        return true
    }
}

@MainActor
private final class MemoryGroupVisibilityPreferences: GroupVisibilityPreferencesStore {
    func loadVisibleGroups(
        supportedGroups: [GodoxGroup],
        defaultVisibleGroups: [GodoxGroup]?
    ) -> [GodoxGroup] {
        let requested = defaultVisibleGroups ?? supportedGroups
        return supportedGroups.filter(requested.contains)
    }

    func saveVisibleGroups(
        _ visibleGroups: [GodoxGroup],
        supportedGroups: [GodoxGroup]
    ) -> [GodoxGroup] {
        supportedGroups.filter(visibleGroups.contains)
    }
}

@MainActor
private final class MemoryChangeDeliveryPreferences: ChangeDeliveryPreferencesStore {
    private(set) var mode: ChangeDeliveryMode = .manual

    func load() -> ChangeDeliveryMode { mode }

    func save(_ mode: ChangeDeliveryMode) {
        self.mode = mode
    }
}

@MainActor
private final class MemoryTransmitterProfilePreferences: TransmitterProfilePreferencesStore {
    func load(
        builtInProfileIDs: [String],
        fallbackDefaultProfileID: String
    ) -> TransmitterProfilePreferenceState {
        TransmitterProfilePreferenceState(
            availableProfileIDs: builtInProfileIDs,
            defaultProfileID: fallbackDefaultProfileID
        )
    }

    func save(
        _ state: TransmitterProfilePreferenceState,
        builtInProfileIDs: [String],
        fallbackDefaultProfileID: String
    ) -> Bool {
        true
    }
}
