import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

public enum ButtonKind: Sendable {
    case primary, sapphire, secondary, quiet, link
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

        private var px: CGFloat { typeScope == .island || kind == .sapphire || height >= 28 ? 12 : 10 }
        private var typeRole: AppType { typeScope == .island || height >= 28 ? .label : .caption }
        private var font: CGFloat { typeRole.size(in: typeScope) }

        private var fill: Color {
            switch kind {
            case .primary, .sapphire: configuration.isPressed ? Tok.accentPressed : hover ? Tok.accentHover : Tok.accent
            case .secondary: configuration.isPressed ? Tok.controlPressed : hover ? Tok.controlHover : Tok.control
            case .quiet, .link: hover || configuration.isPressed ? Tok.wash : .clear
            }
        }

        private var label: Color {
            switch kind {
            case .primary, .sapphire: .white
            case .secondary: Tok.text
            case .quiet: hover || configuration.isPressed ? Tok.text : Tok.text2
            case .link: hover || configuration.isPressed ? Tok.text : Tok.textAction
            }
        }

        @ViewBuilder private var face: some View {
            if kind == .sapphire {
                Capsule()
                    .fill(fill.shadow(.inner(color: Tok.sapphireHighlight, radius: 0, x: 0, y: 1))
                        .shadow(.inner(color: hover ? Tok.sapphireInnerHover : Tok.sapphireInnerRest,
                                       radius: hover ? 5 : 3, x: 0, y: hover ? -4 : -2)))
                    .overlay { Capsule().strokeBorder(Tok.sapphireEdge, lineWidth: 1) }
            } else {
                Capsule().fill(fill)
            }
        }

        var body: some View {
            configuration.label
                .font(Typography.ui(font, weight: AppFont.emphasisWeight))
                .tracking(kind == .sapphire ? AppType.label.tracking(in: .island)
                          : typeScope == .island ? typeRole.tracking(in: typeScope) : 0)
                .foregroundStyle(label)
                .padding(.horizontal, px)
                .frame(minWidth: minimumWidth)
                .frame(height: height)
                .background { face }
                .contentShape(.capsule)
                .opacity(enabled ? 1 : Opacity.disabled)
                .scaleEffect(configuration.isPressed && !reduceMotion && typeScope != .island ? Opacity.pressScale : 1)
                .animation(reduceMotion ? nil : (configuration.isPressed ? Motion.hoverIn : Motion.hoverOut), value: configuration.isPressed)
                .animation(reduceMotion ? nil : kind == .sapphire ? .easeOut(duration: 0.20)
                           : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
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
    private let minimumWidth: CGFloat?
    private let action: () -> Void

    public init(_ title: String, glyph: Glyph? = nil, kind: ButtonKind = .secondary,
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
        assert(height == 24 || height == 28 || (kind == .sapphire && height == 32),
               "AppButton height must be 24/28, or 32 for Sapphire")
        #endif
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let glyph { Icon(glyph, size: 12, weight: .medium, tint: (kind == .primary || kind == .sapphire) ? .white : nil) }
                Text(title).contentTransition(.opacity)
            }
        }
        .buttonStyle(AppButtonStyle(kind: kind, height: height, minimumWidth: minimumWidth))
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
