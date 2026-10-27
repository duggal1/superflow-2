import SuperflowKernel
import SuperflowPorts

/// Spoken commands: "new line", "new paragraph", "newline".
/// Whole-phrase only: the phrase must start the utterance, end it, or sit next to punctuation,
/// so "a new line of credit" is never rewritten.
public struct CommandsStage: TextStage {
    public let id = "commands"
    public init() {}

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard context.settings.commandsEnabled else { return draft }
        var output = draft
        output.text = Self.transform(draft.text)
        return output
    }

    public static func transform(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { transformLine(String($0)) }
            .joined(separator: "\n")
    }

    private static func transformLine(_ line: String) -> String {
        let tokens = Tokenizer.tokens(in: line)
        guard !tokens.isEmpty else { return line }
        var pieces: [(text: String, isBreak: Bool)] = []
        var i = 0
        while i < tokens.count {
            if let match = match(tokens, at: i) {
                pieces.append((match.breakText, true))
                i += match.length
                continue
            }
            pieces.append((tokens[i].full, false))
            i += 1
        }
        var out = ""
        for piece in pieces {
            if piece.isBreak {
                while out.hasSuffix(" ") { out.removeLast() }
                out += piece.text
            } else {
                if !out.isEmpty, !out.hasSuffix("\n"), !out.hasSuffix(" ") { out += " " }
                out += piece.text
            }
        }
        return out
    }

    private static func match(_ tokens: [Token], at i: Int) -> (length: Int, breakText: String)? {
        let word = tokens[i].core.lowercased()
        guard !tokens[i].endsClause else { return nil }
        var length = 0
        var text = ""
        if word == "newline" {
            length = 1
            text = "\n"
        } else if word == "new", i + 1 < tokens.count {
            let next = tokens[i + 1].core.lowercased()
            if next == "paragraph" {
                length = 2
                text = "\n\n"
            } else if next == "line" {
                length = 2
                text = "\n"
            }
        }
        guard length > 0 else { return nil }
        let atStart = i == 0 || tokens[i - 1].endsClause
        let atEnd = i + length == tokens.count || tokens[i + length - 1].endsClause
        return (atStart || atEnd) ? (length, text) : nil
    }
}
