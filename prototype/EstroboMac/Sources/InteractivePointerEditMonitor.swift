import AppKit
import SwiftUI

/// Observes pointer-down/up without taking hit testing away from the native
/// control underneath it. This keeps keyboard and accessibility adjustments
/// discrete while opening the controller transaction at the actual mouse-down.
@MainActor
struct InteractivePointerEditMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onEditingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> InteractivePointerMonitorView {
        let view = InteractivePointerMonitorView()
        view.update(isEnabled: isEnabled, onEditingChanged: onEditingChanged)
        return view
    }

    func updateNSView(_ view: InteractivePointerMonitorView, context: Context) {
        view.update(isEnabled: isEnabled, onEditingChanged: onEditingChanged)
    }

    static func dismantleNSView(
        _ view: InteractivePointerMonitorView,
        coordinator: ()
    ) {
        view.stopMonitoringAndFinish()
    }
}

@MainActor
final class InteractivePointerMonitorView: NSView {
    private var localEventMonitor: Any?
    private var isEnabled = false
    private var isTrackingPointer = false
    private var onEditingChanged: (Bool) -> Void = { _ in }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoringAndFinish()
        } else {
            startMonitoringIfNeeded()
        }
    }

    func update(
        isEnabled: Bool,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        self.onEditingChanged = onEditingChanged
        self.isEnabled = isEnabled
        if !isEnabled {
            finishTracking()
        }
        startMonitoringIfNeeded()
    }

    func stopMonitoringAndFinish() {
        finishTracking()
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func startMonitoringIfNeeded() {
        guard window != nil, localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDown:
                beginTrackingIfNeeded(event)
            case .leftMouseUp:
                finishTrackingAfterDispatch()
            case .keyDown where event.keyCode == 53:
                finishTrackingAfterDispatch()
            default:
                break
            }
            return event
        }
    }

    private func beginTrackingIfNeeded(_ event: NSEvent) {
        guard isEnabled,
              !isTrackingPointer,
              event.window === window else {
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }
        isTrackingPointer = true
        onEditingChanged(true)
    }

    /// The native slider commits its final value while dispatching mouse-up.
    /// Ending on the next main-loop turn guarantees the final draft exists
    /// before the controller arms its one debounce.
    private func finishTrackingAfterDispatch() {
        guard isTrackingPointer else { return }
        isTrackingPointer = false
        let finish = onEditingChanged
        DispatchQueue.main.async {
            finish(false)
        }
    }

    private func finishTracking() {
        guard isTrackingPointer else { return }
        isTrackingPointer = false
        onEditingChanged(false)
    }
}
