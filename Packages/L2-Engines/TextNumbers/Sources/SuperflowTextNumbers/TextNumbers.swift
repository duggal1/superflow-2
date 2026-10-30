import Foundation
import SuperflowKernel

public enum TextNumbers {
    public static func apply(_ words: [Word], _ options: NumberOptions = .init()) -> [Word] {
        var output: [Word] = []
        output.reserveCapacity(words.count)
        var i = 0
        func emit(_ core: String, _ used: Int) {
            output.append(Word.merged(core, from: words[i], to: words[i + used - 1], protected: true))
            i += used
        }
        while i < words.count {
            guard NumberLex.editable(words, i) else { output.append(words[i]); i += 1; continue }
            if options.largeNumberStyle == .abbreviated, words[i].key == "half", !words[i].hardBreak {
                let scaleIndex = i + (i + 1 < words.count && ["a", "an"].contains(words[i + 1].key) ? 2 : 1)
                if NumberLex.editable(words, scaleIndex),
                   let suffix = NumberTables.abbrevSuffix[words[scaleIndex].key],
                   (i..<scaleIndex).allSatisfy({ NumberLex.editable(words, $0) && !words[$0].hardBreak }) {
                    var core = "0.5" + suffix
                    var used = scaleIndex - i + 1
                    let next = scaleIndex + 1
                    if !words[scaleIndex].hardBreak, NumberLex.editable(words, next),
                       let currency = NumberPieces.currency[words[next].key] {
                        core = currency + core
                        used += 1
                    }
                    emit(core, used)
                    continue
                }
            }
            if isListMarker(words, at: i) { output.append(words[i]); i += 1; continue }
            if let (clock, used) = NumberPieces.clock(words, i) { emit(clock, used); continue }
            if NumberPieces.yearContext(output), let (year, used) = NumberPieces.year(words, i) {
                emit(String(year), used)
                continue
            }
            if let run = NumberPieces.digitRun(words, i) { emit(run.digits, run.used); continue }
            guard let parsed = NumberLex.parseCardinal(words, i) else { output.append(words[i]); i += 1; continue }
            if parsed.ordinal {
                if let previous = output.last, !previous.hardBreak,
                   NumberPieces.months.contains(previous.key), (1...31).contains(parsed.value) {
                    emit(String(parsed.value), parsed.used)
                } else if parsed.value >= 10 {
                    emit(String(parsed.value) + NumberPieces.ordinalSuffix(parsed.value), parsed.used)
                } else { output.append(words[i]); i += 1 }
                continue
            }
            var j = i + parsed.used
            var decimals: [String] = []
            while NumberLex.editable(words, j), words[j].key == "point", !words[j].hardBreak,
                  !words[j - 1].hardBreak, let digits = NumberPieces.digitsAfter(words, j + 1) {
                decimals.append(digits.digits)
                j += 1 + digits.used
            }
            var core: String
            if decimals.isEmpty {
                let next = NumberLex.editable(words, j) && !words[j - 1].hardBreak ? words[j].key : ""
                let hasUnit = NumberPieces.currency[next] != nil || next == "percent" || NumberPieces.techUnits[next] != nil
                if parsed.used == 1, parsed.value < 10, !hasUnit, !digitize(words, i, options) {
                    output.append(words[i]); i += 1; continue
                }
                let year = parsed.big && (1900...2099).contains(parsed.value) && NumberPieces.yearContext(output)
                core = year ? String(parsed.value) : NumberPieces.group(parsed.value, options.grouping)
                if options.largeNumberStyle == .abbreviated,
                   let scale = NumberLex.scales[words[j - 1].key], parsed.value % scale == 0,
                   let suffix = NumberTables.abbrevSuffix[words[j - 1].key] {
                    core = String(parsed.value / scale) + suffix
                }
            } else {
                core = NumberPieces.group(parsed.value, options.grouping) + "." + decimals.joined(separator: ".")
                if decimals.count == 1, NumberLex.editable(words, j), !words[j - 1].hardBreak,
                   NumberLex.scales[words[j].key] != nil {
                    if options.largeNumberStyle == .abbreviated,
                       let suffix = NumberTables.abbrevSuffix[words[j].key] {
                        core += suffix
                    } else {
                        core += " " + words[j].key
                    }
                    j += 1
                }
            }
            var used = j - i
            let next = NumberLex.editable(words, j) && !words[j - 1].hardBreak ? words[j].key : ""
            if let symbol = NumberPieces.currency[next] {
                var k = j + 1
                var cents = ""
                if decimals.isEmpty, !words[j].hardBreak,
                   NumberLex.editable(words, k), words[k].key == "and", !words[k].hardBreak,
                   let fraction = NumberLex.parseCardinal(words, k + 1), !fraction.ordinal, fraction.value < 100,
                   !words[k + fraction.used].hardBreak,
                   NumberLex.editable(words, k + 1 + fraction.used),
                   ["cent", "cents"].contains(words[k + 1 + fraction.used].key) {
                    cents = "." + String(format: "%02d", Int(fraction.value))
                    k += fraction.used + 2
                }
                core = symbol + core + cents
                used = k - i
            } else if next == "percent" { core += "%"; used += 1 }
            else if let unit = NumberPieces.techUnits[next] { core += " " + unit; used += 1 }
            emit(core, used)
        }
        return output
    }

    private static func isListMarker(_ words: [Word], at index: Int) -> Bool {
        guard index > 0, words[index - 1].key == "number", !words[index - 1].hardBreak,
              let value = NumberLex.units[words[index].key], (1...10).contains(value) else { return false }
        guard index + 1 < words.count, !words[index].hardBreak else { return true }
        let next = words[index + 1].key
        return !NumberLex.isNumberToken(next) && next != "point" && next != "percent"
            && NumberPieces.currency[next] == nil && NumberPieces.techUnits[next] == nil
    }

    private static func digitize(_ words: [Word], _ i: Int, _ options: NumberOptions) -> Bool {
        guard options.small == .digits else { return false }
        guard words[i].key == "one" else { return true }
        let previous = i > 0 && !words[i - 1].hardBreak ? words[i - 1].key : ""
        let next = i + 1 < words.count && !words[i].hardBreak ? words[i + 1].key : ""
        return !NumberPieces.onePrevious.contains(previous) && !NumberPieces.oneNext.contains(next)
    }
}
