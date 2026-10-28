import AppKit
import SuperflowDesignSystem
import SwiftUI

/// The real NVIDIA eye, drawn from the vendor's own logo asset and tinted with the
/// one vendor colour in the app (`Tok.brandNvidia`).
///
/// The mark is template-rendered so the asset's own counters stay transparent and
/// the tint lands exactly on the letterforms: the same eye at 14 pt in a row and at
/// 64 pt in a page header, with no raster fallback.
@MainActor
public struct NVIDIAIcon: View {
    /// The asset's own ratio (248.899 × 164.698). The mark is wider than it is tall,
    /// so callers give a width and the height follows.
    public static let aspect: CGFloat = 248.899 / 164.698

    public static var resourceURL: URL? {
        Bundle.module.url(forResource: "nvidia", withExtension: "svg")
    }

    private static let image: NSImage? = resourceURL.flatMap { NSImage(contentsOf: $0) }

    /// The mark's width. Height is `size / aspect`.
    public var size: CGFloat
    public var tint: Color

    public init(size: CGFloat = 20, tint: Color = Tok.brandNvidia) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(tint)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size / Self.aspect)
        .accessibilityLabel("NVIDIA")
    }
}

/// S1-mini's mark. The bundled artwork is an opaque dark tile with no alpha, so it is
/// clipped to a rounded tile rather than knocked out: on a light card it reads as a
/// vendor plate, on a dark one it sits on the surface.
@MainActor
public struct S1MiniMark: View {
    private static let image: NSImage? =
        Bundle.module.url(forResource: "s1-mini", withExtension: "webp")
            .flatMap { NSImage(contentsOf: $0) }

    public var size: CGFloat

    public init(size: CGFloat = 24) {
        self.size = size
    }

    private var radius: CGFloat { max(4, (size * 0.25).rounded()) }

    public var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Rectangle().fill(Tok.well)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .accessibilityLabel("S1-mini")
    }
}
