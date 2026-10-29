import AppKit

@MainActor
enum HugeIcon {
    private static let names: [Glyph: String] = [
        .dashboard: "dashboard", .history: "history", .dictionary: "dictionary",
        .shortcuts: "shortcuts", .meetings: "meetings", .settings: "settings",
        .models: "models", .mic: "mic", .keyboard: "keyboard", .waveform: "waveform",
        .cleanup: "cleanup", .person: "person", .power: "power", .handTap: "handTap",
        .eyeSlash: "eyeSlash", .diagnostics: "diagnostics", .licenses: "licenses",
        .number: "number", .textSize: "textSize", .paragraph: "paragraph",
        .blocks: "blocks", .code: "code", .chart: "chart", .timeSaved: "timeSaved",
        .liveText: "liveText", .appearance: "appearance", .space: "space",
        .textAppend: "textAppend", .folder: "folder", .delete: "delete",
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
