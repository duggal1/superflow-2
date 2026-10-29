import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

public enum ButtonKind: Sendable {
    case primary, secondary, quiet, link
}

public struct AppButtonStyle: ButtonStyle {
    public var kind: ButtonKind
    public var height: CGFloat
    public var minimumWidth: CGFloat?

    public init(kind: ButtonKind = .secondary, height: CGFloat = ControlHeight.regular, minimumWidth: CGFloat? = nil) {
        self.kind = kind
        self.height = height
        self.minimumWidth = minimumWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, kind: kind, height: height, minimumWidth: minimumWidth)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let kind: ButtonKind
        let height: CGFloat
        let minimumWidth: CGFloat?
        @Environment(\.appTypeScope) private var typeScope
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hover = false

        private var px: CGFloat { typeScope == .island || height >= 28 ? 12 : 10 }
        private var typeRole: AppType { typeScope == .island || height >= 28 ? .label : .caption }
        private var font: CGFloat { typeRole.size(in: typeScope) }

        private var deadPrimary: Bool { !enabled && kind == .primary }

        private var fill: Color {
            if deadPrimary { return Tok.control }
            return switch kind {
            case .primary: configuration.isPressed ? Tok.accentPressed : hover ? Tok.accentHover : Tok.accent
            case .secondary: configuration.isPressed ? Tok.controlPressed : hover ? Tok.controlHover : Tok.control
            case .quiet, .link: hover || configuration.isPressed ? Tok.wash : .clear
            }
        }

        private var label: Color {
            if deadPrimary { return Tok.text2 }
            return switch kind {
            case .primary: .white
            case .secondary: Tok.text
            case .quiet: hover || configuration.isPressed ? Tok.text : Tok.text2
            case .link: hover || configuration.isPressed ? Tok.text : Tok.textAction
            }
        }

        var body: some View {
            configuration.label
                .font(Typography.ui(font, weight: AppFont.emphasisWeight))
                .tracking(typeScope == .island ? typeRole.tracking(in: typeScope) : 0)
                .foregroundStyle(label)
                .padding(.horizontal, px)
                .frame(minWidth: minimumWidth)
                .frame(height: height)
                .background(fill, in: .capsule)
                .contentShape(.capsule)
                .opacity(enabled || deadPrimary ? 1 : Opacity.disabled)
                .scaleEffect(configuration.isPressed && !reduceMotion && typeScope != .island ? Opacity.pressScale : 1)
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
    private let glyph: Icon?
    private let kind: ButtonKind
    private let height: CGFloat
    private let enabled: Bool
    private let minimumWidth: CGFloat?
    private let action: () -> Void

    public init(_ title: String, glyph: Icon? = nil, kind: ButtonKind = .secondary,
                height: CGFloat = ControlHeight.regular, enabled: Bool = true, minimumWidth: CGFloat? = nil,
                action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.kind = kind
        self.height = height
        self.enabled = enabled
        self.minimumWidth = minimumWidth
        self.action = action
        #if DEBUG
        assert(height == 24 || height == 28 || height == 32, "AppButton height must be 24, 28 or 32")
        #endif
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let glyph { IconView(glyph, size: 12, weight: .medium, tint: kind == .primary ? .white : nil) }
                Text(title).contentTransition(.opacity)
            }
        }
        .buttonStyle(AppButtonStyle(kind: kind, height: height, minimumWidth: minimumWidth))
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}


public struct IconButton: View {
    private let glyph: Icon
    private let label: String
    private let size: CGFloat
    private let tint: Color
    private let enabled: Bool
    private let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ glyph: Icon, label: String, size: CGFloat = 16, tint: Color = Tok.text2,
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
            IconView(glyph, size: size, tint: tint)
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
