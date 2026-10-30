import Foundation
import SuperflowKernel
import SuperflowPorts

/// Pure, deterministic, streaming line formatter.
/// Carry-over is one unfinished sentence plus at most one tentative block, so memory is O(block).
public struct LineFormatter: Sendable {
    public var settings: LineFormatSettings
    private var carry = ""
    private var current: [String] = []
    private var currentWords = 0
    private var pending: [String] = []
    private var canMergeIntoLast = true
    private var started = false

    public init(settings: LineFormatSettings = LineFormatSettings()) {
        self.settings = settings
        self.current.reserveCapacity(8)
        self.pending.reserveCapacity(8)
    }

    public var separator: String {
        settings.breakStyle == .paragraph ? "\n\n" : "\n"
    }

    /// Feeds a chunk. Returns blocks that are final (the last block is held back for merge-at-seam).
    public mutating func feed(_ text: String, flush: Bool = false) -> [String] {
        guard !text.isEmpty else { return finish() }
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        var emitted: [String] = []
        for (i, part) in parts.enumerated() {
            let line = String(part)
            let hardEnd = i < parts.count - 1
            append(line, hardEnd: hardEnd, into: &emitted)
        }
        if flush {
            emitted.append(contentsOf: hardFlush())
        }
        return emitted
    }

    public mutating func finish() -> [String] {
        var emitted = hardFlush()
        if !pending.isEmpty {
            var last = pending.removeLast()
            if shouldAddFinalPeriod(last) { last = addFinalPeriod(last) }
            pending.append(last)
        }
        emitted.append(contentsOf: pending)
        pending.removeAll(keepingCapacity: true)
        started = false
        return emitted
    }

    /// Convenience for batch callers.
    ///
    /// Fenced code passes through untouched and inline code, paths and
    /// filenames are masked before formatting, so capitalization, punctuation
    /// spacing and sentence splitting cannot rewrite code.
    public static func format(_ text: String, settings: LineFormatSettings = LineFormatSettings(),
                              preserveLists: Bool = false) -> String {
        let separator = settings.breakStyle == .paragraph ? "\n\n" : "\n"
        var output: [String] = []
        for segment in FencedBlocks.split(text) {
            switch segment {
            case .code(let code):
                output.append(code)
            case .prose(let prose):
                var preserver = CodePreserver()
                let masked = preserver.mask(prose)
                var formatter = LineFormatter(settings: settings)
                var blocks = formatter.feed(masked)
                blocks.append(contentsOf: formatter.finish())
                let formatted = preserver.restore(preserveLists ? joinBlocks(blocks, separator: formatter.separator)
                    : blocks.joined(separator: formatter.separator))
                if !formatted.isEmpty { output.append(formatted) }
            }
        }
        return output.joined(separator: separator)
    }

    private static func joinBlocks(_ blocks: [String], separator: String) -> String {
        var output = ""
        var previous = ""
        for block in blocks {
            if !output.isEmpty {
                let nextIsItem = ListFormatter.isListLine(block)
                let followsList = ListFormatter.isListLine(previous)
                output += nextIsItem && (followsList || previous.hasSuffix(":")) ? "\n" : separator
            }
            output += block
            previous = block.components(separatedBy: "\n").last ?? block
        }
        return output
    }

    // MARK: feeding
    private mutating func append(_ line: String, hardEnd: Bool, into emitted: inout [String]) {
        let line = ListFormatter.normalize(line)
        if carry.isEmpty {
            carry = line
        } else if line.isEmpty {
            // hard boundary only
        } else if carry.last?.isWhitespace == true || line.first?.isWhitespace == true {
            carry += line
        } else {
            carry += " " + line
        }
        var local = carry
        if hardEnd {
            emitAllSentences(from: &local, final: true, into: &emitted)
            forceBreak(into: &emitted)
        } else {
            emitAllSentences(from: &local, final: false, into: &emitted)
        }
        carry = local
    }

    private mutating func emitAllSentences(from text: inout String, final: Bool, into emitted: inout [String]) {
        let (sentences, remainder) = SentenceSplitter.split(text)
        for sentence in sentences { consume(sentence, into: &emitted) }
        if final, !remainder.isEmpty {
            consume(remainder, into: &emitted)
            text = ""
        } else {
            text = remainder
        }
    }

    private mutating func consume(_ raw: String, into emitted: inout [String]) {
        let sentence = normalizeSpacing(raw)
        guard !sentence.isEmpty else { return }
        let words = wordCount(sentence)
        if currentWords > 0, currentWords + words > settings.hardMax, currentWords >= settings.minWords {
            emitCurrent(into: &emitted)
        }
        if words > settings.hardMax {
            if currentWords > 0 { emitCurrent(into: &emitted) }
            for piece in splitLongSentence(sentence) {
                emitCurrentBlock(piece, into: &emitted, allowMerge: false)
            }
            return
        }
        current.append(sentence)
        currentWords += words
        started = true
        if currentWords >= settings.minWords && currentWords <= settings.hardMax {
            emitCurrent(into: &emitted)
        }
    }

    private mutating func forceBreak(into emitted: inout [String]) {
        emitCurrent(into: &emitted, allowMerge: false)
    }

    private mutating func emitCurrent(into emitted: inout [String], allowMerge: Bool = true) {
        guard !current.isEmpty else { return }
        let block = current.joined(separator: " ")
        current.removeAll(keepingCapacity: true)
        currentWords = 0
        emitCurrentBlock(block, into: &emitted, allowMerge: allowMerge)
    }

    private mutating func emitCurrentBlock(_ block: String, into emitted: inout [String], allowMerge: Bool = true) {
        let text = finalize(block)
        guard !text.isEmpty else { return }
        if allowMerge, canMergeIntoLast, let last = pending.last,
           wordCount(last) < 8, wordCount(last) + wordCount(text) <= settings.hardMax {
            pending[pending.count - 1] = last + " " + text
            return
        }
        pending.append(text)
        canMergeIntoLast = allowMerge
        if pending.count > 1 {
            emitted.append(pending.removeFirst())
        }
        _ = started
    }

    private mutating func hardFlush() -> [String] {
        var emitted: [String] = []
        emitCurrent(into: &emitted)
        if !carry.isEmpty {
            let remainder = normalizeSpacing(carry)
            carry = ""
            if !remainder.isEmpty { consume(remainder, into: &emitted) }
            emitCurrent(into: &emitted)
        }
        return emitted
    }

    // MARK: splitting
    private func splitLongSentence(_ sentence: String) -> [String] {
        var remaining = sentence
        var pieces: [String] = []
        var guardCount = 0
        while wordCount(remaining) > settings.hardMax && guardCount < 64 {
            guardCount += 1
            let tokens = Tokenizer.tokens(in: remaining)
            guard tokens.count > settings.hardMax else { break }
            let lower = min(max(1, settings.preferredMax - 1), tokens.count - 1)
            let upper = min(max(1, settings.hardMax - 1), tokens.count - 1)
            var chosen: Int?
            if lower <= upper {
                for i in stride(from: upper, through: lower, by: -1) {
                    if tokens[i].trail.contains(";") { chosen = i; break }
                }
                if chosen == nil {
                    for i in stride(from: upper, through: lower, by: -1) {
                        if tokens[i].trail.contains(",") { chosen = i; break }
                    }
                }
            }
            let index = chosen ?? upper
            let piece = tokens[0...index].map(\.full).joined(separator: " ")
            pieces.append(normalizeSpacing(piece))
            remaining = tokens[(index + 1)...].map(\.full).joined(separator: " ")
            remaining = normalizeSpacing(remaining)
        }
        if !remaining.isEmpty { pieces.append(remaining) }
        return pieces
    }

    // MARK: text polish
    private func normalizeSpacing(_ s: String) -> String {
        var t = s
        if settings.collapseSpaces {
            t = t.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
        }
        if settings.fixPunctuationSpacing {
            t = t.replacingOccurrences(of: " +([,.;:!?])", with: "$1", options: .regularExpression)
            t = addMissingPunctuationSpaces(t)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addMissingPunctuationSpaces(_ text: String) -> String {
        let source = text as NSString
        guard let spacingRegex = try? NSRegularExpression(pattern: "[,;:!?](?=[^\\s,.;:!?])"),
              let urlRegex = try? NSRegularExpression(pattern: "(?i)(?:https?://|www\\.)[^\\s]+") else {
            return text
        }
        let searchRange = NSRange(location: 0, length: source.length)
        let urls = urlRegex.matches(in: text, range: searchRange).map(\.range)
        let punctuation = spacingRegex.matches(in: text, range: searchRange)
        var insertionOffsets: [Int] = []

        for match in punctuation {
            let location = match.range.location
            let character = source.character(at: location)
            if urls.contains(where: { NSLocationInRange(location, $0) }) { continue }
            if character == 44, location > 0, location + 1 < source.length,
               isASCIIDigit(source.character(at: location - 1)),
               isASCIIDigit(source.character(at: location + 1)) {
                continue
            }
            if character == 58, location > 0, location + 1 < source.length,
               isASCIIDigit(source.character(at: location - 1)),
               isASCIIDigit(source.character(at: location + 1)) {
                continue
            }
            insertionOffsets.append(location + 1)
        }

        let output = NSMutableString(string: text)
        for offset in insertionOffsets.reversed() { output.insert(" ", at: offset) }
        return output as String
    }

    private func isASCIIDigit(_ value: unichar) -> Bool { (48...57).contains(value) }

    private func finalize(_ s: String) -> String {
        var t = normalizeSpacing(s)
        if settings.capitalize {
            t = capitalize(t)
        }
        return t
    }

    private func capitalize(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var atStart = true
        for (i, ch) in chars.enumerated() {
            if atStart, ch.isLetter {
                out.append(Character(ch.uppercased()))
                atStart = false
                continue
            }
            out.append(ch)
            if ".?!".contains(ch) {
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                if next == nil || next!.isWhitespace { atStart = true }
            } else if ch == "\n" {
                atStart = true
            } else if !ch.isWhitespace && !"\"')]”’".contains(ch) {
                atStart = false
            }
        }
        return out.replacingOccurrences(of: "(^|\\s)i(?=\\s|$|[.,!?;:])", with: "$1I", options: .regularExpression)
    }

    private func shouldAddFinalPeriod(_ block: String) -> Bool {
        guard settings.finalPeriod else { return false }
        let total = pending.reduce(0) { $0 + wordCount($1) } + wordCount(block) + currentWords
        guard total > 3 else { return false }
        guard let last = block.last else { return false }
        return !".?!…:;".contains(last)
    }

    private func addFinalPeriod(_ block: String) -> String {
        let trimmed = block.trimmingCharacters(in: .whitespaces)
        return trimmed + "."
    }
}

public struct LineFormatStage: SuperflowPorts.TextStage {
    public let id = "lineformat"
    private let settings: LineFormatSettings
    public init(settings: LineFormatSettings) { self.settings = settings }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var output = draft
        var text = LineFormatter.format(draft.text, settings: settings, preserveLists: true)
        if settings.trailingSpace && !text.isEmpty && !text.hasSuffix(" ") { text += " " }
        output.text = text
        return output
    }
}
