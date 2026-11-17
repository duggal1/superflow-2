import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// A live meeting. The existing barcode renderer reads the same meter as the
/// dictation waveform, so one measurement drives both presentations. A rolling
/// clock says this is a duration, not a mode.
struct MeetingLiveView: View {
    let elapsed: Int
    let context: FlowContext

    var body: some View {
        HStack(spacing: IslandTokens.Space.md) {
            IconView(.settingMeeting, size: IslandTokens.Size.glyph, tint: IslandTokens.Color.danger)
                .frame(width: IslandTokens.Size.row, alignment: .leading)
            Text(ClockText(elapsed: elapsed))
                .appType(IslandTokens.TypeRole.metric)
                .foregroundStyle(IslandTokens.Color.ink)
                .monospacedDigit()
            Spacer(minLength: 0)
            IslandPixelBarcode(meter: context.meter, columns: 24)
            IconButton(.close, label: "End meeting", size: IslandTokens.Size.glyph,
                       tint: IslandTokens.Color.ink2, action: context.actions.endMeeting)
                .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
        }
        .padding(.horizontal, IslandTokens.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording \(ClockText(elapsed: elapsed))")
    }
}

/// A finished meeting offers the generated follow-ups. Choosing one submits it
/// as the next question, which moves the machine through thinking to answer.
struct MeetingEndedView: View {
    let suggestions: [String]
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            HStack(spacing: IslandTokens.Space.sm) {
                IconView(.checkmark, size: IslandTokens.Size.glyph, tint: IslandTokens.Color.wavePeak)
                Text("Meeting saved").appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
                IconButton(.close, label: "Dismiss", size: IslandTokens.Size.glyph,
                           tint: IslandTokens.Color.ink2, action: context.actions.dismiss)
                    .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
            }
            Text("Ask a follow-up").appType(IslandTokens.TypeRole.caption)
                .foregroundStyle(IslandTokens.Color.ink2)
            if suggestions.isEmpty {
                Text("No suggestions for this meeting.")
                    .appType(IslandTokens.TypeRole.body)
                    .foregroundStyle(IslandTokens.Color.ink2)
            } else {
                VStack(alignment: .leading, spacing: IslandTokens.Space.xs) {
                    ForEach(Array(suggestions.enumerated()), id: \.element) { i, item in
                        RowButton(item, height: IslandTokens.Size.row) {
                            context.actions.suggestion(item)
                        } content: {
                            HStack(spacing: IslandTokens.Space.sm) {
                                Rectangle()
                                    .fill(IslandTokens.Color.wave)
                                    .frame(width: IslandTokens.Size.hairline * 2,
                                           height: IslandTokens.Size.hairline * 2)
                                Text(item).appType(IslandTokens.TypeRole.body)
                                    .foregroundStyle(IslandTokens.Color.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .modifier(RowReveal(index: i))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private func ClockText(elapsed: Int) -> String {
    let s = max(0, elapsed)
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}
