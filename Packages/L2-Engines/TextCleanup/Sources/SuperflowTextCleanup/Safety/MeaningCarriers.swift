import Foundation
import NaturalLanguage

/// Checks meaning carriers without requiring identical surface grammar.
enum MeaningCarriers {
    private static let negators: Set<String> = ["not", "no", "never", "none", "nothing", "nobody", "neither", "nor", "cannot", "without"]
    private static let quantifiers: Set<String> = ["always", "only", "all", "every", "any", "more", "less", "fewer", "most", "least", "before", "after"]
    private static let stop: Set<String> = Set("a an the and or but so if then than that this these those of to in on at for with by from as is are was were be been being am i me my we our you your he she it its they them their do does did have has had just like really very actually basically well okay ok oh yeah um uh there here what when where how why which who will would can could should also too now mean wait make 't n't ca".split(separator: " ").map(String.init))

    static func accepts(_ input: String, _ output: String) -> Bool {
        let source = words(input), target = words(output)
        guard count(source, matching: { negators.contains($0) || $0.hasSuffix("n't") }) ==
                count(target, matching: { negators.contains($0) || $0.hasSuffix("n't") }),
              quantifierCounts(source) == quantifierCounts(target) else { return false }
        for magnitude in ["hundred", "thousand", "million", "billion", "trillion"] {
            if source.filter({ $0 == magnitude }).count != target.filter({ $0 == magnitude }).count { return false }
        }
        var sentenceStart = true
        let outputWords = Set(output.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: .punctuationCharacters) })
        for raw in input.split(whereSeparator: \.isWhitespace) {
            let word = raw.trimmingCharacters(in: .punctuationCharacters)
            if !sentenceStart, word.first?.isUppercase == true, word != "I", !word.hasPrefix("I'"), !word.hasPrefix("I’"), !outputWords.contains(word) { return false }
            sentenceStart = raw.last.map { ".?!…".contains($0) } ?? false
        }
        if source == target { return true }
        let before = lemmas(input), after = lemmas(output)
        return before.subtracting(after).count <= max(1, before.count / 12)
            && after.subtracting(before).count <= (after.count <= 25 ? 0 : 1)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }
    private static func count(_ words: [String], matching predicate: (String) -> Bool) -> Int {
        var previous: String?
        var count = 0
        for (index, word) in words.enumerated() {
            if word == "no", index + 1 < words.count, words[index + 1] == "wait" { previous = nil; continue }
            if predicate(word) { if previous != word { count += 1 }; previous = word }
            else { previous = nil }
        }
        return count
    }
    private static func quantifierCounts(_ words: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        var previous: String?
        for word in words {
            let key = word == "fewer" ? "less" : word
            if quantifiers.contains(word) {
                if key != previous { result[key, default: 0] += 1 }
                previous = key
            } else { previous = nil }
        }
        return result
    }
    private static func lemmas(_ text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        var result: Set<String> = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let surface = text[range].lowercased()
            let rawLemma = (tag?.rawValue ?? surface).lowercased()
            let lemma = ["seen": "see", "saw": "see", "saved": "save" ][rawLemma] ?? rawLemma
            if !stop.contains(surface), !stop.contains(lemma), !negators.contains(surface),
               !quantifiers.contains(surface), !surface.hasSuffix("n't"), !surface.contains(where: \.isNumber), lemma.count > 1 {
                result.insert(lemma)
            }
            return true
        }
        return result
    }
}
