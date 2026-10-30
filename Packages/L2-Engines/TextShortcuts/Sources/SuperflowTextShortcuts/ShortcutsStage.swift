import Foundation
import SuperflowKernel
import SuperflowPorts

/// Expands shortcut triggers verbatim and short-circuits the rest of the pipeline.
public struct ShortcutsStage: SuperflowPorts.TextStage {
    public let id = "shortcuts"
    public static let maxContentBytes = 200 * 1024
    private let entries: [ShortcutEntry]

    public init(entries: [ShortcutEntry]) {
        self.entries = entries.filter { $0.enabled && !$0.trigger.isEmpty && !$0.content.isEmpty }
    }

    /// Lowercase, map spoken dot/slash/dash, collapse spaces, strip surrounding punctuation.
    public static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        for (word, symbol) in [("dot", "."), ("slash", "/"), ("dash", "-")] {
            t = t.replacingOccurrences(of: "\\s*\\b\(word)\\b\\s*", with: symbol, options: .regularExpression)
        }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?;:\"'")))
    }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        let whole = Self.normalize(draft.text)
        for entry in entries where entry.match == .wholeUtterance && Self.normalize(entry.trigger) == whole {
            return expand(draft, with: entry)
        }
        for entry in entries where entry.match == .inline {
            if let result = inline(draft, entry: entry) { return result }
        }
        return draft
    }

    private func expand(_ draft: TranscriptDraft, with entry: ShortcutEntry) -> TranscriptDraft {
        var out = draft
        guard entry.content.utf8.count <= Self.maxContentBytes else {
            out.diagnostics.append(Diagnostic(stage: id, message: "shortcut content exceeds 200 KB"))
            return out
        }
        out.text = entry.content
        out.shortCircuit = true
        out.protected.literals.insert(entry.content)
        out.diagnostics.append(Diagnostic(stage: id, message: "expanded shortcut"))
        return out
    }

    private func inline(_ draft: TranscriptDraft, entry: ShortcutEntry) -> TranscriptDraft? {
        let target = Self.normalize(entry.trigger)
        guard !target.isEmpty, entry.content.utf8.count <= Self.maxContentBytes else { return nil }
        let tokens = Tokenizer.tokens(in: draft.text)
        guard !tokens.isEmpty else { return nil }
        let maxWindow = min(8, max(1, entry.trigger.split(whereSeparator: { $0.isWhitespace }).count + 2))
        for i in tokens.indices {
            let available = tokens.count - i
            for width in stride(from: min(maxWindow, available), through: 1, by: -1) {
                let slice = tokens[i..<(i + width)]
                guard !slice.dropLast().contains(where: { $0.endsClause || $0.core.isEmpty }) else { continue }
                let candidate = Self.normalize(slice.map(\.core).joined(separator: " "))
                guard candidate == target else { continue }
                var out = draft
                let before = String(draft.text[draft.text.startIndex..<tokens[i].range.lowerBound])
                let after = String(draft.text[tokens[i + width - 1].range.upperBound...])
                out.text = before + tokens[i].lead + entry.content + tokens[i + width - 1].trail + after
                out.protected.literals.insert(entry.content)
                out.diagnostics.append(Diagnostic(stage: id, message: "inline shortcut expanded"))
                return out
            }
        }
        return nil
    }
}
