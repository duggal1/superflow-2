import Foundation
import SuperflowKernel
import SuperflowPorts

/// Deterministic rule checker used to exercise the gate and the precision
/// report. It deliberately implements the same four categories the real Harper
/// adapter ships: spelling, agreement, repetition and a/an.
actor PatternGrammarChecker: GrammarChecker {
    private static let misspellings: [String: String] = [
        "teh": "the", "recieve": "receive", "seperate": "separate", "definately": "definitely",
        "occured": "occurred", "wich": "which", "becuase": "because", "thier": "their",
        "adn": "and", "waht": "what", "alot": "a lot", "dont": "don't", "cant": "can't",
        "wont": "won't", "im": "I'm", "ive": "I've", "doesnt": "doesn't", "didnt": "didn't",
        "isnt": "isn't", "wasnt": "wasn't", "couldnt": "couldn't", "wouldnt": "wouldn't",
        "shouldnt": "shouldn't", "thats": "that's", "youre": "you're", "theyre": "they're",
        "weve": "we've", "theres": "there's", "heres": "here's", "lets": "let's",
        "truely": "truly", "untill": "until", "wierd": "weird", "freind": "friend",
        "beleive": "believe", "acheive": "achieve", "begining": "beginning",
        "calender": "calendar", "comming": "coming", "enviroment": "environment",
        "excercise": "exercise", "familar": "familiar", "goverment": "government",
        "happend": "happened", "immediatly": "immediately", "knowlege": "knowledge",
        "libary": "library", "maintenence": "maintenance", "neccessary": "necessary",
        "occassion": "occasion", "posession": "possession", "priviledge": "privilege",
        "questionaire": "questionnaire", "reccomend": "recommend", "refered": "referred",
        "relevent": "relevant", "remeber": "remember", "rythm": "rhythm",
        "similiar": "similar", "succesful": "successful", "suprise": "surprise",
        "tommorow": "tomorrow", "writting": "writing", "yeild": "yield",
        "accomodate": "accommodate", "agressive": "aggressive", "apparant": "apparent",
        "basicly": "basically", "comittee": "committee", "concensus": "consensus",
        "dilemna": "dilemma", "embarass": "embarrass", "existance": "existence",
        "fourty": "forty", "garantee": "guarantee", "harrass": "harass",
        "independant": "independent", "liason": "liaison", "millenium": "millennium",
        "noticable": "noticeable", "occurence": "occurrence", "persistant": "persistent",
        "publically": "publicly", "recieved": "received",
        "supercede": "supersede", "tommorrow": "tomorrow", "wether": "whether",
    ]

    private static let agreements: [String: String] = [
        "they is": "they are", "we is": "we are", "you is": "you are", "i is": "I am",
        "i are": "I am", "he are": "he is", "she are": "she is", "it are": "it is",
        "he have": "he has", "she have": "she has", "it have": "it has",
        "they has": "they have", "we has": "we have", "you has": "you have",
        "he were": "he was", "she were": "she was", "it were": "it was",
        "they was": "they were", "we was": "we were", "you was": "you were",
        "there is many": "there are many", "there was many": "there were many",
        "there is several": "there are several", "he don't": "he doesn't",
        "she don't": "she doesn't", "it don't": "it doesn't", "they doesn't": "they don't",
        "we doesn't": "we don't", "you doesn't": "you don't",
    ]

    private static let vowelExceptions: Set<String> = [
        "hour", "honest", "honor", "honour", "heir", "herb",
        "mri", "faq", "html", "api", "sql", "nft", "r&d", "fbi", "xml",
    ]
    private static let consonantExceptions: Set<String> = [
        "university", "unique", "unit", "union", "universal", "universe", "unify",
        "uniform", "unicycle", "use", "user", "used", "useful", "usual", "usually",
        "utility", "utensil", "euro", "europe", "european", "one", "once",
        "ubiquitous", "ukulele",
    ]

    private struct Raw {
        var location: Int
        var length: Int
        var kind: String
        var suggestion: String
    }

    func lint(_ text: String, customWords: [String]) async -> [GrammarLint] {
        let custom = Set(customWords.map { $0.lowercased() })
        var raw: [Raw] = []
        raw.append(contentsOf: spellingLints(text, custom: custom))
        raw.append(contentsOf: repetitionLints(text))
        raw.append(contentsOf: articleLints(text))
        raw.append(contentsOf: agreementLints(text))
        raw.sort { lhs, rhs in
            lhs.location == rhs.location ? lhs.length > rhs.length : lhs.location < rhs.location
        }
        var out: [GrammarLint] = []
        var end = -1
        for lint in raw where lint.location >= end {
            out.append(GrammarLint(utf16Start: lint.location, utf16Length: lint.length,
                                   kind: lint.kind, suggestion: lint.suggestion))
            end = lint.location + lint.length
        }
        return out
    }

    private func spellingLints(_ text: String, custom: Set<String>) -> [Raw] {
        let ns = text as NSString
        var out: [Raw] = []
        for (wrong, right) in Self.misspellings {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: wrong))\\b"
            guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if custom.contains(wrong) { continue }
                out.append(Raw(location: match.range.location, length: match.range.length,
                               kind: "Spelling", suggestion: matchCase(right, as: ns.substring(with: match.range))))
            }
        }
        return out
    }

    private func repetitionLints(_ text: String) -> [Raw] {
        let ns = text as NSString
        guard let rx = try? NSRegularExpression(pattern: "\\b([A-Za-z']+)(\\s+)\\1\\b",
                                                options: [.caseInsensitive]) else { return [] }
        return rx.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            let word = ns.substring(with: match.range(at: 1))
            return Raw(location: match.range.location, length: match.range.length,
                       kind: "Repetition", suggestion: word)
        }
    }

    private func articleLints(_ text: String) -> [Raw] {
        let ns = text as NSString
        guard let rx = try? NSRegularExpression(pattern: "\\b([Aa]n?)\\s+([A-Za-z][A-Za-z'’-]*)",
                                                options: []) else { return [] }
        var out: [Raw] = []
        for match in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let article = ns.substring(with: match.range(at: 1))
            let next = ns.substring(with: match.range(at: 2)).lowercased()
            guard !next.isEmpty else { continue }
            let expected = Self.expectedArticle(next)
            guard expected != article.lowercased() else { continue }
            let suggestion = article.first?.isUppercase == true
                ? expected.prefix(1).uppercased() + expected.dropFirst()
                : expected
            out.append(Raw(location: match.range(at: 1).location, length: match.range(at: 1).length,
                           kind: "aOrAn", suggestion: suggestion))
        }
        return out
    }

    private func agreementLints(_ text: String) -> [Raw] {
        let ns = text as NSString
        var out: [Raw] = []
        for (wrong, right) in Self.agreements {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: wrong))\\b"
            guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let original = ns.substring(with: match.range)
                out.append(Raw(location: match.range.location, length: match.range.length,
                               kind: "Agreement", suggestion: matchCase(right, as: original)))
            }
        }
        return out
    }

    private static func expectedArticle(_ word: String) -> String {
        let head = word.split(separator: "-").first.map(String.init) ?? word
        if vowelExceptions.contains(head) { return "an" }
        if consonantExceptions.contains(head) { return "a" }
        guard let first = head.first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }

    private func matchCase(_ replacement: String, as original: String) -> String {
        guard original.first?.isUppercase == true, let first = replacement.first else { return replacement }
        return first.uppercased() + replacement.dropFirst()
    }
}

/// Checker whose agreement suggestions are only right half the time, used to
/// prove that a category below 98 percent precision ships disabled.
actor NoisyAgreementChecker: GrammarChecker {
    func lint(_ text: String, customWords: [String]) async -> [GrammarLint] {
        let ns = text as NSString
        var out: [GrammarLint] = []
        for (index, word) in ["they is", "we is"].enumerated() {
            let range = ns.range(of: word)
            guard range.location != NSNotFound else { continue }
            out.append(GrammarLint(utf16Start: range.location, utf16Length: range.length,
                                   kind: "Agreement",
                                   suggestion: index.isMultiple(of: 2) ? "they are" : "totally wrong"))
        }
        return out
    }
}
