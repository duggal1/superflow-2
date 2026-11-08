import Foundation
import SuperflowKernel
import SuperflowPorts

/// Recognizes family names independently of numeric model versions. A model
/// release is not required to appear in a static dictionary before its version
/// can be transcribed. Ambiguous ordinary words are left unchanged.
enum ModelNameNormalizer {
    private struct Family: Sendable {
        let canonical: String
        let aliases: [String]
        var requiresVersion = false
        var hyphenVersion = false
        var contextual = false
    }

    private static let families: [Family] = [
        .init(canonical: "Claude Opus", aliases: ["claude opus", "opus"], requiresVersion: true),
        .init(canonical: "Claude Sonnet", aliases: ["claude sonnet", "sonnet"], requiresVersion: true),
        .init(canonical: "Claude Haiku", aliases: ["claude haiku", "haiku"], requiresVersion: true),
        .init(canonical: "Claude Fable", aliases: ["claude fable", "fable"], requiresVersion: true),
        .init(canonical: "Claude Mythos", aliases: ["claude mythos", "mythos"], requiresVersion: true),
        .init(canonical: "ChatGPT", aliases: ["chat gbd", "chat gpt", "chatgpt"]),
        .init(canonical: "GPT", aliases: ["gpt", "g p t"], hyphenVersion: true),
        .init(canonical: "Gemini", aliases: ["gemini"]),
        .init(canonical: "Gemma", aliases: ["gemma"], requiresVersion: true),
        .init(canonical: "Grok", aliases: ["grok", "grock"]),
        .init(canonical: "Qwen", aliases: ["qwen", "quen", "quinn"], requiresVersion: true),
        .init(canonical: "DeepSeek", aliases: ["deepseek", "deep seek"]),
        .init(canonical: "Llama", aliases: ["llama"], requiresVersion: true),
        .init(canonical: "Mistral", aliases: ["mistral"], requiresVersion: true),
        .init(canonical: "Mixtral", aliases: ["mixtral"], requiresVersion: true),
        .init(canonical: "Phi", aliases: ["phi"], requiresVersion: true),
        .init(canonical: "Nemotron", aliases: ["nemotron", "nemo tron"]),
        .init(canonical: "Kimi", aliases: ["kimi"], requiresVersion: true),
        .init(canonical: "GLM", aliases: ["glm", "g l m"], requiresVersion: true),
        .init(canonical: "MiniMax", aliases: ["minimax", "mini max"], requiresVersion: true),
        .init(canonical: "Command R", aliases: ["command r"], requiresVersion: true),
        .init(canonical: "Granite", aliases: ["granite"], requiresVersion: true),
        .init(canonical: "Jamba", aliases: ["jamba"], requiresVersion: true),
        .init(canonical: "Falcon", aliases: ["falcon"], requiresVersion: true),
        .init(canonical: "ERNIE", aliases: ["ernie"], requiresVersion: true),
        .init(canonical: "Nova", aliases: ["nova"], requiresVersion: true),
        .init(canonical: "Sonar", aliases: ["perplexity sonar", "sonar"], requiresVersion: true),
        .init(canonical: "OLMo", aliases: ["olmo", "ol mo"], requiresVersion: true),
        .init(canonical: "DBRX", aliases: ["dbrx", "d b r x"], requiresVersion: true),
        .init(canonical: "Aya", aliases: ["aya"], requiresVersion: true),
        .init(canonical: "Reka", aliases: ["reka"], requiresVersion: true),
        .init(canonical: "Hunyuan", aliases: ["hunyuan"], requiresVersion: true),
        .init(canonical: "InternLM", aliases: ["internlm", "intern l m"], requiresVersion: true),
        .init(canonical: "OpenAI", aliases: ["open air", "open ai"], contextual: true),
        .init(canonical: "Anthropic", aliases: ["entropic", "enthropic", "anthropic"], contextual: true),
    ]

    private struct Candidate {
        let range: NSRange
        let text: String
    }

    private static let digits: [String: String] = [
        "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3",
        "four": "4", "five": "5", "six": "6", "seven": "7",
        "eight": "8", "nine": "9",
    ]
    private static let tokenPattern = try! NSRegularExpression(
        pattern: #"[A-Za-z]+|\d+(?:\.\d+)*"#)
    private static let contextualWords: Set<String> = [
        "ai", "api", "model", "models", "llm", "language", "claude",
        "gpt", "chatgpt", "released", "inference", "token", "tokens",
    ]

    static func normalize(_ input: String, protected: Protected = Protected()) -> (text: String, literals: Set<String>) {
        let source = input as NSString
        let reserved = protected.ranges(in: input).map { NSRange($0, in: input) }
        var matches: [Candidate] = []
        for family in families {
            for alias in family.aliases {
                let phrase = NSRegularExpression.escapedPattern(for: alias)
                    .replacingOccurrences(of: " ", with: #"\s+"#)
                guard let expression = try? NSRegularExpression(
                    pattern: #"(?<![\p{L}\p{N}])"# + phrase + #"(?![\p{L}\p{N}])"#,
                    options: [.caseInsensitive]) else { continue }
                for found in expression.matches(in: input, range: NSRange(location: 0, length: source.length)) {
                    if reserved.contains(where: { NSIntersectionRange($0, found.range).length > 0 }) { continue }
                    let version = versionTail(source, after: NSMaxRange(found.range), allowVariants: family.hyphenVersion)
                    if family.requiresVersion && version == nil { continue }
                    if family.contextual && !hasModelContext(source, range: found.range) { continue }
                    let suffix = version.map { (family.hyphenVersion ? "-" : " ") + $0.value } ?? ""
                    let result = family.canonical + suffix
                    let end = version?.end ?? NSMaxRange(found.range)
                    matches.append(Candidate(
                        range: NSRange(location: found.range.location, length: end - found.range.location),
                        text: result))
                }
            }
        }
        // Longest match wins. A smaller alias inside "Claude Opus" cannot run again.
        matches.sort {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            return $0.range.length > $1.range.length
        }
        var offset = 0
        var output = ""
        var protected = Set<String>()
        for match in matches where match.range.location >= offset {
            output += source.substring(with: NSRange(location: offset, length: match.range.location - offset))
            output += match.text
            protected.insert(match.text)
            offset = NSMaxRange(match.range)
        }
        output += source.substring(from: offset)
        return (output, protected)
    }

    private static func hasModelContext(_ source: NSString, range: NSRange) -> Bool {
        let start = max(0, range.location - 48)
        let end = min(source.length, NSMaxRange(range) + 48)
        let surroundings = source.substring(with: NSRange(location: start, length: end - start))
        let tokens = tokenPattern.matches(in: surroundings, range: NSRange(location: 0, length: (surroundings as NSString).length))
            .map { (surroundings as NSString).substring(with: $0.range).lowercased() }
        // "open air concert" is not "OpenAI"; only strong model vocabulary qualifies.
        return tokens.contains(where: contextualWords.contains)
    }

    private static func versionTail(_ source: NSString, after end: Int, allowVariants: Bool) -> (value: String, end: Int)? {
        guard end < source.length else { return nil }
        let tail = source.substring(from: end) as NSString
        let tokens = tokenPattern.matches(in: tail as String,
                                         range: NSRange(location: 0, length: tail.length))
        guard !tokens.isEmpty else { return nil }
        func word(_ index: Int) -> String? {
            guard tokens.indices.contains(index) else { return nil }
            return tail.substring(with: tokens[index].range).lowercased()
        }
        var index = 0
        if word(index) == "version" || word(index) == "v" { index += 1 }
        guard let major = word(index), let number = digits[major] ?? numeric(major),
              let first = tokens.indices.contains(index) ? tokens[index] : nil else { return nil }
        let gap = tail.substring(to: first.range.location)
        guard gap.allSatisfy({ $0.isWhitespace || $0 == "-" }) else { return nil }
        index += 1
        var result = number
        var finish = NSMaxRange(first.range)
        if word(index) == "point" {
            index += 1
            var decimal = ""
            while let part = word(index), decimal.count < 4,
                  let digit = digits[part] ?? numeric(part) {
                decimal += digit
                finish = NSMaxRange(tokens[index].range)
                index += 1
            }
            if !decimal.isEmpty { result += "." + decimal }
        }
        // Model variant names are not decimal digits. Keep them attached to
        // the spoken GPT version instead of leaving a lowercase stray suffix.
        if allowVariants, let variant = word(index), let canonical = gptVariants[variant],
           let token = tokens.indices.contains(index) ? tokens[index] : nil {
            let separator = tail.substring(with: NSRange(location: finish, length: token.range.location - finish))
            if separator.allSatisfy(\.isWhitespace) {
                result += " " + canonical
                finish = NSMaxRange(token.range)
            }
        }
        return (result, end + finish)
    }

    private static let gptVariants: [String: String] = [
        "astra": "Astra", "sol": "Sol", "luna": "Luna", "terra": "Terra",
    ]

    private static func numeric(_ value: String) -> String? {
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              value.first != ".", value.last != ".", !value.contains("..") else { return nil }
        return value
    }
}

struct ModelNameStage: SuperflowPorts.TextStage {
    let id = "modelNames"

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var output = draft
        let normalized = ModelNameNormalizer.normalize(draft.text, protected: draft.protected)
        output.text = normalized.text
        output.protected.literals.formUnion(normalized.literals)
        return output
    }
}
