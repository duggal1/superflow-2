import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// Apple's native slider, tinted accent, wrapped once so every slider in the app
/// is identical and shares one left edge. Fixed 280 wide: slider flexes, readout 64.
public struct TimingSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let unit: String

    public init(value: Binding<Double>, in range: ClosedRange<Double>,
                step: Double = 50, unit: String) {
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    public var body: some View {
        HStack(spacing: Space.md) {
            // Continuous; snapped in the setter. Passing `step:` would draw a tick per step.
            Slider(value: snapped, in: range)
                .tint(Tok.accent)
                .clickable()
                .accessibilityValue("\(Int(value)) \(unit)")
            Text("\(Int(value)) \(unit)")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Tok.text2)
                .contentTransition(.numericText(value: value))
                .animation(.snappy(duration: 0.15), value: value)
                .frame(width: 64, alignment: .trailing)
        }
        .frame(width: 280)
    }

    private var snapped: Binding<Double> {
        Binding(get: { value },
                set: { value = min(range.upperBound, max(range.lowerBound, ($0 / step).rounded() * step)) })
    }
}

/// Two bare chevrons around a tabular value. No native Stepper appearance.
public struct AppStepper: View {
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let unit: String
    private let enabled: Bool

    public init(value: Binding<Int>, in range: ClosedRange<Int>,
                unit: String = "", enabled: Bool = true) {
        _value = value
        self.range = range
        self.unit = unit
        self.enabled = enabled
    }

    public var body: some View {
        HStack(spacing: Space.xxs) {
            StepButton(glyph: .chevronLeft, label: "Decrease",
                       enabled: enabled && value > range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }
            Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Tok.text)
                .contentTransition(.numericText(value: Double(value)))
                .frame(minWidth: 56)
            StepButton(glyph: .chevronRight, label: "Increase",
                       enabled: enabled && value < range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .animation(.snappy(duration: 0.20), value: value)
        .accessibilityElement()
        .accessibilityLabel("Value")
        .accessibilityValue(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
    }

    private struct StepButton: View {
        let glyph: Glyph
        let label: String
        let enabled: Bool
        let action: () -> Void
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                Icon(glyph, size: 12, weight: .medium, tint: Tok.text)
                    .frame(width: 28, height: 28)
                    .background(hover && enabled ? Tok.controlHover : .clear, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(PressStyle())
            .onHover { hover = $0 }
            .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
            .opacity(enabled ? 1 : 0.35)
            .accessibilityLabel(label)
            .clickable(enabled)
        }
    }
}

/// A keycap that records the next chord. Escape cancels; Return confirms.
public struct KeyRecorder: View {
    @Binding private var chord: String
    private let enabled: Bool
    @State private var recording = false
    @State private var hover = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(chord: Binding<String>, enabled: Bool = true) {
        _chord = chord
        self.enabled = enabled
    }

    public var body: some View {
        Button {
            recording.toggle()
        } label: {
            Group {
                if recording {
                    Text("Press a key")
                        .font(Typography.secondary)
                        .foregroundStyle(Tok.text2)
                } else {
                    KeyCap(chord.isEmpty ? "—" : chord)
                }
            }
            .padding(.horizontal, Space.xs)
            .frame(height: ControlHeight.regular)
            .background(recording || hover ? Tok.controlHover : Tok.control, in: .capsule)
            .focusRing(radius: ControlHeight.regular / 2, active: focused)
            .contentShape(.capsule)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : Opacity.disabled)
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
        .clickable(enabled)
        .focusable(enabled)
        .focusEffectDisabled()
        .focused($focused)
        .onChange(of: recording) { _, isRecording in
            if isRecording { focused = true }
        }
        .onKeyPress(phases: .down) { press in
            guard recording else { return .ignored }
            if press.key == .escape {
                recording = false
                return .handled
            }
            let text = chordLabel(press)
            guard !text.isEmpty else { return .handled }
            chord = text
            recording = false
            return .handled
        }
        .accessibilityLabel("Record shortcut")
        .accessibilityValue(chord)
    }

    private func chordLabel(_ press: KeyPress) -> String {
        var parts: [String] = []
        if press.modifiers.contains(.control) { parts.append("⌃") }
        if press.modifiers.contains(.option) { parts.append("⌥") }
        if press.modifiers.contains(.shift) { parts.append("⇧") }
        if press.modifiers.contains(.command) { parts.append("⌘") }
        let key = press.characters.uppercased()
        guard !key.isEmpty, key.first?.isLetter == true || key.first?.isNumber == true else {
            return ""
        }
        parts.append(key)
        return parts.joined()
    }
}
