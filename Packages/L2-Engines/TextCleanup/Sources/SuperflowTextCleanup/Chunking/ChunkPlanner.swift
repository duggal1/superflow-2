import Foundation
import SuperflowKernel

public struct CleanupConfig: Sendable, Equatable {
    public static let maximumInputTokens = 850
    public var softTokenTarget: Int
    public var hardTokenCap: Int
    public var interactiveDeadlineMs: Int
    public var backgroundDeadlineMs: Int
    public var workers: Int
    public var ratioFloor: Double
    /// Legacy configuration only. CleanupService never retries a model call.
    public var retryDepth: Int
    public var hallucinationFloor: Int
    public var maxNewTokens: Int
    /// Seam overlap as a fraction of the soft token target (clamped to
    /// 0...0.20; 0 disables the overlap). Every chunk after the first
    /// re-shares the previous chunk's trailing sentence so the model never
    /// starts blind at a seam. Overlap is on by default (plan.md §13); a
    /// consumer that joins chunk texts must dedupe the repeated opening or
    /// seam words will be duplicated in the finished assembly.
    public var overlapPercent: Double
    /// Structure-only formatting policy. Defaults keep every optional rewrite
    /// off except list and paragraph shaping after cleanup.
    public var format: FormatConfig

    public init(softTokenTarget: Int = 600, hardTokenCap: Int = 850, interactiveDeadlineMs: Int = 1_500,
                backgroundDeadlineMs: Int = 30_000, workers: Int = 6, ratioFloor: Double = 0.6,
                retryDepth: Int = 0, hallucinationFloor: Int = 1_024, maxNewTokens: Int = 1_137,
                overlapPercent: Double = 0.12, format: FormatConfig = FormatConfig()) {
        self.softTokenTarget = min(Self.maximumInputTokens, max(1, softTokenTarget))
        self.hardTokenCap = min(Self.maximumInputTokens, max(1, hardTokenCap))
        self.interactiveDeadlineMs = interactiveDeadlineMs
        self.backgroundDeadlineMs = backgroundDeadlineMs
        // Up to ten contexts run long-transcript chunks in parallel; more would
        // queue. The 600-token target is ~60% of the ~1,000-token model budget
        // and leaves a 250-token margin under the 850-token cap for protected
        // spans and seam overlap (plan.md §13). The old 800/850 pair sat at
        // ~94% of the cap and left almost no headroom.
        self.workers = min(10, max(1, workers))
        self.ratioFloor = ratioFloor
        self.retryDepth = retryDepth
        self.hallucinationFloor = hallucinationFloor
        self.maxNewTokens = maxNewTokens
        self.overlapPercent = overlapPercent
        self.format = format
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
        let hard = min(CleanupConfig.maximumInputTokens, max(1, config.hardTokenCap))
        let target = min(hard, max(1, config.softTokenTarget))
        let fullText = Tokenizer.join(words)
        // plan.md §12 stage 7: decide list structure before choosing any cut.
        // The item spans pin chunk boundaries so a bullet run or an email block
        // is never split across a seam.
        let layouts = Self.listLayouts(words: words,
                                       segments: ListPlanner.plan(fullText, protected: protected))
        let total = await count(fullText)
        if total <= target { return [ChunkPlan(index: 0, text: fullText, tokens: total)] }
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
            // Keep a detected list whole when it fits this window; otherwise
            // defer the entire list to the next chunk. Never cut inside an item.
            var end = Self.listCut(start: start, limit: limit, layouts: layouts)
                ?? Self.bestCut(words, lo: lower, hi: limit, layouts: layouts) ?? limit
            let candidate = Tokenizer.join(words[start..<end])
            var measured = await count(candidate)
            while measured > target {
                // Scale the cut using the real tokenizer count; stepping one word
                // at a time can otherwise require hundreds of helper round trips.
                let estimate = max(1, Int(Double(end - start) * Double(target) / Double(measured)))
                let desired = min(end - 1, start + estimate)
                let shorter = Self.previousCut(words, before: desired + 1, after: start,
                                               layouts: layouts)
                    ?? (start + 1..<end).first {
                        !words[$0 - 1].glue && !Self.isListInterior($0, in: layouts)
                    }
                guard let shorter else { break }
                end = shorter
                measured = await count(Tokenizer.join(words[start..<end]))
            }
            if measured <= target {
                var cursor = end
                while cursor < words.count, prefix[cursor + 1] - prefix[start] <= hard * 2 {
                    cursor += 1
                    guard !words[cursor - 1].glue,
                          cursor == words.count || words[cursor - 1].sentenceEnd || words[cursor - 1].pause else { continue }
                    // Extending into a list would leave part of the run here and
                    // the rest in the next chunk.
                    guard !layouts.contains(where: { $0.start <= cursor && cursor < $0.end }) else { break }
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
                // Never open the re-shared tail in the middle of a list item.
                cursor = Self.legalizedOverlapStart(cursor, bodyStart: body.start, layouts: layouts)
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

    /// A detected list, mapped back to word indices. `start`/`end` bracket the
    /// whole item run; `itemStarts` are the only legal cuts inside it.
    private struct ListLayout {
        var start: Int
        var end: Int
        var itemStarts: Set<Int>
    }

    public static func bestCut(_ words: [Word], lo: Int, hi: Int) -> Int? {
        bestCut(words, lo: lo, hi: hi, layouts: [])
    }

    private static func bestCut(_ words: [Word], lo: Int, hi: Int,
                                layouts: [ListLayout]) -> Int? {
        let low = max(1, lo)
        let high = min(hi, words.count)
        guard low <= high else { return nil }
        var best: Int?
        var score = -1
        for cut in stride(from: high, through: low, by: -1) where !words[cut - 1].glue {
            guard !isListInterior(cut, in: layouts) else { continue }
            let previous = words[cut - 1]
            let onItemBoundary = layouts.contains { $0.itemStarts.contains(cut) }
            let value = onItemBoundary ? 6
                : (previous.sentenceEnd || previous.pause ? 4 : (previous.hardBreak ? 2 : 0))
            if value > score { best = cut; score = value }
        }
        return best
    }

    /// If the whole list fits the candidate window, take it; otherwise defer
    /// the list to the next chunk so no item is lost at the seam.
    private static func listCut(start: Int, limit: Int, layouts: [ListLayout]) -> Int? {
        for layout in layouts where layout.start > start && layout.start <= limit {
            return layout.end <= limit ? layout.end : layout.start
        }
        return nil
    }

    private static func isListInterior(_ index: Int, in layouts: [ListLayout]) -> Bool {
        layouts.contains { index > $0.start && index < $0.end && !$0.itemStarts.contains(index) }
    }

    /// Keeps a re-shared tail from opening in the middle of a list item.
    private static func legalizedOverlapStart(_ cursor: Int, bodyStart: Int,
                                              layouts: [ListLayout]) -> Int {
        guard let layout = layouts.first(where: {
            cursor >= $0.start && cursor < $0.end && $0.start < bodyStart
        }) else { return cursor }
        guard !layout.itemStarts.contains(cursor) else { return cursor }
        let next = layout.itemStarts.filter { $0 > cursor && $0 < bodyStart }.min() ?? bodyStart
        return min(next, bodyStart)
    }

    /// Maps ListPlanner's segments back to word indices by matching each lead
    /// and item in order, so boundaries survive tokenization and timing metadata.
    private static func listLayouts(words: [Word], segments: [CleanupSegment]) -> [ListLayout] {
        var layouts: [ListLayout] = []
        var cursor = 0
        for segment in segments {
            guard case .list(let lead, let items) = segment else { continue }
            if !lead.isEmpty {
                let leadKeys = keys(lead)
                if let at = match(leadKeys, in: words, from: cursor) { cursor = at + leadKeys.count }
            }
            var itemStarts: Set<Int> = []
            var first = words.count
            var end = first
            for item in items {
                let itemKeys = keys(item)
                guard !itemKeys.isEmpty,
                      let at = match(itemKeys, in: words, from: cursor) else { continue }
                first = min(first, at)
                end = max(end, at + itemKeys.count)
                itemStarts.insert(at)
                cursor = at + itemKeys.count
            }
            guard !itemStarts.isEmpty else { continue }
            layouts.append(ListLayout(start: first, end: end, itemStarts: itemStarts))
        }
        return layouts
    }

    private static func keys(_ text: String) -> [String] {
        Tokenizer.words(text).map(\.key)
    }

    private static func match(_ keys: [String], in words: [Word], from start: Int) -> Int? {
        guard !keys.isEmpty, start >= 0, start + keys.count <= words.count else { return nil }
        for index in start...(words.count - keys.count) {
            var matches = true
            for (offset, key) in keys.enumerated() where words[index + offset].key != key {
                matches = false
                break
            }
            if matches { return index }
        }
        return nil
    }

    private static func previousCut(_ words: [Word], before end: Int, after start: Int,
                                    layouts: [ListLayout] = []) -> Int? {
        guard end > start + 1 else { return nil }
        return stride(from: end - 1, through: start + 1, by: -1).first {
            !words[$0 - 1].glue && !isListInterior($0, in: layouts)
        }
    }
}
