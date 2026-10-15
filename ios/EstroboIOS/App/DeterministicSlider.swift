import SwiftUI
import UIKit

@MainActor
final class SteppedUISlider: UISlider {
    var accessibilityStep: Float = 1

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        let defaultRect = super.trackRect(forBounds: bounds)
        return CGRect(
            x: defaultRect.minX,
            y: defaultRect.midY - 2,
            width: defaultRect.width,
            height: 4
        )
    }

    override func accessibilityIncrement() {
        applyAccessibilityStep(accessibilityStep)
    }

    override func accessibilityDecrement() {
        applyAccessibilityStep(-accessibilityStep)
    }

    private func applyAccessibilityStep(_ delta: Float) {
        guard isEnabled, delta != 0 else { return }
        let nextValue = min(maximumValue, max(minimumValue, value + delta))
        guard nextValue != value else { return }
        value = nextValue
        sendActions(for: .valueChanged)
    }
}

/// A quiet ruler aligned to the usable UISlider track. Major and minor ticks
/// improve position reading without intercepting gestures or adding labels to
/// VoiceOver's navigation order.
struct SliderRulerTicks: View {
    let tickCount: Int
    let majorTickEvery: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<max(2, tickCount), id: \.self) { index in
                Rectangle()
                    .fill(Color.secondary.opacity(index.isMultiple(of: majorTickEvery) ? 0.65 : 0.4))
                    .frame(
                        width: 1,
                        height: index.isMultiple(of: majorTickEvery) ? 10 : 5
                    )
                if index < max(2, tickCount) - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 10, alignment: .top)
        .padding(.horizontal, 14)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A stepped slider whose interaction lifetime follows UIKit control events.
///
/// SwiftUI's `Slider.onEditingChanged` is convenient, but a missed terminal
/// callback can leave a continuous edit open indefinitely. This adapter owns
/// that small state machine explicitly: touch-up finishes, touch cancellation
/// and teardown fail closed, and non-touch value changes are treated as one
/// atomic edit.
struct DeterministicSlider: UIViewRepresentable {
    @Binding var value: Double
    @Environment(\.isEnabled) private var environmentIsEnabled

    let range: ClosedRange<Double>
    let step: Double
    let isEnabled: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityIdentifier: String
    let onInteractionBegan: @MainActor () -> Void
    let onInteractionEnded: @MainActor () -> Void
    let onInteractionCancelled: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UISlider {
        let slider = SteppedUISlider(frame: .zero)
        slider.isContinuous = true
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchDown(_:)),
            for: .touchDown
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchEnded(_:)),
            for: [.touchUpInside, .touchUpOutside]
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchCancelled(_:)),
            for: .touchCancel
        )
        update(slider, coordinator: context.coordinator)
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        update(slider, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ slider: UISlider, coordinator: Coordinator) {
        coordinator.cancelInteraction()
        slider.removeTarget(nil, action: nil, for: .allEvents)
    }

    private func update(_ slider: UISlider, coordinator: Coordinator) {
        let effectiveIsEnabled = isEnabled && environmentIsEnabled
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        (slider as? SteppedUISlider)?.accessibilityStep = Float(step)
        slider.isEnabled = effectiveIsEnabled
        slider.accessibilityLabel = accessibilityLabel
        slider.accessibilityValue = accessibilityValue
        slider.accessibilityIdentifier = accessibilityIdentifier

        if !coordinator.isInteracting {
            slider.value = Float(snapped(value))
        }
        if !effectiveIsEnabled {
            coordinator.cancelInteraction()
        }
    }

    private func snapped(_ proposedValue: Double) -> Double {
        let bounded = min(max(proposedValue, range.lowerBound), range.upperBound)
        guard step > 0 else { return bounded }
        let offset = ((bounded - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + offset * step, range.lowerBound), range.upperBound)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: DeterministicSlider
        private(set) var isInteracting = false

        init(_ parent: DeterministicSlider) {
            self.parent = parent
        }

        @objc func touchDown(_ slider: UISlider) {
            beginInteraction()
        }

        @objc func valueChanged(_ slider: UISlider) {
            let snappedValue = parent.snapped(Double(slider.value))
            slider.value = Float(snappedValue)
            changeInteractionValue(snappedValue, isTracking: slider.isTracking)
        }

        @objc func touchEnded(_ slider: UISlider) {
            endInteraction()
        }

        @objc func touchCancelled(_ slider: UISlider) {
            cancelInteraction()
        }

        func beginInteraction() {
            guard !isInteracting else { return }
            isInteracting = true
            parent.onInteractionBegan()
        }

        /// `UISlider` accessibility and keyboard adjustments may emit only
        /// `valueChanged`. When UIKit is not tracking a touch, close that edit
        /// immediately so it cannot strand the controller's delivery gate.
        func changeInteractionValue(_ proposedValue: Double, isTracking: Bool) {
            beginInteraction()
            parent.value = parent.snapped(proposedValue)
            if !isTracking {
                endInteraction()
            }
        }

        func endInteraction() {
            guard isInteracting else { return }
            isInteracting = false
            parent.onInteractionEnded()
        }

        func cancelInteraction() {
            guard isInteracting else { return }
            isInteracting = false
            parent.onInteractionCancelled()
        }
    }
}
