import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// A live meeting. The brand pixel disc is the record mark — a physical lamp on
/// the instrument, not a red app icon. The barcode reads the same meter as the
/// dictation waveform, so one measurement drives both presentations.
struct MeetingLiveView: View {
    let elapsed: Int
    let context: FlowContext

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: IslandTokens.Space.md) {
                RecordDisc()
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
            .frame(height: IslandTokens.Size.band)
            Spacer(minLength: 0)
            PixelRule(tone: Ramp.blue[1])
                .padding(.horizontal, IslandTokens.Space.sm)
        }
        .padding(.horizontal, IslandTokens.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording \(ClockText(elapsed: elapsed))")
    }
}

/// A finished meeting offers the generated follow-ups. Each one is a pixel
/// register row: a cell caret, the question, and a dotted rule that fills the
/// line. Choosing one submits it as the next question.
struct MeetingEndedView: View {
    let suggestions: [String]
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            PixelHeading(glyph: PixelBitmap.check, title: "Meeting saved", tone: Ramp.blue[4])
            PixelFlowRail(active: 5)
            Text("Ask a follow-up").appType(IslandTokens.TypeRole.caption)
                .foregroundStyle(IslandTokens.Color.ink2)
            if suggestions.isEmpty {
                HStack(spacing: IslandTokens.Space.sm) {
                    PixelBand(active: false, cells: 16)
                    Text("No suggestions for this meeting.")
                        .appType(IslandTokens.TypeRole.body)
                        .foregroundStyle(IslandTokens.Color.ink2)
                }
            } else {
                VStack(alignment: .leading, spacing: IslandTokens.Space.xs) {
                    ForEach(Array(suggestions.enumerated()), id: \.element) { i, item in
                        RowButton(item, height: IslandTokens.Size.row) {
                            context.actions.suggestion(item)
                        } content: {
                            HStack(spacing: IslandTokens.Space.sm) {
                                PixelBitmap(rows: PixelGlyphs.compose, cell: 1, gap: 0,
                                            tone: i == 0 ? Ramp.blue[4] : Ramp.blue[3])
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
            PixelRule(tone: Ramp.blue[1])
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelFramed()
    }
}

private func ClockText(elapsed: Int) -> String {
    let s = max(0, elapsed)
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}
