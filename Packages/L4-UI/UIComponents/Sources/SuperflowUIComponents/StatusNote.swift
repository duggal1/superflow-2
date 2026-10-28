import SuperflowDesignSystem
import SwiftUI

/// The sidebar's engine status, drawn in pixels on the glass itself.
///
/// There is no plate. The old note sat on `Tok.surface`, which read as a black
/// hole in the sidebar at night; the fix is to delete the plate, not the pixels.
/// State is carried by a 6 × 5 mark of 3 pt cells and, only while the work is
/// genuinely indeterminate, a 4 pt scan rail under the label:
///
/// - **caret** — one lit centre cell with its ring dimmed. Ready, or an error the
///   label already explains.
/// - **comet** — a head with a dithered trail and the rail beneath it, stepping
///   left to right every 160 ms. Only for work with no end to show: a model
///   loading, or the microphone live while you speak.
/// - **slab** — a solid 3 × 5 block. Failure, unmistakable by shape, so no status
///   hue is needed anywhere in the note.
public struct StatusNote: View {
    public let text: String
    public var level: DotLevel = .warning
    /// True only while the work genuinely has no end to show. Deterministic states
    /// must pass `false`, or the note would animate forever.
    public var working: Bool

    public init(text: String, level: DotLevel = .warning, working: Bool = false) {
        self.text = text
        self.level = level
        self.working = working
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                StatusPixelMark(level: level, working: working)
                Text(text)
                    .appType(.label)
                    .foregroundStyle(Tok.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            StatusScanRail(active: working)
                .padding(.leading, 33)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 6 × 5 cells of 3 pt with 1 pt gaps (23 × 19), whole device pixels, never
/// antialiased. The 3/1 pair is a glyph-scale exception to the 4 pt grid and
/// lives only here.
private struct StatusPixelMark: View {
    let level: DotLevel
    let working: Bool

    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let cols = 6
    static let rows = 5
    static let cell: CGFloat = 3
    static let gap: CGFloat = 1
    static let step: TimeInterval = 0.16

    private var width: CGFloat {
        CGFloat(Self.cols) * Self.cell + CGFloat(Self.cols - 1) * Self.gap
    }
    private var height: CGFloat {
        CGFloat(Self.rows) * Self.cell + CGFloat(Self.rows - 1) * Self.gap
    }

    var body: some View {
        let animating = working && !reduceMotion
        TimelineView(.animation(minimumInterval: Self.step, paused: !animating)) { context in
            let frame = animating
                ? Int(context.date.timeIntervalSinceReferenceDate / Self.step)
                : 0
            Canvas { ctx, _ in draw(&ctx, frame: frame, animating: animating) }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, frame: Int, animating: Bool) {
        let cell = Self.cell
        let pitch = Self.cell + Self.gap
        // The head sweeps one cell past the right edge and returns, so the mark
        // reads as motion instead of a loop that visibly restarts on the last column.
        let head = frame % (Self.cols + 3) - 1
        let quiet = Tok.text2.opacity(0.16)

        for row in 0..<Self.rows {
            for col in 0..<Self.cols {
                let tone: Color
                if level == .error {
                    // Shape carries the failure. A 3-wide slab is enough.
                    tone = col < 3 ? Tok.text : .clear
                } else if animating {
                    let distance = head - col
                    switch distance {
                    case 0:  tone = Ramp.blue[4]
                    case 1:  tone = (col + row) % 2 == 0 ? Ramp.blue[3] : Ramp.blue[2]
                    case 2:  tone = Ramp.blue[2]
                    case 3:  tone = Ramp.blue[1]
                    default: tone = quiet
                    }
                } else {
                    let dx = abs(col - (Self.cols - 1) / 2)
                    let dy = abs(row - (Self.rows - 1) / 2)
                    if dx == 0 && dy == 0 {
                        tone = Ramp.blue[4]
                    } else if dx + dy == 1 {
                        tone = Ramp.blue[2]
                    } else {
                        tone = quiet
                    }
                }
                guard tone != .clear else { continue }
                let rect = CGRect(x: CGFloat(col) * pitch, y: CGFloat(row) * pitch,
                                  width: cell, height: cell)
                ctx.fill(Path(rect), with: .color(tone), style: FillStyle(antialiased: false))
            }
        }
    }
}

/// The animated half of the footer: 4 × 2 cells on a 6 pt pitch, with a comet head
/// and a dithered cooling trail. It is the only moving line in the sidebar, and it
/// moves only while the state is indeterminate. Reduce Motion freezes the head.
private struct StatusScanRail: View {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cell: CGFloat = 4
    private static let gap: CGFloat = 2
    private static let step: TimeInterval = 0.08

    var body: some View {
        let animating = active && !reduceMotion
        TimelineView(.animation(minimumInterval: Self.step, paused: !animating)) { context in
            let frame = animating
                ? Int(context.date.timeIntervalSinceReferenceDate / Self.step)
                : 0
            Canvas { ctx, size in
                draw(&ctx, size: size, frame: frame, animating: animating)
            }
        }
        .frame(height: 2)
        .opacity(active ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, frame: Int, animating: Bool) {
        let pitch = Self.cell + Self.gap
        let cols = max(1, Int((size.width + Self.gap) / pitch))
        let head = animating ? frame % (cols + 4) - 1 : 0
        let quiet = Tok.text2.opacity(0.14)

        for col in 0..<cols {
            let distance = head - col
            let tone: Color
            switch distance {
            case 0:  tone = Ramp.blue[4]
            case 1:  tone = Ramp.blue[3]
            case 2:  tone = Ramp.blue[2]
            case 3:  tone = Ramp.blue[1]
            default: tone = quiet
            }
            let rect = CGRect(x: CGFloat(col) * pitch, y: 0, width: Self.cell, height: 2)
            ctx.fill(Path(rect), with: .color(tone), style: FillStyle(antialiased: false))
        }
    }
}
