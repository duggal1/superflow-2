import Foundation
import SuperflowKernel
import SuperflowPorts

/// Tier 2 grammar gate. Harper may only touch allowlisted lint kinds, only outside protected
/// spans, only inside the 3 percent edit budget and only under the 50 ms time cap.
public struct GrammarGateStage: TextStage {
    public let id: String
    public let policy: GrammarGatePolicy
    private let checker: any GrammarChecker

    public init(checker: any GrammarChecker, policy: GrammarGatePolicy = .loadBundled(),
                id: String = "grammar") {
        self.checker = checker
        self.policy = policy
        self.id = id
    }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard policy.enabled, !draft.shortCircuit else { return draft }
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return draft }

        let started = DispatchTime.now().uptimeNanoseconds
        let lints = await checker.lint(draft.text, customWords: Array(draft.protected.literals).sorted())
        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)

        var output = draft
        guard elapsedMs <= policy.timeCapMs else {
            output.diagnostics.append(Diagnostic(stage: id,
                message: "skipped: lint took \(elapsedMs) ms (cap \(policy.timeCapMs) ms)"))
            return output
        }

        let accepted = Self.acceptedEdits(lints, in: draft.text, policy: policy,
                                          protected: draft.protected)
        let totalWords = max(1, wordCount(draft.text))
        let changedWords = accepted.reduce(0) { $0 + max(1, wordCount($1.replacement)) }
        let ratio = Double(changedWords) / Double(totalWords)
        guard ratio <= policy.maxEditRatio else {
            output.diagnostics.append(Diagnostic(stage: id,
                message: "skipped: edit budget \(accepted.count) edits / \(totalWords) words"))
            return output
        }
        guard !accepted.isEmpty else { return output }

        output.text = Self.apply(accepted, to: draft.text)
        output.diagnostics.append(Diagnostic(stage: id, message: "applied \(accepted.count) lints"))
        return output
    }

    public struct Edit: Sendable, Equatable {
        public var range: NSRange
        public var replacement: String
        public init(range: NSRange, replacement: String) {
            self.range = range
            self.replacement = replacement
        }
    }

    /// Lints are filtered, clamped to the string, de-overlapped and returned in ascending order.
    public static func acceptedEdits(_ lints: [GrammarLint], in text: String,
                                     policy: GrammarGatePolicy, protected: Protected) -> [Edit] {
        let ns = text as NSString
        let length = ns.length
        let protectedRanges = protected.ranges(in: text)
        var edits: [Edit] = []
        for lint in lints {
            guard let suggestion = lint.suggestion, !suggestion.isEmpty,
                  policy.allows(kind: lint.kind) else { continue }
            let location = lint.utf16Start
            let count = lint.utf16Length
            guard location >= 0, count > 0, location <= length, location + count <= length else { continue }
            let range = NSRange(location: location, length: count)
            guard let swiftRange = Range(range, in: text) else { continue }
            guard !protectedRanges.contains(where: { $0.overlaps(swiftRange) }) else { continue }
            guard ns.substring(with: range) != suggestion else { continue }
            if let last = edits.last, range.location < last.range.location + last.range.length { continue }
            edits.append(Edit(range: range, replacement: suggestion))
        }
        return edits
    }

    public static func apply(_ edits: [Edit], to text: String) -> String {
        let result = NSMutableString(string: text)
        for edit in edits.reversed() {
            let end = edit.range.location + edit.range.length
            guard edit.range.location >= 0, end <= result.length else { continue }
            result.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return result as String
    }
}
