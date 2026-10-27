import SuperflowDesignSystem
import SwiftUI

/// System glass on the navigation layer, with a solid fallback when transparency
/// is reduced. Nothing here fakes glass with gradients or custom blur.
public struct GlassSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public enum Style: Sendable {
        case regular, interactive
    }

    private let radius: CGFloat
    private let style: Style
    private let content: Content

    public init(radius: CGFloat = Radius.card, style: Style = .regular,
                @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.style = style
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(style == .interactive ? .regular.interactive() : .regular,
                                in: shape)
        } else if reduceTransparency {
            content.background(Tok.surface, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

/// Capsule-shaped system glass, for toasts and floating pills.
public struct GlassCapsule<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let interactive: Bool
    private let content: Content

    public init(interactive: Bool = false, @ViewBuilder content: () -> Content) {
        self.interactive = interactive
        self.content = content()
    }

    public var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        } else if reduceTransparency {
            content.background(Tok.surface, in: .capsule)
        } else {
            content.background(.regularMaterial, in: .capsule)
        }
    }
}

/// Groups neighboring glass elements so they can morph as one system.
public struct GlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = Space.xs, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// A floating palette or action bar shell. Solid content stays outside.
public struct FloatingPanel<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GlassSurface(radius: Radius.card) {
            content.padding(Space.sm)
        }
    }
}
