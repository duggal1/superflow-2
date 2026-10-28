import SuperflowDesignSystem
import SwiftUI

/// The Island's dictation meter: 11 x 7 cells of 2 pt on a 3 pt pitch, a
/// 32 x 20 box.
///
/// The newest level sits in the centre column and older levels spread outward,
/// so the shape is a symmetric envelope — the voice radiating from the notch,
/// not a bar chart scrolling sideways. A column with no level is one blue cell
/// on the midline: silence is a visible dotted line, never a slab of near-black
/// cells. That was the old bug — on a black Island, `controlPressed` silence was
/// invisible and the meter looked dead until the level passed its gate.
public struct IslandPixelMeter: View {
    private let trail: [Float]
    private let columns: Int

    public init(trail: [Float], columns: Int = WaveformModel.columns) {
        self.trail = trail
        self.columns = columns
    }

    public var body: some View {
        let columns = columns, trail = trail
        Canvas { context, _ in
            let mid = WaveformModel.rows / 2
            for column in 0..<columns {
                let distance = abs(column - columns / 2)
                let level = trail[min(distance, trail.count - 1)]
                let half = WaveformModel.cells(level, max: WaveformModel.halfMax)
                guard half > 0 else {
                    cell(&context, column: column, row: mid, tone: Ramp.blue[2])
                    continue
                }
                for row in (mid - half)...(mid + half) {
                    let tip = abs(row - mid) == half
                    cell(&context, column: column, row: row,
                         tone: tip ? Ramp.blue[4] : Ramp.blue[3])
                }
            }
        }
        .frame(width: CGFloat(columns) * 3 - 1, height: 20)
        .accessibilityHidden(true)
    }
}

/// The Island's meeting meter: the same trail as a scrolling barcode, 24 columns
/// of 2 pt cells on a 3 pt pitch.
///
/// The newest column is on the right and wears the full white scan head; the
/// next two stay blue 400 and the tail cools to blue 300 then navy. A meeting is
/// a duration, so the strip reads left to right like a tape instead of radiating
/// from the notch.
public struct IslandPixelBarcode: View {
    private let trail: [Float]
    private let columns: Int

    public init(trail: [Float], columns: Int = WaveformModel.barcodeColumns) {
        self.trail = trail
        self.columns = columns
    }

    public var body: some View {
        let columns = columns, trail = trail
        Canvas { context, _ in
            let mid = 2
            for column in 0..<columns {
                let age = columns - 1 - column
                let level = trail[min(age, trail.count - 1)]
                let half = WaveformModel.cells(level, max: 2)
                guard half > 0 else {
                    cell(&context, column: column, row: mid,
                         tone: age > 15 ? Ramp.blue[1] : Ramp.blue[2])
                    continue
                }
                let tone: Color = age == 0 ? Tok.text
                    : age < 3 ? Ramp.blue[4]
                    : age < 14 ? Ramp.blue[3]
                    : Ramp.blue[2]
                for row in (mid - half)...(mid + half) {
                    cell(&context, column: column, row: row, tone: tone)
                }
            }
        }
        .frame(width: CGFloat(columns) * 3 - 1, height: 14)
        .accessibilityHidden(true)
    }
}

/// One 2 x 2 cell on a 3 pt pitch. Whole device pixels, never antialiased.
/// The 2/1 cell and gap are a glyph-scale exception to the 3 pt graph gap and
/// live only in the Island's meters.
private func cell(_ context: inout GraphicsContext, column: Int, row: Int, tone: Color) {
    let rect = CGRect(x: CGFloat(column) * 3, y: CGFloat(row) * 3, width: 2, height: 2)
    context.fill(Path(rect), with: .color(tone), style: FillStyle(antialiased: false))
}
