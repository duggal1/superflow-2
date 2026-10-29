import Foundation
import SuperflowFeatureIsland
import SuperflowMeetingEngine

/// Keeps numeric aggregates, never a second copy of meeting text. The engine's
/// resident turn window can rotate without losing the panel's totals.
struct MeetingPulseTracker {
    private struct TurnSummary {
        var words: Int
        var seconds: Double
        var speaker: String
    }

    private var recent: [Int: TurnSummary] = [:]
    private var watermark = -1
    private var totals: [String: SpeakerShare] = [:]
    private var words = 0
    private var timeline: [Int8] = []
    private var speakerIDs: [String] = []
    private var slice: Double = 2

    mutating func update(_ document: MeetingDocument, seconds: TimeInterval) -> MeetingPulse {
        let duration = max(1, seconds)
        while duration / slice > 1800 {
            timeline = stride(from: 0, to: timeline.count, by: 2).map { timeline[$0] }
            slice *= 2
        }
        let count = min(1800, max(1, Int(ceil(duration / slice))))
        if timeline.count < count { timeline += repeatElement(-1, count: count - timeline.count) }
        for turn in document.turns where !turn.isGap {
            let summary = TurnSummary(words: turn.text.split(whereSeparator: \.isWhitespace).count,
                                      seconds: Double(max(0, turn.endMs - turn.startMs)) / 1000,
                                      speaker: turn.speakerID)
            if let previous = recent[turn.index] {
                words -= previous.words
                if var share = totals[previous.speaker] {
                    share.seconds -= previous.seconds
                    totals[previous.speaker] = share
                }
            } else if turn.index <= watermark { continue }
            words += summary.words
            var share = totals[turn.speakerID] ?? SpeakerShare(
                id: turn.speakerID, name: turn.speakerName, seconds: 0, isYou: turn.speakerID == "self")
            share.seconds += summary.seconds
            totals[share.id] = share
            recent[turn.index] = summary
            if !speakerIDs.contains(turn.speakerID), speakerIDs.count < 128 { speakerIDs.append(turn.speakerID) }
            if let index = speakerIDs.firstIndex(of: turn.speakerID) {
                let lo = min(count - 1, max(0, Int(Double(turn.startMs) / 1000 / slice)))
                let hi = min(count - 1, max(lo, Int(Double(max(turn.startMs, turn.endMs - 1)) / 1000 / slice)))
                for i in lo...hi { timeline[i] = Int8(index) }
            }
        }
        watermark = max(watermark, document.turns.map(\.index).max() ?? -1)
        let keep = Set(document.turns.suffix(512).map(\.index))
        recent = recent.filter { keep.contains($0.key) }
        let current = document.turns.last.flatMap {
            duration - Double($0.endMs) / 1000 < 3 ? $0.speakerName : nil
        }
        return MeetingPulse(words: max(0, words),
                            speakers: speakerIDs.compactMap { totals[$0] }, current: current,
                            wpm: Int(Double(max(0, words)) * 60 / duration),
                            slices: timeline, slice: slice)
    }
}
