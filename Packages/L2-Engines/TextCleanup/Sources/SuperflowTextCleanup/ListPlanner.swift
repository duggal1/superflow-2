import Foundation
import SuperflowKernel

public enum CleanupSegment: Sendable, Equatable {
    case prose(String)
    case list(lead: String, items: [String])
}

public enum ListPlanner {
    private static let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
    private static let cardinals = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
    private static let blocked: Set<String> = ["a", "one", "per", "every", "each", "few", "couple", "half", "last", "next", "this", "another", "at"]
    private static let closers = [["i", "think"], ["i", "guess"], ["that's"], ["that", "is"], ["that", "should"], ["and", "that's"], ["anyway"], ["thanks"], ["thank", "you"], ["let", "me", "know"], ["so", "yeah"], ["okay", "so"]]
    private struct Mark { var position: Int; var length: Int }

    public static func plan(_ text: String, protected: Protected = Protected(), timings: [WordTiming] = []) -> [CleanupSegment] {
        // Existing command-created newlines and markdown remain hard boundaries.
        text.components(separatedBy: "\n").flatMap { line in planLine(line, protected: protected, timings: timings) }
    }

    private static func planLine(_ text: String, protected: Protected, timings: [WordTiming]) -> [CleanupSegment] {
        let words = Tokenizer.tokens(in: text)
        let timed = WordTimingProjection.apply(to: Tokenizer.words(text, protected: protected), timings: timings)
        guard !words.isEmpty else { return [] }
        let ranges = protected.ranges(in: text)
        let keys = words.map { $0.core.lowercased().replacingOccurrences(of: "’", with: "'") }
        func matches(_ marker: [String], _ index: Int) -> Bool {
            index + marker.count <= words.count && marker.enumerated().allSatisfy { offset, key in
                keys[index + offset] == key && !ranges.contains { $0.overlaps(words[index + offset].range) }
            }
        }
        func sequence(_ markers: [[String]]) -> [Mark]? {
            for start in words.indices where matches(markers[0], start) {
                if start > 0, blocked.contains(keys[start - 1]) { continue }
                var chain = [Mark(position: start, length: markers[0].count)]
                var cursor = start + markers[0].count
                for marker in markers.dropFirst() {
                    guard cursor < words.count,
                          let next = (cursor..<min(words.count, cursor + 61)).first(where: { matches(marker, $0) && ($0 == 0 || !blocked.contains(keys[$0 - 1])) }),
                          next > cursor else { break }
                    chain.append(Mark(position: next, length: marker.count))
                    cursor = next + marker.count
                }
                if chain.count >= 3 { return chain }
            }
            return nil
        }
        let bullets = words.indices.filter { matches(["bullet"], $0) }.map {
            Mark(position: $0, length: $0 + 1 < keys.count && ["point", "points"].contains(keys[$0 + 1]) ? 2 : 1)
        }
        guard let chain = sequence(ordinals.map { [$0] }) ?? sequence(cardinals.map { ["number", $0] }) ?? (bullets.count >= 2 ? bullets : nil),
              let first = chain.first else { return [.prose(text)] }
        func joined(_ range: Range<Int>) -> String { words[range].map(\.full).joined(separator: " ") }
        let leadEnd = (0..<first.position).last(where: { words[$0].trail.contains { ".?!".contains($0) } || timed[$0].pause }).map { $0 + 1 } ?? 0
        var result: [CleanupSegment] = []
        if leadEnd > 0 { result.append(.prose(joined(0..<leadEnd))) }
        var items: [String] = []
        var tail = words.count
        for (index, marker) in chain.enumerated() {
            let start = marker.position + marker.length
            var end = index + 1 < chain.count ? chain[index + 1].position : words.count
            if index == chain.count - 1, start + 2 < end {
                for cut in (start + 2)..<end {
                    let closes = closers.contains { phrase in
                        cut + phrase.count <= end && phrase.enumerated().allSatisfy { keys[cut + $0.offset] == $0.element }
                    }
                    if !timed[cut - 1].glue, words[cut - 1].trail.contains(where: { ".?!".contains($0) }) || timed[cut - 1].pause || closes {
                        tail = cut; end = cut; break
                    }
                }
            }
            while end > start, keys[end - 1] == "and", !timed[end - 1].protected, !timed[end - 1].glue { end -= 1 }
            guard start < end else { return [.prose(text)] }
            items.append(joined(start..<end))
        }
        result.append(.list(lead: joined(leadEnd..<first.position), items: items))
        if tail < words.count { result.append(contentsOf: planLine(joined(tail..<words.count), protected: protected, timings: timings)) }
        return result
    }
}

public enum ListRenderer {
    private static func stripEnd(_ text: String, protected: Protected) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = result.last, ".,;:!?".contains(last) {
            let ending = result.index(before: result.endIndex)..<result.endIndex
            if protected.overlaps(ending, in: result, detect: false) { break }
            result.removeLast()
        }
        return result
    }
    public static func render(lead: String, items: [String], protected: Protected = Protected()) -> String {
        let body = items.map { "- " + stripEnd($0, protected: protected) }.joined(separator: "\n")
        let heading = stripEnd(lead, protected: protected)
        return heading.isEmpty ? body : heading + ":\n" + body
    }
}
