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

/// Increase Contrast for a shape that is not a rounded rectangle (the Island's
/// notch silhouette). Lives here because strokes are only allowed in this file.
public struct ShapeContrastStroke<S: Shape>: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    public let shape: S

    public init(shape: S) {
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                shape
                    .stroke(Tok.contrastStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

public extension View {
    func contrastStroke<S: Shape>(_ shape: S) -> some View {
        modifier(ShapeContrastStroke(shape: shape))
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
