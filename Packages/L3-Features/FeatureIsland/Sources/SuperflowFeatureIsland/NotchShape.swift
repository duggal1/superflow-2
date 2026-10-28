import SwiftUI

/// The Island silhouette: flat top flush with the bezel, concave fillets at the
/// top corners (the black flares out into the menu bar), convex rounded bottom.
/// True quarter-circle Béziers so the radii read as circles at 8x zoom.
public struct NotchShape: Shape, Equatable {
    public var top: CGFloat
    public var bottom: CGFloat

    public init(top: CGFloat, bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(top, bottom) }
        set {
            top = newValue.first
            bottom = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let t = max(0, min(top, rect.height))
        let b = max(0, min(bottom, max(rect.height - t, 0), (rect.width - 2 * t) / 2))
        let k: CGFloat = 0.5522847498
        let l = rect.minX, r = rect.maxX
        let y0 = rect.minY, y1 = rect.maxY

        var p = Path()
        p.move(to: CGPoint(x: l, y: y0))

        // Top-left concave: centre (l, y0 + t), from the top of the circle to its right side.
        p.addCurve(to: CGPoint(x: l + t, y: y0 + t),
                   control1: CGPoint(x: l + k * t, y: y0),
                   control2: CGPoint(x: l + t, y: y0 + t - k * t))
        p.addLine(to: CGPoint(x: l + t, y: y1 - b))

        // Bottom-left convex: centre (l + t + b, y1 - b).
        p.addCurve(to: CGPoint(x: l + t + b, y: y1),
                   control1: CGPoint(x: l + t, y: y1 - b + k * b),
                   control2: CGPoint(x: l + t + b - k * b, y: y1))
        p.addLine(to: CGPoint(x: r - t - b, y: y1))

        // Bottom-right convex: centre (r - t - b, y1 - b).
        p.addCurve(to: CGPoint(x: r - t, y: y1 - b),
                   control1: CGPoint(x: r - t - b + k * b, y: y1),
                   control2: CGPoint(x: r - t, y: y1 - b + k * b))
        p.addLine(to: CGPoint(x: r - t, y: y0 + t))

        // Top-right concave: centre (r, y0 + t), from its left side to the top.
        p.addCurve(to: CGPoint(x: r, y: y0),
                   control1: CGPoint(x: r - t, y: y0 + t - k * t),
                   control2: CGPoint(x: r - k * t, y: y0))
        p.closeSubpath()
        return p
    }
}
