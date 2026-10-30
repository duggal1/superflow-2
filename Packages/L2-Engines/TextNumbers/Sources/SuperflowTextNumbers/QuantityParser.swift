import Foundation
import SuperflowKernel

extension Word {
    var isConvertible: Bool { !isProtected && !core.isEmpty }
}

struct ParsedQuantity {
    var value: Decimal
    var consumed: Int
    var largestScale: UInt64? = nil
    var isOrdinal = false
    var hasFraction = false
    var impliedOne = false
    var literalCurrency: String? = nil
}

enum QuantityParser {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func parse(_ words: [Word], at start: Int) -> ParsedQuantity? {
        let w = words[start]
        if w.key == "half" { return half(words, at: start) }
        if let (value, symbol) = literal(w) { return literalQuantity(words, at: start, value: value, symbol: symbol) }
        return spoken(words, at: start)
    }

    static func decimal(_ s: String) -> Decimal? {
        guard let f = s.first, f.isASCII, f.isNumber else { return nil }
        let halves = s.split(separator: ".", omittingEmptySubsequences: false)
        guard halves.count <= 2, halves.allSatisfy({ !$0.isEmpty }),
              !(halves.count == 2 && halves[1].contains(",")) else { return nil }
        let groups = halves[0].split(separator: ",", omittingEmptySubsequences: false)
        if groups.count > 1 {
            guard groups[0].count <= 3, groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        let cleaned = s.replacingOccurrences(of: ",", with: "")
        guard cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        return Decimal(string: cleaned, locale: posix)
    }

    private static func literal(_ w: Word) -> (Decimal, String?)? {
        guard w.isConvertible, let value = decimal(w.core) else { return nil }
        let symbol = w.lead.first.flatMap {
            w.lead.count == 1 && NumberLexicon.currencySymbols.contains($0) ? w.lead : nil
        }
        return (value, symbol)
    }

    private static func literalQuantity(_ words: [Word], at start: Int, value: Decimal, symbol: String?) -> ParsedQuantity? {
        guard words[start].trail.isEmpty, start + 1 < words.count else { return nil }
        let next = words[start + 1]
        guard next.isConvertible, next.lead.isEmpty else { return nil }
        if let s = NumberLexicon.scales[next.key] {
            return ParsedQuantity(value: value * Decimal(s), consumed: 2, largestScale: s, literalCurrency: symbol)
        }
        if symbol == nil, next.key == "percent" || NumberLexicon.currencies[next.key] != nil {
            return ParsedQuantity(value: value, consumed: 1)
        }
        return nil
    }

    private static func compact(_ w: Word) -> (Decimal, UInt64)? {
        guard let last = w.core.last?.lowercased().first,
              let s = NumberLexicon.compactSuffixes[last],
              let v = decimal(String(w.core.dropLast())) else { return nil }
        return (v * Decimal(s), s)
    }

    private static func half(_ words: [Word], at start: Int) -> ParsedQuantity? {
        guard words[start].trail.isEmpty else { return nil }
        var j = start + 1
        if j < words.count, words[j].key == "a" || words[j].key == "an", words[j].trail.isEmpty { j += 1 }
        guard j < words.count, words[j].isConvertible, words[j].lead.isEmpty else { return nil }
        let consumed = j + 1 - start
        if let s = NumberLexicon.scales[words[j].key] {
            return ParsedQuantity(value: Decimal(s) / 2, consumed: consumed, largestScale: s)
        }
        if let (v, s) = compact(words[j]) {
            return ParsedQuantity(value: v / 2, consumed: consumed, largestScale: s)
        }
        return nil
    }

    private static func startsNumber(_ w: Word) -> Bool {
        w.isConvertible && w.lead.isEmpty
            && (NumberLexicon.units[w.key] != nil || NumberLexicon.tens[w.key] != nil)
    }

    private static func spoken(_ words: [Word], at start: Int) -> ParsedQuantity? {
        let n = words.count
        var i = start
        var total = Decimal(0)
        var group = 0
        var lastScale = UInt64.max
        var largest: UInt64? = nil
        var implied = false, ordinal = false, sawZero = false
        var afterBoundary = false
        var consumedNumber = false
        var danglingAnd = false

        if words[start].key == "a" || words[start].key == "an" {
            guard start + 1 < n, words[start].trail.isEmpty,
                  words[start + 1].isConvertible, words[start + 1].lead.isEmpty,
                  words[start + 1].key == "hundred" || NumberLexicon.scales[words[start + 1].key] != nil
            else { return nil }
            group = 1; implied = true; i = start + 1
        }

        loop: while i < n {
            let w = words[i]
            guard w.isConvertible, i == start || w.lead.isEmpty else { break }
            let k = w.key
            var terminal = !w.trail.isEmpty
            danglingAnd = false
            if sawZero && k != "point" { break }

            if k == "point" {
                guard consumedNumber, !ordinal, total == 0, w.trail.isEmpty else { break loop }
                var j = i + 1
                var digits = ""
                while j < n, words[j].isConvertible, words[j].lead.isEmpty,
                      let d = NumberLexicon.units[words[j].key], d < 10, digits.count < 12 {
                    digits.append(String(d)); j += 1
                    if !words[j - 1].trail.isEmpty { break }
                }
                guard !digits.isEmpty, let frac = Decimal(string: "0." + digits, locale: posix) else { break loop }
                var value = Decimal(group) + frac
                var consumed = j - start
                var scale: UInt64? = nil
                if words[j - 1].trail.isEmpty, j < n, words[j].isConvertible, words[j].lead.isEmpty,
                   let s = NumberLexicon.scales[words[j].key] {
                    value *= Decimal(s); scale = s; consumed += 1
                }
                return ParsedQuantity(value: value, consumed: consumed, largestScale: scale,
                                      hasFraction: true, impliedOne: implied)
            } else if let v = NumberLexicon.units[k] {
                if v == 0 {
                    guard i == start else { break loop }
                    sawZero = true
                } else {
                    let place = group % 100
                    guard place == 0 || (v < 10 && place >= 20 && place % 10 == 0) else { break loop }
                    group += v
                }
                afterBoundary = false
            } else if let v = NumberLexicon.ordinalUnits[k] {
                let place = group % 100
                guard place == 0 || (v < 10 && place >= 20 && place % 10 == 0) else { break loop }
                group += v; ordinal = true; terminal = true; afterBoundary = false
            } else if let v = NumberLexicon.tens[k] {
                guard group % 100 == 0 else { break loop }
                group += v; afterBoundary = false
            } else if let v = NumberLexicon.ordinalTens[k] {
                guard group % 100 == 0 else { break loop }
                group += v; ordinal = true; terminal = true; afterBoundary = false
            } else if k == "hundred" || k == "hundredth" {
                guard group > 0, group < 100 else { break loop }
                group *= 100; afterBoundary = true
                if k == "hundredth" { ordinal = true; terminal = true }
            } else if let s = NumberLexicon.scales[k] {
                guard group > 0, s < lastScale else { break loop }
                total += Decimal(group) * Decimal(s)
                group = 0; lastScale = s; largest = max(largest ?? 0, s); afterBoundary = true
            } else if k == "and" {
                guard afterBoundary, !terminal, i + 1 < n, startsNumber(words[i + 1]) else { break loop }
                danglingAnd = true
            } else {
                break loop
            }
            if k != "and" { consumedNumber = true }
            i += 1
            if terminal { break }
        }

        guard consumedNumber else { return nil }
        if danglingAnd { i -= 1 }
        return ParsedQuantity(value: total + Decimal(group), consumed: i - start,
                              largestScale: largest, isOrdinal: ordinal, impliedOne: implied)
    }
}
