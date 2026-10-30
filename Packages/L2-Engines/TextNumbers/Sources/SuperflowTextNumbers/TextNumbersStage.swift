import Foundation
import SuperflowKernel

public struct TextNumbersStage: TextStage {
    public let name = "TextNumbers"
    private let config: TextNumbersConfig
    public init(config: TextNumbersConfig = .init()) { self.config = config }

    private struct Replacement { let words: [Word]; let consumed: Int }

    public func apply(_ draft: TextDraft) -> TextDraft {
        let words = Self.splitHyphenated(draft.words)
        var out: [Word] = []
        out.reserveCapacity(words.count)
        var i = 0
        while i < words.count {
            if let r = replacement(in: words, at: i) {
                out.append(contentsOf: r.words); i += r.consumed
            } else {
                out.append(words[i]); i += 1
            }
        }
        for k in out.indices where out[k].core.contains(where: \.isNumber) { out[k].isProtected = true }
        return TextDraft(words: out)
    }

    private func replacement(in w: [Word], at i: Int) -> Replacement? {
        guard w[i].isConvertible else { return nil }
        if let r = year(in: w, at: i) ?? digitRun(in: w, at: i) { return r }
        guard let q = QuantityParser.parse(w, at: i) else { return nil }

        let end = i + q.consumed
        let (suffix, extra) = Self.suffix(after: end, in: w, for: q)
        let cue = i > 0 && w[i - 1].trail.isEmpty && NumberLexicon.yearCues.contains(w[i - 1].key)
        guard let text = QuantityFormatter(config: config).render(q, suffix: suffix, yearCue: cue) else { return nil }

        let first = w[i], last = w[end + extra - 1]
        return Replacement(words: build(text, first: first, last: last, dropLead: q.literalCurrency != nil),
                           consumed: q.consumed + extra)
    }

    private func build(_ text: String, first: Word, last: Word, dropLead: Bool = false) -> [Word] {
        var ws = Word.tokenize((dropLead ? "" : first.lead) + text + last.trail)
        for k in ws.indices { ws[k].isProtected = true }
        if !ws.isEmpty { ws[0].glue = first.glue; ws[0].pauseBefore = first.pauseBefore }
        return ws
    }

    private static func suffix(after end: Int, in w: [Word], for q: ParsedQuantity) -> (NumberSuffix, Int) {
        if let sym = q.literalCurrency { return (.currency(sym), 0) }
        guard !q.isOrdinal, end < w.count, w[end - 1].trail.isEmpty else { return (.none, 0) }
        let next = w[end]
        guard next.isConvertible else { return (.none, 0) }
        if next.lead.isEmpty {
            if next.key == "percent" { return (.percent, 1) }
            if let sym = NumberLexicon.currencies[next.key] { return (.currency(sym), 1) }
        }
        let attached = next.lead.isEmpty || (next.glue && next.lead == "-")
        if attached, NumberLexicon.modelNouns.contains(next.key),
           let s = q.largestScale, s >= 1_000_000, !NumberLexicon.indianScales.contains(s) {
            return (.model, 0)
        }
        return (.none, 0)
    }

    private func year(in w: [Word], at i: Int) -> Replacement? {
        guard let hi = NumberLexicon.centuries[w[i].key], w[i].trail.isEmpty, i + 1 < w.count else { return nil }
        let b = w[i + 1]
        guard b.isConvertible, b.lead.isEmpty else { return nil }

        func unit(at j: Int) -> Int? {
            guard j < w.count, w[j].isConvertible, w[j].lead.isEmpty,
                  let u = NumberLexicon.units[w[j].key], (1...9).contains(u) else { return nil }
            return u
        }

        var lo = 0, used = 2
        if let t = NumberLexicon.tens[b.key] {
            lo = t
            if b.trail.isEmpty, let u = unit(at: i + 2) { lo += u; used = 3 }
        } else if let t = NumberLexicon.units[b.key], t >= 10 {
            lo = t
        } else if b.key == "oh", b.trail.isEmpty, let u = unit(at: i + 2) {
            lo = u; used = 3
        } else {
            return nil
        }
        if i + used < w.count {
            let k = w[i + used].key
            if k == "hundred" || k == "percent" || NumberLexicon.scales[k] != nil
                || NumberLexicon.currencies[k] != nil { return nil }
        }
        return Replacement(words: build(String(hi * 100 + lo), first: w[i], last: w[i + used - 1]), consumed: used)
    }

    private func digitRun(in w: [Word], at i: Int) -> Replacement? {
        var j = i
        var digits = ""
        while j < w.count, w[j].isConvertible, j == i || w[j].lead.isEmpty,
              let d = NumberLexicon.units[w[j].key], d < 10 {
            digits.append(String(d)); j += 1
            if !w[j - 1].trail.isEmpty { break }
        }
        if j < w.count, !digits.isEmpty, w[j - 1].trail.isEmpty,
           w[j].key == "hundred" || NumberLexicon.scales[w[j].key] != nil {
            digits.removeLast(); j -= 1
        }
        guard digits.count >= max(2, config.minDigitRun) else { return nil }
        return Replacement(words: build(digits, first: w[i], last: w[j - 1]), consumed: j - i)
    }

    private static func splitHyphenated(_ words: [Word]) -> [Word] {
        var out: [Word] = []
        out.reserveCapacity(words.count)
        for w in words {
            guard w.isConvertible, w.core.contains("-"), !w.core.hasPrefix("-"), !w.core.hasSuffix("-") else {
                out.append(w); continue
            }
            let parts = w.core.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { out.append(w); continue }
            let a = parts[0].lowercased(), b = parts[1].lowercased()

            let tensUnit = NumberLexicon.tens[a] != nil
                && (NumberLexicon.units[b].map { (1...9).contains($0) } == true || NumberLexicon.ordinalUnits[b].map { $0 < 10 } == true)
            let scaleNoun = NumberLexicon.scales[a].map { $0 >= 1_000 } == true && NumberLexicon.modelNouns.contains(b)

            if tensUnit {
                out.append(Word(lead: w.lead, core: parts[0], isProtected: w.isProtected, glue: w.glue, pauseBefore: w.pauseBefore, pause: w.pause))
                out.append(Word(core: parts[1], trail: w.trail, isProtected: w.isProtected, pause: w.pause))
            } else if scaleNoun {
                out.append(Word(lead: w.lead, core: parts[0], isProtected: w.isProtected, glue: w.glue, pauseBefore: w.pauseBefore, pause: w.pause))
                out.append(Word(lead: "-", core: parts[1], trail: w.trail, isProtected: w.isProtected, glue: true, pause: w.pause))
            } else {
                out.append(w)
            }
        }
        return out
    }
}
