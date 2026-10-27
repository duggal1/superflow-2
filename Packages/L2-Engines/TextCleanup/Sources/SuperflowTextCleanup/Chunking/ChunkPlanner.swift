import Foundation
import SuperflowKernel

public struct CleanupConfig: Sendable, Equatable {
    public var softTokenTarget: Int
    public var hardTokenCap: Int
    public var interactiveDeadlineMs: Int
    public var backgroundDeadlineMs: Int
    public var workers: Int
    public var ratioFloor: Double
    public var retryDepth: Int
    public var hallucinationFloor: Int
    public var maxNewTokens: Int

    public init(softTokenTarget: Int = 600, hardTokenCap: Int = 850, interactiveDeadlineMs: Int = 1_500,
                backgroundDeadlineMs: Int = 30_000, workers: Int = 3, ratioFloor: Double = 0.6,
                retryDepth: Int = 3, hallucinationFloor: Int = 1_024, maxNewTokens: Int = 1_024) {
        self.softTokenTarget = softTokenTarget
        self.hardTokenCap = hardTokenCap
        self.interactiveDeadlineMs = interactiveDeadlineMs
        self.backgroundDeadlineMs = backgroundDeadlineMs
        self.workers = max(1, workers)
        self.ratioFloor = ratioFloor
        self.retryDepth = retryDepth
        self.hallucinationFloor = hallucinationFloor
        self.maxNewTokens = maxNewTokens
    }
}

public struct ChunkPlan: Sendable, Equatable {
    public var index: Int
    public var text: String
    public var tokens: Int
    public init(index: Int, text: String, tokens: Int) {
        self.index = index
        self.text = text
        self.tokens = tokens
    }
}

/// Splits text at ASR sentence boundaries, then clauses, then words. Never mid-word.
/// Token counts come from the model's own tokenizer through `count`.
public struct ChunkPlanner: Sendable {
    public let config: CleanupConfig
    public let protected: Protected

    public init(config: CleanupConfig = CleanupConfig(), protected: Protected = Protected()) {
        self.config = config
        self.protected = protected
    }

    public func plan(_ text: String, count: @Sendable (String) async -> Int) async -> [ChunkPlan] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let total = await count(trimmed)
        if total <= config.hardTokenCap {
            return [ChunkPlan(index: 0, text: trimmed, tokens: total)]
        }

        var pieces: [String] = []
        for paragraph in trimmed.components(separatedBy: "\n") {
            let (sentences, remainder) = SentenceSplitter.split(paragraph)
            var all = sentences
            if !remainder.isEmpty { all.append(remainder) }
            for sentence in all where !sentence.isEmpty {
                let tokens = await count(sentence)
                if tokens > config.hardTokenCap {
                    pieces.append(contentsOf: splitLong(sentence))
                } else {
                    pieces.append(sentence)
                }
            }
        }

        var result: [ChunkPlan] = []
        var bucket: [String] = []
        var bucketTokens = 0
        func flush() {
            guard !bucket.isEmpty else { return }
            result.append(ChunkPlan(index: result.count, text: bucket.joined(separator: " "), tokens: bucketTokens))
            bucket.removeAll(keepingCapacity: true)
            bucketTokens = 0
        }
        for piece in pieces {
            let t = await count(piece)
            if bucketTokens > 0, bucketTokens + t > config.softTokenTarget { flush() }
            if t > config.hardTokenCap {
                // splitLong should have prevented this; hard fallback by words.
                let words = Tokenizer.words(in: piece)
                var start = 0
                let approxPerChunk = max(1, config.softTokenTarget * 3 / 4)
                while start < words.count {
                    let end = min(words.count, start + approxPerChunk)
                    let slice = words[start..<end].joined(separator: " ")
                    flush()
                    result.append(ChunkPlan(index: result.count, text: slice, tokens: await count(slice)))
                    start = end
                }
                continue
            }
            if bucketTokens + t > config.hardTokenCap, !bucket.isEmpty { flush() }
            bucket.append(piece)
            bucketTokens += t
        }
        flush()
        return result.enumerated().map { ChunkPlan(index: $0.offset, text: $0.element.text, tokens: $0.element.tokens) }
    }

    private func splitLong(_ sentence: String) -> [String] {
        var remaining = sentence
        var pieces: [String] = []
        var guardCount = 0
        while wordCount(remaining) > config.hardTokenCap * 3 / 4 && guardCount < 128 {
            guardCount += 1
            let tokens = Tokenizer.tokens(in: remaining)
            guard tokens.count > 12 else { break }
            let target = min(tokens.count - 1, max(8, config.softTokenTarget * 3 / 4))
            var chosen: Int?
            for i in stride(from: target, through: max(4, target / 2), by: -1) {
                if tokens[i].trail.contains(";") { chosen = i; break }
            }
            if chosen == nil {
                for i in stride(from: target, through: max(4, target / 2), by: -1) {
                    if tokens[i].trail.contains(",") { chosen = i; break }
                }
            }
            let index = chosen ?? min(target, tokens.count - 1)
            let piece = tokens[0...index].map(\.full).joined(separator: " ")
            if !piece.isEmpty { pieces.append(piece) }
            remaining = tokens[(index + 1)...].map(\.full).joined(separator: " ")
        }
        if !remaining.isEmpty { pieces.append(remaining) }
        return pieces
    }
}
