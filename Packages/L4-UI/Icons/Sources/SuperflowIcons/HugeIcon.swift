import AppKit

@MainActor
enum HugeIcon {
    private static let names: [Glyph: String] = [
        .dashboard: "dashboard", .dictionary: "dictionary",
        .meetings: "meetings",
        .models: "models", .person: "person", .appearance: "appearance",
        .liveText: "liveText", .chart: "chart", .paragraph: "paragraph", .licenses: "licenses",
    ]

    private static let images: [Glyph: NSImage] = names.reduce(into: [:]) { result, entry in
        guard let url = Bundle.module.url(forResource: "huge-\(entry.value)", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return }
        image.isTemplate = true
        result[entry.key] = image
    }

    static var glyphs: [Glyph] { Array(names.keys) }

    static func image(for glyph: Glyph) -> NSImage? { images[glyph] }
}
