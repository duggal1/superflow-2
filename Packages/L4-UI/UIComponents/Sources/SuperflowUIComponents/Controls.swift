import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

public struct Segmented<Value: Hashable>: View {
    public struct Item {
        public let value: Value
        public let title: String
        public init(_ title: String, value: Value) {
            self.title = title
            self.value = value
        }
    }

    @Binding private var selection: Value
    private let items: [Item]
    private let onCard: Bool
    @Namespace private var ns
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<Value>, items: [Item], onCard: Bool = false) {
        _selection = selection
        self.items = items
        self.onCard = onCard
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                Button { selection = item.value } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == item.value ? Tok.text : Tok.text2)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background {
                            if selection == item.value {
                                Capsule().fill(onCard ? Tok.control : Tok.controlHover)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .clickable()
                .accessibilityAddTraits(selection == item.value ? .isSelected : [])
                .accessibilityLabel(item.title)
            }
        }
        .padding(2)
        .background(onCard ? Tok.well : Tok.surface, in: .capsule)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selection)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .focusStep()
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .accessibilityElement(children: .contain)
    }

    private func step(_ delta: Int) {
        guard let index = items.firstIndex(where: { $0.value == selection }) else { return }
        let next = min(max(index + delta, 0), items.count - 1)
        selection = items[next].value
    }
}

public struct AppToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { Color.clear.frame(width: 38, height: 32) }
            .buttonStyle(SwitchStyle(isOn: configuration.isOn))
            .focusStep(Capsule())
            .clickable()
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
    }

    private struct SwitchStyle: ButtonStyle {
        let isOn: Bool
        func makeBody(configuration: Configuration) -> some View { Face(isOn: isOn, pressed: configuration.isPressed) }
        private struct Face: View {
            let isOn: Bool
            let pressed: Bool
            @Environment(\.isEnabled) private var enabled
            @Environment(\.accessibilityReduceMotion) private var reduce
            @State private var hover = false
            private var track: Color {
                guard isOn else { return Tok.controlPressed }
                return pressed ? Tok.accentPressed : hover ? Tok.accentHover : Tok.accent
            }
            var body: some View {
                let knob: CGFloat = pressed ? 22 : 18
                Capsule().fill(track)
                    .frame(width: 38, height: 22)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: knob, height: 18).padding(2)
                            .offset(x: isOn ? 34 - knob : 0)
                    }
                    .frame(height: 32)
                    .contentShape(.rect)
                    .opacity(enabled ? 1 : Opacity.disabled)
                    .animation(reduce ? nil : .snappy(duration: 0.22), value: isOn)
                    .animation(reduce ? nil : .snappy(duration: 0.12), value: pressed)
                    .animation(.easeOut(duration: 0.10), value: hover)
                    .onHover { hover = $0 }
            }
        }
    }
}

public struct AppToggle: View {
    private let label: String
    @Binding private var isOn: Bool
    private let enabled: Bool
    public init(_ label: String, isOn: Binding<Bool>, enabled: Bool = true) {
        self.label = label
        _isOn = isOn
        self.enabled = enabled
    }
    public var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(AppToggleStyle())
            .labelsHidden()
            .disabled(!enabled)
            .accessibilityLabel(label)
    }
}

// AppStepper (pass 3 trough)
public struct AppStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit: String?
    let label: String

    @State private var scrubBase: Int?
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, unit: String? = nil, label: String) {
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 2) {
            StepChip(glyph: .minus, atBound: value <= range.lowerBound) { nudge(-1) }
            readout
            StepChip(glyph: .add, atBound: value >= range.upperBound) { nudge(1) }
        }
        .padding(2)
        .frame(height: 28)
        .background(Tok.well, in: .capsule)
        .opacity(enabled ? 1 : Opacity.disabled)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(unit.map { "\(value) \($0)" } ?? "\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    private var readout: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Tok.text)
                .contentTransition(.numericText(value: Double(value)))
            if let unit { Text(unit).font(.system(size: 13)).foregroundStyle(Tok.text2) }
        }
        .frame(minWidth: 72, minHeight: 24)
        .contentShape(.rect)
        .scrubbable(scrubBase != nil)
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { g in
                    let base = scrubBase ?? value
                    scrubBase = base
                    let steps = Int((g.translation.width / 8).rounded(.towardZero))
                    value = min(max(base + steps * step, range.lowerBound), range.upperBound)
                }
                .onEnded { _ in scrubBase = nil }
        )
    }

    private func nudge(_ dir: Int) {
        let next = min(max(value + dir * step, range.lowerBound), range.upperBound)
        guard next != value else {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
            return
        }
        value = next
    }
}

private struct StepChip: View {
    let glyph: Glyph
    let atBound: Bool
    let tick: () -> Void

    @State private var hover = false
    @State private var down = false
    @State private var hold: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Icon(glyph, size: 12, weight: .medium)
            .foregroundStyle(Tok.text)
            .frame(width: 24, height: 24)
            .background(down ? Tok.controlPressed : hover ? Tok.controlHover : Tok.control, in: .circle)
            .contentShape(.circle)
            .scaleEffect(down ? 0.92 : 1)
            .opacity(atBound ? 0.35 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: down)
            .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
            .onHover { hover = $0 }
            .focusStep(Circle())
            .clickable(!atBound)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !down else { return }
                        down = true
                        tick()
                        hold = Task {
                            try? await Task.sleep(for: .milliseconds(380))
                            var n = 0
                            while !Task.isCancelled {
                                tick(); n += 1
                                try? await Task.sleep(for: .milliseconds(n < 8 ? 90 : 45))
                            }
                        }
                    }
                    .onEnded { _ in down = false; hold?.cancel(); hold = nil }
            )
    }
}
