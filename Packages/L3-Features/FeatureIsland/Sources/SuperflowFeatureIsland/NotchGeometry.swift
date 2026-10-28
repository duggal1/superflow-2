import AppKit

/// Pure notch model. This is the only place that reads a screen, and it reads
/// `frame`, never the menu-bar-excluding rectangle that caused the floating badge.
public struct NotchGeometry: Equatable, Sendable {
    /// Screen frame in global coordinates.
    public let frame: CGRect
    /// Notch size in points. `.zero` on displays without a notch.
    public let notch: CGSize
    /// X of the notch (or of the screen when there is no notch), global, snapped
    /// to device pixels.
    public let centerX: CGFloat
    /// Height of the top band: the notch height, or 32 on displays without a notch.
    public let band: CGFloat
    public let scale: CGFloat

    public static let fallbackBand: CGFloat = 32
    public var hasNotch: Bool { notch.width > 0 }

    /// Pure and testable. Widths, not coordinates, so it works whatever space the
    /// auxiliary areas are reported in.
    public init(frame: CGRect, safeTop: CGFloat, leftWidth: CGFloat?, rightWidth: CGFloat?,
                scale: CGFloat) {
        let scale = max(1, scale)
        let snap = { (value: CGFloat) in (value * scale).rounded() / scale }
        var notch = CGSize.zero
        var band = Self.fallbackBand
        var center = frame.midX
        if safeTop > 0, let left = leftWidth, let right = rightWidth,
           frame.width - left - right > 0 {
            let width = frame.width - left - right
            notch = CGSize(width: width, height: safeTop)
            band = safeTop
            center = frame.minX + left + width / 2
        }
        self.frame = frame
        self.notch = notch
        self.band = band
        self.centerX = snap(center)
        self.scale = max(1, scale)
    }

    public init(screen: NSScreen) {
        self.init(frame: screen.frame,
                  safeTop: screen.safeAreaInsets.top,
                  leftWidth: screen.auxiliaryTopLeftArea?.width,
                  rightWidth: screen.auxiliaryTopRightArea?.width,
                  scale: screen.backingScaleFactor)
    }
}

public enum IslandScreens {
    /// The display that has a notch. The Island lives here at rest.
    public static var home: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    /// The display that holds keyboard focus. The Island moves here while it is doing something.
    public static var active: NSScreen? {
        NSScreen.main ?? home ?? NSScreen.screens.first
    }
}
