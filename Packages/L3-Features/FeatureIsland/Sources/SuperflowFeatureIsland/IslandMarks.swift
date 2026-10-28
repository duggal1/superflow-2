import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// One blue pixel on the shelf under the notch. The only content at rest: it
/// says the notch is awake and clickable without bringing back a pill.
struct HoverMark: View {
    var body: some View {
        Rectangle()
            .fill(Ramp.blue[4])
            .frame(width: 2, height: 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 2)
            .accessibilityHidden(true)
    }
}

/// "Hands-free" and "Meeting" are promises about what the keys will do, so the
/// wing names them instead of showing the destination app icon. A bare symbol
/// carries the mode; the word carries the meaning.
struct ModeLabel: View {
    let text: String
    let glyph: Glyph

    var body: some View {
        HStack(spacing: 6) {
            Icon(glyph, size: 12, weight: .medium, tint: Ramp.blue[4])
                .frame(width: 12, height: 20)
            Text(text)
                .appType(.caption)
                .foregroundStyle(Tok.text)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// The six seconds an accidental Escape is held. One 4 x 12 cell per second,
/// lit while the second is still on the table, plus the digit so the deadline is
/// never ambiguous.
struct UndoTimer: View {
    let remaining: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(max(0, remaining))")
                .appType(.label)
                .monospacedDigit()
                .foregroundStyle(Tok.text)
                .contentTransition(.numericText(value: Double(max(0, remaining))))
                .animation(.snappy(duration: 0.15), value: remaining)

            BarCountdown(remaining: remaining, total: total)
        }
        .frame(width: 64, alignment: .trailing)
        .accessibilityLabel("\(remaining) seconds left to undo")
    }
}

/// The same cells, without the digit: a notice lives for five seconds, and the
/// rail counts them down so the card never disappears unannounced.
struct NoticeTimer: View {
    let remaining: Int
    let total: Int

    var body: some View {
        BarCountdown(remaining: remaining, total: total)
            .accessibilityLabel("Closes in \(remaining) seconds")
    }
}

/// One 4 x 12 cell per second. Lit while the second is still on the table.
struct BarCountdown: View {
    let remaining: Int
    let total: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { index in
                Rectangle()
                    .fill(index < remaining ? Ramp.blue[4] : Tok.control)
                    .frame(width: 4, height: 12)
            }
        }
        .frame(width: CGFloat(total) * 6 - 2, height: 12)
        .accessibilityHidden(true)
    }
}

/// A five-cell diamond of 2 pt cells. The notice's mark: one accent core with a
/// dithered ring, the same language as the page full stop.
struct NoticeMark: View {
    private static let cells: [(Int, Int)] = [
        (2, 0),
        (1, 1), (2, 1), (3, 1),
        (0, 2), (1, 2), (2, 2), (3, 2), (4, 2),
        (1, 3), (2, 3), (3, 3),
        (2, 4),
    ]

    var body: some View {
        Canvas { context, _ in
            for (x, y) in Self.cells {
                let core = x == 2 && y == 2
                let tone = core ? Ramp.blue[4] : (x + y) % 2 == 0 ? Ramp.blue[3] : Ramp.blue[2]
                let rect = CGRect(x: CGFloat(x) * 4, y: CGFloat(y) * 4, width: 2, height: 2)
                context.fill(Path(rect), with: .color(tone), style: FillStyle(antialiased: false))
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
