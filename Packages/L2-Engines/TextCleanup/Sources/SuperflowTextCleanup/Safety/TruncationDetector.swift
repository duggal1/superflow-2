import Foundation
import SuperflowKernel

public enum TruncationReason: String, Sendable, Equatable {
    case emptyOutput
    case ratioBelowFloor
    case missingTail
    case endsMidSentence
    case hitTokenCap
}

public struct TruncationDetector: Sendable {
    public var ratioFloor: Double
    public init(ratioFloor: Double = 0.6) { self.ratioFloor = ratioFloor }

    public func detect(input: String, output: String, hitTokenCap: Bool) -> TruncationReason? {
        if hitTokenCap { return .hitTokenCap }
        let outputWords = wordCount(output)
        if outputWords == 0 { return .emptyOutput }
        let inputWords = wordCount(input)
        if inputWords > 6, Double(outputWords) / Double(inputWords) < ratioFloor { return .ratioBelowFloor }

        let inputTail = Tokenizer.words(in: input).last.map(normalize) ?? ""
        let outputTail = Tokenizer.words(in: output).last.map(normalize) ?? ""
        if !inputTail.isEmpty, !isEquivalentTail(inputTail, outputTail) { return .missingTail }

        let inputEnds = SentenceSplitter.endsSentence(input)
        let outputEnds = SentenceSplitter.endsSentence(output)
        if inputEnds && !outputEnds { return .endsMidSentence }
        return nil
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    private func isEquivalentTail(_ input: String, _ output: String) -> Bool {
        if input == output { return true }
        guard !input.isEmpty, !output.isEmpty, abs(input.count - output.count) <= 1 else { return false }
        let lhs = Array(input)
        let rhs = Array(output)
        var row = Array(0...rhs.count)
        for (index, character) in lhs.enumerated() {
            var next = [index + 1] + Array(repeating: 0, count: rhs.count)
            for column in 1...rhs.count {
                next[column] = character == rhs[column - 1]
                    ? row[column - 1]
                    : 1 + min(row[column - 1], row[column], next[column - 1])
            }
            row = next
        }
        return row[rhs.count] <= 1
    }
}

public struct HallucinationGuard: Sendable {
    public var maxUnexplainedRatio: Double
    public var maxUnexplainedWords: Int
    public init(maxUnexplainedRatio: Double = 0.05, maxUnexplainedWords: Int = 1) {
        self.maxUnexplainedRatio = maxUnexplainedRatio
        self.maxUnexplainedWords = maxUnexplainedWords
    }

    /// Output words must be explained by input words, or be numbers/punctuation/short function words.
    public func allows(input: String, output: String) -> Bool {
        let inputWords = Set(Tokenizer.words(in: input).map { $0.lowercased() })
        let outputWords = Tokenizer.words(in: output).map { $0.lowercased() }
        guard !outputWords.isEmpty else { return false }
        var unexplained = 0
        for word in outputWords {
            let core = word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            if core.isEmpty || inputWords.contains(core) { continue }
            if core.allSatisfy({ $0.isNumber || $0.isPunctuation }) { continue }
            if core.count <= 2 { continue }
            if inputWords.contains(where: { editDistance($0, core) <= 1 && abs($0.count - core.count) <= 1 }) { continue }
            if Self.allowedConversions.contains(core) { continue }
            unexplained += 1
        }
        return unexplained <= maxUnexplainedWords
            && Double(unexplained) / Double(outputWords.count) <= maxUnexplainedRatio
    }

    static let allowedConversions: Set<String> = [
        "at", "dot", "slash", "dash", "percent", "and", "okay", "ok", "cannot", "can't", "dont", "don't",
        "im", "i'm", "ive", "i've", "its", "it's", "were", "we're", "thats", "that's",
    ]

    private func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
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
