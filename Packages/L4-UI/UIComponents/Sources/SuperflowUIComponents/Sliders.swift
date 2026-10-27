import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

public struct TimingSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 50
    let unit: String
    @State private var live: Double?

    public init(value: Binding<Double>, in range: ClosedRange<Double>,
                step: Double = 50, unit: String) {
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    public var body: some View {
        HStack(spacing: 16) {
            Slider(value: Binding(
                get: { live ?? value },
                set: { live = $0; value = ($0 / step).rounded() * step }),
                   in: range) { editing in
                if !editing { withAnimation(.snappy(duration: 0.18)) { live = nil } }
            }
            .tint(Tok.accent)
            .focusEffectDisabled()
            .clickable()
            .accessibilityValue("\(Int(value)) \(unit)")

            Text("\(Int(value)) \(unit)")
                .font(.system(size: 13)).monospacedDigit().foregroundStyle(Tok.text2)
                .contentTransition(.numericText(value: value))
                .animation(.snappy(duration: 0.15), value: value)
                .frame(width: 64, alignment: .trailing)
        }
        .frame(width: 280)
    }
}

// AppStepper is implemented in Controls.swift (pass 3 trough).
