import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI
import UniformTypeIdentifiers

// Pass 4: components that belong to the Island and to nothing else.

/// A full-surface click target. Features may not use `onTapGesture` or a raw
/// `Button`, so the Island's notch gets this instead.
public struct SurfaceButton: View {
    private let label: String
    private let action: () -> Void

    public init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) { Color.clear.contentShape(.rect) }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .clickable()
            .accessibilityLabel(label)
    }
}

/// The real icon of the app the text will land in. Loaded once per bundle id.
public struct AppIcon: View {
    private let bundleID: String
    private let size: CGFloat

    public init(bundleID: String, size: CGFloat) {
        self.bundleID = bundleID
        self.size = size
    }

    public var body: some View {
        Image(nsImage: AppIconCache.icon(for: bundleID))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

@MainActor
private enum AppIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for bundleID: String) -> NSImage {
        if let cached = cache.object(forKey: bundleID as NSString) { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .application)
        }
        cache.setObject(image, forKey: bundleID as NSString)
        return image
    }
}
