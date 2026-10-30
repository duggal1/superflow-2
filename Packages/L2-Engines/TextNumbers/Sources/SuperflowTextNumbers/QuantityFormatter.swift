import Foundation

enum NumberSuffix { case none, percent, currency(String), model }

struct QuantityFormatter {
    let config: TextNumbersConfig

    func render(_ q: ParsedQuantity, suffix: NumberSuffix, yearCue: Bool) -> String? {
        let v = q.value
        switch suffix {
        case .percent:
            return plain(v) + "%"
        case .currency(let symbol):
            return symbol + currency(q)
        case .model:
            guard let s = q.largestScale,
                  let a = abbreviate(v, scale: s, stepDown: false, lowerK: false) else { return grouped(v, indian: false) }
            return a
        case .none:
            if q.isOrdinal {
                guard v >= 10 else { return nil }
                return grouped(v, indian: useIndian(q)) + ordinalSuffix(v)
            }
            if q.impliedOne { return nil }
            if let s = q.largestScale {
                if s >= 1_000_000, !NumberLexicon.indianScales.contains(s),
                   let a = abbreviate(v, scale: s, stepDown: true, lowerK: false) { return a }
                return grouped(v, indian: useIndian(q))
            }
            if q.hasFraction { return plain(v) }
            guard v >= Decimal(config.smallNumberThreshold) else { return nil }
            let p = plain(v)
            if yearCue, p.count == 4, let n = Int(p), (1900...2099).contains(n) { return p }
            return grouped(v, indian: useIndian(q))
        }
    }

    private func currency(_ q: ParsedQuantity) -> String {
        let v = q.value
        if config.currencyStyle == .abbreviated, let s = q.largestScale {
            if let name = NumberLexicon.indianScaleNames[s] {
                let m = v / Decimal(s)
                if isClean(m) { return plain(m) + " " + name }
            } else if v >= 1_000, let a = abbreviate(v, scale: s, stepDown: true, lowerK: true) {
                return a
            }
        }
        if q.hasFraction, q.largestScale == nil { return fixedTwo(v) }
        return grouped(v, indian: useIndian(q))
    }

    private func fixedTwo(_ v: Decimal) -> String {
        let p = plain(v)
        guard let dot = p.firstIndex(of: ".") else { return p }
        let decimals = p.distance(from: dot, to: p.endIndex) - 1
        return decimals >= 2 ? p : p + String(repeating: "0", count: 2 - decimals)
    }

    private func abbreviate(_ v: Decimal, scale: UInt64, stepDown: Bool, lowerK: Bool) -> String? {
        let table = NumberLexicon.abbreviations
        guard var idx = table.firstIndex(where: { $0.scale == scale }) else { return nil }
        var m = v / Decimal(table[idx].scale)
        if stepDown { while m < 1, idx < table.count - 1 { idx += 1; m = v / Decimal(table[idx].scale) } }
        while m >= 1000, idx > 0 { idx -= 1; m = v / Decimal(table[idx].scale) }
        guard isClean(m) else { return nil }
        var label = table[idx].label
        if lowerK && label == "K" { label = "k" }
        return plain(m) + label
    }

    private func isClean(_ m: Decimal) -> Bool {
        (plain(m).split(separator: ".").dropFirst().first?.count ?? 0) <= 3
    }

    func plain(_ d: Decimal) -> String {
        var s = "\(d)"
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    private func useIndian(_ q: ParsedQuantity) -> Bool {
        switch config.grouping {
        case .indian: return true
        case .western: return false
        case .auto: return q.largestScale.map(NumberLexicon.indianScales.contains) == true
        }
    }

    private func grouped(_ v: Decimal, indian: Bool) -> String {
        let parts = plain(v).split(separator: ".", omittingEmptySubsequences: false)
        let ip = String(parts[0])
        let fp = parts.count > 1 ? "." + parts[1] : ""
        guard ip.count > 3 else { return ip + fp }
        var result = ""
        var count = 0, size = 3
        for ch in ip.reversed() {
            if count == size { result.append(","); count = 0; if indian { size = 2 } }
            result.append(ch); count += 1
        }
        return String(result.reversed()) + fp
    }

    private func ordinalSuffix(_ v: Decimal) -> String {
        guard let n = Int(plain(v)) else { return "th" }
        if (11...13).contains(n % 100) { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
