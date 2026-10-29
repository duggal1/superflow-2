import Foundation
import SuperflowDesignSystem
import SwiftUI

/// The Island's dictation meter: 11 x 7 cells of 2 pt on a 3 pt pitch, a
/// 32 x 20 box.
///
/// The live column sits in the centre and the samples spread outward, so the
/// shape is a symmetric envelope — the voice radiating from the notch, not a
/// bar chart scrolling sideways. A column with no level is one blue cell on the
/// midline: silence is a visible dotted line, never a slab of near-black cells.
struct IslandPixelMeter: View {
    let meter: IslandMeterModel
    var columns = 11
    @Environment(\.displayScale) private var scale

    var body: some View {
        let cols = columns
        let grid = IslandPixelGrid(scale: scale)
        TimelineView(.animation) { timeline in
            let _ = meter.advance(timeline.date.timeIntervalSinceReferenceDate)
            let live = meter.shown
            let trail = meter.trail
            Canvas { context, _ in
                let mid = 3
                for column in 0..<cols {
                    let distance = abs(column - cols / 2)
                    let value = distance == 0
                        ? live
                        : trail[min(distance - 1, trail.count - 1)]
                    let half = islandHalf(value, max: 3)
                    let x = CGFloat(column) * 3
                    guard half > 0 else {
                        cell(&context, grid, x, mid, Ramp.blue[2])
                        continue
                    }
                    for row in (mid - half)...(mid + half) {
                        let tip = abs(row - mid) == half
                        let tone = tip ? (distance == 0 ? Tok.text : Ramp.blue[4]) : Ramp.blue[3]
                        cell(&context, grid, x, row, tone)
                    }
                }
            }
        }
        .frame(width: grid.length(CGFloat(cols) * 3 - 1), height: grid.length(20))
        .accessibilityHidden(true)
    }
}

/// The Island's meeting meter: the same samples as a scrolling barcode, 24
/// columns of 2 pt cells on a 3 pt pitch.
///
/// The live column slides in from the right edge between samples, snapped to
/// whole device pixels, so the strip glides at the display rate while the cells
/// stay crisp. A meeting is a duration, so it reads left to right like a tape
/// instead of radiating from the notch.
struct IslandPixelBarcode: View {
    let meter: IslandMeterModel
    var columns = 24

    @Environment(\.displayScale) private var scale

    var body: some View {
        let cols = columns
        let grid = IslandPixelGrid(scale: scale)
        TimelineView(.animation) { timeline in
            let _ = meter.advance(timeline.date.timeIntervalSinceReferenceDate)
            let live = meter.shown
            let trail = meter.trail
            let phase = meter.phase
            Canvas { context, _ in
                let mid = 2
                for sample in 0...cols {
                    let age = cols - 1 - sample
                    let value: Float = sample == cols
                        ? live
                        : trail[min(age, trail.count - 1)]
                    let x = (CGFloat(sample) - phase) * 3
                    let half = islandHalf(value, max: 2)
                    guard half > 0 else {
                        cell(&context, grid, x, mid, age > 15 ? Ramp.blue[1] : Ramp.blue[2])
                        continue
                    }
                    let tone: Color = sample == cols ? Tok.text
                        : age < 3 ? Ramp.blue[4]
                        : age < 14 ? Ramp.blue[3]
                        : Ramp.blue[2]
                    for row in (mid - half)...(mid + half) {
                        cell(&context, grid, x, row, tone)
                    }
                }
            }
        }
        .frame(width: grid.length(CGFloat(cols) * 3 - 1), height: grid.length(14))
        .accessibilityHidden(true)
    }
}

/// One 2 x 2 cell on a 3 pt pitch. Whole device pixels, never antialiased.
private func cell(_ context: inout GraphicsContext, _ grid: IslandPixelGrid, _ x: CGFloat, _ row: Int, _ tone: Color) {
    context.fill(Path(grid.rect(CGRect(x: x, y: CGFloat(row) * 3, width: 2, height: 2))),
                 with: .color(tone),
                 style: FillStyle(antialiased: false))
}
