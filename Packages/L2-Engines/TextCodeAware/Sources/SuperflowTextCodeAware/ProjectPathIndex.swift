import Foundation
import SuperflowKernel

/// Bounded lookup from spoken words to project-relative paths.
///
/// Every key is a contiguous window of at most six words from one indexed
/// path. Resolution requires exactly one match; two files that share a spoken
/// name stay untouched.
struct ProjectPathIndex: Sendable {
    private let pathsByKey: [String: [String]]
    let entryCount: Int

    init(paths: [String]) {
        var map: [String: [String]] = [:]
        var counted = 0
        for raw in paths {
            guard let path = ProjectContext.normalizedRelative(raw) else { continue }
            let words = CodeAwareTables.words(in: path)
            guard !words.isEmpty else { continue }
            counted += 1
            var local = Set<String>()
            let limit = min(6, words.count)
            for length in 1...limit {
                for start in 0...(words.count - length) {
                    let key = words[start..<(start + length)].joined(separator: " ")
                    guard local.insert(key).inserted else { continue }
                    map[key, default: []].append(path)
                }
            }
        }
        pathsByKey = map
        entryCount = counted
    }

    var isEmpty: Bool { pathsByKey.isEmpty }

    /// All paths whose spoken key is exactly these words.
    func matches(_ words: [Substring]) -> [String] {
        pathsByKey[words.joined(separator: " ")] ?? []
    }
}
