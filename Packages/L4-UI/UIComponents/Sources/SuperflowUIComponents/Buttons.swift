import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

public enum ButtonKind: Sendable {
    case primary, secondary, quiet, link
}

public struct AppButtonStyle: ButtonStyle {
    public var kind: ButtonKind
    public var height: CGFloat

    public init(kind: ButtonKind = .secondary, height: CGFloat = ControlHeight.regular) {
        self.kind = kind
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, kind: kind, height: height)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let kind: ButtonKind
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hover = false

        private var px: CGFloat { height >= 28 ? 12 : 10 }
        private var font: CGFloat { height >= 28 ? 13 : 12 }

        private var fill: Color {
            switch kind {
            case .primary: configuration.isPressed ? Tok.accentPressed : hover ? Tok.accentHover : Tok.accent
            case .secondary: configuration.isPressed ? Tok.controlPressed : hover ? Tok.controlHover : Tok.control
            case .quiet, .link: hover || configuration.isPressed ? Tok.wash : .clear
            }
        }

        private var label: Color {
            switch kind {
            case .primary: .white
            case .secondary: Tok.text
            case .quiet: hover || configuration.isPressed ? Tok.text : Tok.text2
            case .link: hover || configuration.isPressed ? Tok.text : Tok.textAction
            }
        }

        var body: some View {
            configuration.label
                .font(Typography.ui(font, weight: AppFont.emphasisWeight))
                .foregroundStyle(label)
                .padding(.horizontal, px)
                .frame(height: height)
                .background(fill, in: .capsule)
                .contentShape(.capsule)
                .opacity(enabled ? 1 : Opacity.disabled)
                .scaleEffect(configuration.isPressed && !reduceMotion ? Opacity.pressScale : 1)
                .animation(reduceMotion ? nil : (configuration.isPressed ? Motion.hoverIn : Motion.hoverOut), value: configuration.isPressed)
                .animation(reduceMotion ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
                .onHover { hover = $0 }
                .clickable(enabled)
                .focusStep()
        }
    }
}

public extension ButtonStyle where Self == AppButtonStyle {
    static func app(_ kind: ButtonKind, height: CGFloat = ControlHeight.regular) -> AppButtonStyle {
        AppButtonStyle(kind: kind, height: height)
    }
}

public struct AppButton: View {
    private let title: String
    private let glyph: Glyph?
    private let kind: ButtonKind
    private let height: CGFloat
    private let enabled: Bool
    private let action: () -> Void

    public init(_ title: String, glyph: Glyph? = nil, kind: ButtonKind = .secondary,
                height: CGFloat = ControlHeight.regular, enabled: Bool = true,
                action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.kind = kind
        self.height = height
        self.enabled = enabled
        self.action = action
        #if DEBUG
        assert(height == 24 || height == 28, "AppButton height must be 24 or 28")
        #endif
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let glyph { Icon(glyph, size: 12, weight: .medium, tint: kind == .primary ? .white : nil) }
                Text(title)
            }
        }
        .buttonStyle(.app(kind, height: height))
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}


public struct IconButton: View {
    private let glyph: Glyph
    private let label: String
    private let size: CGFloat
    private let tint: Color
    private let enabled: Bool
    private let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ glyph: Glyph, label: String, size: CGFloat = 16, tint: Color = Tok.text2,
                enabled: Bool = true, action: @escaping () -> Void) {
        self.glyph = glyph
        self.label = label
        self.size = size
        self.tint = tint
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Icon(glyph, size: size, tint: tint)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : Opacity.disabled)
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
        .clickable(enabled)
        .help(label)
        .accessibilityLabel(label)
        .focusStep(.rect(cornerRadius: Radius.chip))
    }
}
