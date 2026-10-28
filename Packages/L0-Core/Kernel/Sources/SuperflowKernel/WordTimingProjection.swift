import Foundation

public enum WordTimingProjection {
    private struct Pair: Hashable {
        let first: String
        let second: String
    }

    private struct TimedToken {
        let key: String
        let entry: Int
        let start: Int
        let end: Int
    }

    public static func apply(to words: [Word], timings: [WordTiming], minimumGapMs: Int = 600) -> [Word] {
        guard words.count > 1, timings.count > 1 else { return words }
        let timed = timings.enumerated().flatMap { entry, timing in
            Tokenizer.words(timing.word).map {
                TimedToken(key: $0.key, entry: entry, start: timing.startMs, end: timing.endMs)
            }
        }
        guard timed.count > 1 else { return words }
        var occurrences: [Pair: Int] = [:]
        var gaps: [Pair: Int] = [:]
        for index in 0..<(timed.count - 1) {
            let first = timed[index]
            let second = timed[index + 1]
            let pair = Pair(first: first.key, second: second.key)
            occurrences[pair, default: 0] += 1
            guard second.entry == first.entry + 1,
                  first.start >= 0, first.end >= first.start,
                  second.start >= first.end, second.end >= second.start else { continue }
            gaps[pair] = second.start - first.end
        }
        var outputOccurrences: [Pair: Int] = [:]
        for index in 0..<(words.count - 1) {
            outputOccurrences[Pair(first: words[index].key, second: words[index + 1].key), default: 0] += 1
        }
        var result = words
        for index in 0..<(words.count - 1) {
            let pair = Pair(first: words[index].key, second: words[index + 1].key)
            guard occurrences[pair] == 1, outputOccurrences[pair] == 1,
                  let gap = gaps[pair], gap >= max(1, minimumGapMs) else { continue }
            result[index].pause = true
        }
        return result
    }
}
