import AppKit
import Darwin
import Foundation
import SwiftUI

@main
@MainActor
enum WorkspaceChromeInteractionCheck {
    static func main() {
        checkWorkspaceChromeSourceContract()
        checkLanguagePickerHitTargets()
        print("Settings-only view switching, shared controls, header, footer, and language hit targets verified")
    }

    private static func checkWorkspaceChromeSourceContract() {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("PrototypeViews.swift")

        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            fail("Could not read PrototypeViews.swift")
        }

        let root = section(
            in: source,
            from: "struct PrototypeRootView: View",
            to: "private struct WorkspaceConfigurationFlow: View"
        )
        expect(
            root.contains(".onChange(of: variant)") &&
                root.contains("workspaceViewPreferences.save(newValue)") &&
                !root.contains("preferredVariant") &&
                !root.contains("WorkspaceVariantSelector(") &&
                !root.contains("WorkspaceViewBar"),
            "The active view must persist without exposing a selector in the main workspace"
        )

        let header = section(
            in: source,
            from: "private struct PrototypeHeader: View",
            to: "private struct PresetLibrarySheet: View"
        )
        expect(
            !header.contains("LanguageToggle()"),
            "The completed workspace header must not expose the language toggle"
        )
        expect(
            !header.contains("connectionCaption") && !header.contains("app.realBluetooth"),
            "The connection status must remain a single line without a Bluetooth subtitle"
        )
        expect(
            header.contains("Text(verbatim: \"Sync\")") &&
                !header.contains("\"Sincronizar valores\""),
            "The header synchronization action must use the fixed label Sync"
        )
        expect(
            occurrences(
                of: ".buttonStyle(QuietButtonStyle(height: HeaderMetrics.controlHeight))",
                in: header
            ) == 4,
            "Sync, disconnect, Presets, and Settings must share the header control height"
        )
        expect(
            occurrences(of: ".frame(height: HeaderMetrics.controlHeight)", in: header) == 2,
            "The connection status and appearance selector must match the header button height"
        )

        let workspaceConfiguration = section(
            in: source,
            from: "private struct WorkspaceConfigurationFlow: View",
            to: "private struct AddWorkingGroupsSheet: View"
        )
        expect(
            workspaceConfiguration.contains("LanguageToggle()"),
            "First-run configuration must keep a language control before Settings is available"
        )

        let footer = section(
            in: source,
            from: "private struct WorkspaceFooter: View",
            to: "private struct FooterApplyControls: View"
        )
        expect(
            !footer.contains("WorkspaceVariantSelector"),
            "The workspace footer must not render the Channels/Inspector/Matrix selector"
        )

        let applyControls = section(
            in: source,
            from: "private struct FooterApplyControls: View",
            to: "private struct WorkspaceVariantSelector: View"
        )
        expect(
            applyControls.contains("else if controller.changeDeliveryMode == .manual") &&
                applyControls.contains("controller.isAutomaticApplyScheduled") &&
                applyControls.contains("discardButton"),
            "Discard must remain available in On Apply and during an automatic debounce"
        )

        let settings = section(
            in: source,
            from: "private struct LocalConfigurationPopover: View",
            to: "private struct SettingsRow<Content: View>: View"
        )
        expect(
            settings.contains("SettingsRow(title: \"Vista\"") &&
                settings.contains("variant: $variant") &&
                !settings.contains("Vista inicial") &&
                !settings.contains("La vista se aplicará la próxima vez"),
            "Settings must call the immediate workspace choice View, never Initial view"
        )
        expect(
            source.components(separatedBy: "WorkspaceVariantSelector(").count - 1 == 1,
            "The Channels/Inspector/Matrix selector must exist only in Settings"
        )

        let quickControls = section(
            in: source,
            from: "struct QuickControlsBar: View",
            to: "private struct GlobalStepButton: View"
        )
        expect(
            quickControls.contains("title: \"Beep\"") &&
                quickControls.contains("controller.setGlobalBeep") &&
                quickControls.contains("title: \"Standby\"") &&
                quickControls.contains("controller.setGlobalStandby"),
            "Beep and Standby must be exposed once as global controls"
        )

        let groupStateControls = section(
            in: source,
            from: "private struct GroupStateControls: View",
            to: "private struct ModelingEditor: View"
        )
        expect(
            !groupStateControls.contains("beepToggle") &&
                !groupStateControls.contains("setBeep"),
            "Groups must not expose an independent Beep toggle"
        )
        expect(
            groupStateControls.contains("AUTO · TTL") &&
                groupStateControls.contains("setOperatingMode"),
            "Every group control must expose Manual and Auto/TTL modes"
        )

        let channels = section(
            in: source,
            from: "private struct ChannelsLayout: View",
            to: "private struct ChannelRow: View"
        )
        let inspector = section(
            in: source,
            from: "private struct InspectorLayout: View",
            to: "private struct MatrixLayout: View"
        )
        let matrix = section(
            in: source,
            from: "private struct MatrixLayout: View",
            to: "// MARK: - Reusable controls and styling"
        )
        for (name, layout) in [
            ("Channels", channels),
            ("Inspector", inspector),
            ("Matrix", matrix),
        ] {
            expect(
                layout.contains("GroupStateControls(") &&
                    layout.contains("ModelingEditor("),
                "\(name) must expose the shared mode, activation, power, and modeling controls"
            )
        }
    }

    private static func checkLanguagePickerHitTargets() {
        var storedLanguage = AppLanguage.es.rawValue
        let languageStore = AppLanguageStore(
            preferences: AppLanguagePreferences(
                storageKey: "Estrobo.tests.languageHitTarget",
                readString: { _ in storedLanguage },
                writeString: { value, _ in storedLanguage = value }
            )
        )

        let width: CGFloat = 320
        let height: CGFloat = 36
        let app = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(
            rootView: SettingsLanguagePicker()
                .environmentObject(languageStore)
                .frame(width: width, height: height)
        )
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        click(
            app: app,
            window: window,
            point: NSPoint(x: 10, y: height / 2)
        )
        expect(
            languageStore.language == .en,
            "Clicking the empty left edge of the English segment must select English"
        )

        click(
            app: app,
            window: window,
            point: NSPoint(x: width - 10, y: height / 2)
        )
        expect(
            languageStore.language == .es,
            "Clicking the empty right edge of the Spanish segment must select Spanish"
        )

        expect(
            storedLanguage == AppLanguage.es.rawValue,
            "Pointer selections must persist through AppLanguageStore"
        )
        window.orderOut(nil)
    }

    private static func click(app: NSApplication, window: NSWindow, point: NSPoint) {
        let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
        let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: 0.02,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        )!

        app.sendEvent(down)
        app.sendEvent(up)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) -> Substring {
        guard let start = source.range(of: startMarker),
              let end = source.range(
                of: endMarker,
                range: start.upperBound..<source.endIndex
              ) else {
            fail("Could not locate source section \(startMarker)")
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    private static func occurrences(of needle: String, in source: Substring) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String
    ) {
        guard condition() else { fail(message()) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
