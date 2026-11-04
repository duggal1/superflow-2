import Foundation

// MARK: - Numbers

private let ONES: [String: Int] = [
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
    "seventeen": 17, "eighteen": 18, "nineteen": 19,
]
private let TENS: [String: Int] = [
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
]
private let SCALE: [String: Int] = [
    "thousand": 1_000, "lakh": 100_000, "million": 1_000_000, "crore": 10_000_000,
    "billion": 1_000_000_000, "trillion": 1_000_000_000_000,
]
private let WORD_SCALES: Set<String> = ["million", "billion", "trillion", "lakh", "crore"] // kept as words: "2.5 million"
private let DIGITW: Set<String> = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

private let NUMW: String = {
    var words: [String] = []
    words.append(contentsOf: ONES.keys)
    words.append(contentsOf: TENS.keys)
    words.append("hundred")
    words.append(contentsOf: SCALE.keys)
    return longestFirst(words).joined(separator: "|")
}()
private let NUMSEQ = #"(?:\#(NUMW))(?:[\s-]+(?:\#(NUMW)|and|point|oh))*"#
private let RUN_RX = rx(#"\b\#(NUMSEQ)\b"#)
private let SEP_RX = rx(#"[\s-]+"#, [])

private let UNIT_AFTER =
    #"percent\b|per\s?cent\b|%|dollars?\b|bucks?\b|euros?\b|rupees?\b|usd\b|gb\b|mb\b|kb\b|tb\b|"# +
    #"gigs?\b|gigabytes?\b|megabytes?\b|ms\b|milliseconds?\b|px\b|pixels?\b|ghz\b|mhz\b|fps\b|degrees?\b|k\b"#
private let UNIT_AHEAD_RX = rx(#"^\s*(?:(?:to|through|thru|-)\s*(?:\#(NUMSEQ)|\d[\d,.]*)\s*)?(?:\#(UNIT_AFTER))"#)
private let ONE_AFTER_RX = rx(#"^\s+(?:or|to|through|and)\s+(?:\#(NUMW))\b"#)
private let ONE_BEFORE_RX = rx(#"(?:\b(?:\#(NUMW))|\d)\s+(?:or|to|through)\s*$"#)

private struct Ctx { var unitAhead: Bool; var oneOk: Bool; var commaFrom: Int }
private struct Card { var value: Int; var next: Int; var tok: String }

private func cardinalAt(_ w: [String], _ i: Int, _ ctx: Ctx) -> Card? {
    var total = 0, cur = 0, j = i
    var lastScale = Int.max
    var best: Card? = nil
    func commit(_ end: Int, _ tok: String) { best = Card(value: total + cur, next: end, tok: tok) }
    while j < w.count {
        let t = w[j]
        let two = cur % 100
        if t == "zero" { if j == i { commit(j + 1, t) }; break }
        if let v = ONES[t] {
            let ok = v < 10 ? (two == 0 || (two >= 20 && two % 10 == 0)) : two == 0
            if ok { cur += v; commit(j + 1, t) } else { break }
        } else if let tv = TENS[t] {
            if two == 0 { cur += tv; commit(j + 1, t) } else { break }
        } else if t == "hundred" {
            if cur == 0 && total == 0 && j == i && ctx.unitAhead { cur = 1 } // "hundred percent"
            if cur > 0 && cur < 100 { cur *= 100; commit(j + 1, t) } else { break }
        } else if let sv = SCALE[t] {
            if cur == 0 && total == 0 && j == i && ctx.unitAhead { cur = 1 }
            if cur > 0 && sv < lastScale { total += cur * sv; cur = 0; lastScale = sv; commit(j + 1, t) } else { break }
        } else if t == "and" {
            if let p = at(w, j - 1), p == "hundred" || SCALE[p] != nil,
               let n = at(w, j + 1), n != "zero", ONES[n] != nil || TENS[n] != nil {
                j += 1
                continue
            }
            break
        } else { break }
        j += 1
    }
    return best
}

private func fmtInt(_ n: Int, _ commaFrom: Int) -> String {
    guard n >= commaFrom else { return String(n) }
    var out = ""
    for (idx, ch) in String(n).reversed().enumerated() {
        if idx > 0 && idx % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return String(out.reversed())
}

private func yearTail(_ w: [String], _ k: Int) -> (v: Int, next: Int)? {
    var r: (v: Int, next: Int)? = nil
    if at(w, k) == "oh", let d = at(w, k + 1), DIGITW.contains(d), d != "zero" {
        r = (ONES[d]!, k + 2)
    } else if let tk = at(w, k), let t = TENS[tk] {
        var u = 0
        if let nx = at(w, k + 1), let v = ONES[nx], v >= 1, v <= 9 { u = v }
        r = (t + u, k + 1 + (u > 0 ? 1 : 0))
    } else if let tk = at(w, k), let v = ONES[tk], v >= 10 {
        r = (v, k + 1)
    }
    if let rr = r, let nx = at(w, rr.next), nx == "hundred" || SCALE[nx] != nil { return nil }
    return r
}

private func isScaleOrHundred(_ s: String?) -> Bool { s.map { $0 == "hundred" || SCALE[$0] != nil } ?? false }

private func numberAt(_ w: [String], _ i: Int, _ ctx: Ctx) -> (text: String, next: Int)? {
    let t = w[i]

    // 1) digit runs: "eight zero eight zero" -> 8080, "four zero four" -> 404
    if DIGITW.contains(t) {
        var j = i
        var s = ""
        while j < w.count && (DIGITW.contains(w[j]) || (w[j] == "oh" && j > i)) {
            s += w[j] == "oh" ? "0" : String(ONES[w[j]]!)
            j += 1
        }
        if j - i >= 3 && at(w, j) != "point" && !isScaleOrHundred(at(w, j)) { return (s, j) }
    }

    // 2) years: "twenty twenty six" -> 2026, "nineteen eighty four" -> 1984
    if !ctx.unitAhead && (t == "nineteen" || t == "twenty") {
        if let y = yearTail(w, i + 1) { return (String((t == "nineteen" ? 19 : 20) * 100 + y.v), y.next) }
    }

    // 3) colloquial hundreds when a unit follows: "one twenty percent" -> 120
    if ctx.unitAhead, DIGITW.contains(t), t != "zero", let nx = at(w, i + 1), let tn = TENS[nx] {
        var v = ONES[t]! * 100 + tn
        var n = i + 2
        if let u = at(w, n), DIGITW.contains(u), u != "zero" { v += ONES[u]!; n += 1 }
        if !isScaleOrHundred(at(w, n)) { return (String(v), n) }
    }

    // 4) cardinals, decimals, versions
    guard let card = cardinalAt(w, i, ctx) else { return nil }
    let j = card.next
    let sv = SCALE[card.tok]
    let intText: String
    if WORD_SCALES.contains(card.tok), let sv = sv, card.value % sv == 0 {
        intText = "\(card.value / sv) \(card.tok)"
    } else {
        intText = fmtInt(card.value, ctx.commaFrom)
    }
    var segs: [String] = []
    var k = j
    while at(w, k) == "point" {
        var m = k + 1
        var ds = ""
        while m < w.count && (DIGITW.contains(w[m]) || w[m] == "oh") {
            ds += w[m] == "oh" ? "0" : String(ONES[w[m]]!)
            m += 1
        }
        if !ds.isEmpty { segs.append(ds); k = m; continue }
        if let c2 = cardinalAt(w, k + 1, ctx), !WORD_SCALES.contains(c2.tok) { segs.append(String(c2.value)); k = c2.next; continue }
        break
    }
    if !segs.isEmpty {
        let head = (WORD_SCALES.contains(card.tok) && sv != nil) ? String(card.value / sv!) : intText
        var text = head + "." + segs.joined(separator: ".")
        if segs.count == 1, let nx = at(w, k), SCALE[nx] != nil { text += " " + nx; k += 1 }
        return (text, k)
    }
    // pronoun guard: "one of the best" stays; "one thirty", "one or two", "one percent" convert
    let nextIsNumber = at(w, i + 1).map { ONES[$0] != nil || TENS[$0] != nil } ?? false
    if t == "one" && card.next == i + 1 && !ctx.oneOk && !nextIsNumber { return nil }
    return (intText, j)
}

private func convertRun(_ m: String, _ ctx: Ctx) -> String {
    let lower = m.lowercased()
    let ns = lower as NSString
    var w: [String] = [], seps: [String] = []
    var last = 0
    for mt in SEP_RX.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
        w.append(ns.substring(with: NSRange(location: last, length: mt.range.location - last)))
        seps.append(ns.substring(with: mt.range))
        last = NSMaxRange(mt.range)
    }
    w.append(ns.substring(from: last))

    var out: [(text: String, sep: String)] = []
    var i = 0
    while i < w.count {
        let sep = i == 0 ? "" : (seps[i - 1].allSatisfy { $0 == "-" } ? "-" : " ")
        if w[i] == "oh", let prev = out.last, let lc = prev.text.last, lc.isNumber,
           let nx = at(w, i + 1), DIGITW.contains(nx), nx != "zero" {
            out.append((text: "0" + String(ONES[nx]!), sep: sep)) // "eleven oh five" -> 11 05
            i += 2
            continue
        }
        if let r = numberAt(w, i, ctx) { out.append((text: r.text, sep: sep)); i = r.next }
        else { out.append((text: w[i], sep: sep)); i += 1 }
    }
    return out.enumerated().map { $0.offset == 0 ? $0.element.text : $0.element.sep + $0.element.text }.joined()
}

// MARK: - Digit-level passes

private let NUM = #"\d[\d,]*(?:\.\d+)?"#
private let RANGE = #"(?:\s*(?:-|to|through|thru|dash)\s*(\#(NUM)))?"#
private let PREV_WORD_RX = rx(#"([A-Za-z]+)\s*$"#, [])

private func prevWord(_ before: String) -> String {
    let ns = before as NSString
    guard let m = PREV_WORD_RX.firstMatch(in: before, range: NSRange(location: 0, length: ns.length)) else { return "" }
    return ns.substring(with: m.range(at: 1)).lowercased()
}
private func isFrom(_ m: M) -> Bool { ["from", "between"].contains(prevWord(m.before)) }
// "from 5 to 10" keeps its words; otherwise a range becomes "5-10"
private func joinRange(_ a: String, _ b: String?, _ m: M, tail: String) -> String {
    guard let b = b else { return a + tail }
    return isFrom(m) ? "\(a) to \(b)\(tail)" : "\(a)-\(b)\(tail)"
}

private let MONTHS = "january|february|march|april|may|june|july|august|september|october|november|december"
private let ORD_DAY =
    #"(?:twenty|thirty)[\s-](?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth)|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|"# +
    #"tenth|eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|twentieth|thirtieth"#
private let ORD_VAL: [String: Int] = [
    "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9,
    "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15,
    "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19, "twentieth": 20, "thirtieth": 30,
]
private let TENS_STEM: [String: Int] = ["twent": 20, "thirt": 30, "fort": 40, "fift": 50, "sixt": 60, "sevent": 70, "eight": 80, "ninet": 90]

private func ordinalSuffix(_ n: Int) -> String {
    let m = n % 100
    if m >= 11 && m <= 13 { return "th" }
    switch n % 10 { case 1: return "st"; case 2: return "nd"; case 3: return "rd"; default: return "th" }
}

private let UNIT_TABLE: [(String, String, String)] = [
    ("kilobytes?|kb", "KB", " "), ("megabytes?|megs?|mb", "MB", " "), ("gigabytes?|gigs?|gb", "GB", " "),
    ("terabytes?|tb", "TB", " "), ("petabytes?|pb", "PB", " "),
    ("milliseconds?|ms", "ms", ""), ("microseconds?", "µs", ""), ("pixels?|px", "px", ""),
    ("gigahertz|ghz", "GHz", " "), ("megahertz|mhz", "MHz", " "), ("kilohertz|khz", "kHz", " "),
    (#"frames\s+per\s+second|fps"#, "fps", " "), (#"megabits?\s+per\s+second|mbps"#, "Mbps", " "),
    (#"gigabits?\s+per\s+second|gbps"#, "Gbps", " "),
]
private let CURRENCY: [String: String] = [
    "dollar": "$", "dollars": "$", "buck": "$", "bucks": "$", "usd": "$", "euro": "€", "euros": "€", "eur": "€",
    "rupee": "₹", "rupees": "₹", "inr": "₹", "rs": "₹", "yen": "¥", "jpy": "¥", "gbp": "£", "quid": "£", "pounds sterling": "£",
]
private let QUANT_NOUNS =
    "seconds?|minutes?|hours?|days?|weeks?|months?|years?|times|items?|people|users?|lines?|pages?|words?|steps?|files?|tokens?|cores?|threads?|requests?|rows?|bytes?|options?|ways?"

private let MONTH_ORD_RX = rx(#"\b(\#(MONTHS))\s+(?:the\s+)?(\#(ORD_DAY))\b"#)
private let COMPOUND_ORD_RX = rx(#"\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)[\s-](first|third|fourth|fifth|sixth|seventh|eighth|ninth)\b"#)
private let TENS_TH_RX = rx(#"\b(twent|thirt|fort|fift|sixt|sevent|eight|ninet)ieth\b"#)
private let A_HUNDRED_RX = rx(#"\ba\s+(?=(?:hundred|thousand|million|billion)\b)"#)
private let PERCENT_RX = rx(#"(\#(NUM))\#(RANGE)\s*(?:percent|per\s?cent|%)(?![\w])"#)
private let CURRENCY_RX: NSRegularExpression = {
    let words = CURRENCY.keys.sorted { $0.count > $1.count }.map { $0.replacingOccurrences(of: " ", with: #"\s+"#) }.joined(separator: "|")
    return rx(#"(\#(NUM))\#(RANGE)\s*(thousand|million|billion|trillion|lakh|crore|k)?\s*\b(\#(words))\b"#)
}()
private let UNIT_RXS: [(NSRegularExpression, String)] = UNIT_TABLE.map { entry in
    (rx(#"(\#(NUM))\#(RANGE)\s*(?:\#(entry.0))\b"#), entry.2 + entry.1)
}
private let DEGREES_RX = rx(#"(\d)\s*degrees?(?:\s+(celsius|centigrade|fahrenheit))?\b"#)
private let K_RX = rx(#"(\d)\s+k\b(?!\w)"#)
private let X_MULT_RX = rx(#"(\d+(?:\.\d+)?)\s*x\b(?=\s+(?:faster|slower|better|worse|more|less|bigger|smaller|cheaper|larger|higher|lower|improvement|speedup|engineer|developer|growth|increase|reduction))"#)
private let BY_RX = rx(#"\b(\d{1,5})\s+by\s+(\d{1,5})\b(\s+(?:feet|foot|ft|inch|inches|cm|mm|meters?|px|pixels?))?"#)
private let DIV_RX = rx(#"\b(?:divid\w*|multipl\w*|times)\s+\S+\s*$"#)
private let TIME_RX = rx(#"\b(\d{1,2})(?:[:\s]+(\d{2}))?\s*([ap])\.?\s?m\b\.?"#)
private let AT_TIME_RX = rx(#"\b(at|by|around|until|till|before|after|about)\s+(\d{1,2})\s+(15|30|45)\b(?!\s*(?:%|\d|[a-z]+\s*\d))"#)
private let MONTH_DAY_RX = rx(#"\b(\#(MONTHS))\s+(\d{1,2})(?:st|nd|rd|th)?\b(?!\s*(?:%|:|\d{3}))"#)
private let MONTH_YEAR_RX = rx(#"\b((?:\#(MONTHS))\s+\d{1,2})\s+(\d{4})\b"#)
private let VERSION_V_RX = rx(#"\b([vV])\s+(\d+(?:\.\d+)+)\b"#, [])
private let RANGE_QUANT_RX = rx(#"(?<![\w.$€₹£-])(\#(NUM))\s+(?:to|through|thru)\s+(\#(NUM))(\s+(?:\#(QUANT_NOUNS)|hundred|thousand|million)\b)"#)
private let SPACE_PERCENT_RX = rx(#"(\d)\s+%"#, [])
private let PURE_INT_DEC1_RX = rx(#"^\d+\.\d$"#, [])

func numberPass(_ input: String, commaFrom: Int) -> String {
    var s = input

    // a) "March third" -> "March 3", "twenty first" -> "21st", "twentieth" -> "20th"
    s = sub(MONTH_ORD_RX, s) { m in
        let parts = m.g(2)!.lowercased().components(separatedBy: CharacterSet(charactersIn: " -"))
        let n = parts.count == 2 ? (TENS[parts[0]] ?? 0) + (ORD_VAL[parts[1]] ?? 0) : (ORD_VAL[parts[0]] ?? 0)
        return "\(cap(m.g(1)!)) \(n)"
    }
    s = sub(COMPOUND_ORD_RX, s) { m in
        let n = (TENS[m.g(1)!.lowercased()] ?? 0) + (ORD_VAL[m.g(2)!.lowercased()] ?? 0)
        return "\(n)\(ordinalSuffix(n))"
    }
    s = sub(TENS_TH_RX, s) { m in "\(TENS_STEM[m.g(1)!.lowercased()] ?? 0)th" }

    // b) words -> digits
    s = sub(A_HUNDRED_RX, s) { _ in "one " }
    s = sub(RUN_RX, s) { m in
        let after = m.after
        let unitAhead = test(UNIT_AHEAD_RX, after)
        let oneOk = unitAhead || test(ONE_AFTER_RX, after) || test(ONE_BEFORE_RX, m.before)
        return convertRun(m.full, Ctx(unitAhead: unitAhead, oneOk: oneOk, commaFrom: commaFrom))
    }

    // c) percent: "120 to 130 percent" -> "120-130%"
    s = sub(PERCENT_RX, s) { m in joinRange(m.g(1)!, m.g(2), m, tail: "%") }

    // d) currency: "five hundred dollars" -> "$500", "2.5 million dollars" -> "$2.5 million", "10 lakh rupees" -> "₹10 lakh"
    s = sub(CURRENCY_RX, s) { m in
        let a = m.g(1)!, b = m.g(2), scale = m.g(3)
        let curKey = m.g(4)!.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let sym = CURRENCY[curKey] ?? "$"
        let aa = (scale == nil && test(PURE_INT_DEC1_RX, a)) ? a + "0" : a // "$2.5" -> "$2.50"
        let tail = scale.map { $0.lowercased() == "k" ? "K" : " " + $0.lowercased() } ?? ""
        guard let b = b else { return "\(sym)\(aa)\(tail)" }
        return isFrom(m) ? "\(sym)\(a) to \(sym)\(b)\(tail)" : "\(sym)\(a)-\(b)\(tail)"
    }

    // e) units: "sixteen gigs" -> "16 GB", "two hundred milliseconds" -> "200ms"
    for (re, tail) in UNIT_RXS {
        s = sub(re, s) { m in joinRange(m.g(1)!, m.g(2), m, tail: tail) }
    }
    s = sub(DEGREES_RX, s) { m in
        let d = m.g(1)!
        guard let u = m.g(2) else { return "\(d)°" }
        return "\(d)°" + (u.lowercased() == "fahrenheit" ? "F" : "C")
    }
    s = subT(K_RX, s, "$1K") // "five k" -> "5K"

    // f) "ten x faster" -> "10x faster"
    s = subT(X_MULT_RX, s, "$1x")

    // g) dimensions: "sixteen by nine" -> "16:9", "1920 by 1080" -> "1920x1080" (never "divide 10 by 2")
    s = sub(BY_RX, s) { m in
        let a = m.g(1)!, b = m.g(2)!, unit = m.g(3) ?? ""
        let startW = max(0, m.offset - 25)
        let endW = min(m.ns.length, m.offset + a.utf16.count + 1)
        let win = m.ns.substring(with: NSRange(location: startW, length: max(0, endW - startW)))
        if test(DIV_RX, win) { return m.full }
        if ["16:9", "4:3", "21:9", "3:2", "1:1", "9:16"].contains("\(a):\(b)") { return "\(a):\(b)\(unit)" }
        if !unit.isEmpty || ((Int(a) ?? 0) >= 100 && (Int(b) ?? 0) >= 100) { return "\(a)x\(b)\(unit)" }
        return m.full
    }

    // h) time: "three thirty pm" -> "3:30 PM", "nine a m" -> "9 AM", "meet at one thirty" -> "meet at 1:30"
    s = sub(TIME_RX, s) { m in
        let h = Int(m.g(1)!) ?? 0
        let mi = m.g(2)
        if h < 1 || h > 12 || (mi != nil && (Int(mi!) ?? 0) > 59) { return m.full }
        return "\(h)\(mi.map { ":" + $0 } ?? "") \(m.g(3)!.uppercased())M"
    }
    s = sub(AT_TIME_RX, s) { m in
        let h = Int(m.g(2)!) ?? 0
        return (h >= 1 && h <= 12) ? "\(m.g(1)!) \(h):\(m.g(3)!)" : m.full
    }

    // i) dates: "March 3 2026" -> "March 3, 2026"
    s = sub(MONTH_DAY_RX, s) { m in "\(cap(m.g(1)!)) \(m.g(2)!)" }
    s = sub(MONTH_YEAR_RX, s) { m in
        let parts = m.g(1)!.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return "\(cap(parts[0])) \(parts[1]), \(m.g(2)!)"
    }

    // j) versions + ranges
    s = subT(VERSION_V_RX, s, "$1$2")
    s = sub(RANGE_QUANT_RX, s) { m in
        let a = m.g(1)!, b = m.g(2)!, tail = m.g(3)!
        let av = Double(a.replacingOccurrences(of: ",", with: "")) ?? 0
        let bv = Double(b.replacingOccurrences(of: ",", with: "")) ?? 0
        if isFrom(m) || bv <= av { return m.full }
        return "\(a)-\(b)\(tail)"
    }
    return subT(SPACE_PERCENT_RX, s, "$1%")
}
