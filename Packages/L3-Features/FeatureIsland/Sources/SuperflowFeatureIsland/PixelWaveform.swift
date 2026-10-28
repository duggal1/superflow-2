import SuperflowDesignSystem
import SwiftUI

/// The Island's meter: 11 x 7 cells of 2 pt with 1 pt gaps, a 32 x 20 box.
///
/// The newest level sits in the centre column and older levels are mirrored
/// outward, so the shape is a symmetric envelope: the voice radiating from the
/// notch, not a bar chart scrolling sideways. A column with no level is one dot
/// on the midline, so silence is a dotted line rather than an invisible slab of
/// near-black cells. Only lit cells are drawn.
///
/// `ambient` is the cleanup state: the same envelope, one ramp step down, so the
/// meter stays on screen after the microphone closes without pretending to be
/// live input.
///
/// The 2/1 cell and gap are a glyph-scale exception to the 3 pt graph gap. They
/// live here and nowhere else.
public struct PixelWaveform: View {
    private static let cell: CGFloat = 2
    private static let gap: CGFloat = 1

    private let history: [Int]
    private let ambient: Bool

    public init(history: [Int], ambient: Bool = false) {
        self.history = history
        self.ambient = ambient
    }

    public var body: some View {
        Canvas { context, _ in
            let pitch = Self.cell + Self.gap
            let midColumn = WaveformModel.columns / 2
            let midRow = WaveformModel.rows / 2
            let interior = ambient ? Ramp.blue[2] : Ramp.blue[3]
            let peak = ambient ? Ramp.blue[3] : Ramp.blue[4]

            for column in 0..<WaveformModel.columns {
                let distance = abs(column - midColumn)
                let half = history.isEmpty ? 0 : history[min(distance, history.count - 1)]

                guard half > 0 else {
                    // Silence is a single 2 pt cell on the midline. The centre
                    // column is one step brighter so the eye can find the newest
                    // sample even when nothing has arrived yet.
                    draw(&context, column: column, row: midRow,
                         tone: column == midColumn ? Tok.text2 : Tok.controlPressed,
                         pitch: pitch)
                    continue
                }

                for row in 0..<WaveformModel.rows {
                    let step = abs(row - midRow)
                    guard step <= half else { continue }
                    // The outer lit cell is the peak, so it carries the bright tip.
                    // The centre column of the peak is the newest sample: full stop.
                    let isTip = step == half
                    let tone = isTip && (column == midColumn || !ambient && step == 1)
                        ? peak
                        : interior
                    draw(&context, column: column, row: row, tone: tone, pitch: pitch)
                }
            }
        }
        .frame(width: 32, height: 20)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, column: Int, row: Int,
                      tone: Color, pitch: CGFloat) {
        let rect = CGRect(x: CGFloat(column) * pitch,
                          y: CGFloat(row) * pitch,
                          width: Self.cell,
                          height: Self.cell)
        context.fill(Path(rect), with: .color(tone), style: FillStyle(antialiased: false))
    }
}
