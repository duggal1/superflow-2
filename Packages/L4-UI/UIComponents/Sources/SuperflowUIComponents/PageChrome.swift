import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// The pointer hand and the window drag area live here, with the bar controls:
/// features compose these and never manage cursors or drag gestures themselves.

public extension View {
    /// Drag the window from here. Replaces `isMovableByWindowBackground`.
    func windowDragArea() -> some View {
        background(WindowDragArea())
    }

    /// Reports this view's frame in the window coordinate space. Used to anchor menus.
    func reportFrame(_ binding: Binding<CGRect>) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(WindowSpace.name))
        } action: { frame in
            binding.wrappedValue = frame
        }
    }

    /// Command-F focuses the page search field.
    func searchShortcut(_ focus: Binding<Bool>) -> some View {
        background {
            Button("Find") { focus.wrappedValue = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Scale on press. No bounce, no colour change: the fill already carries state.
public struct PressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? Opacity.pressScale : 1)
                .animation(reduceMotion ? nil : Motion.hoverIn, value: configuration.isPressed)
        }
    }
}

/// Drag handle for the hidden title bar. A clear fill that takes clicks and drags
/// the window instead of letting a background double-click maximise it.
public struct WindowDragArea: View {
    public init() {}

    public var body: some View {
        Color.clear
            .contentShape(.rect)
            .gesture(WindowDragGesture())
    }
}

/// Search on the canvas. No `.searchable`, no stroke, no ring: the caret is the
/// focus indicator and the fill steps once on hover and once on focus.
public struct SearchField: View {
    @Binding private var text: String
    private let prompt: String
    @Binding private var isFocused: Bool
    @FocusState private var focus: Bool
    @State private var hover = false

    public init(text: Binding<String>, prompt: String, isFocused: Binding<Bool>) {
        _text = text
        self.prompt = prompt
        _isFocused = isFocused
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            Icon(.search, size: 14, tint: Tok.text2)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Tok.text2))
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Tok.text)
                .tint(Tok.accent)
                .focused($focus)
                .onKeyPress(.escape) {
                    if text.isEmpty { focus = false } else { text = "" }
                    return .handled
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Icon(.close, size: 12, weight: .medium, tint: Tok.text2)
                        .frame(width: 20, height: 20)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .clickable()
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.leading, Space.sm)
        .padding(.trailing, text.isEmpty ? Space.sm : Space.xs)
        .frame(height: Layout.control)
        .frame(minWidth: 200, idealWidth: 280, maxWidth: 320)
        .background(focus || hover ? Tok.fieldHover : Tok.field, in: .capsule)
        .contrastStroke(radius: Layout.control / 2)
        .contentShape(.capsule)
        .onTapGesture { focus = true }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: focus)
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
        .onChange(of: isFocused) { _, value in focus = value }
        .onChange(of: focus) { _, value in isFocused = value }
        .accessibilityElement(children: .contain)
    }
}

/// Bare at rest. A fill appears on hover only. 32 x 32 hit target, 16pt icon.
public struct BarIconButton: View {
    private let glyph: Glyph
    private let label: String
    private let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    public init(glyph: Glyph, label: String, action: @escaping () -> Void) {
        self.glyph = glyph
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Icon(glyph, size: 16, tint: Tok.text)
                .frame(width: Layout.control, height: Layout.control)
                .background(hover && enabled ? Tok.control : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
        .opacity(enabled ? 1 : 0.35)
        .focusStep(Circle())
        .accessibilityLabel(label)
        .clickable(enabled)
    }
}
