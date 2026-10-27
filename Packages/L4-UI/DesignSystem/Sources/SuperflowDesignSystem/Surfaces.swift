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
    func contrastStroke(radius: CGFloat) -> some View {
        modifier(ContrastStroke(radius: radius))
    }
}

public func cellHash(_ i: Int, _ j: Int, _ seed: UInt32) -> CGFloat {
    var h = UInt32(truncatingIfNeeded: i) &* 374761393
        &+ UInt32(truncatingIfNeeded: j) &* 668265263
        &+ seed &* 2246822519
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return CGFloat(h) / CGFloat(UInt32.max)
}
