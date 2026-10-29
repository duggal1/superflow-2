import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// One tone per speaker, in a fixed order. You are always the bright blue;
/// everyone else steps through the ramp so no two neighbours match.
func speakerTone(_ share: SpeakerShare, index: Int) -> Color {
    if share.isYou { return Ramp.blue[4] }
    switch index % 3 {
    case 0: return Tok.text2
    case 1: return Ramp.blue[2]
    default: return Ramp.blue[3]
    }
}

/// The live meeting clock: "4:12", or "1:04:12" once a meeting passes the hour.
struct ClockMetric: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let total = max(0, Int(timeline.date.timeIntervalSince(since)))
            Text(total >= 3600
                 ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
                 : String(format: "%d:%02d", total / 60, total % 60))
                .appType(.metric)
                .monospacedDigit()
                .foregroundStyle(Tok.text)
                .contentTransition(.numericText())
        }
        .frame(minWidth: 104, alignment: .leading)
        .accessibilityLabel("Meeting running")
    }
}

/// 110 ticks of 3 x 8 on a 4 pt pitch: each tick is a stretch of the meeting,
/// coloured by who held the floor. A white head marks now, and each marked
/// moment is one white dot above the strip.
struct MeetingTimeline: View {
    let pulse: MeetingPulse
    let marks: [TimeInterval]

    var body: some View {
        let slices = pulse.slices
        let speakers = pulse.speakers
        let slice = pulse.slice
        let marks = marks

        Canvas { context, _ in
            let columns = 110
            let count = slices.count

            func fill(_ rect: CGRect, _ tone: Color) {
                context.fill(Path(rect), with: .color(tone),
                             style: FillStyle(antialiased: false))
            }

            guard count > 0 else {
                for column in 0..<columns {
                    fill(CGRect(x: CGFloat(column) * 4 + 1, y: 9, width: 1, height: 1),
                         Tok.controlPressed)
                }
                return
            }

            let group = max(1, Int(ceil(Double(count) / Double(columns))))
            let used = Int(ceil(Double(count) / Double(group)))
            for column in 0..<columns {
                let x = CGFloat(column) * 4
                guard column < used else {
                    fill(CGRect(x: x + 1, y: 9, width: 1, height: 1), Tok.controlPressed)
                    continue
                }
                var counts: [Int8: Int] = [:]
                for value in slices[(column * group)..<min(count, (column + 1) * group)] {
                    counts[value, default: 0] += 1
                }
                let top = counts.max { $0.value < $1.value }?.key ?? -1
                guard top >= 0, Int(top) < speakers.count else {
                    fill(CGRect(x: x + 1, y: 9, width: 1, height: 1), Ramp.blue[1])
                    continue
                }
                let tone = column == used - 1
                    ? Tok.text
                    : speakerTone(speakers[Int(top)], index: Int(top))
                fill(CGRect(x: x, y: 6, width: 3, height: 8), tone)
            }

            guard slice > 0 else { return }
            for mark in marks {
                let column = min(used - 1, max(0, Int(mark / (slice * Double(group)))))
                fill(CGRect(x: CGFloat(column) * 4, y: 0, width: 3, height: 3), Tok.text)
            }
        }
        .frame(width: 439, height: 14)
        .animation(.snappy(duration: 0.20), value: slices.count)
        .accessibilityHidden(true)
    }
}

/// The meeting wings clicked open: clock and pace, the whole meeting as a
/// timeline, the talk share as a legend, and the three actions. The share bar is
/// gone because the legend carries the same percentages.
struct MeetingPanel: View {
    let model: IslandModel

    private var pad: CGFloat { IslandLayout.cardPad }

    var body: some View {
        let geometry = model.geometry
        let pulse = model.pulse
        let total = max(1, pulse.speakers.reduce(0) { $0 + $1.seconds })
        let marks = (pulse.marks + model.markedMoments).sorted()
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
                    stat(pulse.words.formatted(), "words")
                    stat(pulse.wpm == 0 ? "—" : "\(pulse.wpm)", "per minute")
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

                MeetingTimeline(pulse: pulse, marks: marks)

                HStack(spacing: 16) {
                    ForEach(Array(pulse.speakers.prefix(4).enumerated()),
                            id: \.element.id) { index, share in
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(speakerTone(share, index: index))
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
                    Spacer(minLength: 0)
                }
                .frame(height: 16)

                if model.prefs.liveText {
                    LiveLine(live: model.live)
                        .frame(height: 20)
                }

                HStack(spacing: 8) {
                    AppButton("Mark", glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                        model.mark()
                    }
                    if !marks.isEmpty {
                        Text("\(marks.count) marked")
                            .appType(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Tok.text2)
                    }
                    Spacer(minLength: 0)
                    AppButton("Discard", glyph: nil, kind: .quiet, height: 24) {
                        model.discardMeeting()
                    }
                    AppButton("End meeting", glyph: nil, kind: .sapphire, height: IslandLayout.actionHeight) {
                        model.endMeeting()
                    }
                }
            }
            .padding(.top, IslandLayout.cardGap)
            .padding(.horizontal, pad)
            .padding(.bottom, pad)

            Spacer(minLength: 0)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .appType(.title)
                .monospacedDigit()
                .foregroundStyle(Tok.text)
                .contentTransition(.numericText())
            Text(label)
                .appType(.caption)
                .foregroundStyle(Tok.text2)
        }
    }
}
