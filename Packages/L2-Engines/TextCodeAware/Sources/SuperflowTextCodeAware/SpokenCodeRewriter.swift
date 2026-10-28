import Foundation
import SuperflowKernel

public enum SpokenCodeRewriter {
    struct Span {
        var core: String
        var last: Int
    }

    static let separators = ["slash": "/", "underscore": "_"]
    static let extensions = CodeAwareTables.extensions.union([
        "rb", "cs", "php", "mdx", "zip", "dmg", "app", "gz",
        "com", "org", "net", "io", "dev", "ai", "co", "edu", "gov",
    ])
    static let domains: Set<String> = ["com", "org", "net", "io", "dev", "ai", "co", "app", "edu", "gov"]
    static let mailCues: Set<String> = ["email", "emailed", "mail", "send", "sent", "cc", "bcc", "contact", "reach", "address", "ping", "forward", "to"]
    static let corrections = [["no", "wait"], ["no", "sorry"], ["wait", "no"], ["i", "mean"], ["i", "meant"], ["make", "that"], ["sorry"], ["actually"]]

    public static func rewrite(_ text: String, protected: Protected = Protected(),
                               stageID: String = "spokenCode") -> CodeAwareOutput {
        var lines: [String] = []
        var edits: [TextEdit] = []
        var literals = Set<String>()
        var inputOffset = 0
        var outputOffset = 0
        for line in text.components(separatedBy: "\n") {
            let tokens = Tokenizer.tokens(in: line)
            let ranges = protected.ranges(in: line, detect: false)
            var output = ""
            var cursor = line.startIndex
            var i = 0
            while i < tokens.count {
                let token = tokens[i]
                guard !ranges.contains(where: { $0.overlaps(token.range) }) else {
                    output += line[cursor..<token.range.upperBound]
                    cursor = token.range.upperBound
                    i += 1
                    continue
                }
                guard var span = assembled(tokens, i) else {
                    output += line[cursor..<token.range.upperBound]
                    cursor = token.range.upperBound
                    i += 1
                    continue
                }
                while !tokens[span.last].endsClause {
                    if let replacement = corrected(tokens, span: span) {
                        span = replacement
                    } else if let next = assembled(tokens, span.last + 1),
                              next.core.lowercased() == span.core.lowercased() {
                        span = next
                    } else {
                        break
                    }
                }
                let end = tokens[span.last].range.upperBound
                guard !ranges.contains(where: { $0.overlaps(token.range.lowerBound..<end) }) else {
                    output += line[cursor..<token.range.upperBound]
                    cursor = token.range.upperBound
                    i += 1
                    continue
                }
                output += line[cursor..<token.range.lowerBound]
                let start = outputOffset + output.utf16.count
                let replacement = token.lead + span.core + tokens[span.last].trail
                output += replacement
                literals.insert(span.core)
                let original = String(line[token.range.lowerBound..<end])
                if original != replacement {
                    let local = NSRange(token.range.lowerBound..<end, in: line)
                    edits.append(TextEdit(stageID: stageID, ruleID: "spoken.code", kind: .replace,
                                          input: TextSpan(location: inputOffset + local.location, length: local.length),
                                          output: TextSpan(location: start, length: replacement.utf16.count)))
                }
                cursor = end
                i = span.last + 1
            }
            output += line[cursor...]
            lines.append(output)
            inputOffset += line.utf16.count + 1
            outputOffset += output.utf16.count + 1
        }
        return CodeAwareOutput(text: lines.joined(separator: "\n"), edits: edits, protected: literals)
    }

    static func identifier(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    static func code(_ s: String) -> Bool {
        s.contains("/") || s.contains("_") || s.contains("@")
            || (s.contains(".") && s.contains(where: \.isLetter))
    }

    static func shape(_ s: String) -> Bool {
        s.contains("_") || s.contains("-") || s.contains(where: \.isNumber)
            || s.dropFirst().contains(where: \.isUppercase)
    }

    static func assembled(_ w: [Token], _ i: Int) -> Span? {
        guard i < w.count else { return nil }
        if let span = email(w, i) ?? chain(w, i) { return span }
        if code(w[i].core) { return Span(core: w[i].core, last: i) }
        return nil
    }

    static func chain(_ w: [Token], _ i: Int) -> Span? {
        guard identifier(w[i].core) else { return nil }
        var body = w[i].core
        var j = i + 1
        var count = 0
        var codeShape = shape(body)
        var hasExtension = false
        while j + 1 < w.count, !w[j - 1].endsClause, !w[j].endsClause,
              let separator = separators[w[j].core.lowercased()], identifier(w[j + 1].core),
              w[j + 1].lead.isEmpty {
            body += separator + w[j + 1].core
            codeShape = codeShape || shape(w[j + 1].core) || separator == "_"
            count += 1
            j += 2
        }
        for _ in 0..<2 {
            guard j < w.count, !w[j - 1].endsClause,
                  w[j].core.lowercased() == "dot", !w[j].endsClause,
                  let ext = extensionAt(w, j + 1) else { break }
            body += "." + ext.core
            j = ext.last + 1
            hasExtension = true
        }
        guard hasExtension || count >= 2 || (count >= 1 && codeShape) else { return nil }
        return Span(core: body, last: j - 1)
    }

    static func extensionAt(_ w: [Token], _ start: Int) -> Span? {
        guard start < w.count, w[start].lead.isEmpty else { return nil }
        let first = w[start].core.lowercased()
        if first.count > 1, extensions.contains(first) { return Span(core: first, last: start) }
        var letters = ""
        var best: Span?
        var j = start
        while j < w.count, j - start < 5, w[j].core.count == 1,
              let letter = w[j].core.first, letter.isLetter, w[j].lead.isEmpty {
            letters += letter.lowercased()
            if extensions.contains(letters) { best = Span(core: letters, last: j) }
            if w[j].endsClause { break }
            j += 1
        }
        return best
    }

    static func email(_ w: [Token], _ i: Int) -> Span? {
        guard i + 4 < w.count, identifier(w[i].core), w[i + 1].core.lowercased() == "at",
              identifier(w[i + 2].core), w[i + 3].core.lowercased() == "dot",
              domains.contains(w[i + 4].core.lowercased()),
              w[i..<(i + 4)].allSatisfy({ !$0.endsClause }),
              w[max(0, i - 4)..<i].contains(where: { mailCues.contains($0.core.lowercased()) }) else { return nil }
        var body = w[i].core + "@" + w[i + 2].core + "." + w[i + 4].core.lowercased()
        var j = i + 5
        while j + 1 < w.count, !w[j - 1].endsClause, !w[j].endsClause,
              w[j].core.lowercased() == "dot", domains.contains(w[j + 1].core.lowercased()) {
            body += "." + w[j + 1].core.lowercased()
            j += 2
        }
        return Span(core: body, last: j - 1)
    }

    static func corrected(_ w: [Token], span: Span) -> Span? {
        for marker in corrections {
            let start = span.last + 1
            let end = start + marker.count
            guard end < w.count,
                  marker.enumerated().allSatisfy({
                      w[start + $0.offset].core.lowercased() == $0.element
                          && !w[start + $0.offset].endsClause
                  }),
                  let next = assembled(w, end),
                  fileExtension(span.core) == fileExtension(next.core) else { continue }
            return next
        }
        return nil
    }

    static func fileExtension(_ code: String) -> String? {
        code.contains(".") ? code.split(separator: ".").last.map { $0.lowercased() } : nil
    }
}
