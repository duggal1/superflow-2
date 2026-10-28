import SuperflowDesignSystem
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

/// The seconds left on a card, as a digit. The rail beside it carries the
/// fraction; the digit makes the deadline unambiguous at a glance.
struct CountdownNumeral: View {
    let deadline: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let seconds = Int(ceil(max(0, (deadline ?? timeline.date)
                .timeIntervalSince(timeline.date))))
            Text("\(seconds)")
                .appType(.caption)
                .monospacedDigit()
                .foregroundStyle(Tok.text2)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.15), value: seconds)
        }
        .frame(width: 16, alignment: .trailing)
    }
}

/// The notice's mark. Shape carries the kind, so the card never needs a status
/// hue: a spark for a milestone, a flame for a streak, a tick for an installed
/// model, an up arrow for an update, and the brand dot for everything else.
///
/// A milestone is the one notice that gets a burst: a single dithered ring
/// behind the mark, 700 ms, once. Nothing else in the app celebrates.
struct NoticeMark: View {
    let kind: IslandNotice.Kind

    var body: some View {
        PixelBitmap(rows: rows, develop: 0.2)
            .frame(width: 20, height: 20)
            .background {
                if kind == .milestone { PixelBurst() }
            }
            .accessibilityHidden(true)
    }

    private var rows: [String] {
        switch kind {
        case .milestone: PixelBitmap.spark
        case .streak: PixelBitmap.flame
        case .modelReady: PixelBitmap.check
        case .update: PixelBitmap.arrowUp
        case .clipboard, .info: PixelBitmap.dot
        }
    }
}
