import Foundation
import SuperflowKernel

public struct TextDisfluencyStage: TextStage {
    public struct Config: Sendable {
        public var minRun = 2
        public var maxPhraseLength = 3
        public var legitimatePairs: Set<String> = ["had", "that"]
        public var fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "er", "erm"]
        public var stripFillers = true
        public var maxStutterPause: Duration = .milliseconds(600)
        public init() {}
    }

    public let name = "TextDisfluency"
    private let config: Config
    public init(config: Config = .init()) { self.config = config }

    public func apply(_ draft: TextDraft) -> TextDraft {
        var words = config.stripFillers ? stripFillers(draft.words) : draft.words
        if words.isEmpty { return draft }
        for _ in 0..<8 {
            let before = words.count
            words = collapseRuns(words)
            words = collapsePhrases(words)
            if words.count == before { break }
        }
        return TextDraft(words: words)
    }

    private func stripFillers(_ words: [Word]) -> [Word] {
        var out: [Word] = []
        out.reserveCapacity(words.count)
        for w in words {
            guard !w.isProtected, w.lead.isEmpty, config.fillers.contains(w.key) else { out.append(w); continue }
            if w.endsSentence, let last = out.indices.last, soft(out[last]) {
                out[last].trail = w.trail
            }
        }
        return out
    }

    private func collapseRuns(_ words: [Word]) -> [Word] {
        var out: [Word] = []
        out.reserveCapacity(words.count)
        var i = 0
        while i < words.count {
            var j = i + 1
            while j < words.count, canRepeat(words[j - 1], words[j]) { j += 1 }
            let run = j - i
            let collapses = run >= max(2, config.minRun)
                && !(run == 2 && config.legitimatePairs.contains(words[i].key))
            if collapses {
                var kept = words[i]
                kept.trail = words[j - 1].trail
                out.append(kept)
            } else {
                out.append(contentsOf: words[i..<j])
            }
            i = j
        }
        return out
    }

    private func canRepeat(_ a: Word, _ b: Word) -> Bool {
        repeatable(a) && repeatable(b)
            && a.key == b.key
            && soft(a)
            && b.lead.isEmpty
            && (b.pauseBefore ?? .zero) <= config.maxStutterPause
    }

    private func collapsePhrases(_ words: [Word]) -> [Word] {
        guard config.maxPhraseLength >= 2, words.count >= 4 else { return words }
        var out: [Word] = []
        out.reserveCapacity(words.count)
        var i = 0
        outer: while i < words.count {
            let maxN = min(config.maxPhraseLength, (words.count - i) / 2)
            if maxN >= 2 {
                for n in stride(from: maxN, through: 2, by: -1) {
                    guard Set(words[i..<(i + n)].map(\.key)).count >= 2 else { continue }
                    var copies = 1
                    while i + (copies + 1) * n <= words.count, isRepeat(words, i, i + copies * n, n) { copies += 1 }
                    if copies >= max(2, config.minRun) {
                        var block = Array(words[i..<(i + n)])
                        block[n - 1].trail = words[i + copies * n - 1].trail
                        out.append(contentsOf: block)
                        i += copies * n
                        continue outer
                    }
                }
            }
            out.append(words[i])
            i += 1
        }
        return out
    }

    private func isRepeat(_ w: [Word], _ a: Int, _ b: Int, _ n: Int) -> Bool {
        guard soft(w[b - 1]), (w[b].pauseBefore ?? .zero) <= config.maxStutterPause else { return false }
        for k in 0..<n {
            let x = w[a + k], y = w[b + k]
            guard repeatable(x), repeatable(y), x.key == y.key, y.lead.isEmpty else { return false }
            if k < n - 1, !(soft(x) && soft(y)) { return false }
        }
        return true
    }

    private func soft(_ w: Word) -> Bool { w.trail.isEmpty || w.trail == "," }

    private func repeatable(_ w: Word) -> Bool {
        !w.isProtected && !w.core.isEmpty && !w.core.contains(where: \.isNumber)
    }
}
