import Foundation
import SuperflowKernel

enum NumberPieces {
    static let months = NumberTables.months
    static let yearPrepositions: Set<String> = ["in", "since", "by", "until", "year", "from", "during", "circa", "of"]
    static let currency = ["dollar": "$", "dollars": "$", "buck": "$", "bucks": "$", "euro": "€", "euros": "€", "pound": "£", "pounds": "£", "rupee": "₹", "rupees": "₹", "yen": "¥"]
    static let techUnits = ["megabyte": "MB", "megabytes": "MB", "gigabyte": "GB", "gigabytes": "GB", "kilobyte": "KB", "kilobytes": "KB", "terabyte": "TB", "terabytes": "TB", "millisecond": "ms", "milliseconds": "ms", "hertz": "Hz", "kilohertz": "kHz", "megahertz": "MHz", "gigahertz": "GHz"]
    static let onePrevious: Set<String> = ["no", "the", "any", "every", "each", "this", "that", "which", "another", "a", "an", "some", "all", "only", "such", "other", "last", "next", "first", "second", "third", "one"]
    static let oneNext: Set<String> = ["of", "by", "another", "who", "whom", "that", "which", "thing", "day", "time", "person", "kind", "way", "more", "is", "was", "can", "could", "should", "would", "might", "must", "has", "does"]

    static func digitsAfter(_ words: [Word], _ start: Int) -> (digits: String, used: Int)? {
        var digits = ""
        var j = start
        while NumberLex.editable(words, j) {
            let digit = words[j].key == "oh" ? 0 : NumberLex.units[words[j].key]
            guard let digit, digit <= 9 else { break }
            digits += String(digit)
            j += 1
            if words[j - 1].hardBreak { break }
        }
        return digits.isEmpty ? nil : (digits, j - start)
    }

    /// A spoken multi-digit integer immediately followed by "point":
    /// "three seven point four" -> "37.4", "one one two point eight" -> "112.8".
    /// Without this, the integer head is emitted as separate numbers and the
    /// coordinate is corrupted ("3 7.4"). Runs of one digit are left to the
    /// cardinal parser, which already handles them.
    static func spokenDecimal(_ words: [Word], _ i: Int) -> (value: String, used: Int)? {
        var whole = ""
        var j = i
        while NumberLex.editable(words, j),
              let digit = NumberLex.units[words[j].key], (1...9).contains(digit) {
            whole += String(digit)
            j += 1
            if words[j - 1].hardBreak { return nil }
        }
        guard whole.count >= 2, whole.count <= 4,
              NumberLex.editable(words, j), words[j].key == "point",
              !words[j].hardBreak,
              let fraction = digitsAfter(words, j + 1) else { return nil }
        return ("\(whole).\(fraction.digits)", j + 1 + fraction.used - i)
    }

    static func digitRun(_ words: [Word], _ i: Int) -> (digits: String, used: Int)? {
        guard words[i].key != "oh", let run = digitsAfter(words, i), run.used >= 3 else { return nil }
        let last = i + run.used - 1
        let next = last + 1 < words.count ? words[last + 1].key : ""
        if !words[last].hardBreak, (NumberLex.isNumberToken(next) && next != "oh") || next == "point" { return nil }
        return run
    }

    static func yearContext(_ output: [Word]) -> Bool {
        guard let last = output.last, !last.hardBreak else { return false }
        if yearPrepositions.contains(last.key) || months.contains(last.key) { return true }
        return output.count >= 2 && Int(last.core).map { (1...31).contains($0) } == true
            && months.contains(output[output.count - 2].key)
    }

    static func year(_ words: [Word], _ i: Int) -> (Int, Int)? {
        let head = words[i].key == "nineteen" ? 19 : (words[i].key == "twenty" ? 20 : 0)
        guard head > 0, !words[i].hardBreak, NumberLex.editable(words, i + 1) else { return nil }
        let key = words[i + 1].key
        var tail: UInt64
        var used = 2
        if key == "oh", !words[i + 1].hardBreak, NumberLex.editable(words, i + 2),
           let unit = NumberLex.units[words[i + 2].key], (1...9).contains(unit) {
            tail = unit
            used = 3
        } else if let ten = NumberLex.tens[key] {
            tail = ten
            if !words[i + 1].hardBreak, NumberLex.editable(words, i + 2),
               let unit = NumberLex.units[words[i + 2].key], (1...9).contains(unit) {
                tail += unit
                used = 3
            }
        } else if let unit = NumberLex.units[key], unit >= 10 { tail = unit }
        else { return nil }
        return (head * 100 + Int(tail), used)
    }

    static func clock(_ words: [Word], _ i: Int, timeContext: Bool = false) -> (String, Int)? {
        // A clock hour is never implied hundreds: "three thirty" is 3:30,
        // not 330. The general cardinal parser must not apply that rule here.
        guard let hour = NumberLex.parseCardinal(words, i, impliedHundreds: false),
              !hour.ordinal, !hour.big,
              (1...12).contains(hour.value), !words[i + hour.used - 1].hardBreak else { return nil }
        var j = i + hour.used
        var minutes: UInt64?
        if NumberLex.editable(words, j + 1), words[j].key == "oh", !words[j].hardBreak,
           let unit = NumberLex.units[words[j + 1].key], (1...9).contains(unit) {
            minutes = unit
            j += 2
        } else if let minute = NumberLex.parseCardinal(words, j), !minute.ordinal, !minute.big,
                  (10...59).contains(minute.value) {
            minutes = minute.value
            j += minute.used
        }
        guard NumberLex.editable(words, j), !words[j - 1].hardBreak else { return nil }
        let key = words[j].key
        let meridiem: String
        let used: Int
        if ["a", "p"].contains(key), !words[j].hardBreak,
           NumberLex.editable(words, j + 1), words[j + 1].key == "m" {
            meridiem = key + "m"
            used = 2
        } else if ["am", "pm"].contains(key) {
            meridiem = key
            used = 1
        } else if timeContext, minutes != nil {
            // "at three thirty" / "by nine twenty" are times even without an
            // explicit AM/PM. Without this, "three thirty" falls through to the
            // cardinal parser and becomes 330.
            meridiem = ""
            used = 0
        } else { return nil }
        let time = minutes.map { String(hour.value) + ":" + String(format: "%02d", Int($0)) } ?? String(hour.value)
        return (time + meridiem, j + used - i)
    }

    static func ordinalSuffix(_ value: UInt64) -> String {
        if (11...13).contains(value % 100) { return "th" }
        switch value % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    static func group(_ value: UInt64, _ grouping: NumberOptions.Grouping) -> String {
        let digits = Array(String(value))
        guard digits.count > 3 else { return String(value) }
        return digits.enumerated().reduce(into: "") { output, entry in
            let remaining = digits.count - entry.offset
            let separator: Bool
            switch grouping {
            case .western: separator = remaining % 3 == 0
            case .indian: separator = remaining == 3 || (remaining > 3 && (remaining - 3) % 2 == 0)
            }
            if entry.offset > 0, separator { output += "," }
            output.append(entry.element)
        }
    }
}
