import Foundation
import SuperflowKernel

/// Ordered assembly of chunk outputs with seam repair.
///
/// Dedupe is comparison-only, never heuristic:
/// 1. Overlap rule — the planner repeated the previous chunk's trailing
///    sentences in the next chunk's input (`ChunkPlan.overlap`), so the next
///    output's opening words should equal the previous output's closing words.
///    A matching suffix/prefix of the recorded overlap length,
///    compared on normalized words (lowercased, apostrophes stripped), is
///    removed from the start of the next piece. Requires at least two matched
///    words so an accidental article repetition can not trigger it.
/// 2. Legacy rule — without overlap metadata (retry halves, hand-stitched
///    pieces), an exactly repeated single boundary word is still collapsed,
///    which is what the original `SeamRepair` did.
///
/// When neither rule matches, both sides are kept verbatim: a wrongly-kept
/// duplicate is visible and cheap to edit, a wrongly-deleted word is silent
/// data loss. A piece that resolves to nothing after dedupe (its whole content
/// was the overlap) contributes no output. Joining never rewrites content —
/// it only trims and chooses a space or a newline, and list lines on either
/// side of a seam join with a newline so two bullet items never merge.
public enum OrderedStitcher {
    /// Backwards-compatible entry point without planner overlap metadata.
    public static func stitch(_ pieces: [String]) -> String {
        stitch(pieces, overlaps: [])
    }

    /// `overlaps[i]` is the raw text chunk i re-shared with chunk i-1 (nil/empty
    /// when the chunk carried no overlap). Pieces must be given in chunk order;
    /// a failed chunk's Tier 0 fallback text arrives exactly like a cleaned one.
    public static func stitch(_ pieces: [String], overlaps: [String?]) -> String {
        var out = ""
        var previousPiece = ""
        for (index, raw) in pieces.enumerated() {
            let piece = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            guard !out.isEmpty else {
                out = piece
                previousPiece = piece
                continue
            }
            var remainder = piece
            if index < overlaps.count, let overlap = overlaps[index], !overlap.isEmpty {
                remainder = cutOverlap(piece: piece, overlapWords: overlap, previousTail: previousPiece)
            } else if overlaps.isEmpty {
                remainder = legacySeam(piece: piece, previousTail: out)
            }
            if remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            out = join(previous: out, next: remainder)
            previousPiece = piece
        }
        guard overlaps.isEmpty else { return out }
        return out
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +\n", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes from `piece` the opening run that repeats the previous output's
    /// closing run, and nothing else.
    private static func cutOverlap(piece: String, overlapWords: String, previousTail: String) -> String {
        let head = Tokenizer.tokens(in: piece)
        guard !head.isEmpty else { return piece }
        let overlapCount = normalizedWordCount(overlapWords)
        let tail = Tokenizer.tokens(in: previousTail)
        guard overlapCount >= 2, overlapCount <= head.count, overlapCount <= tail.count else { return piece }
        let left = tail.suffix(overlapCount).map { normalized($0.core) }
        let right = head.prefix(overlapCount).map { normalized($0.core) }
        guard left == right else { return piece }
        guard overlapCount < head.count else { return "" }
        return String(piece[head[overlapCount].range.lowerBound...])
    }

    /// Seams without overlap metadata: collapse an exactly repeated boundary
    /// word only. This is the original seam behavior, kept for retry halves
    /// and any caller without planner metadata.
    private static func legacySeam(piece: String, previousTail: String) -> String {
        let head = Tokenizer.tokens(in: piece)
        guard !head.isEmpty else { return piece }
        let tail = Tokenizer.tokens(in: previousTail)
        guard !tail.isEmpty else { return piece }
        let match = legacyMatch(tail: tail, head: head)
        guard match > 0 else { return piece }
        return head.dropFirst(match).map(\.full).joined(separator: " ")
    }

    private static func legacyMatch(tail: [Token], head: [Token]) -> Int {
        let last = normalized(tail.last?.core ?? "")
        let first = normalized(head.first?.core ?? "")
        guard !last.isEmpty, !first.isEmpty, last == first else { return 0 }
        return 1
    }

    /// Words compared at the seam: lowercased, stripped to letters, numbers
    /// and hyphens. The tokenizer already peeled lead/trail punctuation, and
    /// stripping apostrophes makes "don't"/"dont" agree when the model chose a
    /// different contraction spelling at the seam.
    private static func normalized(_ core: String) -> String {
        let lowered = core.lowercased()
        var result = ""
        result.reserveCapacity(lowered.count)
        for character in lowered {
            if character.isLetter || character.isNumber || character == "-" {
                result.append(character)
            }
        }
        return result
    }

    private static func normalizedWordCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return Tokenizer.tokens(in: text)
            .compactMap { normalized($0.core).isEmpty ? nil : $0.core }
            .count
    }

    // MARK: Joining

    /// Lists are the one layout feature that must survive a seam: a bullet or
    /// numbered line against a non-list neighbour would otherwise merge two
    /// items into one line. Everything else joins with a space.
    private static func join(previous: String, next: String) -> String {
        let previousLine = previous.lastIndex(of: "\n").map { previous[previous.index(after: $0)...] } ?? previous[...]
        let nextLine = next.firstIndex(of: "\n").map { next[..<$0] } ?? next[...]
        let previousIsListLine = lineStartsList(previousLine)
        let nextIsListLine = lineStartsList(nextLine)
        if previousIsListLine || nextIsListLine {
            return previous + "\n" + next
        }
        return previous + " " + next
    }

    private static func lineStartsList(_ raw: Substring) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, "-*•".contains(first) { return true }
        var digits = 0
        for character in trimmed {
            if character.isNumber { digits += 1; continue }
            if digits > 0, character == "." || character == ")" { return true }
            break
        }
        return false
    }
}
