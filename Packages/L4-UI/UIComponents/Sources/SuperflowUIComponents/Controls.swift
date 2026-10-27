import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// Filters that truly belong inside content. Page-level filters stay in the bar.
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
    private let onCanvas: Bool
    @Namespace private var ns
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<Value>, items: [Item], onCard: Bool = false) {
        _selection = selection
        self.items = items
        onCanvas = !onCard
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                Button {
                    selection = item.value
                } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == item.value ? Tok.text : Tok.text2)
                        .padding(.horizontal, Space.sm)
                        .frame(height: ControlHeight.small)
                        .background {
                            if selection == item.value {
                                Capsule()
                                    .fill(onCanvas ? Tok.controlHover : Tok.control)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(PressStyle())
                .clickable()
                .accessibilityAddTraits(selection == item.value ? .isSelected : [])
                .accessibilityLabel(item.title)
            }
        }
        .padding(2)
        .background(onCanvas ? Tok.surface : Tok.well, in: .capsule)
        .animation(reduceMotion ? nil : Motion.slide, value: selection)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .focusRing(radius: ControlHeight.small / 2 + 3, active: focused)
        .onKeyPress(.leftArrow) {
            step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            step(1)
            return .handled
        }
        .accessibilityElement(children: .contain)
    }

    private func step(_ delta: Int) {
        guard let index = items.firstIndex(where: { $0.value == selection }) else { return }
        let next = min(max(index + delta, 0), items.count - 1)
        selection = items[next].value
    }
}

/// The only toggle in the app. 38 x 22 track, 18pt knob that stretches to 22
/// while pressed, accent when on, 32pt hit height. System focus ring removed;
/// our 2pt ring replaces it.
public struct AppToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Color.clear.frame(width: 38, height: 32)
        }
        .buttonStyle(SwitchStyle(isOn: configuration.isOn))
        .focusEffectDisabled()
        .clickable()
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }

    private struct SwitchStyle: ButtonStyle {
        let isOn: Bool

        func makeBody(configuration: Configuration) -> some View {
            Face(isOn: isOn, pressed: configuration.isPressed)
        }
    }

    private struct Face: View {
        let isOn: Bool
        let pressed: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduce
        @FocusState private var focused: Bool
        @State private var hover = false

        var body: some View {
            let knob: CGFloat = pressed ? 22 : 18
            Capsule()
                .fill(isOn ? (hover ? Tok.accentHover : Tok.accent) : Tok.controlPressed)
                .frame(width: 38, height: 22)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white)
                        .frame(width: knob, height: 18)
                        .padding(2)
                        .offset(x: isOn ? 34 - knob : 0)
                }
                .focusRing(radius: 11, active: focused)
                .frame(width: 38, height: 32)
                .contentShape(.rect)
                .focusable()
                .focused($focused)
                .opacity(enabled ? 1 : Opacity.disabled)
                .animation(reduce ? nil : .snappy(duration: 0.22), value: isOn)
                .animation(reduce ? nil : .snappy(duration: 0.12), value: pressed)
                .animation(.easeOut(duration: 0.10), value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// Label plus the one switch. Features never reach for a raw Toggle.
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
