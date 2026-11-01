import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

struct ModelPipeline: View {
    let noise: Bool
    let speech: Bool
    let cleanup: Bool

    private static let disc = ["..###..", ".#####.", "#######", "#######", "#######", ".#####.", "..###.."]
    private static let mic = ["..###..", ".#####.", ".#####.", ".#####.", "..###..", "...#...", "..###.."]
    private static let caret = ["#", "#", "#", "#", "#", "#", "#"]

    var body: some View {
        Card(padding: 20) {
            HStack(alignment: .top, spacing: 0) {
                node("Mic", rows: Self.mic, lit: true)
                link(noise)
                node("Noise", rows: Self.disc, lit: noise)
                link(noise && speech)
                node("Speech", rows: Self.disc, lit: speech)
                link(speech && cleanup)
                node("Cleanup", rows: Self.disc, lit: cleanup)
                link(speech)
                node("Your text", rows: Self.caret, lit: speech)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictation path. Noise \(noise ? "on" : "off"). Speech \(speech ? "ready" : "missing"). Cleanup \(cleanup ? "on" : "off").")
    }

    private func node(_ label: String, rows: [String], lit: Bool) -> some View {
        VStack(spacing: 8) {
            PixelMark(rows: rows, cell: 3, color: lit ? Ramp.blue[4] : Tok.controlPressed)
                .frame(height: 21)
            Text(label).appType(.caption).foregroundStyle(lit ? Tok.text : Tok.text2)
        }
        .frame(width: 64)
    }

    private func link(_ lit: Bool) -> some View {
        Canvas { context, size in
            let count = max(0, Int((size.width + 2) / 4))
            let offset = floor((size.width - CGFloat(count) * 4 + 2) / 2)
            for index in 0..<count {
                context.fill(Path(CGRect(x: offset + CGFloat(index) * 4, y: 10, width: 2, height: 2)),
                             with: .color(lit ? (index.isMultiple(of: 3) ? Ramp.blue[4] : Ramp.blue[3]) : Tok.controlPressed),
                             style: FillStyle(antialiased: false))
            }
        }
        .frame(maxWidth: .infinity).frame(height: 21)
        .accessibilityHidden(true)
    }
}
