import Foundation
import SuperflowKernel

public struct CodeAwareOutput: Sendable, Equatable {
    public var text: String
    public var edits: [TextEdit]
    public var protected: Set<String>
    public init(text: String, edits: [TextEdit], protected: Set<String>) {
        self.text = text
        self.edits = edits
        self.protected = protected
    }
}

/// Deterministic filename, extension and project-path cleanup.
///
/// The rewriter never reads the filesystem. It only sees the injected project
/// context and its bounded index. Ambiguous, protected or out-of-root spans are
/// left exactly as dictated.
public enum CodeAwareRewriter {
    struct Candidate {
        let last: Int
        let body: String
        let ruleID: String
        let protect: String?
    }

    public static func rewrite(_ text: String, protected: Protected,
                               project: ProjectContext?, coding: Bool,
                               settings: CodeAwareSettings,
                               stageID: String = "codeAware") -> CodeAwareOutput {
        rewrite(text, protected: protected, project: project, coding: coding, settings: settings,
                index: ProjectPathIndex(paths: project?.paths ?? []), stageID: stageID)
    }

    static func rewrite(_ text: String, protected: Protected,
                        project: ProjectContext?, coding: Bool,
                        settings: CodeAwareSettings, index: ProjectPathIndex,
                        stageID: String) -> CodeAwareOutput {
        guard settings.enabled else {
            return CodeAwareOutput(text: text, edits: [], protected: [])
        }
        let lines = text.components(separatedBy: "\n")
        var outLines: [String] = []
        var edits: [TextEdit] = []
        var produced = Set<String>()
        var inputLineStart = 0
        var outputLineStart = 0

        for (lineIndex, line) in lines.enumerated() {
            let isLast = lineIndex == lines.count - 1
            let rewritten = rewriteLine(line, protected: protected, project: project,
                                        coding: coding, settings: settings, index: index,
                                        stageID: stageID, inputLineStart: inputLineStart,
                                        outputLineStart: outputLineStart, produced: &produced,
                                        edits: &edits)
            outLines.append(rewritten)
            inputLineStart += line.utf16.count + (isLast ? 0 : 1)
            outputLineStart += rewritten.utf16.count + (isLast ? 0 : 1)
        }
        return CodeAwareOutput(text: outLines.joined(separator: "\n"), edits: edits,
                               protected: produced)
    }

    private static func rewriteLine(_ line: String, protected: Protected,
                                    project: ProjectContext?, coding: Bool,
                                    settings: CodeAwareSettings, index: ProjectPathIndex,
                                    stageID: String, inputLineStart: Int, outputLineStart: Int,
                                    produced: inout Set<String>,
                                    edits: inout [TextEdit]) -> String {
        let tokens = Tokenizer.tokens(in: line)
        guard !tokens.isEmpty else { return line }
        let ranges = protected.ranges(in: line, detect: true)
        var out = ""
        var cursor = line.startIndex
        var outputUTF16 = 0
        var i = 0

        while i < tokens.count {
            let token = tokens[i]
            guard token.range.lowerBound >= cursor else { i += 1; continue }
            if overlaps(token.range, ranges) {
                out += line[cursor..<token.range.upperBound]
                outputUTF16 += line[cursor..<token.range.upperBound].utf16.count
                cursor = token.range.upperBound
                i += 1
                continue
            }
            guard let candidate = candidate(tokens: tokens, at: i, protectedRanges: ranges,
                                            project: project, coding: coding,
                                            settings: settings, index: index) else {
                out += line[cursor..<token.range.upperBound]
                outputUTF16 += line[cursor..<token.range.upperBound].utf16.count
                cursor = token.range.upperBound
                i += 1
                continue
            }

            let start = tokens[i].range.lowerBound
            let end = tokens[candidate.last].range.upperBound
            guard start >= cursor, !overlaps(start..<end, ranges) else {
                out += line[cursor..<token.range.upperBound]
                outputUTF16 += line[cursor..<token.range.upperBound].utf16.count
                cursor = token.range.upperBound
                i += 1
                continue
            }
            let lead = line[cursor..<start]
            out += lead
            outputUTF16 += lead.utf16.count
            let outputStart = outputStartOffset(outputLineStart, outputUTF16)
            out += candidate.body
            outputUTF16 += candidate.body.utf16.count
            let local = NSRange(start..<end, in: line)
            edits.append(TextEdit(stageID: stageID, ruleID: candidate.ruleID, kind: .replace,
                                  input: TextSpan(location: inputLineStart + local.location,
                                                  length: local.length),
                                  output: TextSpan(location: outputStart,
                                                   length: candidate.body.utf16.count)))
            if let literal = candidate.protect { produced.insert(literal) }
            cursor = end
            i = candidate.last + 1
        }
        out += line[cursor...]
        return out
    }

    private static func outputStartOffset(_ lineStart: Int, _ local: Int) -> Int { lineStart + local }

    private static func candidate(tokens: [Token], at i: Int, protectedRanges: [Range<String.Index>],
                                  project: ProjectContext?, coding: Bool,
                                  settings: CodeAwareSettings, index: ProjectPathIndex) -> Candidate? {
        if settings.normalizeFilenames {
            if let dot = dotExtension(tokens, at: i) { return dot }
            if let bare = bareExtension(tokens, at: i, coding: coding) { return bare }
            if let slug = slugFilename(tokens, at: i, coding: coding) { return slug }
        }
        if settings.resolvePaths, project?.resolvesPaths == true, coding,
           !index.isEmpty, let path = projectPath(tokens, at: i, index: index) {
            return path
        }
        return nil
    }

    /// "hero dot t s x", "config dot json", "prospect main engine dot ts".
    private static func dotExtension(_ tokens: [Token], at i: Int) -> Candidate? {
        guard CodeAwareTables.isPlainWord(tokens[i].core), tokens[i].trail.isEmpty else { return nil }
        let first = tokens[i].core.lowercased()
        guard !CodeAwareTables.extensions.contains(first),
              !CodeAwareTables.stemStopwords.contains(first) else { return nil }
        var stem = [first]
        var j = i + 1
        while j < tokens.count, stem.count < 3 {
            let core = tokens[j].core.lowercased()
            guard CodeAwareTables.isPlainWord(tokens[j].core),
                  !CodeAwareTables.stemStopwords.contains(core),
                  tokens[j].trail.isEmpty else { break }
            stem.append(core)
            j += 1
        }
        guard j < tokens.count, tokens[j].core.lowercased() == "dot",
              tokens[j].trail.isEmpty else { return nil }
        guard let extensionName = extensionAfterDot(tokens, from: j + 1) else { return nil }
        let body = stem.joined(separator: "-") + "." + extensionName.name
            + tokens[extensionName.last].trail
        return Candidate(last: extensionName.last, body: body, ruleID: "filename.extension",
                         protect: stem.joined(separator: "-") + "." + extensionName.name)
    }

    private static func extensionAfterDot(_ tokens: [Token], from start: Int) -> (name: String, last: Int)? {
        guard start < tokens.count else { return nil }
        let first = tokens[start].core.lowercased()
        // A single spoken word that is already an extension: "json", "swift".
        if first.count > 1, CodeAwareTables.extensions.contains(first) {
            return (first, start)
        }
        // Otherwise consume the whole contiguous run of spelled-out letters and
        // only accept it when the complete run is an extension. Taking the first
        // prefix match would cut "t s x" down to "ts" and leave the "x".
        var letters = ""
        var last = start - 1
        var j = start
        while j < tokens.count, letters.count < 6,
              tokens[j].core.count == 1, let character = tokens[j].core.first,
              character.isLetter, tokens[j].trail.isEmpty {
            letters += character.lowercased()
            last = j
            j += 1
        }
        guard last >= start, CodeAwareTables.extensions.contains(letters) else { return nil }
        return (letters, last)
    }

    /// "hero tsx" -> hero.tsx, only in a coding session and only when the
    /// extension ends the clause. "renders tsx files" stays prose.
    private static func bareExtension(_ tokens: [Token], at i: Int, coding: Bool) -> Candidate? {
        guard coding, i + 1 < tokens.count else { return nil }
        guard CodeAwareTables.isPlainWord(tokens[i].core), tokens[i].trail.isEmpty,
              !CodeAwareTables.stemStopwords.contains(tokens[i].core.lowercased()),
              !CodeAwareTables.extensions.contains(tokens[i].core.lowercased()) else { return nil }
        let extensionName = tokens[i + 1].core.lowercased()
        guard CodeAwareTables.extensions.contains(extensionName) else { return nil }
        let atEnd = i + 2 >= tokens.count
            || CodeAwareTables.endsClause(tokens[i + 1].trail)
        guard atEnd else { return nil }
        let body = tokens[i].core + "." + extensionName + tokens[i + 1].trail
        return Candidate(last: i + 1, body: body, ruleID: "filename.extension",
                         protect: tokens[i].core + "." + extensionName)
    }

    /// "the file prospect main engine" -> "the file prospect-main-engine".
    private static func slugFilename(_ tokens: [Token], at i: Int, coding: Bool) -> Candidate? {
        guard coding, i > 0 else { return nil }
        let previous = tokens[i - 1].core.lowercased()
        guard ["file", "filename", "called", "named"].contains(previous) else { return nil }
        var words: [String] = []
        var last = i
        var j = i
        while j < tokens.count, words.count < 3 {
            let core = tokens[j].core.lowercased()
            guard CodeAwareTables.isPlainWord(tokens[j].core),
                  !CodeAwareTables.stemStopwords.contains(core),
                  !CodeAwareTables.extensions.contains(core) else { break }
            words.append(core)
            last = j
            j += 1
            if CodeAwareTables.endsClause(tokens[last].trail) { break }
        }
        guard words.count >= 2 else { return nil }
        let body = words.joined(separator: "-") + tokens[last].trail
        return Candidate(last: last, body: body, ruleID: "filename.slug",
                         protect: words.joined(separator: "-"))
    }

    /// Resolves a spoken phrase only when the bounded index has exactly one
    /// path whose word window matches the whole phrase.
    private static func projectPath(_ tokens: [Token], at i: Int,
                                    index: ProjectPathIndex) -> Candidate? {
        var words: [String] = []
        var positions: [Int] = []
        var trailingDirectory: Int?
        var j = i
        while j < tokens.count, words.count < 6 {
            let core = tokens[j].core.lowercased()
            if CodeAwareTables.separators.contains(core) {
                j += 1
                continue
            }
            if CodeAwareTables.directoryWords.contains(core) {
                if !words.isEmpty { trailingDirectory = j }
                break
            }
            guard CodeAwareTables.isPlainWord(tokens[j].core),
                  !CodeAwareTables.stemStopwords.contains(core) else { break }
            words.append(core)
            positions.append(j)
            if CodeAwareTables.endsClause(tokens[j].trail) { break }
            j += 1
        }
        guard !words.isEmpty else { return nil }

        // The whole spoken run must match the path. A prefix match would turn
        // "prospect main engine notes" into a path plus a stray word.
        var chosen: (length: Int, path: String)?
        if !words.isEmpty {
            var matches = index.matches(words.map { Substring($0) })
            if trailingDirectory != nil {
                // "folder" is a directory intent: never resolve it to a file.
                matches = matches.filter { $0.hasSuffix("/") }
                if matches.isEmpty { return nil }
            }
            if !matches.isEmpty {
                guard matches.count == 1 else { return nil } // ambiguous: leave it alone
                chosen = (words.count, matches[0])
            }
        }
        guard let chosen else { return nil }
        if chosen.length == 1 {
            let word = words[0]
            guard word.count >= 3, !CodeAwareTables.commonEnglish.contains(word),
                  !CodeAwareTables.extensions.contains(word) else { return nil }
        }
        var last = positions[chosen.length - 1]
        if chosen.length == words.count, let trailingDirectory { last = trailingDirectory }
        let body = chosen.path + tokens[last].trail
        return Candidate(last: last, body: body, ruleID: "path.project", protect: chosen.path)
    }

    private static func overlaps(_ range: Range<String.Index>,
                                 _ ranges: [Range<String.Index>]) -> Bool {
        ranges.contains { $0.overlaps(range) }
    }
}
