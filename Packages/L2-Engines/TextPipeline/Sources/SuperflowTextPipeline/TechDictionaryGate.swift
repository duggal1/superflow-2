import Foundation
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowTechDictionary

/// Context gate for Tier B aliases.
///
/// Tier A aliases are always applied. Tier B aliases fire only when the user
/// pinned them, the project vocabulary contains them, or a dev co-word sits
/// within ±3 tokens. The active-application gate is intentionally absent until
/// the pipeline carries the frontmost bundle identifier; omitting it makes the
/// gate more conservative, never less.
struct TechDictionaryGate: Sendable {
    private let pinned: Set<String>
    private let projectTokens: Set<String>
    private let projectText: String

    /// High-signal developer co-words. Deliberately excludes ordinary English
    /// that happens to be a dev term as well (library, package, server, build,
    /// install, framework, config): those made "next year at the library" fire.
    private static let devWords: Set<String> = [
        "js", "ts", "react", "api", "sdk", "npm", "pnpm", "deploy", "docker", "git",
        "repo", "component", "model", "edit", "build", "config",
    ]

    init(userEntries: [LexiconEntry], project: ProjectContext?) {
        pinned = Set(userEntries.map { Self.normalized($0.canonical) })
        let paths = project?.paths ?? []
        projectTokens = Set(paths.flatMap { Self.tokens($0) })
        projectText = paths.joined(separator: " ").lowercased()
    }

    func accepts(trigger: String, canonical: String, line: String, context: TextContext) -> Bool {
        guard let rule = TechDictionary.rule(trigger: trigger, canonical: canonical) else {
            return true
        }
        let tokens = Self.tokens(line)
        if !rule.neg.isEmpty, Self.contains(Set(rule.neg), in: tokens, near: trigger, radius: 3) {
            return false
        }
        guard rule.tier == .b else { return true }

        if pinned.contains(Self.normalized(canonical)) { return true }
        if projectAllows(canonical) { return true }

        var words = Self.devWords
        words.formUnion(rule.requires.map { Self.normalized($0) })
        return Self.contains(words, in: tokens, near: trigger, radius: 3)
    }

    private func projectAllows(_ canonical: String) -> Bool {
        let canon = Self.tokens(canonical)
        guard !canon.isEmpty else { return false }
        if canon.allSatisfy(projectTokens.contains) { return true }
        let compact = Self.normalized(canonical)
        return compact.count >= 4 && Self.normalized(projectText).contains(compact)
    }

    private static func contains(_ words: Set<String>, in line: [String],
                                 near trigger: String, radius: Int) -> Bool {
        // The lexicon normalizer drops the spoken word "dot", so "dot go" and
        // "go" share one trie key. Gate on the spoken tokens that remain.
        let target = tokens(trigger).filter { $0 != "dot" }
        guard !target.isEmpty, line.count >= target.count else { return false }
        for start in 0...(line.count - target.count) {
            guard Array(line[start..<start + target.count]) == target else { continue }
            let end = start + target.count
            let lower = max(0, start - radius)
            let upper = min(line.count - 1, end - 1 + radius)
            for index in lower...upper where index < start || index >= end {
                if words.contains(line[index]) { return true }
            }
        }
        return false
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
