import Foundation
import NaturalLanguage

/// Checks meaning carriers without requiring identical surface grammar.
enum MeaningCarriers {
    private static let negators: Set<String> = ["not", "no", "never", "none", "nothing", "nobody", "neither", "nor", "cannot", "without"]
    private static let quantifiers: Set<String> = ["always", "only", "all", "every", "any", "more", "less", "fewer", "most", "least", "before", "after"]
    private static let stop: Set<String> = Set("a an the and or but so if then than that this these those of to in on at for with by from as is are was were be been being am i me my we our you your he she it its they them their do does did have has had just like really very actually basically well okay ok oh yeah um uh there here what when where how why which who will would can could should also too now mean wait make 't n't ca".split(separator: " ").map(String.init))
    /// S1-mini normalizes apostrophes per its Styling axis ("dont" -> "don't").
    /// Without this, the same negation is counted twice in the raw transcript
    /// and once in the cleaned one, and valid cleanup falls back to raw text.
    private static let contractions: [String: String] = [
        "dont": "don't", "cant": "can't", "wont": "won't", "isnt": "isn't",
        "arent": "aren't", "wasnt": "wasn't", "werent": "weren't", "didnt": "didn't",
        "doesnt": "doesn't", "shouldnt": "shouldn't", "couldnt": "couldn't",
        "wouldnt": "wouldn't", "havent": "haven't", "hasnt": "hasn't", "hadnt": "hadn't",
    ]
    private static let revisionCues: Set<String> = ["sorry", "wait", "actually", "mean", "nope"]
    private static let numberWords: Set<String> = [
        "zero", "oh", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
        "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million", "billion",
    ]
    private static let calendarWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december", "tomorrow", "today",
    ]

    static func hasRevisionCue(_ text: String) -> Bool {
        let tokens = words(text)
        if tokens.contains(where: { revisionCues.contains($0) }) { return true }
        for (index, word) in tokens.enumerated() where word == "no" {
            guard index + 1 < tokens.count else { continue }
            if calendarWords.contains(tokens[index + 1]) { return true }
        }
        // A transcript ending in a spoken number is about to be rendered as
        // digits ("three thirty" -> "3:30"), which changes lemma heads.
        if let last = tokens.last, numberWords.contains(last) { return true }
        // Spoken magnitudes and email/domain words are rendered as compact
        // values ("twenty three thousand" -> "$23,000", "dot com" -> ".com").
        if tokens.contains(where: { ["dollars", "dot"].contains($0) }) { return true }
        return tokens.contains("make") && tokens.contains("that")
    }

    static func accepts(_ input: String, _ output: String, allowsRevision: Bool = false) -> Bool {
        let source = words(input), target = words(output)
        guard count(source, matching: { negators.contains($0) || $0.hasSuffix("n't") }) ==
                count(target, matching: { negators.contains($0) || $0.hasSuffix("n't") }),
              quantifierCounts(source) == quantifierCounts(target) else { return false }
        if !allowsRevision {
            for magnitude in ["hundred", "thousand", "million", "billion", "trillion"] {
                if source.filter({ $0 == magnitude }).count != target.filter({ $0 == magnitude }).count { return false }
            }
        }
        var sentenceStart = true
        let rawWords = input.split(whereSeparator: \.isWhitespace).map(String.init)
        let outputWords = Set(output.split(whereSeparator: \.isWhitespace)
            .map { String($0.trimmingCharacters(in: .punctuationCharacters)).lowercased() })
        let wordsForRevision = words(input)
        for (index, raw) in rawWords.enumerated() {
            let word = raw.trimmingCharacters(in: .punctuationCharacters)
            let lowered = word.lowercased()
            // A revised-away value ("Friday actually no wait Thursday") is meant
            // to disappear; only an unrelated dropped proper noun is a defect.
            let revisedAway = allowsRevision && calendarWords.contains(lowered)
                && Self.valuePrecedesRevisionCue(wordsForRevision, index)
            // Single-letter tokens ("P 95" -> "P95") are formatting, not a
            // capitalized entity that could have been dropped.
            if word.count > 1, !sentenceStart, word.first?.isUppercase == true,
               word != "I", !word.hasPrefix("I'"), !word.hasPrefix("I’"),
               !outputWords.contains(lowered), !revisedAway { return false }
            sentenceStart = raw.last.map { ".?!…".contains($0) } ?? false
        }
        if source == target { return true }
        let before = lemmas(input), after = lemmas(output)
        // An explicit correction legitimately replaces the abandoned value and
        // its magnitude word with the value the speaker landed on.
        // Longer dictation legitimately gains and loses more lemma heads as
        // S1-mini normalizes grammar; hard checks above (negation, quantifiers,
        // magnitudes) still guard meaning.
        let allowance = allowsRevision ? max(1, before.count) : max(1, before.count / 6)
        let newWordAllowance = max(1, after.count / 6)
        return before.subtracting(after).count <= allowance
            && after.subtracting(before).count <= newWordAllowance
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { token in contractions[String(token)] ?? String(token) }
    }
    private static func count(_ words: [String], matching predicate: (String) -> Bool) -> Int {
        var previous: String?
        var count = 0
        for (index, word) in words.enumerated() {
            // "no wait / no sorry / no actually" revises a value; it is not a
            // negation of the clause that follows.
            let followsCue = index > 0 && revisionCues.contains(words[index - 1])
            let revisesValue = index + 1 < words.count
                && (revisionCues.contains(words[index + 1]) || calendarWords.contains(words[index + 1]))
            let discourseNo = word == "no" && index + 1 < words.count
                && (negators.contains(words[index + 1]) || words[index + 1].hasSuffix("n't"))
            // A false-start double negator ("don't not want") is one semantic
            // negation spoken twice, not two. The cleanup model keeps the first.
            let stutterNegator = (word == "not" || word == "no")
                && index > 0 && words[index - 1].hasSuffix("n't")
            // A negator inside an abandoned value that a revision cue replaces
            // ("returning a 403 not a 500 wait no 429") is not a clause negation:
            // a revision cue within a few words, followed by a concrete value,
            // means this negator is about to be discarded along with the value.
            let abandonedValueNegator = (negators.contains(word) || word.hasSuffix("n't"))
                && Self.negatorPrecedesRevisedValue(words, index)
            if word == "no", followsCue || revisesValue || discourseNo { previous = nil; continue }
            if stutterNegator || abandonedValueNegator { previous = nil; continue }
            if predicate(word) { if previous != word { count += 1 }; previous = word }
            else { previous = nil }
        }
        return count
    }
    /// True when a concrete value is followed shortly by a revision cue, i.e.
    /// the value the speaker abandoned ("Friday actually no wait Thursday").
    private static func valuePrecedesRevisionCue(_ words: [String], _ index: Int) -> Bool {
        let upper = min(5, words.count - index - 1)
        guard upper >= 1 else { return false }
        for offset in 1...upper where revisionCues.contains(words[index + offset]) {
            return true
        }
        return false
    }

    /// True when a negator sits in an abandoned value that a nearby revision
    /// cue replaces with a concrete number or date ("a 403 not a 500 wait no
    /// 429"). Bounded to six words so an ordinary negation later in the clause
    /// is never mistaken for a false start.
    private static func negatorPrecedesRevisedValue(_ words: [String], _ index: Int) -> Bool {
        let upper = min(6, words.count - index - 1)
        guard upper >= 1 else { return false }
        for offset in 1...upper {
            guard revisionCues.contains(words[index + offset]) else { continue }
            let afterUpper = min(index + offset + 5, words.count)
            guard afterUpper > index + offset + 1 else { continue }
            for after in (index + offset + 1)..<afterUpper {
                if numberWords.contains(words[after]) || calendarWords.contains(words[after])
                    || words[after].contains(where: \.isNumber) {
                    return true
                }
            }
        }
        return false
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
