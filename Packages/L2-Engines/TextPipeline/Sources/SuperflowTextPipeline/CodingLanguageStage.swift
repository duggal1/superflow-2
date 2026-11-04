import Foundation
import SuperflowKernel
import SuperflowPorts

/// Renders explicit code speech, not ordinary prose. It never runs a shell
/// command or supplies arguments the speaker did not say.
enum CodingLanguageNormalizer {
    private static let extensions: Set<String> = [
        "md", "txt", "json", "yaml", "yml", "toml", "swift", "ts", "tsx",
        "js", "jsx", "rs", "py", "sh", "zsh", "css", "html", "xml", "sql",
        "env", "gitignore", "lock", "plist", "m", "mm", "cpp", "h", "c",
    ]
    private static let canonicalFiles: [String: String] = [
        "agents": "AGENTS", "readme": "README", "license": "LICENSE",
        "changelog": "CHANGELOG", "contributing": "CONTRIBUTING",
        "makefile": "Makefile",
    ]
    private static let gitVerbs: Set<String> = [
        "add", "commit", "push", "merge", "checkout", "remote", "branch",
        "fetch", "clone", "pull", "status", "log", "diff", "restore",
        "switch", "reset", "stash", "rebase", "tag", "show", "init",
        "worktree", "rev-parse", "ls-files",
    ]

    private static let filename = try! NSRegularExpression(pattern:
        #"(?i)(?<![\w./])([A-Za-z][\w-]{0,49})\s+(?:dot|period)\s+([a-z][a-z0-9]{0,9})(?![\w])"#)
    private static let command = try! NSRegularExpression(pattern:
        #"(?i)(?<![\w./])(?:git|get)\s+(?:[a-z]+(?:-[a-z]+)?)\b"#)
    private static let remoteFlag = try! NSRegularExpression(pattern:
        #"(?i)\b(?:get|git)\s+remote\s+(?:dash\s+)?v\b"#)
    private static let addDot = try! NSRegularExpression(pattern:
        #"(?i)\b(?:get|git)\s+add\s+(?:dot|period)\b"#)

    private struct Replacement {
        let range: NSRange
        let text: String
        let protect: Bool
    }

    static func normalize(_ input: String, protected: Protected = Protected())
        -> (text: String, literals: Set<String>) {
        let ns = input as NSString
        let exclusions = protected.ranges(in: input).map { NSRange($0, in: input) }
        let full = NSRange(location: 0, length: ns.length)
        var candidates: [Replacement] = []

        for match in filename.matches(in: input, range: full) {
            let base = ns.substring(with: match.range(at: 1))
            let ext = ns.substring(with: match.range(at: 2)).lowercased()
            guard extensions.contains(ext) else { continue }
            // The filename grammar requires the explicit spoken dot and a
            // recognized file extension; "dot" in normal prose stays ordinary.
            let name = canonicalFiles[base.lowercased()] ?? base
            candidates.append(.init(range: match.range, text: name + "." + ext, protect: true))
        }

        for match in command.matches(in: input, range: full) {
            let phrase = ns.substring(with: match.range)
            let words = phrase.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count == 2, gitVerbs.contains(words[1]) else { continue }
            candidates.append(.init(range: match.range, text: "git " + words[1], protect: false))
        }

        for match in remoteFlag.matches(in: input, range: full) {
            candidates.append(.init(range: match.range, text: "git remote -v", protect: true))
        }
        for match in addDot.matches(in: input, range: full) {
            candidates.append(.init(range: match.range, text: "git add .", protect: true))
        }

        // More specific command or filename candidates beat nested prefixes.
        candidates.sort {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            return $0.range.length > $1.range.length
        }
        var out = ""
        var last = 0
        var literals = Set<String>()
        for candidate in candidates where candidate.range.location >= last {
            if exclusions.contains(where: { NSIntersectionRange(candidate.range, $0).length > 0 }) {
                continue
            }
            out += ns.substring(with: NSRange(location: last, length: candidate.range.location - last))
            out += candidate.text
            if candidate.protect { literals.insert(candidate.text) }
            last = NSMaxRange(candidate.range)
        }
        out += ns.substring(from: last)
        return (out, literals)
    }
}

struct CodingLanguageStage: SuperflowPorts.TextStage {
    let id = "codingLanguage"

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var output = draft
        let change = CodingLanguageNormalizer.normalize(draft.text, protected: draft.protected)
        output.text = change.text
        output.protected.literals.formUnion(change.literals)
        return output
    }
}
