import Foundation

public enum EnumerationDetector {
    public enum Hint: Equatable, Sendable {
        case none
        case list(items: Int)
    }

    private static let ordinals = [
        "first", "second", "third", "fourth", "fifth",
        "sixth", "seventh", "eighth", "ninth", "tenth",
    ]
    private static let cardinals = [
        "one", "two", "three", "four", "five", "six",
        "seven", "eight", "nine", "ten",
    ]
    private static let labels: Set<String> = ["number", "step", "item", "point", "reason"]

    public static func detect(_ raw: String) -> Hint {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return .none }
        func normalized(_ s: String) -> String { s.lowercased().filter { $0.isLetter } }
        func clauseStart(_ index: Int) -> Bool {
            index == 0
                || ".,;:!?".contains(tokens[index - 1].last ?? " ")
                || tokens[index].first?.isUppercase == true
        }

        var ordinalHits: [(value: Int, index: Int)] = []
        var cardinalHits: [(value: Int, index: Int)] = []
        for index in tokens.indices {
            let word = normalized(tokens[index])
            if let value = ordinals.firstIndex(of: word), clauseStart(index) {
                ordinalHits.append((value + 1, index))
            }
            if let value = cardinals.firstIndex(of: word) {
                let labeled = index > 0 && labels.contains(normalized(tokens[index - 1]))
                if labeled || clauseStart(index) {
                    cardinalHits.append((value + 1, index))
                }
            }
        }
        let best = max(run(ordinalHits), run(cardinalHits))
        return best >= 3 ? .list(items: best) : .none
    }

    /// True when a detected run needs both chunks to reach its full count, so
    /// the caller may put the run back into one model request.
    public static func straddles(_ left: String, _ right: String) -> Bool {
        guard case .list(let combined) = detect(left + " " + right) else { return false }
        return combined > max(listCount(detect(left)), listCount(detect(right)))
    }

    private static func listCount(_ hint: Hint) -> Int {
        if case .list(let count) = hint { return count }
        return 0
    }

    /// Longest chain 1, 2, 3, ... in order of appearance, items at least two
    /// tokens apart.
    private static func run(_ hits: [(value: Int, index: Int)]) -> Int {
        var expected = 1
        var last = -10
        var count = 0
        for hit in hits where hit.value == expected && hit.index - last >= 2 {
            count += 1
            expected += 1
            last = hit.index
        }
        return count
    }
}

/// Maps the detector's hint to the S1-mini control-line value. The model card
/// exposes exactly two structure values: `prose` and `lists`.
public protocol StructureMapping: Sendable {
    func structure(for hint: EnumerationDetector.Hint, base: String) -> String
}

public struct S1MiniStructureMapping: StructureMapping {
    public init() {}

    public func structure(for hint: EnumerationDetector.Hint, base: String) -> String {
        guard case .list = hint else { return base }
        switch base.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "prose":
            return "lists"
        case "lists", "list", "bullets":
            return "lists"
        default:
            return base
        }
    }
}
