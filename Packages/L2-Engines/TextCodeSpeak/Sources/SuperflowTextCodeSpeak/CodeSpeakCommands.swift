import Foundation

enum IdentifierStyle: String, CaseIterable, Sendable {
    case camel
    case snake
    case kebab
    case pascal
    case constant

    var commandWord: String { rawValue }
    var ruleID: String { "identifier.\(rawValue)" }
}

enum SymbolJoin: Sendable {
    case none
    case leading
    case trailing
}

struct SymbolCommand: Sendable {
    let pattern: [String]
    let body: String
    let ruleID: String
    let join: SymbolJoin

    init(_ pattern: [String], _ body: String, _ ruleID: String, join: SymbolJoin = .none) {
        self.pattern = pattern
        self.body = body
        self.ruleID = ruleID
        self.join = join
    }
}

enum CodeSpeakCommands {
    /// Ordinary English that must never be folded into an identifier. Kept
    /// deliberately small: precision matters more than recall, and words like
    /// "by", "in" and "for" remain legal inside real identifiers.
    static let stopwords: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those",
        "it", "is", "are", "was", "were", "be", "been", "being",
        "and", "or", "but", "if", "then", "so",
        "we", "you", "i", "they", "he", "she",
        "my", "our", "your", "their", "his", "her", "its",
        "of", "to",
    ]

    static let fileExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "rs", "go",
        "java", "kt", "kts", "c", "h", "cc", "cpp", "hpp", "m", "mm",
        "json", "yaml", "yml", "toml", "ini", "cfg", "env", "conf",
        "md", "txt", "sh", "bash", "zsh", "fish", "css", "scss", "html",
        "sql", "xml", "csv", "lock", "mod", "sum", "plist",
        "png", "jpg", "jpeg", "gif", "svg", "pdf", "ico", "webp",
        "log", "diff", "patch",
    ]

    /// Single spoken words that are common enough as identifiers to accept on
    /// their own. Everything else needs at least two target words, which keeps
    /// ordinary phrases such as "the camel case study" untouched.
    static let singleWordIdentifiers: Set<String> = [
        "id", "url", "api", "uuid", "guid", "json", "yaml", "html", "css",
        "sql", "http", "https", "env", "db", "ui", "ux", "auth", "token",
        "repo", "config", "enum", "bool", "int", "str",
    ]

    /// Longest patterns first so "open square bracket" wins over "open bracket".
    static let symbols: [SymbolCommand] = [
        SymbolCommand(["open", "parentheses"], "(", "symbol.openParen", join: .trailing),
        SymbolCommand(["open", "parenthesis"], "(", "symbol.openParen", join: .trailing),
        SymbolCommand(["open", "parens"], "(", "symbol.openParen", join: .trailing),
        SymbolCommand(["open", "paren"], "(", "symbol.openParen", join: .trailing),
        SymbolCommand(["close", "parentheses"], ")", "symbol.closeParen", join: .leading),
        SymbolCommand(["close", "parenthesis"], ")", "symbol.closeParen", join: .leading),
        SymbolCommand(["close", "parens"], ")", "symbol.closeParen", join: .leading),
        SymbolCommand(["close", "paren"], ")", "symbol.closeParen", join: .leading),

        SymbolCommand(["open", "square", "brackets"], "[", "symbol.openBracket", join: .trailing),
        SymbolCommand(["open", "square", "bracket"], "[", "symbol.openBracket", join: .trailing),
        SymbolCommand(["open", "brackets"], "[", "symbol.openBracket", join: .trailing),
        SymbolCommand(["open", "bracket"], "[", "symbol.openBracket", join: .trailing),
        SymbolCommand(["close", "square", "brackets"], "]", "symbol.closeBracket", join: .leading),
        SymbolCommand(["close", "square", "bracket"], "]", "symbol.closeBracket", join: .leading),
        SymbolCommand(["close", "brackets"], "]", "symbol.closeBracket", join: .leading),
        SymbolCommand(["close", "bracket"], "]", "symbol.closeBracket", join: .leading),

        SymbolCommand(["open", "curly", "braces"], "{", "symbol.openBrace", join: .trailing),
        SymbolCommand(["open", "curly", "brace"], "{", "symbol.openBrace", join: .trailing),
        SymbolCommand(["open", "curly"], "{", "symbol.openBrace", join: .trailing),
        SymbolCommand(["open", "braces"], "{", "symbol.openBrace", join: .trailing),
        SymbolCommand(["open", "brace"], "{", "symbol.openBrace", join: .trailing),
        SymbolCommand(["close", "curly", "braces"], "}", "symbol.closeBrace", join: .leading),
        SymbolCommand(["close", "curly", "brace"], "}", "symbol.closeBrace", join: .leading),
        SymbolCommand(["close", "curly"], "}", "symbol.closeBrace", join: .leading),
        SymbolCommand(["close", "braces"], "}", "symbol.closeBrace", join: .leading),
        SymbolCommand(["close", "brace"], "}", "symbol.closeBrace", join: .leading),

        SymbolCommand(["open", "angle", "bracket"], "<", "symbol.openAngle", join: .trailing),
        SymbolCommand(["close", "angle", "bracket"], ">", "symbol.closeAngle", join: .leading),

        SymbolCommand(["triple", "equals"], "===", "symbol.tripleEquals"),
        SymbolCommand(["double", "equals"], "==", "symbol.doubleEquals"),
        SymbolCommand(["not", "equals"], "!=", "symbol.notEquals"),
        SymbolCommand(["not", "equal"], "!=", "symbol.notEquals"),
        SymbolCommand(["double", "colon"], "::", "symbol.doubleColon"),
        SymbolCommand(["colon", "colon"], "::", "symbol.doubleColon"),
        SymbolCommand(["fat", "arrow"], "=>", "symbol.fatArrow"),
    ]

    static func identifier(from words: [String], style: IdentifierStyle) -> String? {
        var parts: [String] = []
        for word in words {
            for subword in CodeSpeakParser.subwords(word) {
                let lower = subword.lowercased()
                if !lower.isEmpty { parts.append(lower) }
            }
        }
        guard !parts.isEmpty else { return nil }
        switch style {
        case .camel:
            return parts[0] + parts.dropFirst().map(capitalized).joined()
        case .pascal:
            return parts.map(capitalized).joined()
        case .snake:
            return parts.joined(separator: "_")
        case .kebab:
            return parts.joined(separator: "-")
        case .constant:
            return parts.joined(separator: "_").uppercased()
        }
    }

    private static func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }
}
