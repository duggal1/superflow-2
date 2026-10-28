import Foundation

/// Small, curated vocabularies. Precision beats recall: a missing conversion is
/// harmless prose, a wrong one changes what the user said.
enum CodeAwareTables {
    /// Extensions the ASR and the user actually dictate in this workflow.
    static let extensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "rs", "go",
        "java", "kt", "kts", "c", "h", "cc", "cpp", "hpp", "m", "mm",
        "json", "yaml", "yml", "toml", "ini", "cfg", "env", "conf",
        "md", "txt", "sh", "bash", "zsh", "fish", "css", "scss", "html",
        "sql", "xml", "csv", "lock", "mod", "sum", "plist",
        "png", "jpg", "jpeg", "gif", "svg", "pdf", "ico", "webp",
        "log", "diff", "patch",
    ]

    /// Words that end a filename run instead of belonging to the stem.
    static let stemStopwords: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those", "my", "our", "your",
        "their", "its", "his", "her", "file", "filename", "folder", "directory",
        "dir", "called", "named", "open", "edit", "fix", "show", "find", "go",
        "navigate", "to", "from", "in", "on", "at", "for", "with", "please",
        "and", "or", "then", "now", "dot", "slash", "backslash", "dash",
        "underscore", "path",
    ]

    /// Spoken separators inside a path or filename.
    static let separators: Set<String> = [
        "slash", "backslash", "dot", "dash", "hyphen", "underscore",
    ]

    /// Words that must never resolve as a one-word project path on their own.
    static let commonEnglish: Set<String> = [
        "main", "index", "test", "tests", "source", "src", "lib", "app", "api",
        "data", "docs", "doc", "build", "dist", "core", "base", "home", "user",
        "users", "system", "server", "client", "router", "route", "engine",
        "module", "package", "config", "settings", "model", "view", "controller",
        "service", "store", "state", "handler", "helper", "utils", "util",
        "types", "type", "shared", "common", "public", "private", "assets",
        "static", "style", "styles", "scripts", "tools", "bin", "run", "start",
        "stop", "new", "old", "next", "prev", "back", "front", "page", "pages",
    ]

    static let pathCues: Set<String> = ["open", "fix", "edit", "show", "find", "go", "navigate", "read"]

    static let directoryWords: Set<String> = ["folder", "directory", "dir"]

    static func isPlainWord(_ core: String) -> Bool {
        guard !core.isEmpty, core.count <= 40 else { return false }
        return core.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    static func endsClause(_ trail: String) -> Bool {
        trail.contains { ".,;:!?".contains($0) }
    }

    /// Splits a project-relative path into lowercase, searchable words.
    static func words(in path: String) -> [String] {
        var out: [String] = []
        for component in path.split(separator: "/") {
            let text = component.replacingOccurrences(of: ".", with: "-")
                .replacingOccurrences(of: "_", with: "-")
            for piece in text.split(separator: "-") {
                let camel = splitCamelCase(String(piece))
                for word in camel where !word.isEmpty {
                    out.append(word.lowercased())
                }
            }
        }
        return out
    }

    private static func splitCamelCase(_ word: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var previous: Character?
        for character in word {
            if let previous, character.isUppercase, previous.isLowercase {
                pieces.append(current)
                current = ""
            }
            current.append(character)
            previous = character
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
