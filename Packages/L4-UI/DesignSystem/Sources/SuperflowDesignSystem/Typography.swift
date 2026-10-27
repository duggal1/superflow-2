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
    public static let largeSize: CGFloat = 15
    public static let headlineSize: CGFloat = 15
    public static let bodySize: CGFloat = 13
    public static let secondarySize: CGFloat = 12
    public static let metricSize: CGFloat = 28
    public static let minimumDisplaySize: CGFloat = 28
}

public enum AppFont {
    /// PostScript name of the bundled display face, `Fonts/SerifVinci.otf`
    /// (TRJN DaVinci italic, CFF). Titles only, 28 and 40, never upright.
    public static let displayName = "TRJNDaVinci-Italic-Trial"
    /// PostScript name of the bundled UI face, `Fonts/AlbertSans-Variable.ttf`.
    /// Every paragraph, label, row and control uses it.
    public static let baseName = "AlbertSans-Regular"

    /// Both faces are variable, so weight is an axis value rather than a face
    /// name. Text sits at 350; emphasis at 500. Nothing else is allowed (R5).
    public static let textWeight: CGFloat = 350
    public static let emphasisWeight: CGFloat = 500

    /// The faces shipped in `Contents/Resources/Fonts`. Both are real font files:
    /// they arrived as WOFF2 with a `.ttf` extension, which CoreText refuses, so
    /// every screen silently fell back to system faces until they were converted.
    public static let bundledFiles = ["SerifVinci.otf", "AlbertSans-Variable.ttf"]

    /// Registers every bundled face the process does not already have. The system
    /// does this for a bundled app through `ATSApplicationFontsPath`; this is the
    /// belt-and-braces path, so one wrong plist value cannot silently drop the
    /// whole type system back to system fonts. Returns the number newly registered.
    @discardableResult
    public static func registerBundledFonts() -> Int {
        guard let resources = Bundle.main.resourceURL else { return 0 }
        let directory = resources.appendingPathComponent("Fonts", isDirectory: true)
        var registered = 0
        for file in bundledFiles {
            let url = directory.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                registered += 1
            } else {
                _ = error?.takeRetainedValue()
            }
        }
        return registered
    }
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

    // One UI face: Albert Sans. Every label, control, row and line of body text
    // uses one of these roles at weight 350, with 500 reserved for emphasis.
    // Numbers stay on SF Pro so digits align in tables and counters. Titles keep
    // the bundled display serif, which is the brand mark, not body text.
    public static var title: Font { ui(TypeScale.titleSize, weight: AppFont.emphasisWeight) }
    public static var large: Font { ui(TypeScale.largeSize, weight: AppFont.textWeight) }
    public static var headline: Font { ui(TypeScale.headlineSize, weight: AppFont.emphasisWeight) }
    public static var body: Font { ui(TypeScale.bodySize, weight: AppFont.textWeight) }
    public static var bodyMedium: Font { ui(TypeScale.bodySize, weight: AppFont.emphasisWeight) }
    public static var secondary: Font { ui(TypeScale.secondarySize, weight: AppFont.textWeight) }
    public static var secondaryMedium: Font { ui(TypeScale.secondarySize, weight: AppFont.emphasisWeight) }
    /// The one role that stays on the system face: 28 Medium, tabular figures.
    public static var metric: Font { .system(size: TypeScale.metricSize, weight: .medium) }
    /// Code, identifiers and flags. SF Mono 12, never below the secondary size.
    public static var mono: Font {
        .system(size: TypeScale.secondarySize, weight: .regular, design: .monospaced)
    }

    /// Reading text. One step above body, Albert Sans 400, sized for a sentence
    /// that has to be read once and understood.
    public static var reading: Font { ui(15, weight: 400) }
    public static var readingSmall: Font { ui(14, weight: 400) }
    /// Larger sizes read loose on Albert Sans; this keeps them on the same rhythm.
    public static let readingTracking: CGFloat = -0.2

    /// The bundled UI face at an explicit variable weight. Missing on a fresh
    /// build or a broken bundle, it falls back to the system face rather than
    /// rendering nothing.
    public static func ui(_ size: CGFloat, weight: CGFloat = AppFont.textWeight) -> Font {
        guard NSFont(name: AppFont.baseName, size: size) != nil else {
            return .system(size: size, weight: weight >= 500 ? .medium : .regular)
        }
        return font(name: AppFont.baseName, size: size, weight: weight)
    }

    /// The same face as an `NSFont`, for attributed strings.
    public static func nsUIFont(_ size: CGFloat, weight: CGFloat = AppFont.textWeight) -> NSFont {
        let tag = "wght".utf8.reduce(0) { ($0 << 8) | Int($1) }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .name: AppFont.baseName,
            NSFontDescriptor.AttributeName.variation: [tag: weight],
        ])
        if let font = NSFont(descriptor: descriptor, size: size) { return font }
        return .systemFont(ofSize: size, weight: weight >= 500 ? .medium : .regular)
    }

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

    public static func display(_ size: CGFloat) -> Font { displayFont(size: size) }


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
/// Reports a missing type face without trapping. Typography falls back to a system
/// serif for titles and to the system face for everything else, so a missing font
/// must never prevent the app from launching.
@discardableResult
public func validateDisplayFont() -> Bool {
    let display = NSFont(name: AppFont.displayName, size: TypeScale.displaySSize) != nil
    if !display {
        NSLog("Superflow: %@ is not registered; using the system serif fallback.",
              AppFont.displayName)
    }
    return display
}
#endif
