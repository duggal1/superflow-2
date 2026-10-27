import SuperflowKernel
import SuperflowPorts

/// Spoken numbers, currency, percentages, years and date ordinals -> written form.
/// Deterministic, idempotent, and forbidden from touching protected spans.
///
/// The stage walks the tokenizer's tokens with a cursor over the original line,
/// so whitespace outside a rewritten span is preserved byte for byte.
public struct NumbersStage: TextStage {
    public let id: String
    public init(id: String = "numbers") { self.id = id }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var output = draft
        output.text = Self.transform(draft.text, protected: draft.protected, settings: context.settings)
        return output
    }

    public static func transform(_ text: String, protected: Protected,
                                 settings: AppSettings) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { transformLine(String($0), protected: protected, settings: settings) }
            .joined(separator: "\n")
    }

    private struct AtomIndex {
        let atoms: [Atom]
        let firstAtomOfToken: [Int]
    }

    private static func atomIndex(_ tokens: [Token]) -> AtomIndex {
        var atoms: [Atom] = []
        var first = [Int](repeating: 0, count: tokens.count)
        for (ti, token) in tokens.enumerated() {
            first[ti] = atoms.count
            let core = token.core.lowercased()
            let parts = core.contains("-") ? core.split(separator: "-").map(String.init) : [core]
            for (pi, part) in parts.enumerated() {
                atoms.append(Atom(word: part, token: ti,
                                  endsPhrase: pi == parts.count - 1 && !token.trail.isEmpty))
            }
        }
        return AtomIndex(atoms: atoms, firstAtomOfToken: first)
    }

    private static func transformLine(_ line: String, protected: Protected,
                                      settings: AppSettings) -> String {
        let tokens = Tokenizer.tokens(in: line)
        guard !tokens.isEmpty else { return line }
        let ranges = protected.ranges(in: line, detect: true)
        let explicitRanges = protected.ranges(in: line, detect: false)
        let index = atomIndex(tokens)
        let atoms = index.atoms
        let protectedFlags = tokens.map { token in
            ranges.contains { $0.overlaps(token.range) }
        }
        let explicitFlags = tokens.map { token in
            explicitRanges.contains { $0.overlaps(token.range) }
        }

        func isProtected(_ from: Int, _ to: Int) -> Bool {
            guard from >= 0, from <= to, to < protectedFlags.count else { return true }
            return (from...to).contains { protectedFlags[$0] }
        }

        var result = ""
        var cursor = line.startIndex
        var ti = 0
        while ti < tokens.count {
            let token = tokens[ti]
            result += line[cursor..<token.range.lowerBound]
            if token.core.contains(where: { $0.isNumber }) {
                if !explicitFlags[ti], let grouped = groupedDigits(token, tokens: tokens, at: ti) {
                    result += grouped
                } else {
                    result += token.full
                }
                cursor = token.range.upperBound
                ti += 1
                continue
            }
            if protectedFlags[ti] || token.core.isEmpty {
                result += token.full
                cursor = token.range.upperBound
                ti += 1
                continue
            }
            let ai = index.firstAtomOfToken[ti]
            guard ai < atoms.count else {
                result += token.full
                cursor = token.range.upperBound
                ti += 1
                continue
            }

            if let year = NumberParser.parseYear(atoms, from: ai) {
                let lastToken = year.lastToken
                let next = lastToken + 1 < tokens.count ? tokens[lastToken + 1].core.lowercased() : ""
                if !isProtected(ti, lastToken), !isAmount(next) {
                    result += token.lead + String(year.year) + tokens[lastToken].trail
                    cursor = tokens[lastToken].range.upperBound
                    ti = lastToken + 1
                    continue
                }
            }

            if let ord = NumberParser.ordinal(atoms, from: ai), !isProtected(ti, ord.lastToken),
               isOrdinalContext(tokens, at: ti, lastToken: ord.lastToken) {
                result += token.lead + "\(ord.value)\(NumberTables.ordinalSuffix(ord.value))"
                    + tokens[ord.lastToken].trail
                cursor = tokens[ord.lastToken].range.upperBound
                ti = ord.lastToken + 1
                continue
            }

            guard let phrase = NumberParser.parse(atoms, from: ai) else {
                result += token.full
                cursor = token.range.upperBound
                ti += 1
                continue
            }
            let lastToken = phrase.lastToken
            guard !isProtected(ti, lastToken) else {
                result += token.full
                cursor = token.range.upperBound
                ti += 1
                continue
            }

            var consumedTo = lastToken
            var currency: CurrencySpec?
            var percent = false
            var hasUnit = false
            var trailing = tokens[lastToken].trail
            if !phrase.endsWithPunctuation, lastToken + 1 < tokens.count {
                let next = tokens[lastToken + 1]
                let word = next.core.lowercased()
                if let spec = NumberTables.currencies[word] {
                    currency = spec
                    consumedTo = lastToken + 1
                    trailing = next.trail
                } else if word == "percent" {
                    percent = true
                    consumedTo = lastToken + 1
                    trailing = next.trail
                } else if word == "per", lastToken + 2 < tokens.count,
                          tokens[lastToken + 2].core.lowercased() == "cent" {
                    percent = true
                    consumedTo = lastToken + 2
                    trailing = tokens[lastToken + 2].trail
                } else if NumberTables.measures.contains(word) {
                    hasUnit = true
                }
            }
            if consumedTo > lastToken, isProtected(consumedTo, consumedTo) {
                result += token.full
                cursor = token.range.upperBound
                ti += 1
                continue
            }

            let small = phrase.decimals == nil && phrase.abbreviation == nil
                && (0...9).contains(phrase.value)
            if small && currency == nil && !percent && !hasUnit && settings.spellOutSmallNumbers {
                result += token.full
                cursor = token.range.upperBound
                ti += 1
                continue
            }

            let grouping = currency?.grouping ?? .western
            let body: String
            if let decimals = phrase.decimals {
                body = NumberTables.group(phrase.value, grouping: grouping) + "." + decimals
            } else if let abbreviation = phrase.abbreviation, settings.numberStyle == .abbreviated {
                body = abbreviation
            } else if currency == nil, !percent, !hasUnit,
                      phrase.value >= 1_900, phrase.value <= 2_099 {
                // "two thousand twenty six" is a year, not a quantity.
                body = String(phrase.value)
            } else {
                body = NumberTables.group(phrase.value, grouping: grouping)
            }
            let symbol = currency?.symbol ?? ""
            result += token.lead + symbol + body + (percent ? "%" : "") + trailing
            cursor = tokens[consumedTo].range.upperBound
            ti = consumedTo + 1
        }
        result += line[cursor...]
        return result
    }

    private static func isAmount(_ word: String) -> Bool {
        NumberTables.scales[word] != nil || word == "hundred"
            || NumberTables.currencies[word] != nil || word == "percent"
    }

    private static func isOrdinalContext(_ tokens: [Token], at first: Int, lastToken: Int) -> Bool {
        let previous = first > 0 ? tokens[first - 1].core.lowercased() : ""
        let nextIndex = lastToken + 1
        let next = nextIndex < tokens.count ? tokens[nextIndex].core.lowercased() : ""
        if NumberTables.ordinalFollowers.contains(previous) || NumberTables.ordinalFollowers.contains(next) {
            return true
        }
        if next == "of", nextIndex + 1 < tokens.count,
           NumberTables.ordinalFollowers.contains(tokens[nextIndex + 1].core.lowercased()) {
            return true
        }
        return false
    }

    /// Long bare digit strings from ASR get thousands separators, except phone
    /// numbers, IDs, zip codes, version numbers and years. The keyword check is
    /// contextual because the ASR has already removed the punctuation that
    /// would otherwise make the token unambiguous.
    private static func groupedDigits(_ token: Token, tokens: [Token], at index: Int) -> String? {
        let core = token.core
        guard core.count >= 5, core.count <= 15,
              core.allSatisfy({ $0.isASCII && $0.isNumber }),
              !core.hasPrefix("0"), let value = Int64(core) else { return nil }
        if token.lead.contains("+") { return nil }
        let previous = index > 0 ? tokens[index - 1].core.lowercased() : ""
        if NumberTables.skipSeparatorAfter.contains(previous) { return nil }
        if core.count >= 10, core.hasPrefix("1") { return nil }
        return token.lead + NumberTables.group(value) + token.trail
    }
}
