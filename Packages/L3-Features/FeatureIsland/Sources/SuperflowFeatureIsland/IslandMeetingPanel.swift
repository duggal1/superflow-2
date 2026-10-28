import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// The live meeting clock: "4:12", or "1:04:12" once a meeting passes the hour.
struct ClockMetric: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let total = max(0, Int(timeline.date.timeIntervalSince(since)))
            Text(Self.clock(total))
                .appType(.metric)
                .foregroundStyle(Tok.text)
                .contentTransition(.numericText())
        }
        .frame(minWidth: 96, alignment: .leading)
        .accessibilityLabel("Meeting running")
    }

    static func clock(_ total: Int) -> String {
        total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Talk time as 88 pixel cells, one per ~1.1% of the meeting. Largest-remainder
/// allocation, so the bar always fills exactly and the last cell never lies.
struct PixelShareBar: View {
    let shares: [SpeakerShare]
    let cells = 88

    /// One tone per speaker, in a fixed order. You are always the bright blue;
    /// everyone else steps through the ramp so no two neighbours match.
    static func tone(_ share: SpeakerShare, index: Int) -> Color {
        if share.isYou { return Ramp.blue[4] }
        return [Tok.text2, Ramp.blue[2], Ramp.blue[3], Tok.controlPressed][index % 4]
    }

    func allocation() -> [Int] {
        let total = shares.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return shares.map { _ in 0 } }
        let raw = shares.map { $0.seconds / total * Double(cells) }
        var out = raw.map { Int($0) }
        let rest = cells - out.reduce(0, +)
        let order = raw.indices.sorted { raw[$0] - Double(out[$0]) > raw[$1] - Double(out[$1]) }
        for index in order.prefix(max(0, rest)) { out[index] += 1 }
        return out
    }

    var body: some View {
        let alloc = allocation()
        let shares = shares
        let cells = cells
        Canvas { context, _ in
            guard alloc.reduce(0, +) > 0 else {
                // Nothing said yet: dust.
                for column in 0..<cells {
                    context.fill(Path(CGRect(x: CGFloat(column) * 5 + 1.5, y: 1.5,
                                             width: 1, height: 1)),
                                 with: .color(Tok.controlPressed),
                                 style: FillStyle(antialiased: false))
                }
                return
            }
            var column = 0
            for (index, count) in alloc.enumerated() {
                for _ in 0..<count {
                    context.fill(Path(CGRect(x: CGFloat(column) * 5, y: 0,
                                             width: 4, height: 4)),
                                 with: .color(Self.tone(shares[index], index: index)),
                                 style: FillStyle(antialiased: false))
                    column += 1
                }
            }
        }
        .frame(width: CGFloat(cells) * 5 - 1, height: 4)
        .animation(.snappy(duration: 0.20), value: alloc)
        .accessibilityLabel("Talk time")
        .accessibilityValue(accessibilityValue(shares))
    }

    private func accessibilityValue(_ shares: [SpeakerShare]) -> String {
        let total = max(1, shares.reduce(0) { $0 + $1.seconds })
        return shares.map {
            "\($0.name) \(Int(($0.seconds / total * 100).rounded())) percent"
        }.joined(separator: ", ")
    }
}

/// The meeting wings clicked open: timer, words, who is talking, and the share
/// bar. It is a card, so it gets the card's band and padding, not a new anatomy.
struct MeetingPanel: View {
    let model: IslandModel

    private var pad: CGFloat { IslandLayout.cardPad }

    var body: some View {
        let geometry = model.geometry
        let pulse = model.pulse
        let total = max(1, pulse.speakers.reduce(0) { $0 + $1.seconds })
        let side = (model.box.body.width - geometry.notch.width) / 2

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        RecordDisc()
                        Text("Recording")
                            .appType(.label)
                            .foregroundStyle(Tok.text)
                    }
                    .fixedSize()
                    RecordDisc()
                }
                .accessibilityLabel("Recording")
                .padding(.leading, pad)
                .frame(width: side, alignment: .leading)

                if geometry.hasNotch {
                    Color.clear.frame(width: geometry.notch.width)
                }

                BarIconButton(glyph: .close, label: "Collapse") { model.send(.notchClicked) }
                    .padding(.trailing, pad - 8)
                    .frame(width: side, alignment: .trailing)
            }
            .frame(height: geometry.band)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 24) {
                    ClockMetric(since: model.meetingStart ?? .now)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pulse.words.formatted())
                            .appType(.title)
                            .monospacedDigit()
                            .foregroundStyle(Tok.text)
                            .contentTransition(.numericText())
                        Text("words")
                            .appType(.caption)
                            .foregroundStyle(Tok.text2)
                    }
                    Spacer(minLength: 0)
                    if let current = pulse.current {
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(Ramp.blue[4])
                                .frame(width: 4, height: 4)
                            Text(current)
                                .appType(.caption)
                                .foregroundStyle(Tok.text)
                                .lineLimit(1)
                        }
                    }
                }

                PixelShareBar(shares: pulse.speakers)

                HStack(spacing: 16) {
                    ForEach(Array(pulse.speakers.prefix(4).enumerated()),
                            id: \.element.id) { index, share in
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(PixelShareBar.tone(share, index: index))
                                .frame(width: 4, height: 4)
                            Text(share.name)
                                .appType(.caption)
                                .foregroundStyle(Tok.text2)
                                .lineLimit(1)
                            Text("\(Int((share.seconds / total * 100).rounded()))%")
                                .appType(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Tok.text2)
                        }
                    }
                }

                if model.prefs.liveText {
                    LiveLine(live: model.live)
                        .frame(height: 20)
                }
            }
            .padding(.top, IslandLayout.cardGap)
            .padding(.horizontal, pad)
            .padding(.bottom, pad)

            Spacer(minLength: 0)
        }
    }
}
