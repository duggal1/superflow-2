import SuperflowDesignSystem
import SwiftUI

/// A borderless field. Inside a card it sits in the well; on the canvas it sits
/// one step above the page. Focus steps the fill once and nothing else.
public struct AppField: View {
    private let label: String
    private let prompt: String
    @Binding private var text: String
    private let height: CGFloat
    private let onCard: Bool
    private let onSubmit: (() -> Void)?
    private let onTab: (() -> Void)?
    @FocusState private var focused: Bool
    @State private var hover = false

    public init(_ label: String, prompt: String = "", text: Binding<String>,
                height: CGFloat = ControlHeight.large,
                onCard: Bool = true, onSubmit: (() -> Void)? = nil,
                onTab: (() -> Void)? = nil) {
        self.label = label
        self.prompt = prompt
        _text = text
        self.height = height
        self.onCard = onCard
        self.onSubmit = onSubmit
        self.onTab = onTab
    }

    public var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Tok.text)
            .focused($focused)
            .onSubmit { onSubmit?() }
            .onKeyPress(.tab) {
                guard let onTab else { return .ignored }
                onTab()
                return .handled
            }
            .padding(.horizontal, Space.sm)
            .frame(height: height)
            .background(fill, in: .rect(cornerRadius: Radius.field, style: .continuous))
            .contrastStroke(radius: Radius.field)
            .contentShape(.rect(cornerRadius: Radius.field))
            .onTapGesture { focused = true }
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: focused)
            .animation(.easeOut(duration: 0.15), value: hover)
            .accessibilityLabel(label)
    }

    /// One fill step on hover and on focus. Text inputs never draw a ring; the
    /// caret is the focus indicator.
    private var fill: Color {
        if onCard { return focused || hover ? Tok.control : Tok.well }
        return focused || hover ? Tok.fieldHover : Tok.field
    }
}

/// A single-line field: 28 tall, 8pt radius, `well` inside a card and `field` on
/// the canvas. One fill step on hover and focus; the caret is the focus
/// indicator, and the I-beam is preserved.
public struct AppTextField: View {
    @Binding private var text: String
    private let label: String
    private let prompt: String
    private let onCanvas: Bool
    @FocusState private var focused: Bool
    @State private var hover = false

    public init(text: Binding<String>, label: String, prompt: String = "",
                onCanvas: Bool = false) {
        _text = text
        self.label = label
        self.prompt = prompt
        self.onCanvas = onCanvas
    }

    private var active: Bool { focused || hover }

    private var fill: Color {
        if onCanvas { return active ? Tok.fieldHover : Tok.field }
        return active ? Tok.control : Tok.well
    }

    public var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Tok.text2))
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Tok.text)
            .tint(Tok.accent)
            .focused($focused)
            .padding(.horizontal, Space.sm)
            .frame(height: ControlHeight.regular)
            .background(fill, in: .rect(cornerRadius: Radius.field, style: .continuous))
            .contrastStroke(radius: Radius.field)
            .contentShape(.rect(cornerRadius: Radius.field))
            .onTapGesture { focused = true }
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: focused)
            .animation(.easeOut(duration: 0.15), value: hover)
            .accessibilityLabel(label)
    }
}

/// The onboarding practice field: real text, selectable, nothing behind it.
public struct PracticeField: View {
    @Binding private var text: String
    private let prompt: String

    public init(_ prompt: String, text: Binding<String>) {
        self.prompt = prompt
        _text = text
    }

    public var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Typography.large)
            .foregroundStyle(Tok.text)
            .lineLimit(2...4)
            .padding(Space.sm)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(Tok.surface,
                        in: .rect(cornerRadius: Radius.field, style: .continuous))
            .textSelection(.enabled)
            .accessibilityLabel(prompt)
    }
}

/// A multiline body editor for shortcut content. Grows to six lines.
public struct AppTextEditor: View {
    private let label: String
    @Binding private var text: String
    private let minHeight: CGFloat
    @FocusState private var focused: Bool

    public init(_ label: String, text: Binding<String>, minHeight: CGFloat = 96) {
        self.label = label
        _text = text
        self.minHeight = minHeight
    }

    public var body: some View {
        TextEditor(text: $text)
            .font(Typography.body)
            .foregroundStyle(Tok.text)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(Space.xs)
            .frame(minHeight: minHeight)
            .background(Tok.well, in: .rect(cornerRadius: Radius.field, style: .continuous))
            .focusStep(.rect(cornerRadius: Radius.field))
            .accessibilityLabel(label)
    }
}
