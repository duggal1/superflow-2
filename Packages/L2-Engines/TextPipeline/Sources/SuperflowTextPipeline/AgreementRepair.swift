import Foundation
import NaturalLanguage
import SuperflowKernel

enum AgreementRepair {
    private static let pronoun = try? NSRegularExpression(
        pattern: #"(?i)\b(we|they|you)[ \t]+(was)\b"#)
    private static let noun = try? NSRegularExpression(
        pattern: #"\b(?:[Tt]he|[Tt]hese|[Tt]hose)[ \t]+(\p{Ll}+)(?:[ \t]+(?:in|at|near)[ \t]+\p{Lu}\p{L}*)?[ \t]+(is|was|don['’]t)(?![\p{L}\p{N}_])"#)

    private static let missingArticle = try? NSRegularExpression(
        pattern: #"(?i)\b(?:when|if|after|before)[ \t]+(user|customer)(?=[ \t]+(?:clicks|enters|selects|submits|signs|opens|chooses)\b)"#)

    static func apply(_ text: String, protected: Protected, checkNouns: Bool) -> String {
        guard !text.contains("```"), !text.contains("~~~"), !text.contains("\""),
              !text.contains("“"), !text.localizedCaseInsensitiveContains("unquote") else { return text }
        guard text.contains("was") || text.contains(" is") || text.contains("don't")
                || text.contains("don’t") || (checkNouns && (text.contains(" user ") || text.contains(" customer ")))
        else { return text }
        let span = NSRange(text.startIndex..., in: text)
        let reserved = protected.ranges(in: text)
        var edits: [(Range<String.Index>, String)] = []
        for match in pronoun?.matches(in: text, range: span) ?? [] {
            guard let range = Range(match.range(at: 2), in: text),
                  let subject = Range(match.range(at: 1), in: text),
                  !reserved.contains(where: { $0.overlaps(range) || $0.overlaps(subject) }) else { continue }
            let isHypothetical = text[..<subject.lowerBound].split(whereSeparator: \.isWhitespace).last
                .map { ["if", "wish", "suppose"].contains($0.lowercased()) } ?? false
            if !isHypothetical { edits.append((range, "were")) }
        }
        if checkNouns, let matches = noun?.matches(in: text, range: span), !matches.isEmpty {
            let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
            for match in matches {
                guard let subject = Range(match.range(at: 1), in: text),
                      let verb = Range(match.range(at: 2), in: text),
                      !reserved.contains(where: { $0.overlaps(subject) || $0.overlaps(verb) }) else { continue }
                let phrase = "the " + text[subject]
                let nounStart = phrase.index(phrase.startIndex, offsetBy: 4)
                tagger.string = phrase
                tagger.setLanguage(.english, range: phrase.startIndex..<phrase.endIndex)
                guard tagger.tag(at: nounStart, unit: .word, scheme: .lexicalClass).0 == .noun,
                      let lemma = tagger.tag(at: nounStart, unit: .word, scheme: .lemma).0?.rawValue
                else { continue }
                let plural = text[subject].hasSuffix("s") && text[subject] != lemma
                switch text[verb] {
                case "is" where plural: edits.append((verb, "are"))
                case "was" where plural: edits.append((verb, "were"))
                case "don't", "don’t":
                    if !plural, !text[subject].hasSuffix("s"), text[subject] == lemma {
                        edits.append((verb, text[verb].contains("’") ? "doesn’t" : "doesn't"))
                    }
                default: break
                }
            }
        }
        if checkNouns {
            for match in missingArticle?.matches(in: text, range: span) ?? [] {
                guard let subject = Range(match.range(at: 1), in: text), text[subject].first?.isLowercase == true,
                      !reserved.contains(where: { $0.overlaps(subject) }) else { continue }
                edits.append((subject, "the " + text[subject]))
            }
        }
        var result = text
        for (range, replacement) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
