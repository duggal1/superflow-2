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

/// Three 2 pt cells that step in place while the model finishes. This is the
/// only looping mark in the app: an indeterminate wait has no end to show, so
/// the loop is the honest form. Reduce Motion holds all three lit instead.
struct PixelWait: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let cell: CGFloat = 2
    private static let pitch: CGFloat = 6
    private static let width = 3 * cell + 2 * (pitch - cell)

    var body: some View {
        Group {
            if reduceMotion {
                row(active: nil)
            } else {
                TimelineView(.periodic(from: .now, by: 0.16)) { context in
                    row(active: Int(context.date.timeIntervalSinceReferenceDate / 0.16) % 3)
                }
            }
        }
        .frame(width: Self.width, height: 20)
        .accessibilityHidden(true)
    }

    private func row(active: Int?) -> some View {
        HStack(spacing: Self.pitch - Self.cell) {
            ForEach(0..<3, id: \.self) { index in
                Rectangle()
                    .fill(tone(index: index, active: active))
                    .frame(width: Self.cell, height: Self.cell)
            }
        }
        .frame(width: Self.width, height: 20)
    }

    private func tone(index: Int, active: Int?) -> Color {
        guard let active else { return Ramp.blue[3] }
        return index == active ? Ramp.blue[4] : Tok.controlPressed
    }
}
