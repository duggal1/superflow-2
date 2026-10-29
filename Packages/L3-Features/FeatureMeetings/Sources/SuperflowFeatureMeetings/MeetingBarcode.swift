import SuperflowDesignSystem
import SuperflowMeetingEngine
import SuperflowUIComponents
import SwiftUI

func meetingTone(_ speaker: MeetingSpeaker, index: Int) -> Color {
    if speaker.isSelf { return Ramp.blue[4] }
    switch index % 3 {
    case 0: return Tok.text2
    case 1: return Ramp.blue[2]
    default: return Ramp.blue[3]
    }
}

enum MeetingBarcodeSamples {
    static func make(turns: [MeetingTurn], durationMs: Int, columns: Int) -> [String?] {
        guard columns > 0 else { return [] }
        guard durationMs > 0 else { return [String?](repeating: nil, count: columns) }
        let span = Double(durationMs) / Double(columns)
        var counts = [[String: Double]](repeating: [:], count: columns)
        for turn in turns where !turn.isGap && turn.endMs > turn.startMs {
            let lo = min(columns - 1, max(0, Int(Double(turn.startMs) / span)))
            let hi = min(columns - 1, max(lo, Int(Double(turn.endMs - 1) / span)))
            for column in lo...hi {
                let overlap = max(0, min(Double(turn.endMs), Double(column + 1) * span)
                                  - max(Double(turn.startMs), Double(column) * span))
                counts[column][turn.speakerID, default: 0] += overlap
            }
        }
        return counts.map { counts in
            guard let top = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }),
                  top.value > 0, top.value >= span - counts.values.reduce(0, +) else { return nil }
            return top.key
        }
    }
}

struct MeetingBarcode: View {
    let turns: [MeetingTurn]
    let speakers: [MeetingSpeaker]
    let durationMs: Int
    var columns = 96
    var pitch: CGFloat = 3
    var tickWidth: CGFloat = 2
    var tickHeight: CGFloat = 6
    var ghost: Int?
    @Environment(\.displayScale) private var scale

    var body: some View {
        let samples = MeetingBarcodeSamples.make(turns: turns, durationMs: durationMs, columns: columns)
        Canvas { context, size in
            func fill(_ rect: CGRect, _ color: Color) {
                let rect = CGRect(x: Pixel.snap(rect.minX, scale), y: Pixel.snap(rect.minY, scale),
                                  width: Pixel.snap(rect.width, scale), height: Pixel.snap(rect.height, scale))
                context.fill(Path(rect), with: .color(color), style: FillStyle(antialiased: false))
            }
            let y = (size.height - tickHeight) / 2
            for (column, speaker) in samples.enumerated() {
                let x = CGFloat(column) * pitch
                if let speaker, let index = speakers.firstIndex(where: { $0.id == speaker }) {
                    fill(CGRect(x: x, y: y, width: tickWidth, height: tickHeight),
                         meetingTone(speakers[index], index: index))
                } else {
                    fill(CGRect(x: x + 1, y: size.height / 2, width: 1, height: 1), Tok.controlPressed)
                }
            }
            if let ghost {
                fill(CGRect(x: CGFloat(ghost) * pitch + 1, y: 0, width: 1, height: size.height), Tok.text)
            }
        }
        .accessibilityHidden(true)
    }
}

struct MeetingStrip: View {
    let document: MeetingDocument
    @Binding var hover: TimeInterval?
    let onJump: (TimeInterval) -> Void

    var body: some View {
        let duration = Double(document.durationMs) / 1000
        TimelineStrip(duration: duration, hover: $hover, onJump: onJump) { width, hover in
            let columns = max(1, Int((width + 1) / 4))
            let ghost = hover.map { min(columns - 1, Int($0 / max(duration, 1) * Double(columns))) }
            MeetingBarcode(turns: document.turns, speakers: document.speakers, durationMs: document.durationMs,
                           columns: columns, pitch: 4, tickWidth: 3, tickHeight: 12, ghost: ghost)
        }
        .frame(height: 20)
    }
}
