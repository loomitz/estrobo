import AppKit
import Darwin
import Foundation
import SwiftUI

@MainActor
private final class InteractiveTestDeadlineScheduler: SessionDeadlineScheduling {
    private final class Entry {
        let token: SessionDeadlineToken
        let action: @MainActor () -> Void
        var didFire = false

        init(token: SessionDeadlineToken, action: @escaping @MainActor () -> Void) {
            self.token = token
            self.action = action
        }
    }

    private var entries: [SessionDeadlineKind: [Entry]] = [:]
    private(set) var scheduleCounts: [SessionDeadlineKind: Int] = [:]
    private(set) var fireDelays: [SessionDeadlineKind: [TimeInterval]] = [:]
    private let realtimeAutomaticApply: Bool

    init(realtimeAutomaticApply: Bool = false) {
        self.realtimeAutomaticApply = realtimeAutomaticApply
    }

    func schedule(
        _ kind: SessionDeadlineKind,
        action: @escaping @MainActor () -> Void
    ) -> SessionDeadlineToken {
        let token = SessionDeadlineToken()
        let entry = Entry(token: token, action: action)
        entries[kind, default: []].append(entry)
        scheduleCounts[kind, default: 0] += 1

        if realtimeAutomaticApply, kind == .automaticApply {
            let scheduledAt = ProcessInfo.processInfo.systemUptime
            let task = Task { @MainActor [weak self, weak entry] in
                do {
                    try await Task.sleep(for: kind.duration)
                } catch {
                    return
                }
                guard let entry, !entry.token.isCancelled, !entry.didFire else { return }
                entry.didFire = true
                self?.fireDelays[kind, default: []].append(
                    ProcessInfo.processInfo.systemUptime - scheduledAt
                )
                entry.action()
            }
            token.installCancellation { task.cancel() }
        }
        return token
    }

    func activeCount(_ kind: SessionDeadlineKind) -> Int {
        entries[kind, default: []].filter {
            !$0.token.isCancelled && !$0.didFire
        }.count
    }

    @discardableResult
    func fireNext(_ kind: SessionDeadlineKind) -> Bool {
        guard let entry = entries[kind, default: []].first(where: { !$0.didFire }) else {
            return false
        }
        entry.didFire = true
        guard !entry.token.isCancelled else { return false }
        entry.action()
        return true
    }
}

@MainActor
private final class InteractiveFakeTransport: GodoxSessionTransport {
    weak var delegate: (any BluetoothClientDelegate)?
    let isSimulation = true

    private(set) var controlPayloads: [Data] = []
    private(set) var testPayloads: [Data] = []
    private(set) var disconnectCount = 0

    func startScanning() {
        emit(.stateChanged(.scanning))
    }

    func stopScanning() {
        emit(.stateChanged(.idle))
    }

    func connect(to device: BluetoothClient.Device) {
        emit(.stateChanged(.connecting(device)))
    }

    func disconnect() {
        disconnectCount += 1
        emit(.stateChanged(.disconnecting(interactiveTestDevice)))
    }

    func forceResetConnection() {
        emit(.discoveryReset)
        emit(.stateChanged(.idle))
    }

    func sendAuthentication(_ payload: Data) {
        emit(.commandSent(.authentication))
    }

    func sendSync(_ payload: Data) {
        emit(.commandSent(.sync))
    }

    func sendTest(_ payload: Data) {
        testPayloads.append(payload)
    }

    func sendControl(_ payload: Data) {
        controlPayloads.append(payload)
    }

    func emit(_ event: BluetoothClient.Event) {
        delegate?.bluetoothClient(didReceive: event)
    }
}

private let interactiveTestDevice = BluetoothClient.Device(
    id: UUID(uuidString: "BEE70000-1111-4222-8333-444444444444")!,
    name: "ESTROBO-INTERACTION-TEST",
    rssi: -38
)

@MainActor
private struct InteractiveFixture {
    let controller: GodoxSessionController
    let transport: InteractiveFakeTransport
    let scheduler: InteractiveTestDeadlineScheduler
}

@MainActor
private final class HarnessPresentationState: ObservableObject {
    @Published var showsControl = true
    @Published var isEnabled = true
}

@MainActor
private struct HorizontalPowerHarness: View {
    @ObservedObject var controller: GodoxSessionController
    @ObservedObject var presentation: HarnessPresentationState

    var body: some View {
        Group {
            if presentation.showsControl {
                DiscretePowerSlider(
                    group: .c,
                    value: controller.groupDraft(.c).draft.power,
                    allowed: controller.allowedPowers(for: .c),
                    enabled: presentation.isEnabled && controller.canEdit(.c),
                    onChange: { controller.setDraftPower(.c, power: $0) }
                )
                .frame(width: 300, height: 44)
            }
        }
        .frame(width: 320, height: 64)
    }
}

@MainActor
private struct VerticalPowerHarness: View {
    @ObservedObject var controller: GodoxSessionController
    @ObservedObject var presentation: HarnessPresentationState

    var body: some View {
        Group {
            if presentation.showsControl {
                VerticalDiscretePowerControl(
                    group: .c,
                    value: controller.groupDraft(.c).draft.power,
                    allowed: controller.allowedPowers(for: .c),
                    enabled: presentation.isEnabled && controller.canEdit(.c),
                    onChange: { controller.setDraftPower(.c, power: $0) }
                )
                .frame(width: 112, height: 250)
            }
        }
        .frame(width: 132, height: 270)
    }
}

@MainActor
private struct FixedIntensityHarness: View {
    @ObservedObject var controller: GodoxSessionController
    @ObservedObject var presentation: HarnessPresentationState

    var body: some View {
        Group {
            if presentation.showsControl {
                VerticalFixedIntensityControl(
                    group: .c,
                    percent: currentPercent,
                    allowedPercents: fixedPercents,
                    enabled: presentation.isEnabled && controller.canEdit(.c),
                    compact: false,
                    onChange: {
                        controller.setDraftModeling(.c, modeling: .fixed(percent: $0))
                    }
                )
                .frame(width: 112, height: 166)
            }
        }
        .frame(width: 132, height: 186)
    }

    private var currentPercent: Int {
        guard case .fixed(let percent) = controller.groupDraft(.c).draft.modeling else {
            return 50
        }
        return percent
    }

    private var fixedPercents: [Int] {
        Array(Set(controller.allowedModelingLights(for: .c).compactMap {
            guard case .fixed(let percent) = $0 else { return nil }
            return percent
        })).sorted()
    }
}

@main
@MainActor
enum InteractiveEditingCheck {
    static func main() {
        checkCentralTokenTransaction()
        checkBeginCancelsExistingDeadline()
        checkReturningToBaselineDoesNotSend()
        checkConcurrentAndIdempotentTokens()
        checkDiscardAndManualMode()
        checkDiscreteChangesRemainNormal()
        checkSessionCancellationReleasesTokens()
        checkRealPointerHarness()
        print(
            "Interactive edit tokens, delivery gates, discard/manual behavior, "
                + "accessibility, and real mouse lifecycle verified"
        )
    }

    private static func checkCentralTokenTransaction() {
        let fixture = makeReadyFixture()
        let powers = alternatePowers(in: fixture.controller)
        let token = fixture.controller.beginInteractiveEdit()

        fixture.controller.setDraftPower(.c, power: powers.first)
        fixture.controller.setDraftPower(.c, power: powers.last)

        expect(fixture.controller.isInteractiveEditActive)
        expect(fixture.controller.activeInteractiveEditCount == 1)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.transport.controlPayloads.isEmpty)
        expect(!fixture.controller.canApply)
        expect(!fixture.controller.canSynchronizeValues)
        expect(!fixture.controller.canSendTest)
        expect(!fixture.controller.canManagePresets)
        expect(!fixture.controller.canConfigureWorkspace)
        expect(fixture.controller.canDisconnect)

        fixture.controller.applyPendingChanges()
        fixture.controller.synchronizeValuesToRadio()
        fixture.controller.sendTestFlash()
        expect(fixture.transport.controlPayloads.isEmpty)
        expect(fixture.transport.testPayloads.isEmpty)

        fixture.controller.endInteractiveEdit(token)
        expect(!fixture.controller.isInteractiveEditActive)
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        expect(fixture.scheduler.scheduleCounts[.automaticApply] == 1)

        expect(fixture.scheduler.fireNext(.automaticApply))
        expect(fixture.transport.controlPayloads.count == 1)
        guard let decoded = SafeGodoxProtocol.groupSnapshot(
            from: fixture.transport.controlPayloads[0]
        ) else {
            fail("The final interactive payload was not a valid A1 snapshot")
        }
        expect(decoded.0 == .c)
        expect(decoded.1.power == powers.last, "Only the last dragged value may be sent")
    }

    private static func checkReturningToBaselineDoesNotSend() {
        let fixture = makeReadyFixture()
        let baseline = fixture.controller.groupDraft(.c).baseline.power
        let changed = alternatePowers(in: fixture.controller).first
        let token = fixture.controller.beginInteractiveEdit()

        fixture.controller.setDraftPower(.c, power: changed)
        fixture.controller.setDraftPower(.c, power: baseline)
        fixture.controller.endInteractiveEdit(token)

        expect(fixture.controller.pendingCount == 0)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(fixture.transport.controlPayloads.isEmpty)
    }

    private static func checkBeginCancelsExistingDeadline() {
        let fixture = makeReadyFixture()
        let changed = alternatePowers(in: fixture.controller).first
        fixture.controller.setDraftPower(.c, power: changed)
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        expect(fixture.controller.isAutomaticApplyScheduled)

        let token = fixture.controller.beginInteractiveEdit()
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
        expect(!fixture.controller.isAutomaticApplyScheduled)
        expect(!fixture.scheduler.fireNext(.automaticApply))
        expect(fixture.transport.controlPayloads.isEmpty)

        fixture.controller.endInteractiveEdit(token)
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
    }

    private static func checkConcurrentAndIdempotentTokens() {
        let fixture = makeReadyFixture()
        let changed = alternatePowers(in: fixture.controller).first
        let first = fixture.controller.beginInteractiveEdit()
        let second = fixture.controller.beginInteractiveEdit()

        fixture.controller.setDraftPower(.c, power: changed)
        fixture.controller.endInteractiveEdit(first)
        fixture.controller.endInteractiveEdit(first)

        expect(fixture.controller.activeInteractiveEditCount == 1)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)

        fixture.controller.endInteractiveEdit(second)
        fixture.controller.endInteractiveEdit(second)
        expect(fixture.controller.activeInteractiveEditCount == 0)
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        expect(
            fixture.scheduler.scheduleCounts[.automaticApply] == 1,
            "The last token must arm exactly one deadline"
        )
    }

    private static func checkDiscardAndManualMode() {
        do {
            let fixture = makeReadyFixture()
            let baseline = fixture.controller.groupDraft(.c).baseline.power
            let changed = alternatePowers(in: fixture.controller).first
            let token = fixture.controller.beginInteractiveEdit()
            fixture.controller.setDraftPower(.c, power: changed)
            fixture.controller.endInteractiveEdit(token)
            expect(fixture.scheduler.activeCount(.automaticApply) == 1)

            fixture.controller.discardPendingChanges()
            expect(fixture.controller.groupDraft(.c).draft.power == baseline)
            expect(fixture.controller.pendingCount == 0)
            expect(fixture.scheduler.activeCount(.automaticApply) == 0)
            expect(!fixture.scheduler.fireNext(.automaticApply))
            expect(fixture.transport.controlPayloads.isEmpty)
        }

        do {
            let fixture = makeReadyFixture(deliveryMode: .manual)
            let baseline = fixture.controller.groupDraft(.c).baseline.power
            let changed = alternatePowers(in: fixture.controller).first
            let token = fixture.controller.beginInteractiveEdit()
            fixture.controller.setDraftPower(.c, power: changed)

            fixture.controller.discardPendingChanges()
            expect(
                fixture.controller.groupDraft(.c).draft.power == changed,
                "Discard must not replace a draft during a held pointer gesture"
            )
            fixture.controller.applyPendingChanges()
            expect(fixture.transport.controlPayloads.isEmpty)

            fixture.controller.endInteractiveEdit(token)
            expect(fixture.scheduler.activeCount(.automaticApply) == 0)
            expect(fixture.controller.canApply)
            fixture.controller.applyPendingChanges()
            expect(fixture.transport.controlPayloads.count == 1)
            expect(fixture.controller.groupDraft(.c).baseline.power == baseline)
        }
    }

    private static func checkDiscreteChangesRemainNormal() {
        do {
            let fixture = makeReadyFixture()
            let allowed = fixture.controller.allowedPowers(for: .c)
            let value = fixture.controller.groupDraft(.c).draft.power
            guard let currentIndex = allowed.firstIndex(of: value) else {
                fail("The keyboard fixture power is outside its slider scale")
            }
            let targetIndex = currentIndex < allowed.count - 1
                ? currentIndex + 1
                : currentIndex - 1
            let control = DiscretePowerSlider(
                group: .c,
                value: value,
                allowed: allowed,
                enabled: true,
                onChange: { fixture.controller.setDraftPower(.c, power: $0) }
            )

            // This is the production Slider binding used by keyboard input.
            control.applyDiscreteInput(Double(targetIndex))
            expect(fixture.controller.groupDraft(.c).draft.power == allowed[targetIndex])
            expect(!fixture.controller.isInteractiveEditActive)
            expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        }

        do {
            let fixture = makeReadyFixture()
            let allowed = fixture.controller.allowedPowers(for: .c)
            let value = fixture.controller.groupDraft(.c).draft.power
            guard let currentIndex = allowed.firstIndex(of: value) else {
                fail("The VoiceOver fixture power is outside its vertical scale")
            }
            let direction: AccessibilityAdjustmentDirection =
                currentIndex < allowed.count - 1 ? .increment : .decrement
            let control = VerticalDiscretePowerControl(
                group: .c,
                value: value,
                allowed: allowed,
                enabled: true,
                onChange: { fixture.controller.setDraftPower(.c, power: $0) }
            )

            // This is the production accessibilityAdjustableAction handler.
            control.applyAccessibilityAdjustment(direction)
            expect(!fixture.controller.isInteractiveEditActive)
            expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        }

        do {
            let fixture = makeReadyFixture()
            let fixedPercents: [Int] = Array(Set<Int>(
                fixture.controller.allowedModelingLights(for: .c).compactMap {
                    guard case .fixed(let percent) = $0 else { return nil }
                    return percent
                }
            )).sorted()
            guard fixedPercents.count > 1 else {
                fail("The VoiceOver fixture needs fixed modeling intensities")
            }
            let initialIndex = fixedPercents.count / 2
            let control = VerticalFixedIntensityControl(
                group: .c,
                percent: fixedPercents[initialIndex],
                allowedPercents: fixedPercents,
                enabled: true,
                compact: false,
                onChange: {
                    fixture.controller.setDraftModeling(.c, modeling: .fixed(percent: $0))
                }
            )

            control.applyAccessibilityAdjustment(AccessibilityAdjustmentDirection.increment)
            expect(!fixture.controller.isInteractiveEditActive)
            expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        }
    }

    private static func checkSessionCancellationReleasesTokens() {
        let fixture = makeReadyFixture()
        let token = fixture.controller.beginInteractiveEdit()
        fixture.controller.setDraftPower(.c, power: alternatePowers(in: fixture.controller).first)

        fixture.controller.disconnect()
        expect(fixture.transport.disconnectCount == 1)
        expect(!fixture.controller.isInteractiveEditActive)
        expect(fixture.controller.activeInteractiveEditCount == 0)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)

        fixture.controller.endInteractiveEdit(token)
        expect(fixture.scheduler.activeCount(.automaticApply) == 0)
    }

    private static func checkRealPointerHarness() {
        let app = NSApplication.shared
        checkHorizontalMouseHoldAndFinalDelivery(app: app)
        checkSimpleClickLifecycle(app: app)
        checkVerticalPowerMouseLifecycle(app: app)
        checkFixedIntensityMouseLifecycle(app: app)
        checkGlobalSliderMouseLifecycle(app: app)
        checkViewRemovalAndDisableReleaseTokens(app: app)
    }

    private static func checkHorizontalMouseHoldAndFinalDelivery(app: NSApplication) {
        let fixture = makeReadyFixture(realtimeAutomaticApply: true)
        let presentation = HarnessPresentationState()
        let window = makeWindow(
            rootView: HorizontalPowerHarness(
                controller: fixture.controller,
                presentation: presentation
            ),
            controller: fixture.controller,
            size: NSSize(width: 320, height: 64)
        )
        defer { window.orderOut(nil) }

        let point = NSPoint(x: 160, y: 32)
        let target = NSPoint(x: 282, y: 32)

        sendMouse(.leftMouseDown, to: window, at: point, eventNumber: 10, app: app)
        pump(0.04)
        expect(fixture.controller.isInteractiveEditActive, "Mouse-down must begin the edit")

        pump(0.76)
        expect(
            fixture.transport.controlPayloads.isEmpty,
            "Holding beyond 700 ms must produce zero payloads"
        )

        sendMouse(.leftMouseDragged, to: window, at: target, eventNumber: 11, app: app)
        pump(0.76)
        expect(fixture.controller.pendingCount > 0)
        expect(
            fixture.transport.controlPayloads.isEmpty,
            "Pausing during a drag must not send an intermediate value"
        )

        sendMouse(.leftMouseUp, to: window, at: target, eventNumber: 12, app: app)
        pump(0.05)
        expect(!fixture.controller.isInteractiveEditActive)
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        expect(fixture.scheduler.scheduleCounts[.automaticApply] == 1)
        let expectedFinal = fixture.controller.groupDraft(.c).draft.power

        expect(
            fixture.transport.controlPayloads.isEmpty,
            "Mouse-up must not send the final value synchronously"
        )
        expect(
            pumpUntil(timeout: 1.50) {
                fixture.transport.controlPayloads.count == 1
            },
            "Mouse-up must eventually send exactly one final payload"
        )
        expect(
            SessionDeadlineKind.automaticApply.duration == .milliseconds(700),
            "Automatic delivery must request the exact 700 ms debounce"
        )
        guard let measuredDelay = fixture.scheduler.fireDelays[.automaticApply]?.first else {
            fail("The realtime scheduler did not record the automatic delivery deadline")
        }
        expect(
            measuredDelay >= 0.700,
            "Automatic delivery fired before its 700 ms deadline"
        )
        pump(0.20)
        expect(
            fixture.transport.controlPayloads.count == 1,
            "Mouse-up must produce only one final payload"
        )
        guard let decoded = fixture.transport.controlPayloads.first.flatMap({
            SafeGodoxProtocol.groupSnapshot(from: $0)
        }) else {
            fail("The real mouse-up did not produce a valid final A1 payload")
        }
        expect(decoded.1.power == expectedFinal)
    }

    private static func checkVerticalPowerMouseLifecycle(app: NSApplication) {
        let fixture = makeReadyFixture()
        let presentation = HarnessPresentationState()
        let window = makeWindow(
            rootView: VerticalPowerHarness(
                controller: fixture.controller,
                presentation: presentation
            ),
            controller: fixture.controller,
            size: NSSize(width: 132, height: 270)
        )
        defer { window.orderOut(nil) }

        let down = NSPoint(x: 76, y: 80)
        let drag = NSPoint(x: 76, y: 220)
        sendMouse(.leftMouseDown, to: window, at: down, eventNumber: 20, app: app)
        pump(0.03)
        expect(fixture.controller.isInteractiveEditActive)
        sendMouse(.leftMouseDragged, to: window, at: drag, eventNumber: 21, app: app)
        sendMouse(.leftMouseUp, to: window, at: drag, eventNumber: 22, app: app)
        pump(0.04)
        expect(!fixture.controller.isInteractiveEditActive)
        expect(fixture.scheduler.activeCount(.automaticApply) <= 1)
    }

    private static func checkSimpleClickLifecycle(app: NSApplication) {
        let fixture = makeReadyFixture()
        let presentation = HarnessPresentationState()
        let window = makeWindow(
            rootView: HorizontalPowerHarness(
                controller: fixture.controller,
                presentation: presentation
            ),
            controller: fixture.controller,
            size: NSSize(width: 320, height: 64)
        )
        defer { window.orderOut(nil) }

        let point = NSPoint(x: 282, y: 32)
        guard let queuedMouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 16,
            clickCount: 1,
            pressure: 0
        ) else {
            fail("Could not create the queued AppKit mouse-up event")
        }

        // A native slider may synchronously track from mouse-down until it
        // receives mouse-up, so the release must already be in AppKit's queue.
        app.postEvent(queuedMouseUp, atStart: true)
        sendMouse(.leftMouseDown, to: window, at: point, eventNumber: 15, app: app)

        if let pendingMouseUp = app.nextEvent(
            matching: .leftMouseUp,
            until: Date(),
            inMode: .default,
            dequeue: true
        ) {
            expect(
                pendingMouseUp.windowNumber == window.windowNumber
                    && pendingMouseUp.eventNumber == queuedMouseUp.eventNumber,
                "The queued mouse-up was replaced by an unexpected event"
            )
            app.sendEvent(pendingMouseUp)
        } else {
            // NSDragEventTracker may consume the queued event without routing
            // it through NSApplication, so let the local monitor see release.
            app.sendEvent(queuedMouseUp)
        }
        pump(0.05)

        expect(!fixture.controller.isInteractiveEditActive)
        expect(fixture.controller.pendingCount > 0, "A plain click must change the slider value")
        expect(fixture.scheduler.activeCount(.automaticApply) == 1)
        expect(fixture.scheduler.scheduleCounts[.automaticApply] == 1)
    }

    private static func checkFixedIntensityMouseLifecycle(app: NSApplication) {
        let fixture = makeReadyFixture()
        let presentation = HarnessPresentationState()
        let window = makeWindow(
            rootView: FixedIntensityHarness(
                controller: fixture.controller,
                presentation: presentation
            ),
            controller: fixture.controller,
            size: NSSize(width: 132, height: 186)
        )
        defer { window.orderOut(nil) }

        let down = NSPoint(x: 58, y: 58)
        let drag = NSPoint(x: 58, y: 138)
        sendMouse(.leftMouseDown, to: window, at: down, eventNumber: 30, app: app)
        pump(0.03)
        expect(fixture.controller.isInteractiveEditActive)
        sendMouse(.leftMouseDragged, to: window, at: drag, eventNumber: 31, app: app)
        sendMouse(.leftMouseUp, to: window, at: drag, eventNumber: 32, app: app)
        pump(0.04)
        expect(!fixture.controller.isInteractiveEditActive)
        expect(fixture.scheduler.activeCount(.automaticApply) <= 1)
    }

    private static func checkGlobalSliderMouseLifecycle(app: NSApplication) {
        let fixture = makeReadyFixture(configureGlobalPower: true)
        let quickControlsHeight: CGFloat = 96
        let window = makeWindow(
            rootView: QuickControlsBar(controller: fixture.controller)
                .frame(width: 1_180, height: quickControlsHeight),
            controller: fixture.controller,
            size: NSSize(width: 1_180, height: quickControlsHeight)
        )
        defer { window.orderOut(nil) }

        // Multi starts inactive, so its global panel is absent and the slider
        // remains in the compact top row until the mode is activated.
        let point = NSPoint(x: 540, y: 48)
        let target = NSPoint(x: 620, y: 48)
        sendMouse(.leftMouseDown, to: window, at: point, eventNumber: 40, app: app)
        pump(0.03)
        expect(fixture.controller.isInteractiveEditActive)
        sendMouse(.leftMouseDragged, to: window, at: target, eventNumber: 41, app: app)
        sendMouse(.leftMouseUp, to: window, at: target, eventNumber: 42, app: app)
        pump(0.04)
        expect(!fixture.controller.isInteractiveEditActive)
        expect(fixture.scheduler.activeCount(.automaticApply) <= 1)
    }

    private static func checkViewRemovalAndDisableReleaseTokens(app: NSApplication) {
        let fixture = makeReadyFixture()
        let presentation = HarnessPresentationState()
        let window = makeWindow(
            rootView: VerticalPowerHarness(
                controller: fixture.controller,
                presentation: presentation
            ),
            controller: fixture.controller,
            size: NSSize(width: 132, height: 270)
        )
        defer { window.orderOut(nil) }

        let point = NSPoint(x: 76, y: 100)
        sendMouse(.leftMouseDown, to: window, at: point, eventNumber: 50, app: app)
        pump(0.03)
        expect(fixture.controller.isInteractiveEditActive)
        presentation.isEnabled = false
        pump(0.05)
        expect(!fixture.controller.isInteractiveEditActive, "Disabling must release the token")
        sendMouse(.leftMouseUp, to: window, at: point, eventNumber: 51, app: app)

        presentation.isEnabled = true
        pump(0.05)
        sendMouse(.leftMouseDown, to: window, at: point, eventNumber: 52, app: app)
        pump(0.03)
        expect(fixture.controller.isInteractiveEditActive)
        presentation.showsControl = false
        pump(0.05)
        expect(!fixture.controller.isInteractiveEditActive, "Disappearing must release the token")
        sendMouse(.leftMouseUp, to: window, at: point, eventNumber: 53, app: app)
    }

    private static func makeReadyFixture(
        deliveryMode: ChangeDeliveryMode = .automatic,
        realtimeAutomaticApply: Bool = false,
        configureGlobalPower: Bool = false
    ) -> InteractiveFixture {
        let transport = InteractiveFakeTransport()
        let scheduler = InteractiveTestDeadlineScheduler(
            realtimeAutomaticApply: realtimeAutomaticApply
        )
        let preferences = ChangeDeliveryPreferences(
            storageKey: "interactive-editing-delivery",
            readString: { _ in deliveryMode.rawValue },
            writeString: { _, _ in }
        )
        var transmitterPreferencesData: Data?
        var libraryData: Data?
        let controller = GodoxSessionController(
            transport: transport,
            deadlineScheduler: scheduler,
            visibilityPreferences: LocalGroupPreferences(
                storageKey: "interactive-editing-visible-groups",
                readArray: { _ in nil },
                writeIntegers: { _, _ in }
            ),
            restorationStore: PendingRestorationStore(
                storageKey: "interactive-editing-restoration",
                readObject: { _ in nil },
                writeData: { _, _ in true },
                removeValue: { _ in true }
            ),
            savedRadioStore: SavedRadioStore(
                storageKey: "interactive-editing-radio",
                readObject: { _ in nil },
                writeData: { _, _ in true },
                removeValue: { _ in true }
            ),
            changeDeliveryPreferences: preferences,
            transmitterProfilePreferences: TransmitterProfilePreferences(
                storageKey: "interactive-editing-profiles",
                readObject: { _ in transmitterPreferencesData },
                writeData: { data, _ in
                    transmitterPreferencesData = data
                    return true
                }
            ),
            studioLibraryStore: StudioLibraryStore(
                storageKey: "interactive-editing-library",
                readObject: { _ in libraryData },
                writeData: { data, _ in
                    libraryData = data
                    return true
                }
            )
        )

        if configureGlobalPower {
            controller.setFlashModel("ad600", assigned: false, to: .b)
        }
        controller.startScanning()
        transport.emit(.discovered(interactiveTestDevice))
        controller.selectDevice(interactiveTestDevice.id)
        controller.radioCode = "111111"
        controller.connectSelectedDevice()
        transport.emit(.stateChanged(.ready(interactiveTestDevice)))
        transport.emit(.readyForAuthentication)
        transport.emit(.notification(.authentication, validAuthenticationResponse()))
        transport.emit(.commandSent(.sync))

        expect(controller.phase == .ready)
        expect(controller.canEdit(.c))
        return InteractiveFixture(
            controller: controller,
            transport: transport,
            scheduler: scheduler
        )
    }

    private static func alternatePowers(
        in controller: GodoxSessionController
    ) -> (first: ManualPower, last: ManualPower) {
        let baseline = controller.groupDraft(.c).baseline.power
        let alternatives = controller.allowedPowers(for: .c).filter { $0 != baseline }
        guard alternatives.count >= 2 else {
            fail("The interaction fixture needs at least two alternate power values")
        }
        return (alternatives[0], alternatives[1])
    }

    private static func validAuthenticationResponse(now: Date = Date()) -> Data {
        let unixSeconds = Int64(now.timeIntervalSince1970.rounded(.towardZero))
        let decodedTime = Int((10_000 - (unixSeconds % 10_000)) % 10_000)
        let digits = String(format: "%04d", decodedTime)
        let encoded = digits.map { character -> Character in
            guard let digit = character.wholeNumberValue,
                  let scalar = UnicodeScalar(54 + digit) else {
                fail("Could not build the synthetic PWOK response")
            }
            return Character(scalar)
        }
        return Data("PWOK,;\(String(encoded))".utf8)
    }

    private static func makeWindow<Content: View>(
        rootView: Content,
        controller: GodoxSessionController,
        size: NSSize
    ) -> NSWindow {
        var storedLanguage = AppLanguage.es.rawValue
        let languageStore = AppLanguageStore(
            preferences: AppLanguagePreferences(
                storageKey: "interactive-editing-language",
                readString: { _ in storedLanguage },
                writeString: { value, _ in storedLanguage = value }
            )
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(
            rootView: rootView
                .environmentObject(controller)
                .environmentObject(languageStore)
        )
        window.makeKeyAndOrderFront(nil)
        pump(0.08)
        return window
    }

    private static func sendMouse(
        _ type: NSEvent.EventType,
        to window: NSWindow,
        at point: NSPoint,
        eventNumber: Int,
        app: NSApplication
    ) {
        let pressure: Float = type == .leftMouseUp ? 0 : 1
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: pressure
        ) else {
            fail("Could not create a synthetic AppKit mouse event")
        }
        app.sendEvent(event)
    }

    private static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func pumpUntil(
        timeout: TimeInterval,
        interval: TimeInterval = 0.02,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            let nextTurn = min(
                deadline,
                Date().addingTimeInterval(interval)
            )
            RunLoop.main.run(until: nextTurn)
        }
        return condition()
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Interactive editing assertion failed",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        guard condition() else {
            fail("\(message) [\(file):\(line)]")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
