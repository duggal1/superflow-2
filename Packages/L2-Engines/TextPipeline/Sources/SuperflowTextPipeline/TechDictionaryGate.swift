import Foundation
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowTechDictionary

/// Context gate for Tier B aliases.
///
/// Tier A aliases are always applied. Tier B aliases fire only when the user
/// pinned them, the project vocabulary contains them, or a dev co-word sits
/// within ±3 tokens, or the supplied active application is a developer tool.
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

    private static let devApps: Set<String> = [
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
        "com.apple.dt.Xcode", "com.jetbrains.intellij", "com.jetbrains.WebStorm",
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "com.anthropic.claudefordesktop", "com.anthropic.claude-code",
    ]

    init(userEntries: [LexiconEntry], project: ProjectContext?) {
        pinned = Set(userEntries.filter(\.enabled).map { Self.normalized($0.canonical) })
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
        if rule.tier == .b, Self.normalized(trigger) == "textract" {
            if Self.projectMentionsTextract(context) { return false }
            if !Set(tokens).intersection(Set(rule.neg)).isEmpty { return false }
        }
        guard rule.tier == .b else { return true }

        if pinned.contains(Self.normalized(canonical)) { return true }
        if let bundle = context.activeAppBundleID, Self.devApps.contains(bundle) {
            if rule.neg.isEmpty || !Self.contains(Set(rule.neg), in: tokens, near: trigger, radius: 3) {
                return true
            }
        }
        if projectAllows(canonical) { return true }
        // AWS Textract is a real product: never replace it when the project
        // mentions textract or the context carries an AWS/document signal.
        if Self.normalized(trigger) == "textract", Self.projectMentionsTextract(context) {
            return false
        }

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
        // The lexicon normalizer concatenates tokens and drops the spoken word
        // "dot", so the trigger text and the line rarely tokenize alike:
        // "m o e" matches "moe", and "aria" matches "a r i a". Locate the
        // match by its normalized key and gate on the tokens it covers.
        let target = Array(normalized(trigger))
        guard !target.isEmpty else { return false }
        for start in 0..<line.count {
            var end = start
            var accumulated = ""
            while end < line.count, accumulated.count < target.count {
                let token = line[end]
                end += 1
                if token == "dot" { continue }
                accumulated += token.filter { $0.isLetter || $0.isNumber || $0 == "'" }
            }
            guard accumulated == String(target) else { continue }
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

    private static func projectMentionsTextract(_ context: TextContext) -> Bool {
        if context.project?.paths.contains(where: { $0.lowercased().contains("textract") }) == true {
            return true
        }
        return false
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
