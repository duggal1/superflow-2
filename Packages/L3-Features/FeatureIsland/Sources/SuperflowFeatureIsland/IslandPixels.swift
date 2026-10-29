import SuperflowDesignSystem
import SwiftUI

/// Tiny hand-drawn marks. `#` is a cell; `.` is empty. A mark with `develop`
/// set fills from left to right in whole columns, so it arrives as a scan
/// rather than a pop.
///
/// These are bitmaps on purpose: at a 2 pt cell an SF Symbol would be a
/// different kind of object, and the Island's whole visual language is square
/// cells on whole pixels.
struct PixelBitmap: View {
    let rows: [String]
    var cell: CGFloat = 2
    var gap: CGFloat = 1
    var tone: Color = Ramp.blue[4]
    /// Seconds. Zero draws the finished mark immediately.
    var develop: TimeInterval = 0

    @State private var born = Date()
    @State private var finished = false
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduce

    static let check = [
        "......#",
        ".....#.",
        "#...#..",
        ".#.#...",
        "..#....",
    ]
    static let lock = [
        ".###.",
        "#...#",
        "#...#",
        "#####",
        "#####",
        "#####",
    ]
    static let spark = [
        "...#...",
        "...#...",
        "..###..",
        "#######",
        "..###..",
        "...#...",
        "...#...",
    ]
    static let flame = [
        "..#..",
        "..##.",
        ".###.",
        "#####",
        "#####",
        ".###.",
    ]
    static let arrowUp = [
        "..#..",
        ".###.",
        "#.#.#",
        "..#..",
        "..#..",
    ]
    static let dot = [
        ".##.",
        "####",
        "####",
        ".##.",
    ]
    /// The brand pixel disc: the same five-row mark as the sidebar's status.
    static let disc = [
        ".###.",
        "#####",
        "#####",
        "#####",
        ".###.",
    ]

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        let columns = rows.map(\.count).max() ?? 0
        let rows = rows, cell = cell, gap = gap, tone = tone
        let animate = develop > 0 && !reduce && !finished
        TimelineView(.animation(paused: !animate)) { timeline in
            let progress = animate
                ? min(1, timeline.date.timeIntervalSince(born) / develop)
                : 1
            let visible = Int((progress * Double(columns)).rounded(.up))
            Canvas { context, _ in
                for (row, line) in rows.enumerated() {
                    for (column, character) in line.enumerated()
                    where character == "#" && column < visible {
                        let rect = grid.rect(CGRect(x: CGFloat(column) * (cell + gap),
                                          y: CGFloat(row) * (cell + gap),
                                          width: cell, height: cell))
                        context.fill(Path(rect), with: .color(tone),
                                     style: FillStyle(antialiased: false))
                    }
                }
            }
        }
        .frame(width: grid.length(CGFloat(columns) * (cell + gap) - gap),
               height: grid.length(CGFloat(rows.count) * (cell + gap) - gap))
        .task(id: develop) {
            guard develop > 0, !reduce else { finished = true; return }
            do { try await Task.sleep(for: .seconds(develop)) } catch { return }
            finished = true
        }
        .accessibilityHidden(true)
    }
}

/// A fixed cell count that drains to the deadline. 18 cells by default, one
/// leaves every third of a second: whole steps, no gradient, and the last lit
/// cell is the bright one so the eye can read the remaining time without a
/// numeral.
struct PixelCountdown: View {
    let deadline: Date
    let total: TimeInterval
    var cells = 18

    @Environment(\.displayScale) private var scale

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        let cells = cells
        let total = max(total, 0.001)
        let deadline = deadline
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            let left = max(0, deadline.timeIntervalSince(timeline.date))
            let lit = min(cells, Int((left / total * Double(cells)).rounded(.up)))
            Canvas { context, _ in
                for index in 0..<cells {
                    let x = CGFloat(index) * 4
                    if index < lit {
                        context.fill(Path(grid.rect(CGRect(x: x, y: 0, width: 3, height: 3))),
                                     with: .color(index == lit - 1 ? Ramp.blue[4] : Ramp.blue[3]),
                                     style: FillStyle(antialiased: false))
                    } else {
                        context.fill(Path(grid.rect(CGRect(x: x + 1, y: 1, width: 1, height: 1))),
                                     with: .color(Tok.controlPressed),
                                     style: FillStyle(antialiased: false))
                    }
                }
            }
        }
        .frame(width: grid.length(CGFloat(cells) * 4 - 1), height: grid.length(3))
        .accessibilityHidden(true)
    }
}

/// One-shot milestone burst: a dithered ring expanding in 14 whole steps over
/// 700 ms behind the notice's mark. Reduce Motion draws nothing; the mark alone
/// is the announcement.
struct PixelBurst: View {
    @State private var born = Date()
    @Environment(\.accessibilityReduceMotion) private var reduce
    private let burstCells = 14

    @Environment(\.displayScale) private var scale

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        if reduce {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let progress = min(1, timeline.date.timeIntervalSince(born) / 0.7)
                let step = (progress * 14).rounded(.up) / 14
                Canvas { context, _ in
                    guard step < 1 else { return }
                    let centre = CGFloat(burstCells - 1) / 2
                    for row in 0..<burstCells {
                        for column in 0..<burstCells {
                            let distance = hypot(CGFloat(column) - centre,
                                                 CGFloat(row) - centre)
                            guard abs(distance - step * 8) < 1.2,
                                  grain(column, row) > step * 0.85 else { continue }
                            let rect = CGRect(x: CGFloat(column) * 4,
                                              y: CGFloat(row) * 4,
                                              width: 3, height: 3)
                            let tone = abs(distance - step * 8) < 0.6
                                ? Ramp.blue[4] : Ramp.blue[3]
                            context.fill(Path(grid.rect(rect)), with: .color(tone),
                                         style: FillStyle(antialiased: false))
                        }
                    }
                }
            }
            .frame(width: grid.length(55), height: grid.length(55))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Deterministic dither: the ring keeps its grain across frames.
    private func grain(_ column: Int, _ row: Int) -> Double {
        var hash = UInt32(truncatingIfNeeded: column) &* 374_761_393
            &+ UInt32(truncatingIfNeeded: row) &* 668_265_263
        hash = (hash ^ (hash >> 13)) &* 1_274_126_177
        hash ^= hash >> 16
        return Double(hash) / Double(UInt32.max)
    }
}

/// Three 2 pt cells stepping every 160 ms: the cleanup wait. Reduce Motion
/// holds all three lit, because a frozen three-cell mark still reads as "busy"
/// while a single frozen cell reads as "done".
struct IslandWait: View {
    @Environment(\.accessibilityReduceMotion) private var reduce

    @Environment(\.displayScale) private var scale

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        let reduce = reduce
        TimelineView(.periodic(from: .now, by: 0.16)) { timeline in
            let active = reduce
                ? -1
                : Int(timeline.date.timeIntervalSinceReferenceDate / 0.16) % 3
            Canvas { context, _ in
                for index in 0..<3 {
                    let tone = index == active ? Ramp.blue[4]
                        : reduce ? Ramp.blue[3] : Ramp.blue[2]
                    context.fill(Path(grid.rect(CGRect(x: CGFloat(index) * 6, y: 0, width: 2, height: 2))),
                                 with: .color(tone), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: grid.length(14), height: grid.length(2))
        .accessibilityHidden(true)
    }
}

/// The brand pixel disc at glyph scale. A meeting's record mark is the product,
/// not an alarm: it stays blue instead of turning the Island into a red light.
struct RecordDisc: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        PixelBitmap(rows: PixelBitmap.disc, develop: 0.14)
            .frame(width: grid.length(14), height: grid.length(14))
    }
}
