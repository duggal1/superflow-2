import AppKit

public extension Glyph {
    var symbolName: String { Self.resolved[self] ?? rawValue }

    private static let resolved: [Glyph: String] = {
        let candidates: [Glyph: [String]] = [
            .dashboard: ["circle.grid.3x3", "circle.grid.2x2", "square.grid.2x2"],
            .history: ["clock", "clock.arrow.circlepath"],
            .dictionary: ["textformat.abc", "textformat", "character.book.closed"],
            .models: ["square.stack.3d.up", "cpu", "shippingbox"],
            .settings: ["switch.2", "slider.horizontal.3", "gearshape"],
            .words: ["text.word.spacing", "text.alignleft"],
            .timeSaved: ["timer", "stopwatch", "hourglass"],
            .speed: ["speedometer", "bolt"],
            .streak: ["calendar", "flame"],
        ]
        var result: [Glyph: String] = [:]
        for (glyph, names) in candidates {
            result[glyph] = names.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
        }
        return result
    }()
}
