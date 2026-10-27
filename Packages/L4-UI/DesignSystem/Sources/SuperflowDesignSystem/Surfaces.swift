import SwiftUI

/// The only stroke besides the focus ring. Appears only with Increase Contrast.
public struct ContrastStroke: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    public let radius: CGFloat

    public init(radius: CGFloat) {
        self.radius = radius
    }

    public func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Tok.contrastStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

public extension View {
    /// Keyboard focus ring. 2pt accent, offset 2. System controls keep the system ring.
    func focusRing(radius: CGFloat, active: Bool) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Tok.accent, lineWidth: Radius.focusRing)
                .padding(-Radius.focusOffset)
                .opacity(active ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    func contrastStroke(radius: CGFloat) -> some View {
        modifier(ContrastStroke(radius: radius))
    }
}
