import AppKit
import Foundation
import SwiftUI

@main
@MainActor
enum MenuBarAccessibilityCheck {
    static func main() async {
        await verifyMockEventOrdering()

        let app = NSApplication.shared
        let interactive = CommandLine.arguments.contains("--interactive")
        app.setActivationPolicy(interactive ? .regular : .accessory)
        app.finishLaunching()

        let controller = MockRadioRuntime.makeController()
        controller.startScanning()
        let discoveredMockTrigger = await pumpUntil(timeout: 3) {
            controller.selectedDevice != nil
        }
        expect(
            discoveredMockTrigger,
            "The mock trigger must be discovered"
        )
        controller.radioCode = "123456"
        controller.connectSelectedDevice()
        let fixtureReachedReady = await pumpUntil(timeout: 10) {
            controller.phase == .ready
        }
        expect(
            fixtureReachedReady,
            "The accessibility fixture must reach Ready; \(phaseDiagnostic(controller))"
        )

        MenuBarAccessibilityActions.sendTest(
            controller: controller,
            enabled: false
        )
        expect(
            !controller.isTestPending,
            "A disabled Menu Bar Test action must not reach the controller"
        )
        MenuBarAccessibilityActions.sendTest(
            controller: controller,
            enabled: true
        )
        expect(
            controller.isTestPending,
            "The enabled Menu Bar Test action must delegate to the shared guarded controller path"
        )
        let testDeliveryCompleted = await pumpUntil(timeout: 2) {
            !controller.isTestPending
        }
        expect(
            testDeliveryCompleted,
            "The simulated Menu Bar Test delivery must complete without Bluetooth hardware"
        )
        expect(
            controller.testHelpMessage == "mock.testHelp",
            "The Menu Bar and main window must share the same Test-help semantics"
        )

        let baselinePower = controller.groupDraft(.b).draft.power
        MenuBarAccessibilityActions.adjustPower(
            .increment,
            controller: controller,
            group: .b,
            enabled: false
        )
        expect(
            controller.groupDraft(.b).draft.power == baselinePower,
            "A disabled VoiceOver adjustment must not change power"
        )
        MenuBarAccessibilityActions.adjustPower(
            .increment,
            controller: controller,
            group: .b,
            enabled: true
        )
        expect(
            controller.groupDraft(.b).draft.power != baselinePower,
            "VoiceOver Increment must use the same discrete power adjustment as the visible control"
        )
        MenuBarAccessibilityActions.adjustPower(
            .decrement,
            controller: controller,
            group: .b,
            enabled: true
        )
        expect(
            controller.groupDraft(.b).draft.power == baselinePower,
            "VoiceOver Decrement must restore the prior discrete power"
        )

        var storedLanguage = AppLanguage.es.rawValue
        let languageStore = AppLanguageStore(
            preferences: AppLanguagePreferences(
                storageKey: "Estrobo.tests.menuBarAccessibility",
                readString: { _ in storedLanguage },
                writeString: { value, _ in storedLanguage = value }
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 360, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(
            rootView: MenuBarControlView(controller: controller)
                .environmentObject(languageStore)
                .frame(width: 360)
        )
        window.contentView = hostingView
        window.title = "Estrobo Menu Bar Accessibility QA"
        window.makeKeyAndOrderFront(nil)
        pump(0.25)

        if interactive {
            app.activate(ignoringOtherApps: true)
            app.run()
            return
        }

        let language = languageStore.language
        guard let appBundlePath = ProcessInfo.processInfo.environment[
            "ESTROBO_TEST_APP_BUNDLE"
        ], let resourceBundle = Bundle(path: appBundlePath) else {
            fputs("FAIL: ESTROBO_TEST_APP_BUNDLE must identify the built Estrobo app\n", stderr)
            exit(1)
        }
        let onDescriptor = MenuBarAccessibilityDescriptors.groupToggle(
            group: .b,
            isOn: true,
            isEnabled: true,
            disabledHint: "unused",
            language: language,
            bundle: resourceBundle
        )
        expect(
            onDescriptor == MenuBarAccessibilityDescriptor(
                label: "Apagar grupo B",
                value: "Encendido",
                hint: "El cambio usa el modo de envío elegido",
                isEnabled: true
            ),
            "The enabled group descriptor must preserve its localized action, value, and hint; found \(onDescriptor)"
        )

        let offDescriptor = MenuBarAccessibilityDescriptors.groupToggle(
            group: .b,
            isOn: false,
            isEnabled: false,
            disabledHint: "Bloqueado para la prueba",
            language: language,
            bundle: resourceBundle
        )
        expect(
            offDescriptor == MenuBarAccessibilityDescriptor(
                label: "Encender grupo B",
                value: "Apagado",
                hint: "Bloqueado para la prueba",
                isEnabled: false
            ),
            "The disabled group descriptor must preserve its state and blocking reason"
        )

        let decreaseDescriptor = MenuBarAccessibilityDescriptors.step(
            group: .b,
            direction: .decrement,
            power: baselinePower,
            isEnabled: false,
            hint: language.localizedString("menubar.minimumPower", bundle: resourceBundle),
            language: language,
            bundle: resourceBundle
        )
        expect(
            decreaseDescriptor.label == "Bajar un tercio EV en el grupo B" &&
                decreaseDescriptor.value == baselinePower.label &&
                decreaseDescriptor.hint == "Este grupo ya está en su potencia mínima permitida" &&
                !decreaseDescriptor.isEnabled,
            "The minimum-power decrement descriptor must remain present, disabled, and explained"
        )

        let increaseDescriptor = MenuBarAccessibilityDescriptors.step(
            group: .b,
            direction: .increment,
            power: baselinePower,
            isEnabled: true,
            hint: "",
            language: language,
            bundle: resourceBundle
        )
        expect(
            increaseDescriptor.label == "Subir un tercio EV en el grupo B" &&
                increaseDescriptor.value == baselinePower.label &&
                increaseDescriptor.hint.isEmpty &&
                increaseDescriptor.isEnabled,
            "The increment descriptor must remain enabled at the minimum power"
        )

        let powerDescriptor = MenuBarAccessibilityDescriptors.power(
            group: .b,
            value: "M, \(baselinePower.label)",
            hint: language.localizedString("menubar.choosePower", bundle: resourceBundle),
            isEnabled: true,
            language: language,
            bundle: resourceBundle
        )
        expect(
            powerDescriptor == MenuBarAccessibilityDescriptor(
                label: "Potencia del grupo B",
                value: "M, \(baselinePower.label)",
                hint: "Elige directamente una potencia permitida",
                isEnabled: true
            ),
            "The power menu descriptor must expose a localized label, value, hint, and enabled state"
        )

        expect(
            MenuBarAccessibilityDescriptors.openApp(
                language: language,
                bundle: resourceBundle
            ).label == "Abrir Estrobo",
            "The Open Estrobo footer action must preserve its localized label"
        )

        let enabledTestDescriptor = MenuBarAccessibilityDescriptors.test(
            isPending: false,
            isEnabled: true,
            hint: "Dispara todos los grupos activos con los ajustes aplicados; Bluetooth no confirma el destello",
            language: language,
            bundle: resourceBundle
        )
        expect(
            enabledTestDescriptor == MenuBarAccessibilityDescriptor(
                label: "Disparo Test global",
                value: "",
                hint: "Dispara todos los grupos activos con los ajustes aplicados; Bluetooth no confirma el destello",
                isEnabled: true
            ),
            "The enabled global Test descriptor must expose one stable identity and its safety help"
        )

        let pendingTestDescriptor = MenuBarAccessibilityDescriptors.test(
            isPending: true,
            isEnabled: false,
            hint: "La orden Test se está entregando al radio",
            language: language,
            bundle: resourceBundle
        )
        expect(
            pendingTestDescriptor == MenuBarAccessibilityDescriptor(
                label: "Disparo Test global",
                value: "Enviando",
                hint: "La orden Test se está entregando al radio",
                isEnabled: false
            ),
            "The global Test descriptor must expose its localized delivery state and blocking reason"
        )

        expect(
                MenuBarAccessibilityDescriptors.quit(
                    language: language,
                    bundle: resourceBundle
                ).label == "Salir de Estrobo",
            "The Quit footer action must preserve its localized label"
        )

        expect(
            hostingView.fittingSize.width > 0 && hostingView.fittingSize.height > 0,
            "The hosted Menu Bar fixture must render to a non-empty native view"
        )
        verifyModifierContract()

        window.orderOut(nil)
        print("Menu Bar accessibility descriptors, actions, rendering, and modifier contract verified")
    }

    private static func verifyMockEventOrdering() async {
        let controlledDelay = ControlledDelay()
        let recorder = MockEventRecorder()
        let transport = MockGodoxSessionTransport { milliseconds in
            await controlledDelay.wait(milliseconds)
        }
        transport.delegate = recorder
        transport.connect(to: MockGodoxSessionTransport.device)

        for _ in 0..<5 {
            await settleTasks()
            expect(
                controlledDelay.resumeLongestPendingWait(),
                "Each mock connection step must register one controlled delay"
            )
        }
        await settleTasks()

        expect(
            recorder.events == [
                "connecting",
                "discovering",
                "subscribing",
                "ready",
                "readyForAuthentication",
            ],
            "Mock connection events must remain ordered when several deadlines become runnable; received \(recorder.events)"
        )

        recorder.reset()
        guard let power = ManualPower.value(decimal: 50),
              let groupFrame = try? SafeGodoxProtocol.manualGroupFrame(
                  group: .b,
                  snapshot: ManualGroupSnapshot(
                      power: power,
                      modeling: .off
                  )
              ) else {
            fputs("FAIL: Unable to build the mock A1 ordering fixture\n", stderr)
            exit(1)
        }
        transport.sendControl(groupFrame)
        for _ in 0..<3 {
            await settleTasks()
            expect(
                controlledDelay.resumeLongestPendingWait(),
                "Each mock control step must register one controlled delay"
            )
        }
        await settleTasks()
        expect(
            recorder.events == [
                "controlWriteStarted",
                "controlWriteCompleted",
                "controlNotification",
            ],
            "Mock A1 acknowledgement events must remain ordered; received \(recorder.events)"
        )
    }

    private static func phaseDiagnostic(_ controller: GodoxSessionController) -> String {
        let phase: String
        if case .failed(let message) = controller.phase {
            phase = "failed(\(message))"
        } else {
            phase = controller.phase.title
        }
        let recentActivity = controller.activity.suffix(6).map(\.message).joined(separator: " | ")
        return recentActivity.isEmpty
            ? "current phase: \(phase)"
            : "current phase: \(phase); recent activity: \(recentActivity)"
    }

    private static func settleTasks() async {
        for _ in 0..<50 {
            await Task.yield()
        }
    }

    private static func verifyModifierContract() {
        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let testURL = URL(fileURLWithPath: #filePath, relativeTo: currentDirectory)
            .standardizedFileURL
        let sourceURL = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MenuBarControlView.swift")
        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            fputs("FAIL: Unable to read \(sourceURL.path)\n", stderr)
            exit(1)
        }

        let modifierFragments = [
            ".accessibilityElement(children: .ignore)",
            ".accessibilityAddTraits(.isButton)",
            ".accessibilityLabel(Text(verbatim: descriptor.label))",
            ".accessibilityValue(Text(verbatim: descriptor.value))",
            ".accessibilityHint(Text(verbatim: descriptor.hint))",
            ".disabled(!descriptor.isEnabled)",
        ]
        for fragment in modifierFragments {
            expect(
                source.contains(fragment),
                "The shared accessible-button modifier must retain \(fragment)"
            )
        }
        let controlCount = source.components(separatedBy: ".menuBarAccessibleButton(").count - 1
        expect(
            controlCount == 7,
            "Every compact button family must use the shared accessibility modifier; found \(controlCount) call sites"
        )
        for fragment in [
            ".accessibilityLabel(Text(verbatim: powerAccessibility.label))",
            ".accessibilityValue(Text(verbatim: powerAccessibility.value))",
            ".accessibilityHint(Text(verbatim: powerAccessibility.hint))",
        ] {
            expect(
                source.contains(fragment),
                "The power menu must retain its public accessibility descriptor contract"
            )
        }
    }

    private static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func pumpUntil(
        timeout: TimeInterval,
        interval: TimeInterval = 0.02,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .seconds(interval))
        }
        return condition()
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private final class ControlledDelay {
        private struct PendingWait {
            let milliseconds: Int
            let continuation: CheckedContinuation<Void, Never>
        }

        private var pendingWaits: [PendingWait] = []

        func wait(_ milliseconds: Int) async {
            await withCheckedContinuation { continuation in
                pendingWaits.append(
                    PendingWait(
                        milliseconds: milliseconds,
                        continuation: continuation
                    )
                )
            }
        }

        func resumeLongestPendingWait() -> Bool {
            guard let index = pendingWaits.indices.max(by: {
                pendingWaits[$0].milliseconds < pendingWaits[$1].milliseconds
            }) else {
                return false
            }
            let pending = pendingWaits.remove(at: index)
            pending.continuation.resume()
            return true
        }
    }

    @MainActor
    private final class MockEventRecorder: BluetoothClientDelegate {
        private(set) var events: [String] = []

        func reset() {
            events.removeAll()
        }

        func bluetoothClient(didReceive event: BluetoothClient.Event) {
            switch event {
            case .stateChanged(.connecting(_)):
                events.append("connecting")
            case .stateChanged(.discovering(_)):
                events.append("discovering")
            case .stateChanged(.subscribing(_)):
                events.append("subscribing")
            case .stateChanged(.ready(_)):
                events.append("ready")
            case .readyForAuthentication:
                events.append("readyForAuthentication")
            case .controlWriteStarted:
                events.append("controlWriteStarted")
            case .controlWriteCompleted:
                events.append("controlWriteCompleted")
            case .notification(.control, _):
                events.append("controlNotification")
            default:
                break
            }
        }
    }
}
