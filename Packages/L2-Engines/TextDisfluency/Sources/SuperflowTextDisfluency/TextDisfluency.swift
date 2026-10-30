import Foundation
import SuperflowKernel

public struct DisfluencyOptions: Sendable {
    public var removeFillers = true
    public var allowedFillers: Set<String>?
    public var keepCopies = 1
    public var keepDoubles: Set<String> = ["had had", "bye bye", "ha ha", "blah blah"]
    public var collapseDuplicates = true
    public var collapseRepeatedPhrases = true
    var thresholds: [String: Int] = [:]
    public init() {}
}

public enum TextDisfluency {
    private static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "hm", "mm", "mmm",
    ]
    private static let numbers: Set<String> = [
        "zero", "oh", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
        "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
        "eighty", "ninety", "hundred", "thousand", "million", "billion", "trillion", "quadrillion",
        "lakh", "lakhs", "crore", "crores", "dozen",
    ]

    public static func apply(_ words: [Word], _ options: DisfluencyOptions = .init()) -> [Word] {
        var result = options.removeFillers ? dropFillers(words, allowed: options.allowedFillers) : words
        guard options.collapseDuplicates else { return result }
        while true {
            let before = result.count
            let largest = options.collapseRepeatedPhrases ? 3 : 1
            for length in 1...largest { result = collapse(result, length: length, options: options) }
            if before == result.count { return result }
        }
    }

    private static func dropFillers(_ words: [Word], allowed: Set<String>?) -> [Word] {
        var output: [Word] = []
        var pendingLead = ""
        for (index, word) in words.enumerated() {
            let attached = word.glue || (index > 0 && words[index - 1].glue)
            let next = index + 1 < words.count ? words[index + 1].key : ""
            let contentAh = word.key == "ah" && ["ha", "yes"].contains(next)
            guard !word.protected, !attached, (allowed?.contains(word.key) ?? isFiller(word.key)), !contentAh else {
                var kept = word
                kept.lead = pendingLead + kept.lead
                pendingLead = ""
                output.append(kept)
                continue
            }
            pendingLead += word.lead
            if !output.isEmpty {
                if !word.trail.isEmpty, !output[output.count - 1].trail.hasSuffix(word.trail) {
                    output[output.count - 1].trail += word.trail
                }
                output[output.count - 1].pause = output[output.count - 1].pause || word.pause
            } else if !word.trail.isEmpty {
                pendingLead += word.trail
            }
        }
        if !pendingLead.isEmpty, !output.isEmpty { output[output.count - 1].trail += pendingLead }
        return output
    }

    private static func isFiller(_ key: String) -> Bool {
        if fillers.contains(key) { return true }
        guard key.count <= 6 else { return false }
        let elongations: [(String, Character)] = [("umm", "m"), ("uhh", "h"), ("hmm", "m"),
                                                  ("erm", "m"), ("err", "r"), ("ahh", "h")]
        return elongations.contains { prefix, suffix in
            key.hasPrefix(prefix) && key.dropFirst(prefix.count).allSatisfy { $0 == suffix }
        }
    }

    private static func collapse(_ words: [Word], length: Int, options: DisfluencyOptions) -> [Word] {
        guard words.count >= length * 2 else { return words }
        var output: [Word] = []
        var index = 0
        while index < words.count {
            guard eligible(words, at: index, length: length, options: options),
                  matches(words, index, index + length, length) else {
                output.append(words[index])
                index += 1
                continue
            }
            var copies = 2
            while index + (copies + 1) * length <= words.count,
                  eligibleCopy(words, at: index + copies * length, length: length),
                  !words[index + copies * length - 1].sentenceEnd,
                  !words[index + copies * length - 1].pause,
                  matches(words, index, index + copies * length, length) {
                copies += 1
            }
            let threshold = length == 1 ? max(2, options.thresholds[words[index].key] ?? 2) : 2
            guard copies >= threshold else {
                output.append(words[index])
                index += 1
                continue
            }
            let kept = min(copies, max(1, options.keepCopies))
            output.append(contentsOf: words[index..<(index + kept * length)])
            let last = words[index + copies * length - 1]
            if !last.trail.isEmpty { output[output.count - 1].trail = last.trail }
            output[output.count - 1].pause = last.pause
            index += copies * length
        }
        return output
    }

    private static func eligible(_ words: [Word], at index: Int, length: Int,
                                 options: DisfluencyOptions) -> Bool {
        guard index + 2 * length <= words.count,
              eligibleCopy(words, at: index, length: length),
              eligibleCopy(words, at: index + length, length: length),
              !words[index + length - 1].sentenceEnd,
              !words[index + length - 1].pause else { return false }
        let gram = words[index..<(index + length)].map(\.key)
        guard !options.keepDoubles.contains((gram + gram).joined(separator: " ")),
              !gram.allSatisfy({ numbers.contains($0) }) else { return false }
        return true
    }

    private static func eligibleCopy(_ words: [Word], at index: Int, length: Int) -> Bool {
        guard index + length <= words.count, index == 0 || !words[index - 1].glue else { return false }
        return (index..<(index + length)).allSatisfy { position in
            let word = words[position]
            let inside = position < index + length - 1
            return !word.protected && !word.glue && !word.core.isEmpty
                && word.core.allSatisfy { $0.isLetter || $0 == "'" || $0 == "’" }
                && (!inside || (!word.sentenceEnd && !word.pause))
        }
    }

    private static func matches(_ words: [Word], _ first: Int, _ second: Int, _ length: Int) -> Bool {
        second + length <= words.count && (0..<length).allSatisfy {
            words[first + $0].key == words[second + $0].key
        }
    }
}
