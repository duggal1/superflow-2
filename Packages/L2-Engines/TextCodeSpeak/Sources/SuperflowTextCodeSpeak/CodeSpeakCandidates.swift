import Foundation

extension CodeSpeakRewriter {
    static func candidate(at index: Int, chunks: [SpeakChunk]) -> Candidate? {
        if let backtick = backtickCandidate(at: index, chunks: chunks) { return backtick }
        if let identifier = identifierCandidate(at: index, chunks: chunks) { return identifier }
        if let symbol = symbolCandidate(at: index, chunks: chunks) { return symbol }
        if let arrow = arrowCandidate(at: index, chunks: chunks) { return arrow }
        if let path = pathCandidate(at: index, chunks: chunks) { return path }
        return flagCandidate(at: index, chunks: chunks)
    }

    static func backtickCandidate(at index: Int, chunks: [SpeakChunk]) -> Candidate? {
        guard chunks[index].core.lowercased() == "backtick" else { return nil }
        var close = index + 1
        while close < chunks.count, chunks[close].core.lowercased() != "backtick" { close += 1 }
        guard close < chunks.count, close > index + 1, close - index <= 40 else { return nil }
        let content = chunks[index + 1...close - 1].map(\.text).joined(separator: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let body = "`" + content + "`"
        return Candidate(last: close, body: body, ruleID: "backtick", protect: body)
    }

    static func identifierCandidate(at index: Int, chunks: [SpeakChunk]) -> Candidate? {
        guard let style = IdentifierStyle(rawValue: chunks[index].core.lowercased()),
              index + 1 < chunks.count, chunks[index + 1].core.lowercased() == "case",
              !endsSentence(chunks[index + 1].suffix),
              let last = clauseEnd(chunks, from: index + 2) else { return nil }
        let words = chunks[(index + 2)...last].map(\.core)
        guard words.count <= 8, words.allSatisfy(isIdentifierWord) else { return nil }
        if words.count == 1 {
            let word = words[0]
            guard CodeSpeakCommands.singleWordIdentifiers.contains(word.lowercased())
                || identifierLike(word) else { return nil }
        }
        guard let body = CodeSpeakCommands.identifier(from: words, style: style) else { return nil }
        return Candidate(last: last, body: body, ruleID: style.ruleID, protect: body)
    }

    static func symbolCandidate(at index: Int, chunks: [SpeakChunk]) -> Candidate? {
        for command in CodeSpeakCommands.symbols {
            guard index + command.pattern.count <= chunks.count else { continue }
            let matches = command.pattern.enumerated().allSatisfy { offset, word in
                chunks[index + offset].core.lowercased() == word
            }
            guard matches, hasOpposite(command, in: chunks) else { continue }
            return Candidate(last: index + command.pattern.count - 1, body: command.body,
                             ruleID: command.ruleID, protect: nil, join: command.join)
        }
        return nil
    }

    /// Bracket-like symbols only convert when the matching close (or open)
    /// command is present in the same line. "open parenthesis in the document"
    /// is prose; "open paren value close paren" is code.
    static func hasOpposite(_ command: SymbolCommand, in chunks: [SpeakChunk]) -> Bool {
        guard command.join != .none else { return true }
        let opposite: String
        if command.ruleID.hasPrefix("symbol.open") {
            opposite = command.ruleID.replacingOccurrences(of: "symbol.open", with: "symbol.close")
        } else if command.ruleID.hasPrefix("symbol.close") {
            opposite = command.ruleID.replacingOccurrences(of: "symbol.close", with: "symbol.open")
        } else {
            return true
        }
        let patterns = CodeSpeakCommands.symbols.filter { $0.ruleID == opposite }.map(\.pattern)
        guard !patterns.isEmpty else { return true }
        for pattern in patterns where pattern.count <= chunks.count {
            for start in 0...(chunks.count - pattern.count) {
                let matches = pattern.enumerated().allSatisfy { offset, word in
                    chunks[start + offset].core.lowercased() == word
                }
                if matches { return true }
            }
        }
        return false
    }

    static func arrowCandidate(at index: Int, chunks: [SpeakChunk]) -> Candidate? {
        guard chunks[index].core.lowercased() == "arrow", codeContext(chunks, at: index) else { return nil }
        return Candidate(last: index, body: "->", ruleID: "symbol.arrow", protect: nil)
    }

    static func pathCandidate(at index: Int, chunks: [SpeakChunk]) -> Candidate? {
        guard let first = plainWord(chunks[index].core), isPathSegment(first) else { return nil }
        var pieces = [first]
        var separators: [String] = []
        var last = index

        while last + 2 < chunks.count, !endsClause(chunks[last].suffix),
              let separator = CodeSpeakParser.separator(chunks[last + 1].core),
              let next = plainWord(chunks[last + 2].core), isPathSegment(next) {
            pieces.append(next)
            separators.append(separator)
            last += 2
            if pieces.count > 8 { return nil }
        }
        guard !separators.isEmpty else { return nil }

        let slashCount = separators.filter { $0 == "/" || $0 == "\\" }.count
        let dotCount = separators.filter { $0 == "." }.count
        let extensionName = pieces.last?.lowercased() ?? ""
        guard slashCount > 0 || dotCount >= 2
            || CodeSpeakCommands.fileExtensions.contains(extensionName) else { return nil }

        var body = pieces[0]
        for (offset, separator) in separators.enumerated() {
            body += separator + pieces[offset + 1]
        }
        guard body.count <= 200 else { return nil }
        return Candidate(last: last, body: body, ruleID: "path", protect: body)
    }

    static func flagCandidate(at index: Int, chunks: [SpeakChunk]) -> Candidate? {
        let word = chunks[index].core.lowercased()
        if word == "double", index + 2 < chunks.count,
           chunks[index + 1].core.lowercased() == "dash",
           let name = plainWord(chunks[index + 2].core), isFlagName(name) {
            let body = "--" + name.lowercased()
            return Candidate(last: index + 2, body: body, ruleID: "flag.long", protect: body)
        }
        if word == "dash" {
            if index + 2 < chunks.count, chunks[index + 1].core.lowercased() == "dash",
               let name = plainWord(chunks[index + 2].core), isFlagName(name) {
                let body = "--" + name.lowercased()
                return Candidate(last: index + 2, body: body, ruleID: "flag.long", protect: body)
            }
            if index + 1 < chunks.count,
               let name = plainWord(chunks[index + 1].core), isShortFlag(name) {
                let body = "-" + name.lowercased()
                return Candidate(last: index + 1, body: body, ruleID: "flag.short", protect: body)
            }
        }
        if word == "single", index + 2 < chunks.count,
           chunks[index + 1].core.lowercased() == "dash",
           let name = plainWord(chunks[index + 2].core), isShortFlag(name) {
            let body = "-" + name.lowercased()
            return Candidate(last: index + 2, body: body, ruleID: "flag.short", protect: body)
        }
        return nil
    }

    // MARK: - Token rules

    static func clauseEnd(_ chunks: [SpeakChunk], from start: Int, limit: Int = 8) -> Int? {
        guard start < chunks.count else { return nil }
        var index = start
        while index < chunks.count {
            guard CodeSpeakParser.isWord(chunks[index].core) else { return nil }
            let count = index - start + 1
            if endsClause(chunks[index].suffix) {
                return count <= limit ? index : nil
            }
            if count > limit { return nil }
            index += 1
        }
        return index - start <= limit ? index - 1 : nil
    }

    static func isIdentifierWord(_ core: String) -> Bool {
        guard plainWord(core) != nil else { return false }
        let lower = core.lowercased()
        return !CodeSpeakCommands.stopwords.contains(lower) && !CodeSpeakParser.isSeparator(lower)
            && lower != "backtick" && !IdentifierStyle.allCases.contains { $0.commandWord == lower }
    }

    static func isPathSegment(_ core: String) -> Bool {
        guard plainWord(core) != nil else { return false }
        let lower = core.lowercased()
        return !CodeSpeakCommands.stopwords.contains(lower) && !CodeSpeakParser.isSeparator(lower)
            && lower != "backtick" && lower != "arrow" && lower != "dash"
    }

    static func isFlagName(_ core: String) -> Bool {
        guard plainWord(core) != nil else { return false }
        return !CodeSpeakCommands.stopwords.contains(core.lowercased())
    }

    static func isShortFlag(_ core: String) -> Bool {
        guard core.count == 1, let character = core.first else { return false }
        return character.isLetter || character.isNumber
    }

    static func plainWord(_ core: String) -> String? {
        guard !core.isEmpty, core.count <= 40,
              core.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            return nil
        }
        return core
    }

    static func endsClause(_ suffix: String) -> Bool {
        suffix.contains { ".,;:!?".contains($0) }
    }

    static func endsSentence(_ suffix: String) -> Bool {
        suffix.contains { ".,;!?".contains($0) }
    }

    static func codeContext(_ chunks: [SpeakChunk], at index: Int) -> Bool {
        if index > 0, identifierLike(chunks[index - 1].core) { return true }
        if index + 1 < chunks.count, identifierLike(chunks[index + 1].core) { return true }
        // "src slash main dot ts arrow app" is a path even though the token
        // immediately before the arrow is just "ts".
        let lower = max(0, index - 4)
        if index > 0 {
            for offset in lower..<index where CodeSpeakParser.isSeparator(chunks[offset].core) {
                return true
            }
        }
        if index + 1 < chunks.count {
            for offset in (index + 1)..<min(chunks.count, index + 5)
            where CodeSpeakParser.isSeparator(chunks[offset].core) {
                return true
            }
        }
        return false
    }

    static func identifierLike(_ core: String) -> Bool {
        if core.contains("_") || core.contains("/") || core.contains(".") || core.contains("-") {
            return true
        }
        let characters = Array(core)
        guard characters.count > 1 else { return false }
        for position in 1..<characters.count
        where characters[position].isUppercase && characters[position - 1].isLowercase {
            return true
        }
        return false
    }
}
