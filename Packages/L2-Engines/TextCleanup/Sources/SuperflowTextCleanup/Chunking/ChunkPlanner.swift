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
    /// inside S1-mini's measured input budget.
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
    /// The raw text this chunk re-shares with the previous chunk as its leading
    /// sentences ("" for the first chunk, or when the seam did not fit). The
    /// stitcher matches this against the previous chunk's output tail and
    /// removes the duplicate from this chunk's output.
    public var overlap: String
    public init(index: Int, text: String, tokens: Int, overlap: String = "") {
        self.index = index
        self.text = text
        self.tokens = tokens
        self.overlap = overlap
    }
}

/// Splits text at ASR sentence boundaries, then clauses, then words. Never mid-word.
/// Token counts come from the model's own tokenizer through `count`.
///
/// After the body buckets are built, a second pass composes the seam overlap:
/// chunk i prepends the trailing sentence pieces of chunk i-1 (up to
/// `overlapPercent` of the soft target, and only as far as the hard cap
/// allows), so the model sees a few sentences of context it has already
/// cleaned. The pieces are whole sentences or whole word slices — never
/// mid-word, never inside a protected span.
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

        // A body bucket keeps its pieces and their counts so the overlap pass
        // can pick a trailing slice without re-tokenizing.
        struct Body {
            var plan: ChunkPlan
            var pieces: [(text: String, tokens: Int)]
        }
        var bodies: [Body] = []
        var bucket: [(text: String, tokens: Int)] = []
        var bucketTokens = 0
        func flush() {
            guard !bucket.isEmpty else { return }
            let text = bucket.map(\.text).joined(separator: " ")
            bodies.append(Body(plan: ChunkPlan(index: bodies.count, text: text, tokens: bucketTokens),
                               pieces: bucket))
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
                    let sliceTokens = await count(slice)
                    bodies.append(Body(plan: ChunkPlan(index: bodies.count, text: slice, tokens: sliceTokens),
                                       pieces: [(text: slice, tokens: sliceTokens)]))
                    start = end
                }
                continue
            }
            if bucketTokens + t > config.hardTokenCap, !bucket.isEmpty { flush() }
            bucket.append((text: piece, tokens: t))
            bucketTokens += t
        }
        flush()

        // Seam overlap pass. One guarded exception keeps a seam alive: the
        // single most recent sentence joins the overlap even when it alone is
        // larger than the percent budget, because losing the seam sentence is
        // worse than a slightly larger input; the hard cap still wins.
        let percent = min(0.20, max(0.0, config.overlapPercent))
        let budget = percent <= 0 ? 0 : max(1, Int(Double(config.softTokenTarget) * percent))
        let maxOverlapPieces = 8
        var plans: [ChunkPlan] = []
        plans.reserveCapacity(bodies.count)
        for index in bodies.indices {
            let body = bodies[index]
            var plan: ChunkPlan
            if index > 0, budget > 0, config.hardTokenCap > body.plan.tokens {
                let allowance = config.hardTokenCap - body.plan.tokens
                let previous = bodies[index - 1]
                var chosen: [(text: String, tokens: Int)] = []
                var sum = 0
                for piece in previous.pieces.reversed() {
                    guard !piece.text.isEmpty, chosen.count < maxOverlapPieces else { break }
                    if chosen.isEmpty {
                        if piece.tokens > allowance { break }
                        chosen.insert(piece, at: 0)
                        sum += piece.tokens
                        continue
                    }
                    guard sum + piece.tokens <= min(budget, allowance) else { break }
                    chosen.insert(piece, at: 0)
                    sum += piece.tokens
                }
                // Inserted at 0 keeps oldest-first order.
                let overlap = chosen.map(\.text).joined(separator: " ")
                if !overlap.isEmpty {
                    let composed = overlap + " " + body.plan.text
                    let tokens = await count(composed)
                    if tokens <= config.hardTokenCap {
                        plan = ChunkPlan(index: index, text: composed, tokens: tokens, overlap: overlap)
                    } else {
                        // Token counting is per-piece; a composed count can drift
                        // past the hard cap. Drop the oldest overlap pieces until
                        // the seam fits, and give the overlap up if it never does.
                        var kept = chosen
                        while true {
                            kept.removeFirst()
                            if kept.isEmpty {
                                plan = body.plan
                                break
                            }
                            let composedKept = kept.map(\.text).joined(separator: " ")
                                + " " + body.plan.text
                            let keptTokens = await count(composedKept)
                            if keptTokens <= config.hardTokenCap {
                                plan = ChunkPlan(index: index, text: composedKept, tokens: keptTokens,
                                                 overlap: kept.map(\.text).joined(separator: " "))
                                break
                            }
                        }
                    }
                } else {
                    plan = body.plan
                }
            } else {
                plan = body.plan
            }
            plan.index = plans.count
            plans.append(plan)
        }
        return plans
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
