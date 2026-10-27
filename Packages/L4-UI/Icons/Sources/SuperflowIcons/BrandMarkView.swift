import AppKit
import SuperflowDesignSystem
import SwiftUI

@MainActor
public struct BrandMarkView: View {
    public static var resourceURL: URL? {
        Bundle.module.url(forResource: "brand-mark", withExtension: "svg")
    }

    private static let sourceImage: NSImage? = {
        guard let url = resourceURL, let image = NSImage(contentsOf: url) else { return nil }
        return image
    }()

    private let size: CGFloat
    private let tint: Color
    private let image: NSImage?

    public init(size: CGFloat = 20, tint: Color = Tok.accent) {
        self.size = size
        self.tint = tint
        if let sourceImage = Self.sourceImage,
           let image = sourceImage.copy() as? NSImage {
            image.size = NSSize(width: size * 108.92 / 110, height: size)
            image.isTemplate = true
            self.image = image
        } else {
            image = nil
        }
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(tint)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
