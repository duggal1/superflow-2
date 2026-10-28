import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// The one presentation layer for forms. `.sheet`, `.alert` and
/// `.confirmationDialog` are banned: a dialog is a root overlay, above menus.
@MainActor
@Observable
public final class DialogHost {
    public struct Presented: Identifiable {
        public let id = UUID()
        let content: AnyView
    }

    public private(set) var presented: Presented?

    public init() {}

    public func present<V: View>(@ViewBuilder _ content: () -> V) {
        presented = Presented(content: AnyView(content()))
    }

    public func dismiss() {
        presented = nil
    }
}

public struct DialogLayer: View {
    @Environment(DialogHost.self) private var host
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    public init() {}

    public var body: some View {
        ZStack {
            if let presented = host.presented {
                ZStack {
                    Tok.modalScrim
                        .contentShape(.rect)
                        .onTapGesture { host.dismiss() }
                    presented.content
                        .scaleEffect(shown || reduceMotion ? 1 : 0.97)
                        .offset(y: shown || reduceMotion ? 0 : 6)
                        .opacity(shown || reduceMotion ? 1 : 0)
                }
                .id(presented.id)
                .transition(.opacity)
                .onAppear { withAnimation(Motion.menuIn) { shown = true } }
                .onDisappear { shown = false }
            }
        }
        .animation(Motion.menuOut, value: host.presented?.id)
    }
}

public struct DialogFrame<Content: View>: View {
    private let title: String
    private let confirmTitle: String
    private let canConfirm: Bool
    private let showsCancel: Bool
    private let onConfirm: () -> Void
    private let content: Content
    @Environment(DialogHost.self) private var host

    public init(title: String, confirmTitle: String, canConfirm: Bool,
                showsCancel: Bool = true, onConfirm: @escaping () -> Void,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.canConfirm = canConfirm
        self.showsCancel = showsCancel
        self.onConfirm = onConfirm
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .appType(.title)
                .foregroundStyle(Tok.text)
            content
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if showsCancel {
                    AppButton("Cancel", kind: .quiet, height: 32) { host.dismiss() }
                }
                AppButton(confirmTitle, kind: .primary, height: 32, enabled: canConfirm) {
                    onConfirm()
                    host.dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Tok.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .modifier(ContrastStroke(radius: Radius.card))
        .background {
            // Esc cancels, ⌘Return confirms. The shortcuts live on real Buttons,
            // so they fire regardless of which field has focus.
            Group {
                Button("Cancel") { host.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Confirm") { onConfirm(); host.dismiss() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canConfirm)
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .pixelAudit("DialogFrame")
    }
}

public struct DialogField<Content: View>: View {
    private let label: String
    private let content: Content

    public init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .appType(.caption)
                .foregroundStyle(Tok.text2)
            content
        }
    }
}

/// Multi-line, SF Mono 12. Same recipe as `AppTextField`.
public struct AppEditor: View {
    @Binding private var text: String
    private let prompt: String
    private let minHeight: CGFloat
    @FocusState private var focus: Bool
    @State private var hover = false

    public init(text: Binding<String>, prompt: String, minHeight: CGFloat = 128) {
        _text = text
        self.prompt = prompt
        self.minHeight = minHeight
    }

    public var body: some View {
        let mono = Font.system(size: 12, design: .monospaced)
        TextEditor(text: $text)
            .font(mono)
            .scrollContentBackground(.hidden)
            .focused($focus)
            .focusEffectDisabled()
            .padding(8)
            .frame(minHeight: minHeight)
            .background(focus || hover ? Tok.bg : Tok.well,
                        in: .rect(cornerRadius: Radius.field, style: .continuous))
            .overlay(alignment: .topLeading) {
                // TextEditor insets its text by about 5pt; tune the two paddings
                // until the placeholder's first glyph sits where the caret will be.
                if text.isEmpty {
                    Text(prompt)
                        .font(mono)
                        .foregroundStyle(Tok.text2)
                        .padding(.leading, 13)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: focus || hover)
            .pixelAudit("AppEditor")
    }
}

/// The Playground and model pages already open informational overlays. They use
/// this dialog frame rather than a sheet.
public struct InfoDialog: View {
    private let title: String
    private let body_: AnyView
    @Environment(DialogHost.self) private var host

    public init(title: String, @ViewBuilder content: () -> some View) {
        self.title = title
        self.body_ = AnyView(content())
    }

    public var body: some View {
        DialogFrame(title: title, confirmTitle: "Done", canConfirm: true, showsCancel: false,
                    onConfirm: {}) {
            ScrollView { body_ }
                .frame(maxHeight: 320)
        }
    }
}
