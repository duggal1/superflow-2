import Foundation
import SuperflowKernel
import SuperflowPorts

public struct NumberCleanupStage: SuperflowPorts.TextStage {
    public let id = "numbers"
    private let grouping: NumberOptions.Grouping

    public init(grouping: NumberOptions.Grouping = .western) { self.grouping = grouping }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var options = NumberOptions()
        options.small = context.settings.spellOutSmallNumbers ? .words : .digits
        options.grouping = grouping
        options.largeNumberStyle = context.settings.numberStyle
        var output = draft
        var literals = Set<String>()
        output.text = draft.text.components(separatedBy: "\n").map { line in
            let source = Tokenizer.words(line, protected: draft.protected)
            let joined = joinSplitNumbers(compactNumericScales(source, line: line, protected: draft.protected,
                                                               options: options))
            let words = TextNumbers.apply(joined, options)
            for word in words where word.protected { literals.insert(word.core) }
            return Tokenizer.join(words)
        }.joined(separator: "\n")
        output.protected.literals.formUnion(literals)
        return output
    }

    /// ASR often drops a filler between the two halves of a spoken number:
    /// "thirty you know seven degrees" must stay 37, not split into 30 + 7.
    /// A filler is removed only when a number word precedes it and the next
    /// non-filler word is also numeric, so ordinary prose keeps its words.
    private func joinSplitNumbers(_ words: [Word]) -> [Word] {
        let fillers: Set<String> = ["you", "know", "i", "mean", "um", "uh", "umm", "uhh", "erm",
                                     "like", "basically", "well", "actually", "sort", "of"]
        var output: [Word] = []
        output.reserveCapacity(words.count)
        var index = 0
        while index < words.count {
            let key = words[index].key.lowercased()
            if fillers.contains(key),
               let previous = output.last, NumberLex.isNumberToken(previous.key.lowercased()),
               let next = (index + 1..<words.count).first(where: { !fillers.contains(words[$0].key.lowercased()) }),
               NumberLex.isNumberToken(words[next].key.lowercased()) {
                index += 1
                continue
            }
            output.append(words[index])
            index += 1
        }
        return output
    }

    private func compactNumericScales(_ words: [Word], line: String, protected: Protected,
                                      options: NumberOptions) -> [Word] {
        guard options.largeNumberStyle == .abbreviated else { return words }
        let slices = line.split(whereSeparator: \.isWhitespace)
        let spans = protected.ranges(in: line, detect: false)
        var result: [Word] = []
        var index = 0
        func explicitlyProtected(_ index: Int) -> Bool {
            spans.contains { $0.overlaps(slices[index].startIndex..<slices[index].endIndex) }
        }
        while index < words.count {
            if index + 1 < words.count, !explicitlyProtected(index), !explicitlyProtected(index + 1),
               !words[index].glue, !words[index].hardBreak, !words[index + 1].glue {
                let first = words[index]
                let second = words[index + 1]
                if !second.protected, let suffix = NumberTables.abbrevSuffix[second.key],
                   first.core.split(separator: ".", omittingEmptySubsequences: false).count == 2,
                   first.core.first != ".", first.core.last != ".",
                   first.core.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                   Decimal(string: first.core, locale: Locale(identifier: "en_US_POSIX")) != nil {
                    result.append(.merged(first.core + suffix, from: first, to: second, protected: true))
                    index += 2
                    continue
                }
                if first.key == "half", !first.protected, second.core == "1M" {
                    result.append(.merged("0.5M", from: first, to: second, protected: true))
                    index += 2
                    continue
                }
            }
            result.append(words[index])
            index += 1
        }
        return result
    }
}
