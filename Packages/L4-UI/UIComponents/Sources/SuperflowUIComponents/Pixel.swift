import os
import SuperflowDesignSystem
import SwiftUI

/// The pixel law: every frame origin, size, offset, padding and radius lands on
/// the 1/scale grid. Any length derived from a `GeometryReader`, a ratio or a
/// division goes through here. Symmetric shapes use `snapEven` so they centre
/// exactly instead of sitting half a pixel off.
public enum Pixel {
    /// Snap a length to the device pixel grid.
    public static func snap(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return (value * scale).rounded() / scale
    }

    /// Snap to an EVEN number of device pixels, so a shape symmetric about its
    /// centre (bar, dot, thumb, knob) has no favourite side.
    public static func snapEven(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return (value * scale / 2).rounded() * 2 / scale
    }

    public static func isOnGrid(_ value: CGFloat, _ scale: CGFloat) -> Bool {
        guard scale > 0 else { return true }
        return abs(value * scale - (value * scale).rounded()) < 0.01
    }
}

#if DEBUG
/// Warns whenever a container is off the device pixel grid. It checks containers,
/// not glyph baselines, so put it on cards, rows, controls, scrubbers and dialog
/// panels.
///
/// `print` is banned in this root by `tools/lint-forbidden`, so the audit reports
/// through the unified log instead: `log stream --predicate 'category ==
/// "pixel-audit"'` while walking the app.
private struct PixelAudit: ViewModifier {
    let name: String
    @Environment(\.displayScale) private var scale
    private static let log = Logger(subsystem: "com.superflow.app", category: "pixel-audit")

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(WindowSpace.name))
            } action: { frame in
                for (axis, value) in [("x", frame.minX), ("y", frame.minY),
                                      ("w", frame.width), ("h", frame.height)]
                where !Pixel.isOnGrid(value, scale) {
                    Self.log.warning(
                        """
                        PixelAudit \(name, privacy: .public): \
                        \(axis, privacy: .public) = \(value) \
                        is off the \(Int(scale))x grid
                        """
                    )
                }
            }
    }
}

public extension View {
    func pixelAudit(_ name: String) -> some View { modifier(PixelAudit(name: name)) }
}
#else
public extension View {
    func pixelAudit(_ name: String) -> some View { self }
}
#endif
