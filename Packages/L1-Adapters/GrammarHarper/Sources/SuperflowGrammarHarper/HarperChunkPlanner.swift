import Foundation

/// A contiguous slice of the source text, addressed in UTF-16 so the offsets
/// Harper returns can be shifted without re-encoding.
public struct HarperChunk: Sendable, Equatable {
    public let utf16Offset: Int
    public let utf16Length: Int

    public init(utf16Offset: Int, utf16Length: Int) {
        self.utf16Offset = utf16Offset
        self.utf16Length = utf16Length
    }
}

/// Splits long dictation at sentence boundaries so Harper can lint independent
/// slices on separate handles. Short text keeps the single-handle fast path.
public enum HarperChunkPlanner {
    /// Below this many UTF-16 units a second handle costs more than it saves.
    public static let parallelThreshold = 600
    /// More handles than this compete with ASR and cleanup for the same cores.
    public static let maximumChunks = 3

    public static func plan(_ text: String) -> [HarperChunk] {
        let total = text.utf16.count
        guard total > 0 else { return [] }
        let whole = [HarperChunk(utf16Offset: 0, utf16Length: total)]
        guard total > parallelThreshold else { return whole }

        let sentences = sentenceRanges(in: text)
        guard sentences.count > 1 else { return whole }

        let desired = min(maximumChunks, sentences.count)
        let target = max(1, (total + desired - 1) / desired)
        var chunks: [HarperChunk] = []
        var start = sentences[0].location
        var end = NSMaxRange(sentences[0])
        var current = sentences[0].length

        for index in 1..<sentences.count {
            let remainingGroups = desired - chunks.count
            let remainingSentences = sentences.count - index
            // Close a chunk only when it is big enough and enough sentences are
            // left to fill the remaining groups.
            if current >= target, remainingGroups > 1, remainingSentences >= remainingGroups {
                chunks.append(HarperChunk(utf16Offset: start, utf16Length: end - start))
                start = sentences[index].location
                current = 0
            }
            end = NSMaxRange(sentences[index])
            current += sentences[index].length
        }
        chunks.append(HarperChunk(utf16Offset: start, utf16Length: end - start))
        return chunks
    }

    private static func sentenceRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                                 options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            let range = NSRange(range, in: text)
            if range.length > 0 { ranges.append(range) }
        }
        return ranges
    }
}

/// Harper reports each chunk relative to its own slice. Shift the offsets back
/// onto the source string, then sort and drop duplicate findings that straddle
/// a chunk edge.
public enum HarperLintMerge {
    public static func shift(_ lints: [HarperLint], by offset: Int) -> [HarperLint] {
        guard offset != 0 else { return lints }
        return lints.map { lint in
            var copy = lint
            copy.utf16Start += offset
            return copy
        }
    }

    public static func merge(_ lints: [HarperLint]) -> [HarperLint] {
        let sorted = lints.sorted {
            if $0.utf16Start != $1.utf16Start { return $0.utf16Start < $1.utf16Start }
            if $0.utf16Length != $1.utf16Length { return $0.utf16Length < $1.utf16Length }
            return $0.kind < $1.kind
        }
        var seen = Set<Key>()
        var output: [HarperLint] = []
        for lint in sorted {
            let key = Key(start: lint.utf16Start, length: lint.utf16Length, kind: lint.kind)
            if seen.insert(key).inserted { output.append(lint) }
        }
        return output
    }

    private struct Key: Hashable {
        let start: Int
        let length: Int
        let kind: String
    }
}
