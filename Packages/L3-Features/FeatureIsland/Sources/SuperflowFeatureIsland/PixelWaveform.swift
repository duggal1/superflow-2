import Foundation
import SuperflowDesignSystem
import SwiftUI

/// Voice samples travel outward from the center as a crisp, symmetric trace.
struct IslandPixelMeter: View {
    let meter: IslandMeterModel
    var columns = 11
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cols = columns
        let grid = IslandPixelGrid(scale: scale)
        TimelineView(.animation) { timeline in
            let _ = meter.advance(timeline.date.timeIntervalSinceReferenceDate)
            let live = meter.shown
            let trail = meter.trail
            let phase = reduceMotion ? 0 : meter.phase
            Canvas { context, _ in
                let mid = 2
                for column in 0..<cols {
                    let distance = abs(column - cols / 2)
                    let value = distance == 0
                        ? live
                        : trail[min(distance - 1, trail.count - 1)]
                    let half = value < 0.04 ? 0 : (value < 0.75 ? 1 : 2)
                    let direction: CGFloat = column == cols / 2 ? 0 : (column < cols / 2 ? -1 : 1)
                    let x = CGFloat(column) * 3 + direction * phase * 3
                    guard half > 0 else {
                        cell(&context, grid, x, mid, Tok.accent)
                        continue
                    }
                    cell(&context, grid, x, mid - half, Tok.accent)
                    cell(&context, grid, x, mid + half, Tok.accent)
                }
            }
        }
        .frame(width: grid.length(CGFloat(cols) * 3 - 1), height: grid.length(14))
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
