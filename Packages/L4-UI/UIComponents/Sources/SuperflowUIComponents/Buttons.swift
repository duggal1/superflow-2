import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

public enum ButtonKind: Sendable {
    case primary, secondary, quiet
}

/// Capsule, no border, no icon unless the icon carries meaning. Heights 24 / 28 / 32.
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

        private var fill: Color {
            switch kind {
            case .primary:
                configuration.isPressed ? Tok.accentPressed : hover ? Tok.accentHover : Tok.accent
            case .secondary:
                configuration.isPressed ? Tok.controlPressed : hover ? Tok.controlHover : Tok.control
            case .quiet:
                .clear
            }
        }

        private var label: Color {
            switch kind {
            case .primary: Tok.onAccent
            case .secondary: Tok.text
            case .quiet: hover || configuration.isPressed ? Tok.text : Tok.text2
            }
        }

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(label)
                .padding(.horizontal, height >= ControlHeight.large ? 14 : 12)
                .frame(height: height)
                .background(fill, in: .capsule)
                .contentShape(.capsule)
                .opacity(enabled ? 1 : Opacity.disabled)
                .scaleEffect(configuration.isPressed && !reduceMotion ? Opacity.pressScale : 1)
                .animation(reduceMotion ? nil : Motion.hoverIn, value: configuration.isPressed)
                .animation(reduceMotion ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
                .onHover { hover = $0 }
                .clickable(enabled)
        }
    }
}

public extension ButtonStyle where Self == AppButtonStyle {
    static func app(_ kind: ButtonKind, height: CGFloat = ControlHeight.regular) -> AppButtonStyle {
        AppButtonStyle(kind: kind, height: height)
    }
}

/// Text buttons for bars, cards and rows. Features never use a raw Button.
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
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let glyph {
                    Icon(glyph, size: 12, weight: .medium,
                         tint: kind == .primary ? Tok.onAccent : nil)
                }
                Text(title)
            }
        }
        .buttonStyle(.app(kind, height: height))
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

/// A bare symbol in a hit target. No circle, no box: the hover fill is the affordance.
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
                .frame(width: size + 12, height: size + 12)
                .background(hover ? Tok.control : .clear,
                            in: .rect(cornerRadius: Radius.chip, style: .continuous))
                .contentShape(.rect(cornerRadius: Radius.chip))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : Opacity.disabled)
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
        .clickable(enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}
