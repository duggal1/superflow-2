import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

/// The Island's pixel instrument-panel language.
///
/// Everything in this file is square cells on the device-pixel grid. There is
/// no stroke, no gradient, no shadow and no symbol font: structure comes from
/// registration corners, dotted rules and cell glyphs, and colour comes from
/// the one blue ramp. This is the visual signature the rebuilt Island was
/// missing — the readout is built out of pixels, not decorated with them.
enum PixelInstrument {
    static let cell: CGFloat = 2
    static let gap: CGFloat = 1
    static let pitch: CGFloat = cell + gap
}

// MARK: - Registration corners

/// Four L-shaped pixel arms. The Island never draws a border; it marks the
/// corners of its readout the way a viewfinder registers a frame. Two cells are
/// brighter so the eye finds the top-left first.
struct PixelCorners: View {
    var arm: Int = 4
    var tone: Color = IslandRamp.step(3)
    var hot: Color = IslandRamp.step(4)
    /// Brackets sit inside the content so the silhouette's clip never eats them.
    var inset: CGFloat = IslandTokens.Space.sm

    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            let grid = IslandPixelGrid(scale: scale)
            let x0 = grid.length(inset)
            let y0 = grid.length(inset)
            let x1 = grid.length(geo.size.width - inset)
            let y1 = grid.length(geo.size.height - inset)
            let thick = grid.length(PixelInstrument.cell)
            let long = grid.length(CGFloat(arm) * PixelInstrument.pitch - PixelInstrument.gap)

            Canvas { context, _ in
                func cell(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                    context.fill(Path(grid.rect(CGRect(x: x, y: y, width: w, height: h))),
                                 with: .color(color), style: FillStyle(antialiased: false))
                }
                // Top-left (hot): the origin of every readout.
                cell(x0, y0, long, thick, hot)
                cell(x0, y0, thick, long, hot)
                // Top-right.
                cell(x1 - long + thick, y0, long, thick, tone)
                cell(x1 - thick, y0, thick, long, tone)
                // Bottom-left.
                cell(x0, y1 - long + thick, long, thick, tone)
                cell(x0, y1 - thick, thick, long, tone)
                // Bottom-right.
                cell(x1 - long + thick, y1 - thick, long, thick, tone)
                cell(x1 - thick, y1 - long, thick, long, tone)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Registers a readout with pixel corner brackets instead of a border.
    func pixelFramed(tone: Color = IslandRamp.step(3), hot: Color = IslandRamp.step(4)) -> some View {
        overlay { PixelCorners(tone: tone, hot: hot) }
    }
}

// MARK: - Dotted rule

/// A single row of cells used instead of a hairline. It never reaches the
/// corners, so the registration marks stay clean.
struct PixelRule: View {
    var tone: Color = IslandRamp.step(1)
    var inset: CGFloat = IslandTokens.Space.sm

    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            let grid = IslandPixelGrid(scale: scale)
            let available = geo.size.width - inset * 2
            let count = max(0, Int(available / (PixelInstrument.pitch * 2)))
            let used = grid.length(CGFloat(count) * PixelInstrument.pitch * 2 - PixelInstrument.gap)
            let start = (grid.length(geo.size.width) - used) / 2
            Canvas { context, _ in
                for index in 0..<count {
                    let x = start + grid.length(CGFloat(index) * PixelInstrument.pitch * 2)
                    context.fill(Path(grid.rect(CGRect(x: x, y: 0,
                                                       width: PixelInstrument.cell,
                                                       height: PixelInstrument.cell))),
                                 with: .color(tone), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(height: IslandTokens.Size.hairline * 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Headings

/// A card heading made of a pixel glyph, a label and a dotted signal rule.
/// Replaces the generic "SF Symbol + Text" header with the Island's own
/// cell-based vocabulary.
struct PixelHeading: View {
    let glyph: [String]
    let title: String
    var tone: Color = IslandRamp.step(4)
    var caption: String?

    var body: some View {
        HStack(spacing: IslandTokens.Space.sm) {
            PixelBitmap(rows: glyph, cell: PixelInstrument.cell,
                        gap: PixelInstrument.gap, tone: tone)
            Text(title).appType(IslandTokens.TypeRole.label)
                .foregroundStyle(IslandTokens.Color.ink)
            if let caption {
                Text(caption).appType(IslandTokens.TypeRole.caption)
                    .foregroundStyle(IslandTokens.Color.ink2)
            }
            PixelRule(tone: IslandRamp.step(2))
        }
        .frame(height: IslandTokens.Size.glyph)
    }
}

/// Pixel glyphs for each Island state. Kept here so a state's identity is one
/// small bitmap, not a boxed symbol.
enum PixelGlyphs {
    static let compose = [
        "..#..",
        "..##.",
        ".###.",
        "..#..",
        "..#..",
    ] // send arrow
    static let listening = [
        ".###.",
        "#...#",
        "#.#.#",
        "#...#",
        ".###.",
    ] // ear / mic cavity
    static let thinking = [
        ".###.",
        "#....",
        ".###.",
        "....#",
        ".###.",
    ] // S-curve
    static let answer = [
        ".###.",
        "#...#",
        "#####",
        "#...#",
        ".###.",
    ] // readout disc
    static let meeting = [
        ".###.",
        "#####",
        "#####",
        "#####",
        ".###.",
    ] // record disc
    static let history = [
        "#....",
        "###..",
        "#.##.",
        "#..##",
        "#...#",
    ] // stacked traces
    static let settings = [
        "#.#.#",
        ".###.",
        "#####",
        ".###.",
        "#.#.#",
    ] // tuning grid
    static let warning = [
        "..#..",
        ".###.",
        "#.#.#",
        "..#..",
        "..#..",
    ]
}

// MARK: - Live data band

/// A one-row cell band that reads as a live signal. The bright head walks the
/// band while `active`; at rest the band holds a single centre cell. Used where
/// a progress bar or a spinner would normally be generic.
struct PixelBand: View {
    var active: Bool = false
    var cells: Int = 24
    var tone: Color = IslandRamp.step(4)

    @Environment(\.displayScale) private var scale
    @Environment(\.islandReduceMotion) private var reduce

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        TimelineView(.animation(paused: !active || reduce)) { timeline in
            let head = active && !reduce
                ? Int(timeline.date.timeIntervalSinceReferenceDate * 8) % cells
                : cells / 2
            Canvas { context, _ in
                for index in 0..<cells {
                    let distance = abs(index - head)
                    let color: Color
                    if distance == 0 { color = tone }
                    else if distance <= 2 && active { color = IslandRamp.step(3) }
                    else if distance <= 4 && active { color = IslandRamp.step(2) }
                    else { color = IslandRamp.step(1) }
                    context.fill(Path(grid.rect(CGRect(x: CGFloat(index) * PixelInstrument.pitch,
                                                       y: 0,
                                                       width: PixelInstrument.cell,
                                                       height: PixelInstrument.cell))),
                                 with: .color(color), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: grid.length(CGFloat(cells) * PixelInstrument.pitch - PixelInstrument.gap),
               height: grid.length(PixelInstrument.cell))
        .accessibilityHidden(true)
    }
}

// MARK: - Pixel send mark

/// A bare pixel arrow used for the compose send action. No circle, no box.
struct PixelSendMark: View {
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        SurfaceButton("Send", action: action)
            .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
            .overlay {
                PixelBitmap(rows: PixelGlyphs.compose, cell: PixelInstrument.cell,
                            gap: PixelInstrument.gap,
                            tone: enabled ? IslandRamp.step(4) : IslandRamp.step(2))
                    .allowsHitTesting(false)
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
    }
}

// MARK: - Flow rail

/// Six pixel channels showing where the Island is in its flow. The lit channel
/// is a state you can see at a glance — the instrument tells you what it is
/// doing without a sentence. Channels are fixed so nothing shifts between
/// states.
struct PixelFlowRail: View {
    /// 0 rest, 1 compose, 2 listening, 3 thinking, 4 answer, 5 meeting.
    let active: Int
    var cellsPerChannel: Int = 3

    @Environment(\.displayScale) private var scale

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        let channels = 6
        let pitch = PixelInstrument.pitch
        let groupWidth = CGFloat(cellsPerChannel) * pitch
        let gap = pitch * 2
        let total = CGFloat(channels) * groupWidth + CGFloat(channels - 1) * gap
        Canvas { context, _ in
            for channel in 0..<channels {
                let origin = CGFloat(channel) * (groupWidth + gap)
                let isActive = channel == active
                for cell in 0..<cellsPerChannel {
                    let tone: Color
                    if isActive {
                        tone = cell == cellsPerChannel / 2 ? IslandRamp.step(4) : IslandRamp.step(3)
                    } else {
                        tone = IslandRamp.step(1)
                    }
                    context.fill(Path(grid.rect(CGRect(x: origin + CGFloat(cell) * pitch,
                                                       y: 0,
                                                       width: PixelInstrument.cell,
                                                       height: PixelInstrument.cell))),
                                 with: .color(tone), style: FillStyle(antialiased: false))
                }
                if channel < channels - 1 {
                    context.fill(Path(grid.rect(CGRect(x: origin + groupWidth + pitch - PixelInstrument.cell,
                                                       y: 0,
                                                       width: PixelInstrument.cell,
                                                       height: PixelInstrument.cell))),
                                 with: .color(IslandRamp.step(1)), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: grid.length(total), height: grid.length(PixelInstrument.cell))
        .accessibilityHidden(true)
    }
}

// MARK: - Text signal

/// A pixel envelope derived from a string's word lengths. An answer becomes a
/// physical trace on the instrument: long words reach further, short words stay
/// near the midline, and empty text is a dormant dotted line. Deterministic,
/// so the same answer always draws the same signal.
struct PixelTextSignal: View {
    let text: String
    var columns: Int = 40

    @Environment(\.displayScale) private var scale

    private var heights: [Int] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return Array(repeating: 0, count: columns) }
        return (0..<columns).map { column in
            let word = words[column % words.count]
            let length = word.filter(\.isLetter).count
            return min(3, max(1, Int((Double(length) / 7.0 * 3.0).rounded(.up))))
        }
    }

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        let bars = heights
        Canvas { context, _ in
            let mid = 3
            for (column, height) in bars.enumerated() {
                let x = grid.length(CGFloat(column) * PixelInstrument.pitch)
                if height == 0 {
                    context.fill(Path(grid.rect(CGRect(x: x,
                                                       y: CGFloat(mid) * PixelInstrument.pitch,
                                                       width: PixelInstrument.cell,
                                                       height: PixelInstrument.cell))),
                                 with: .color(IslandRamp.step(2)), style: FillStyle(antialiased: false))
                    continue
                }
                for row in (mid - height)...(mid + height) {
                    let tone = row == mid - height || row == mid + height ? IslandRamp.step(4) : IslandRamp.step(3)
                    context.fill(Path(grid.rect(CGRect(x: x,
                                                       y: CGFloat(row) * PixelInstrument.pitch,
                                                       width: PixelInstrument.cell,
                                                       height: PixelInstrument.cell))),
                                 with: .color(tone), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: grid.length(CGFloat(columns) * PixelInstrument.pitch - PixelInstrument.gap),
               height: grid.length(7 * PixelInstrument.pitch - PixelInstrument.gap))
        .accessibilityHidden(true)
    }
}

// MARK: - Small cells used inline

/// A two-pixel caret that marks where the next character lands.
struct PixelCaret: View {
    var tone: Color = IslandRamp.step(4)
    @Environment(\.displayScale) private var scale

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        Rectangle()
            .fill(tone)
            .frame(width: grid.length(PixelInstrument.cell),
                   height: grid.length(IslandTokens.Size.glyph))
            .accessibilityHidden(true)
    }
}
