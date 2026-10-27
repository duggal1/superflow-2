import Foundation
import SuperflowKernel
import SuperflowPorts

/// One dictation-style sentence plus the text Harper should produce.
public struct GrammarGoldenCase: Sendable, Equatable {
    public var input: String
    public var expected: String
    public var protected: Protected

    public init(_ input: String, _ expected: String, protected: Protected = Protected()) {
        self.input = input
        self.expected = expected
        self.protected = protected
    }
}

/// Per-category precision measured on the golden corpus. PLAN section 11 ships
/// a category only when it clears 98 percent precision.
public struct GrammarCategoryReport: Sendable, Equatable {
    public struct Category: Sendable, Equatable {
        public var kind: String
        public var proposed: Int
        public var correct: Int

        public init(kind: String, proposed: Int, correct: Int) {
            self.kind = kind
            self.proposed = max(0, proposed)
            self.correct = min(max(0, correct), max(0, proposed))
        }

        /// Zero when a category proposed nothing: no evidence means no shipping.
        public var precision: Double {
            proposed == 0 ? 0 : Double(correct) / Double(proposed)
        }
    }

    public var categories: [String: Category]
    public var caseCount: Int
    public var minimumPrecision: Double

    public init(categories: [String: Category] = [:], caseCount: Int = 0,
                minimumPrecision: Double = 0.98) {
        self.categories = categories
        self.caseCount = caseCount
        self.minimumPrecision = min(1, max(0, minimumPrecision))
    }

    public func category(_ kind: String) -> Category? {
        categories[GrammarGatePolicy.canonical(kind)]
    }

    public func ships(_ kind: String) -> Bool {
        guard let category = category(kind) else { return false }
        return category.proposed > 0 && category.precision >= minimumPrecision
    }

    public var enabledKinds: [String] {
        categories.values.filter { $0.proposed > 0 && $0.precision >= minimumPrecision }
            .map(\.kind).sorted()
    }

    public var disabledKinds: [String] {
        categories.values.filter { $0.proposed == 0 || $0.precision < minimumPrecision }
            .map(\.kind).sorted()
    }

    public func summary() -> String {
        let rows = categories.values.sorted { $0.kind < $1.kind }.map { category in
            String(format: "%@ %d/%d %.3f", category.kind, category.correct,
                   category.proposed, category.precision)
        }
        return rows.joined(separator: "; ")
    }
}

extension GrammarGateStage {
    /// Runs every lint the checker proposes over the corpus and scores each
    /// category by whether its single edit moves the text closer to `expected`.
    /// This mirrors what the gate would apply (allowlist, valid ranges,
    /// protected spans, non-overlapping edits) but does not apply the edit
    /// budget, because the budget is a per-chunk safety valve, not a rule test.
    public static func audit(_ cases: [GrammarGoldenCase],
                             checker: any GrammarChecker,
                             minimumPrecision: Double = 0.98) async -> GrammarCategoryReport {
        var tally: [String: (proposed: Int, correct: Int)] = [:]
        for golden in cases {
            let lints = await checker.lint(golden.input,
                                           customWords: Array(golden.protected.literals).sorted())
            let ns = golden.input as NSString
            let protectedRanges = golden.protected.ranges(in: golden.input)
            let base = levenshtein(golden.input, golden.expected)
            var used: [NSRange] = []
            for lint in lints {
                guard let suggestion = lint.suggestion, !suggestion.isEmpty else { continue }
                let location = lint.utf16Start
                let count = lint.utf16Length
                guard location >= 0, count > 0, location <= ns.length,
                      location + count <= ns.length else { continue }
                let range = NSRange(location: location, length: count)
                guard let swiftRange = Range(range, in: golden.input) else { continue }
                guard !protectedRanges.contains(where: { $0.overlaps(swiftRange) }) else { continue }
                guard ns.substring(with: range) != suggestion else { continue }
                guard !used.contains(where: { $0.intersection(range) != nil }) else { continue }
                used.append(range)

                let key = GrammarGatePolicy.canonical(lint.kind)
                guard !key.isEmpty else { continue }
                let candidate = (golden.input as NSString).replacingCharacters(in: range, with: suggestion)
                let entry = tally[key] ?? (0, 0)
                let improved = levenshtein(candidate, golden.expected) < base
                tally[key] = (entry.proposed + 1, entry.correct + (improved ? 1 : 0))
            }
        }
        var categories: [String: GrammarCategoryReport.Category] = [:]
        for (key, value) in tally {
            categories[key] = GrammarCategoryReport.Category(
                kind: GrammarGatePolicy.displayName(key),
                proposed: value.proposed, correct: value.correct)
        }
        return GrammarCategoryReport(categories: categories, caseCount: cases.count,
                                     minimumPrecision: minimumPrecision)
    }

    /// Character-level Levenshtein distance, capped so a pathological golden
    /// cannot make the audit quadratic in an unbounded way.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        if x.count > 4_000 || y.count > 4_000 { return abs(x.count - y.count) }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                current[j] = x[i - 1] == y[j - 1]
                    ? previous[j - 1]
                    : 1 + min(previous[j - 1], previous[j], current[j - 1])
            }
            previous = current
        }
        return previous[y.count]
    }
}
