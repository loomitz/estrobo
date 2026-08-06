import AppKit
import Darwin
import Foundation
import SwiftUI

/// A minimal regression harness for the custom modeling-menu event ordering.
///
/// It intentionally reads the event mask used by `ModelingMenuCoordinator`
/// from the production view source, then recreates the relevant AppKit event
/// sequence with the same plain SwiftUI `Button` used by the menu. A real
/// pointer selection completes on mouse-up; an accessibility or direct action
/// does not emit the monitored mouse event.
final class ModelingOptionProbeState: ObservableObject {
    @Published var isOptionVisible = true
    @Published var selectionCount = 0
}

struct ModelingOptionProbeView: View {
    @ObservedObject var state: ModelingOptionProbeState

    var body: some View {
        ZStack {
            Color.clear
            if state.isOptionVisible {
                Button("FIXED") {
                    state.selectionCount += 1
                }
                .buttonStyle(.plain)
                .frame(width: 140, height: 44)
                .background(Color.gray)
            }
        }
        .frame(width: 220, height: 120)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let sourcePath = "Sources/PrototypeViews.swift"
guard let source = try? String(contentsOfFile: sourcePath, encoding: .utf8),
      let monitorStart = source.range(of: "private func startMonitoringClicks()"),
      let monitorEnd = source.range(
          of: "private func stopMonitoringClicks()",
          range: monitorStart.upperBound..<source.endIndex
      ) else {
    fail("Could not locate ModelingMenuCoordinator.startMonitoringClicks")
}

let monitorSource = source[monitorStart.lowerBound..<monitorEnd.lowerBound]
let monitoredEvent: NSEvent.EventType
let monitoredMask: NSEvent.EventTypeMask
let detectedMask: String

if monitorSource.contains(".leftMouseDown") {
    monitoredEvent = .leftMouseDown
    monitoredMask = .leftMouseDown
    detectedMask = "leftMouseDown"
} else if monitorSource.contains(".leftMouseUp") {
    monitoredEvent = .leftMouseUp
    monitoredMask = .leftMouseUp
    detectedMask = "leftMouseUp"
} else {
    fail("Could not determine the local mouse-monitor event mask")
}

let app = NSApplication.shared
let state = ModelingOptionProbeState()
let window = NSWindow(
    contentRect: NSRect(x: 80, y: 80, width: 220, height: 120),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.contentView = NSHostingView(
    rootView: ModelingOptionProbeView(state: state)
)
window.makeKeyAndOrderFront(nil)
RunLoop.main.run(until: Date().addingTimeInterval(0.05))

let monitor = NSEvent.addLocalMonitorForEvents(matching: monitoredMask) { event in
    DispatchQueue.main.async {
        state.isOptionVisible = false
    }
    return event
}

let point = NSPoint(x: 110, y: 57)
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

// A mouse-down monitor's deferred close runs before the later mouse-up action.
// A mouse-up monitor instead returns the event to the option before closing.
if monitoredEvent == .leftMouseDown {
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}

app.sendEvent(up)
RunLoop.main.run(until: Date().addingTimeInterval(0.02))

let pointerSelectionCount = state.selectionCount
state.selectionCount += 1
let directActionCount = state.selectionCount - pointerSelectionCount

if let monitor {
    NSEvent.removeMonitor(monitor)
}
window.orderOut(nil)

print(
    "detectedMonitor=\(detectedMask) "
        + "pointerSelection=\(pointerSelectionCount) "
        + "directAction=\(directActionCount)"
)
fflush(stdout)

guard pointerSelectionCount == 1, directActionCount == 1 else {
    fail("Pointer selection was preempted before mouse-up")
}
