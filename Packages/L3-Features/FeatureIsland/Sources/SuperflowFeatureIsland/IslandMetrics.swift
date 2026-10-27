import CoreGraphics
import Foundation
import SuperflowDesignSystem

/// Shared geometry for the Island view and the AppKit panel that hosts it.
/// Keeping one source of truth prevents the SwiftUI content from being a
/// different width than the window that contains it.
public enum IslandMetrics {
    public static let compactWidth: CGFloat = 280
    public static let expandedWidth: CGFloat = 460
    public static let compactHeight: CGFloat = 60
    public static let expandedHeight: CGFloat = 160
    public static let compactContentHeight: CGFloat = 28
    public static let topInset: CGFloat = Layout.islandTopInset
}

/// Click-versus-drag policy for the Island. The AppKit host owns the actual
/// mouse tracking; this pure helper is the single definition of the 4pt
/// threshold so the behavior can be unit tested and reused by the host.
public enum IslandDragPolicy {
    public static let threshold: CGFloat = Layout.islandDragThreshold

    public static func isDrag(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) >= threshold
    }

    public static func isClick(_ translation: CGSize) -> Bool {
        !isDrag(translation)
    }
}
