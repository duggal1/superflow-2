import AppKit

public extension Icon {
    var symbolName: String { Self.resolved[self] ?? rawValue }

    private static let resolved: [Icon: String] = {
        let candidates: [Icon: [String]] = [
            .history: ["clock.arrow.trianglehead.counterclockwise.rotate.90", "clock.arrow.circlepath"],
            .capsuleShape: ["capsule.inset.filled", "capsule.fill"],
            .words: ["text.word.spacing", "text.alignleft"],
            .timeSaved: ["hourglass", "stopwatch"],
            .speed: ["gauge.with.needle", "gauge"],
            .streak: ["flame"],
        ]
        var result: [Icon: String] = [:]
        for (glyph, names) in candidates {
            result[glyph] = names.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
        }
        return result
    }()
}
