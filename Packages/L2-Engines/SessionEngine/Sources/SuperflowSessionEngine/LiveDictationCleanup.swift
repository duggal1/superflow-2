import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

actor LiveDictationCleanup {
    struct Prepared: Sendable {
        let prefix: PipelineResult?
        let pending: Task<PipelineResult, Never>?
        let tail: String
        let tailWithoutPending: String

        func resolve(pipeline: TextPipeline, context: TextContext) async -> PipelineResult {
            var head = prefix
            var remaining = tail
            if let pending {
                let result = await withTaskCancellationHandler {
                    await pending.value
                } onCancel: {
                    pending.cancel()
                }
                if LiveDictationCleanup.reusable(result) {
                    head = LiveDictationCleanup.merge(head, result, rawTail: tailWithoutPending)
                    remaining = tailWithoutPending
                }
            }
            if remaining.isEmpty, let head { return head }
            let suffix = await pipeline.run(remaining, context: context)
            return LiveDictationCleanup.merge(head, suffix, rawTail: remaining)
        }
    }

    private struct Piece {
        let id: UUID
        let raw: String
        let end: Int
        let task: Task<PipelineResult, Never>
        var result: PipelineResult?
    }

    private var revision: UUID?
    private var offeredPrefix = ""
    private var pieces: [Piece] = []

    func offer(_ raw: String, revision: UUID, pipeline: TextPipeline, context: TextContext) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.revision != revision || !Self.matches(offeredPrefix, in: text) {
            reset()
            self.revision = revision
        }

        var available = min(4, max(1, context.settings.cleanupWorkers))
            - pieces.filter { $0.result == nil }.count
        while available > 0, pieces.count < 48 {
            let remaining = text.dropFirst(offeredPrefix.count).drop(while: \.isWhitespace)
            guard let rawPiece = Self.checkpoint(in: String(remaining)),
                  let range = text.range(of: rawPiece, range: remaining.startIndex..<text.endIndex),
                  range.lowerBound == remaining.startIndex else { return }
            offeredPrefix = String(text[..<range.upperBound])
            let id = UUID()
            let task = Task(priority: .utility) { await pipeline.run(rawPiece, context: context) }
            Task {
                let result = await task.value
                if !task.isCancelled { self.complete(id, result: result) }
            }
            pieces.append(Piece(id: id, raw: offeredPrefix, end: offeredPrefix.count, task: task))
            available -= 1
        }
    }

    func take(_ raw: String, revision: UUID) -> Prepared? {
        var retained: UUID?
        defer { reset(keeping: retained) }
        guard revision == self.revision else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var prefix: PipelineResult?
        var pending: Task<PipelineResult, Never>?
        var end = 0
        var pendingEnd = 0
        for piece in pieces {
            guard Self.matches(piece.raw, in: text) else { break }
            let remainder = text.dropFirst(piece.end).drop(while: \.isWhitespace)
            guard !Self.opensWithCorrection(remainder) else { break }
            guard let result = piece.result else {
                retained = piece.id
                pending = piece.task
                pendingEnd = piece.end
                break
            }
            guard Self.reusable(result) else { break }
            prefix = Self.merge(prefix, result, rawTail: "")
            end = piece.end
        }
        guard prefix != nil || pending != nil else { return nil }
        return Prepared(prefix: prefix, pending: pending,
                        tail: text.dropFirst(end).trimmingCharacters(in: .whitespacesAndNewlines),
                        tailWithoutPending: text.dropFirst(pendingEnd).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func reset() { reset(keeping: nil) }

    private func reset(keeping id: UUID?) {
        for piece in pieces where piece.id != id { piece.task.cancel() }
        pieces.removeAll(keepingCapacity: true)
        offeredPrefix = ""
        revision = nil
    }

    private static func reusable(_ result: PipelineResult) -> Bool {
        result.draft.cleanupState == .cleaned && result.shortCircuitedBy == nil
    }

    private static func merge(_ head: PipelineResult?, _ suffix: PipelineResult, rawTail: String) -> PipelineResult {
        guard let head else { return suffix }
        var draft = suffix.draft
        let lastLine = head.text.split(separator: "\n").last?.trimmingCharacters(in: .whitespaces) ?? ""
        let separator = lastLine.hasPrefix("- ") ? "\n\n" : " "
        draft.text = [head.text, suffix.text.isEmpty && suffix.draft.cleanupState != .cleaned
                      ? rawTail : suffix.text].filter { !$0.isEmpty }.joined(separator: separator)
        draft.diagnostics.insert(contentsOf: head.draft.diagnostics, at: 0)
        return PipelineResult(draft: draft, timings: head.timings + suffix.timings,
                              shortCircuitedBy: suffix.shortCircuitedBy)
    }

    static func checkpoint(in raw: String) -> String? {
        let sentences = SentenceSplitter.split(raw).complete
        var end = raw.startIndex
        var count = 0
        for sentence in sentences {
            let start = raw[end...].drop(while: \.isWhitespace).startIndex
            guard raw[start...].hasPrefix(sentence),
                  let next = raw.index(start, offsetBy: sentence.count, limitedBy: raw.endIndex) else { return nil }
            count += sentence.split(whereSeparator: \.isWhitespace).count
            end = next
            guard count >= 9 else { continue }
            let remaining = raw[end...]
            guard remaining.split(whereSeparator: \.isWhitespace).prefix(2).count == 2 else { return nil }
            if opensWithCorrection(remaining) { continue }
            return String(raw[..<end])
        }
        return nil
    }

    private static func opensWithCorrection(_ text: Substring) -> Bool {
        let opening = text.split(whereSeparator: \.isWhitespace).prefix(2)
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        guard let first = opening.first else { return false }
        return ["no", "actually", "sorry", "wait", "rather", "correction"].contains(first)
            || [["i", "mean"], ["i", "meant"], ["scratch", "that"], ["make", "that"]].contains(opening)
    }

    private static func matches(_ prefix: String, in text: String) -> Bool {
        guard !prefix.isEmpty else { return true }
        guard text.hasPrefix(prefix) else { return false }
        return text.dropFirst(prefix.count).first?.isWhitespace ?? true
    }

    private func complete(_ id: UUID, result: PipelineResult) {
        guard let index = pieces.firstIndex(where: { $0.id == id }) else { return }
        pieces[index].result = result
    }

    func waitForTesting() async {
        for piece in pieces { complete(piece.id, result: await piece.task.value) }
    }
}
