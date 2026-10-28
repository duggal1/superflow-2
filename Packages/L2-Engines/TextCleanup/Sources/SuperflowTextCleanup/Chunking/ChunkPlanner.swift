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
    /// Seam overlap as a fraction of the soft token target (clamped to
    /// 0...0.20; 0 disables the overlap). Every chunk after the first
    /// re-shares the previous chunk's trailing sentences so the model never
    /// starts blind at a seam, and the stitcher dedupes the repeated opening
    /// from the finished assembly. With the product sizes (soft 600, hard 850)
    /// the 12% default adds about 72 tokens per seam, which keeps overlap+body
    /// inside the provisional input budget pending calibration.
    public var overlapPercent: Double

    public init(softTokenTarget: Int = 600, hardTokenCap: Int = 850, interactiveDeadlineMs: Int = 1_500,
                backgroundDeadlineMs: Int = 30_000, workers: Int = 3, ratioFloor: Double = 0.6,
                retryDepth: Int = 3, hallucinationFloor: Int = 1_024, maxNewTokens: Int = 1_024,
                overlapPercent: Double = 0.12) {
        self.softTokenTarget = softTokenTarget
        self.hardTokenCap = hardTokenCap
        self.interactiveDeadlineMs = interactiveDeadlineMs
        self.backgroundDeadlineMs = backgroundDeadlineMs
        self.workers = max(1, workers)
        self.ratioFloor = ratioFloor
        self.retryDepth = retryDepth
        self.hallucinationFloor = hallucinationFloor
        self.maxNewTokens = maxNewTokens
        self.overlapPercent = overlapPercent
    }
}

public struct ChunkPlan: Sendable, Equatable {
    public var index: Int
    public var text: String
    public var tokens: Int
    public var overlap: String
    public var ownedText: String

    public init(index: Int, text: String, tokens: Int, overlap: String = "", ownedText: String? = nil) {
        self.index = index
        self.text = text
        self.tokens = tokens
        self.overlap = overlap
        self.ownedText = ownedText ?? text
    }
}

public struct ChunkPlanner: Sendable {
    public let config: CleanupConfig
    public let protected: Protected

    public init(config: CleanupConfig = CleanupConfig(), protected: Protected = Protected()) {
        self.config = config
        self.protected = protected
    }

    public func plan(_ text: String, count: @Sendable (String) async -> Int) async -> [ChunkPlan] {
        await plan(Tokenizer.words(text, protected: protected), count: count)
    }

    public func plan(_ words: [Word], count: @Sendable (String) async -> Int) async -> [ChunkPlan] {
        guard !words.isEmpty else { return [] }
        let hard = max(1, config.hardTokenCap)
        let target = min(hard, max(1, config.softTokenTarget))
        let fullText = Tokenizer.join(words)
        let total = await count(fullText)
        if total <= hard { return [ChunkPlan(index: 0, text: fullText, tokens: total)] }
        var prefix = [0]
        prefix.reserveCapacity(words.count + 1)
        for word in words { prefix.append(prefix[prefix.count - 1] + Self.weight(word)) }
        var bodies: [(start: Int, end: Int, tokens: Int)] = []
        var start = 0
        while start < words.count {
            var limit = start + 1
            while limit < words.count, prefix[limit + 1] - prefix[start] <= target { limit += 1 }
            while limit < words.count, words[limit - 1].glue { limit += 1 }
            let lower = max(start + 1, start + (limit - start) * 3 / 4)
            var end = Self.bestCut(words, lo: lower, hi: limit) ?? limit
            let candidate = Tokenizer.join(words[start..<end])
            var measured = await count(candidate)
            while measured > hard, let shorter = Self.previousCut(words, before: end, after: start) {
                end = shorter
                measured = await count(Tokenizer.join(words[start..<end]))
            }
            if measured <= target {
                var cursor = end
                while cursor < words.count, prefix[cursor + 1] - prefix[start] <= hard * 2 {
                    cursor += 1
                    guard !words[cursor - 1].glue,
                          cursor == words.count || words[cursor - 1].sentenceEnd || words[cursor - 1].pause else { continue }
                    let extended = await count(Tokenizer.join(words[start..<cursor]))
                    guard extended <= target else { break }
                    end = cursor
                    measured = extended
                }
            }
            // A protected term can itself exceed the model budget. Keep it whole;
            // the caller rejects oversized input and returns its deterministic text.
            bodies.append((start, end, measured))
            start = end
        }
        var plans: [ChunkPlan] = []
        plans.reserveCapacity(bodies.count)
        let overlapBudget = Int(Double(target) * min(0.20, max(0, config.overlapPercent)))
        for (index, body) in bodies.enumerated() {
            let owned = Tokenizer.join(words[body.start..<body.end])
            var overlapStart = body.start
            if index > 0, overlapBudget > 0, body.tokens < hard {
                let previous = bodies[index - 1]
                var cursor = body.start
                while cursor > previous.start,
                      prefix[body.start] - prefix[cursor - 1] <= overlapBudget {
                    cursor -= 1
                }
                // Prefer the last complete sentence when it fits the hard budget.
                if let sentence = (previous.start..<body.start).reversed().first(where: {
                    $0 == previous.start || words[$0 - 1].sentenceEnd || words[$0 - 1].pause
                }) {
                    cursor = min(cursor, sentence)
                }
                while cursor > previous.start, words[cursor - 1].glue { cursor -= 1 }
                overlapStart = cursor
            }
            var composed = Tokenizer.join(words[overlapStart..<body.end])
            var measured = overlapStart == body.start ? body.tokens : await count(composed)
            while measured > hard, overlapStart < body.start {
                repeat { overlapStart += 1 }
                while overlapStart < body.start && words[overlapStart - 1].glue
                composed = Tokenizer.join(words[overlapStart..<body.end])
                measured = overlapStart == body.start ? body.tokens : await count(composed)
            }
            plans.append(ChunkPlan(index: index, text: composed, tokens: measured,
                                   overlap: Tokenizer.join(words[overlapStart..<body.start]), ownedText: owned))
        }
        return plans
    }

    public static func weight(_ word: Word) -> Int {
        let length = word.core.count
        if word.core.contains(where: { "/._-@".contains($0) }) { return max(2, length / 2) }
        return 1 + length / 7
    }

    public static func bestCut(_ words: [Word], lo: Int, hi: Int) -> Int? {
        let low = max(1, lo)
        let high = min(hi, words.count)
        guard low <= high else { return nil }
        var best: Int?
        var score = -1
        for cut in stride(from: high, through: low, by: -1) where !words[cut - 1].glue {
            let previous = words[cut - 1]
            let value = previous.sentenceEnd || previous.pause ? 4 : (previous.hardBreak ? 2 : 0)
            if value > score { best = cut; score = value }
        }
        return best
    }

    private static func previousCut(_ words: [Word], before end: Int, after start: Int) -> Int? {
        guard end > start + 1 else { return nil }
        return stride(from: end - 1, through: start + 1, by: -1).first { !words[$0 - 1].glue }
    }
}
