import AppKit
import SwiftUI

/// The NVIDIA eye mark used to identify NVIDIA model providers.
///
/// The bundled SVG is loaded from the icon package's resource bundle so the
/// mark stays crisp at every row size without shipping a raster fallback.
@MainActor
public struct NVIDIAIcon: View {
    public static var resourceURL: URL? {
        Bundle.module.url(forResource: "nvidia", withExtension: "svg")
    }

    private static let image: NSImage? = resourceURL.flatMap { NSImage(contentsOf: $0) }

    public var size: CGFloat
    /// Vendor marks render as a monochrome template so they sit with SF Symbols.
    public var tint: Color?

    public init(size: CGFloat = 18, tint: Color? = nil) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(tint ?? Color.primary)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("NVIDIA")
    }
}
