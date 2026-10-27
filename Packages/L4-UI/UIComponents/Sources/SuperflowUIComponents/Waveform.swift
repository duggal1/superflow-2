import SuperflowDesignSystem
import SwiftUI

public enum Waveform {
    /// Keeps the newest `count` levels, normalizes against the loudest recent
    /// sample, and returns bar heights in 0...1. Silence is a small floor, not
    /// a flat line, so the control still reads as live.
    public static func bars(from levels: [Float], count: Int) -> [CGFloat] {
        let width = max(1, count)
        guard !levels.isEmpty else {
            return Array(repeating: 0.08, count: width)
        }
        let recent = levels.suffix(width).map { max(0, min(1, $0)) }
        let padded = Array(repeating: Float(0), count: max(0, width - recent.count)) + recent
        let peak = max(0.08, padded.max() ?? 0)
        return padded.map { CGFloat(max(0.06, min(1, $0 / peak))) }
    }

    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot()
    }
}

public struct WaveformView: View {
    public let levels: [Float]
    public let tint: Color
    public let barWidth: CGFloat
    public let spacing: CGFloat
    public let minHeight: CGFloat

    public init(levels: [Float], tint: Color = Tok.accent, barWidth: CGFloat = 2,
                spacing: CGFloat = 2, minHeight: CGFloat = 4) {
        self.levels = levels
        self.tint = tint
        self.barWidth = barWidth
        self.spacing = spacing
        self.minHeight = minHeight
    }

    public var body: some View {
        Canvas { context, size in
            let slot = barWidth + spacing
            let count = max(1, Int(size.width / slot))
            let bars = Waveform.bars(from: levels, count: count)
            for (index, value) in bars.enumerated() {
                let height = max(minHeight, value * size.height)
                let rect = CGRect(x: CGFloat(index) * slot,
                                  y: (size.height - height) / 2,
                                  width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(tint))
            }
        }
        .accessibilityHidden(true)
    }
}
