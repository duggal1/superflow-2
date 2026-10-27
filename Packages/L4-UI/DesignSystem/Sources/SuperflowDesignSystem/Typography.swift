import AppKit
import CoreGraphics
import SwiftUI
import CoreText

public enum TypeScale {
    public static let displaySize: CGFloat = 40
    public static let displayLineHeight: CGFloat = 0.96
    public static let displayTracking: CGFloat = -2
    public static let displaySSize: CGFloat = 28
    public static let displaySLineHeight: CGFloat = 0.98
    public static let displaySTracking: CGFloat = -1.4
    public static let titleSize: CGFloat = 22
    public static let headlineSize: CGFloat = 15
    public static let bodySize: CGFloat = 13
    public static let secondarySize: CGFloat = 12
    public static let monoSize: CGFloat = 12
    public static let metricSize: CGFloat = 28
    public static let minimumDisplaySize: CGFloat = 28
}

public enum AppFont {
    /// PostScript name of the bundled display face (OFL). ATSApplicationFontsPath
    /// registers it at launch; `validateDisplayFont()` reports if it does not.
    /// Display/title face (TRJN DaVinci italic).
    public static let displayName = "TRJNDaVinci-Italic-Trial"
    /// Base face for description/rest (Albert Sans).
    public static let baseName = "AlbertSans-Regular"
}

public enum Typography {
    public static var display: Font { displayFont(size: TypeScale.displaySize) }

    public static var displayS: Font { displayFont(size: TypeScale.displaySSize) }

    public static var displayFallback: Font {
        .system(size: TypeScale.displaySize, weight: .medium, design: .serif).italic()
    }

    public static var displaySFallback: Font {
        .system(size: TypeScale.displaySSize, weight: .medium, design: .serif).italic()
    }

    public static var italic: Font { .custom(AppFont.displayName, size: TypeScale.bodySize) }

    public static var title: Font { Typography.font(name: AppFont.baseName, size: TypeScale.titleSize, weight: 350) }
    public static var headline: Font { Typography.font(name: AppFont.baseName, size: TypeScale.headlineSize, weight: 350) }
    public static var body: Font { Typography.font(name: AppFont.baseName, size: TypeScale.bodySize, weight: 350) }
    public static var bodyMedium: Font { Typography.font(name: AppFont.baseName, size: TypeScale.bodySize, weight: 350) }
    public static var secondary: Font { Typography.font(name: AppFont.baseName, size: TypeScale.secondarySize, weight: 350) }
    public static var secondaryMedium: Font { Typography.font(name: AppFont.baseName, size: TypeScale.secondarySize, weight: 350) }
    public static var mono: Font { Typography.font(name: AppFont.baseName, size: TypeScale.monoSize, weight: 350) }
    /// The one added role: SF Pro 28 Medium, tabular.
    public static var metric: Font { Typography.font(name: AppFont.baseName, size: TypeScale.metricSize, weight: 350) }

public static func font(name: String, size: CGFloat, weight: CGFloat? = nil) -> Font {
        if let weight {
            let tag = "wght".utf8.reduce(0) { ($0 << 8) | Int($1) }
            let desc = NSFontDescriptor(fontAttributes: [
                .name: name,
                NSFontDescriptor.AttributeName.variation: [tag: weight]
            ])
            if let nsFont = NSFont(descriptor: desc, size: size) {
                return Font(nsFont)
            }
        }
        if let nsFont = NSFont(name: name, size: size) {
            return Font(nsFont)
        }
        return .custom(name, size: size)
    }

    public static func displayFont(size: CGFloat) -> Font {
        let size = max(TypeScale.minimumDisplaySize, size)
        guard NSFont(name: AppFont.displayName, size: size) != nil else {
            return .system(size: size, weight: .medium, design: .serif).italic()
        }
        return Typography.font(name: AppFont.displayName, size: size)
    }

    public static func displayTracking(size: CGFloat) -> CGFloat {
        let size = max(TypeScale.minimumDisplaySize, size)
        guard NSFont(name: AppFont.displayName, size: size) != nil else { return 0 }
        return size >= TypeScale.displaySize ? TypeScale.displayTracking : TypeScale.displaySTracking
    }
}

public extension View {
    func displayStyle(size: CGFloat = TypeScale.displaySSize) -> some View {
        font(Typography.displayFont(size: size))
            .tracking(Typography.displayTracking(size: size))
            .lineSpacing(0)
            .foregroundStyle(Tok.text)
    }
}

#if DEBUG
/// Reports a missing display font without trapping. Typography already falls back
/// to a system serif, so a missing font must never prevent the app from launching.
@discardableResult
public func validateDisplayFont() -> Bool {
    let registered = NSFont(name: AppFont.displayName, size: TypeScale.displaySSize) != nil
    if !registered {
        NSLog("Superflow: %@ is not registered; using the system serif fallback.",
              AppFont.displayName)
    }
    return registered
}
#endif
