import Foundation
import SuperflowKernel

enum ParagraphBoundaries {
    static func restore(from source: String, in cleaned: String) -> String {
        let paragraphs = source.components(separatedBy: "\n\n")
        guard paragraphs.count > 1, !cleaned.contains("\n\n") else { return cleaned }
        let tokens = Tokenizer.tokens(in: cleaned)
        var cursor = 1
        var breaks: [Range<String.Index>] = []
        for paragraph in paragraphs.dropFirst() {
            let anchor = Tokenizer.tokens(in: paragraph).prefix(3).map { $0.core.lowercased() }
            guard anchor.count == 3, tokens.count >= 4, cursor <= tokens.count - 3 else { continue }
            for index in cursor...(tokens.count - 3) {
                let previous = tokens[index - 1]
                guard previous.endsClause else { continue }
                let candidate = tokens[index..<(index + 3)].map { $0.core.lowercased() }
                guard anchor == candidate else { continue }
                breaks.append(previous.range.upperBound..<tokens[index].range.lowerBound)
                cursor = index + 3
                break
            }
        }
        var output = cleaned
        for gap in breaks.reversed() {
            output.replaceSubrange(gap, with: "\n\n")
        }
        return output
    }
}
