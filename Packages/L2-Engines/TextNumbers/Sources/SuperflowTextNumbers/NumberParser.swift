struct Atom {
    let word: String
    let token: Int
    let endsPhrase: Bool
}

struct NumberPhrase {
    let value: Int64
    var decimals: String?
    var abbreviation: String?
    let lastToken: Int
    let lastAtom: Int
    let endsWithPunctuation: Bool
}

enum NumberParser {
    private enum Kind { case none, unit, teen, tens, hundred, scale }

    /// Parses a contiguous run of number words starting at atom `start`. Returns nil when the run
    /// is not a valid number (e.g. "one one", "hundred", "twenty ten").
    static func parse(_ atoms: [Atom], from start: Int) -> NumberPhrase? {
        var j = start
        var total: Int64 = 0
        var current: Int64 = 0
        var kind: Kind = .none
        var scaleCount = 0
        var lastScale = Int64.max
        var firstScaleWord: String?
        var decimals: String?
        var endsWithPunctuation = false

        guard start < atoms.count else { return nil }

        if ["a", "an"].contains(atoms[j].word), j + 1 < atoms.count,
           ["hundred", "thousand", "million", "billion", "lakh", "crore"].contains(atoms[j + 1].word) {
            current = 1
            kind = .unit
            j += 1
        }

        loop: while j < atoms.count {
            let word = atoms[j].word
            var consumed = true

            if let unit = NumberTables.units[word] {
                switch kind {
                case .none, .hundred, .scale:
                    current += unit
                    kind = unit >= 10 ? .teen : .unit
                case .tens:
                    guard (1...9).contains(unit) else { break loop }
                    current += unit
                    kind = .unit
                case .unit, .teen:
                    break loop
                }
            } else if let ten = NumberTables.tens[word] {
                guard kind == .none || kind == .hundred || kind == .scale else { break loop }
                current += ten
                kind = .tens
            } else if word == "hundred" {
                guard kind == .unit || kind == .teen, current > 0 else { break loop }
                current *= 100
                kind = .hundred
            } else if let scale = NumberTables.scales[word] {
                guard kind == .unit || kind == .teen || kind == .tens || kind == .hundred, scale < lastScale else { break loop }
                if scaleCount == 0 {
                    firstScaleWord = word
                }
                total += current * scale
                current = 0
                kind = .scale
                lastScale = scale
                scaleCount += 1
            } else if word == "and" {
                guard kind == .hundred || kind == .scale, j + 1 < atoms.count else { break loop }
                let next = atoms[j + 1].word
                guard NumberTables.units[next] != nil || NumberTables.tens[next] != nil else { break loop }
                j += 1
                consumed = false
            } else if word == "point", kind != .none, kind != .scale {
                var k = j + 1
                var digits = ""
                var punct = false
                while k < atoms.count {
                    let digit: Int64?
                    if atoms[k].word == "oh" { digit = 0 } else { digit = NumberTables.units[atoms[k].word] }
                    guard let d = digit, (0...9).contains(d) else { break }
                    digits += String(d)
                    if atoms[k].endsPhrase {
                        punct = true
                        k += 1
                        break
                    }
                    k += 1
                }
                guard !digits.isEmpty else { break loop }
                decimals = digits
                endsWithPunctuation = punct
                if !punct, scaleCount == 0, total == 0, k < atoms.count,
                   let scale = NumberTables.scales[atoms[k].word],
                   let suffix = NumberTables.abbrevSuffix[atoms[k].word] {
                    let coefficient = Double(current) + (Double("0.\(digits)") ?? 0)
                    let value = Int64((coefficient * Double(scale)).rounded())
                    let abbreviation = "\(current).\(digits)\(suffix)"
                    let last = atoms[k]
                    return NumberPhrase(value: value, decimals: nil, abbreviation: abbreviation,
                                        lastToken: last.token, lastAtom: k, endsWithPunctuation: last.endsPhrase)
                }
                let last = atoms[k - 1]
                return NumberPhrase(value: total + current, decimals: digits, abbreviation: nil,
                                    lastToken: last.token, lastAtom: k - 1, endsWithPunctuation: endsWithPunctuation)
            } else {
                break loop
            }

            if consumed {
                if atoms[j].endsPhrase {
                    endsWithPunctuation = true
                    j += 1
                    break
                }
                j += 1
            }
        }

        guard j > start, kind != .none else { return nil }
        let value = total + current
        var abbreviation: String?
        if scaleCount > 0, kind == .scale, let word = firstScaleWord,
           let scale = NumberTables.scales[word], let suffix = NumberTables.abbrevSuffix[word] {
            abbreviation = compact(value, scale: scale, suffix: suffix)
        }
        let last = atoms[j - 1]
        return NumberPhrase(value: value, decimals: decimals, abbreviation: abbreviation,
                            lastToken: last.token, lastAtom: j - 1, endsWithPunctuation: endsWithPunctuation)
    }

    private static func compact(_ value: Int64, scale: Int64, suffix: String) -> String? {
        guard value > 0 else { return nil }
        var whole = value / scale
        guard (1...999).contains(whole) else { return nil }

        let places = max(0, 3 - String(whole).count)
        let factor: Int64 = places == 2 ? 100 : (places == 1 ? 10 : 1)
        let remainder = value % scale
        var fraction = (remainder * factor + scale / 2) / scale
        if fraction == factor {
            whole += 1
            fraction = 0
        }
        guard whole <= 999 else { return nil }
        guard places > 0, fraction > 0 else { return "\(whole)\(suffix)" }
        var fractionalDigits = String(repeating: "0", count: max(0, places - String(fraction).count)) + String(fraction)
        while fractionalDigits.last == "0" { fractionalDigits.removeLast() }
        return "\(whole).\(fractionalDigits)\(suffix)"
    }

    /// "twenty twenty six" -> 2026. A bare "twenty five" is 25, because five is a unit, not a decade.
    static func parseYear(_ atoms: [Atom], from start: Int) -> (year: Int, lastAtom: Int, lastToken: Int, punct: Bool)? {
        guard start < atoms.count, ["nineteen", "twenty"].contains(atoms[start].word), !atoms[start].endsPhrase,
              start + 1 < atoms.count else { return nil }
        let century = atoms[start].word == "nineteen" ? 19 : 20
        let second = atoms[start + 1]
        if let ten = NumberTables.tens[second.word] {
            if !second.endsPhrase, start + 2 < atoms.count,
               let unit = NumberTables.units[atoms[start + 2].word], (1...9).contains(unit) {
                let a = atoms[start + 2]
                return (century * 100 + Int(ten) + Int(unit), start + 2, a.token, a.endsPhrase)
            }
            return (century * 100 + Int(ten), start + 1, second.token, second.endsPhrase)
        }
        if let teen = NumberTables.units[second.word], (10...19).contains(teen) {
            return (century * 100 + Int(teen), start + 1, second.token, second.endsPhrase)
        }
        if second.word == "oh", !second.endsPhrase, start + 2 < atoms.count,
           let unit = NumberTables.units[atoms[start + 2].word], (1...9).contains(unit) {
            let a = atoms[start + 2]
            return (century * 100 + Int(unit), start + 2, a.token, a.endsPhrase)
        }
        return nil
    }

    /// "twenty first" -> 21, "third" -> 3, "one hundredth" -> 100.
    /// The stage only converts these in a date or counting context.
    static func ordinal(_ atoms: [Atom], from start: Int) -> (value: Int, lastAtom: Int, lastToken: Int, punct: Bool)? {
        guard start < atoms.count else { return nil }
        let word = atoms[start].word
        if let value = NumberTables.ordinalUnits[word] {
            return (value, start, atoms[start].token, atoms[start].endsPhrase)
        }
        if let ten = NumberTables.tens[word], start + 1 < atoms.count, !atoms[start].endsPhrase,
           let unit = NumberTables.ordinalUnits[atoms[start + 1].word], (1...9).contains(unit) {
            let last = atoms[start + 1]
            return (Int(ten) + unit, start + 1, last.token, last.endsPhrase)
        }
        if let unit = NumberTables.units[word], (1...9).contains(unit), start + 1 < atoms.count,
           !atoms[start].endsPhrase,
           let scale = NumberTables.ordinalUnits[atoms[start + 1].word], scale >= 100 {
            let last = atoms[start + 1]
            return (Int(unit) * scale, start + 1, last.token, last.endsPhrase)
        }
        return nil
    }
}
