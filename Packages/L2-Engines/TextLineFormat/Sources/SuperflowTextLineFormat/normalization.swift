//
//  Normalizer.swift
//  Superflow output normalizer: deterministic inverse text normalization (ITN),
//  emoji commands, and developer punctuation.
//
//  Pipeline position:
//    Nemotron -> S1 mini -> formatting -> Normalizer.normalize() -> tech dictionary (still last)
//
//  Pure Foundation. No I/O, no model calls. Idempotent. Conservative on ambiguous English.
//  Port of normalize.ts (83 passing cases). Regexes are ICU (NSRegularExpression).
//

import Foundation

public struct NormalizeOptions {
    public var emoji = true
    public var numbers = true
    public var tech = true
    /// Thousands separator from this value. 10000 keeps 8080 / 2026 clean.
    public var commaFrom = 10_000
    public init() {}
}

public enum Normalizer {
    public static func normalize(_ input: String, options: NormalizeOptions = NormalizeOptions()) -> String {
        var s = input
        if options.emoji { s = emojiPass(s) }
        if options.numbers { s = numberPass(s, commaFrom: options.commaFrom) }
        if options.tech { s = techPass(s) }
        s = subT(MULTISPACE_RX, s, " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Regex helpers

struct M {
    let ns: NSString
    let result: NSTextCheckingResult
    var full: String { ns.substring(with: result.range) }
    var offset: Int { result.range.location }
    var before: String { ns.substring(to: result.range.location) }
    var after: String { ns.substring(from: NSMaxRange(result.range)) }
    func g(_ i: Int) -> String? {
        let r = result.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }
}

func rx(_ pattern: String, _ opts: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
    do { return try NSRegularExpression(pattern: pattern, options: opts) }
    catch { fatalError("Bad regex: \(pattern)\n\(error)") }
}

func sub(_ re: NSRegularExpression, _ s: String, _ f: (M) -> String) -> String {
    let ns = s as NSString
    let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
    if matches.isEmpty { return s }
    var out = ""
    var last = 0
    for m in matches {
        out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        out += f(M(ns: ns, result: m))
        last = NSMaxRange(m.range)
    }
    out += ns.substring(from: last)
    return out
}

func subT(_ re: NSRegularExpression, _ s: String, _ template: String) -> String {
    re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
}

func test(_ re: NSRegularExpression, _ s: String) -> Bool {
    re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
}

func at(_ w: [String], _ i: Int) -> String? { (i >= 0 && i < w.count) ? w[i] : nil }
private func esc(_ x: String) -> String {
    var o = ""
    for c in x { if ".*+?^${}()|[]\\".contains(c) { o.append("\\") }; o.append(c) }
    return o
}
private func phrase(_ x: String) -> String { esc(x).replacingOccurrences(of: " ", with: #"[\s-]+"#) }
func longestFirst(_ xs: [String]) -> [String] { xs.sorted { $0.count > $1.count } }
func cap(_ x: String) -> String { x.prefix(1).uppercased() + x.dropFirst().lowercased() }
private func collapseSpaces(_ x: String) -> String {
    x.lowercased().components(separatedBy: CharacterSet(charactersIn: " -\t\n")).filter { !$0.isEmpty }.joined(separator: " ")
}

private let MULTISPACE_RX = rx(#"[ \t]{2,}"#, [])

// MARK: - Emoji

private let EMOJI_TABLE: [(String, [String])] = [
    ("😂", ["laughing", "laugh", "lol", "tears of joy", "joy", "crying laughing"]),
    ("🤣", ["rofl", "lmao", "rolling on the floor laughing", "rolling laughing"]),
    ("😭", ["crying", "cry", "sobbing", "sob", "loudly crying"]),
    ("😢", ["sad", "sad face", "tear"]),
    ("😊", ["smile", "smiling", "happy", "blushing"]),
    ("😁", ["grin", "grinning"]),
    ("😄", ["big smile"]),
    ("🙂", ["slight smile"]),
    ("😉", ["wink", "winking"]),
    ("😍", ["heart eyes", "love eyes", "in love"]),
    ("😘", ["kiss", "kissing", "blowing kiss"]),
    ("🥰", ["smiling hearts", "love face"]),
    ("😎", ["cool", "sunglasses"]),
    ("🤔", ["thinking", "thinking face"]),
    ("🤨", ["raised eyebrow"]),
    ("😐", ["neutral", "straight face"]),
    ("🙄", ["eye roll", "eye rolling", "rolling eyes"]),
    ("😅", ["sweat smile", "nervous laugh", "nervous"]),
    ("😬", ["grimace", "grimacing", "awkward"]),
    ("😱", ["screaming", "scream", "shocked"]),
    ("😮", ["surprised", "wow"]),
    ("🤯", ["mind blown", "exploding head"]),
    ("😡", ["angry", "mad"]),
    ("🤬", ["cursing", "swearing"]),
    ("😴", ["sleeping", "sleepy", "tired"]),
    ("🤮", ["vomit", "vomiting", "puke", "throwing up", "barf"]),
    ("🤢", ["nauseated", "sick", "green face"]),
    ("🥺", ["pleading", "puppy eyes", "begging"]),
    ("😏", ["smirk", "smirking"]),
    ("😇", ["angel", "halo"]),
    ("😈", ["devil"]),
    ("🤡", ["clown"]),
    ("🤓", ["nerd"]),
    ("🥳", ["party face", "partying"]),
    ("🥶", ["freezing", "cold face"]),
    ("🥵", ["hot face", "sweating"]),
    ("💀", ["skull", "dead"]),
    ("👻", ["ghost"]),
    ("💩", ["poop"]),
    ("🤝", ["handshake"]),
    ("👍", ["thumbs up", "like"]),
    ("👎", ["thumbs down", "dislike"]),
    ("👏", ["clap", "clapping", "applause"]),
    ("🙌", ["raised hands", "hooray", "praise"]),
    ("🙏", ["pray", "praying", "folded hands", "thank you hands", "namaste"]),
    ("💪", ["flex", "muscle", "strong"]),
    ("👌", ["ok hand", "okay hand"]),
    ("✌️", ["peace", "victory"]),
    ("🤞", ["crossed fingers", "fingers crossed"]),
    ("👋", ["wave", "waving"]),
    ("🫡", ["salute"]),
    ("🤷", ["shrug"]),
    ("🤦", ["facepalm"]),
    ("👀", ["eyes"]),
    ("🧠", ["brain"]),
    ("❤️", ["heart", "red heart", "love"]),
    ("💔", ["broken heart"]),
    ("🧡", ["orange heart"]),
    ("💛", ["yellow heart"]),
    ("💚", ["green heart"]),
    ("💙", ["blue heart"]),
    ("💜", ["purple heart"]),
    ("🖤", ["black heart"]),
    ("🤍", ["white heart"]),
    ("🔥", ["fire", "flame", "lit"]),
    ("✨", ["sparkles", "sparkle"]),
    ("⭐", ["star"]),
    ("💯", ["hundred", "one hundred", "100", "hundred points"]),
    ("✅", ["check", "check mark", "green check", "tick"]),
    ("❌", ["cross", "cross mark", "red x"]),
    ("⚠️", ["warning"]),
    ("🚀", ["rocket"]),
    ("🎉", ["party popper", "party", "celebration", "confetti"]),
    ("🎂", ["cake", "birthday cake"]),
    ("🍕", ["pizza"]),
    ("🍺", ["beer"]),
    ("☕", ["coffee"]),
    ("🐛", ["bug"]),
    ("🤖", ["robot"]),
    ("💡", ["light bulb", "idea"]),
    ("⚡", ["lightning", "bolt"]),
    ("🌙", ["moon"]),
    ("☀️", ["sun"]),
    ("🌈", ["rainbow"]),
    ("❄️", ["snowflake"]),
    ("💰", ["money bag"]),
    ("🤑", ["money face"]),
    ("💸", ["flying money"]),
    ("🎯", ["target", "bullseye"]),
    ("📌", ["pushpin", "pin"]),
    ("🔒", ["lock"]),
    ("🔑", ["key"]),
    ("🐐", ["goat"]),
    ("🙈", ["see no evil", "monkey"]),
]

// Flags come from ISO codes (regional indicator symbols). No per-flag table.
private let COUNTRIES: [String: [String]] = [
    "US": ["us", "u s", "usa", "u s a", "united states", "united states of america", "america", "american"],
    "GB": ["uk", "u k", "united kingdom", "british", "britain", "great britain"],
    "IN": ["india", "indian"], "CA": ["canada", "canadian"], "MX": ["mexico", "mexican"],
    "BR": ["brazil", "brazilian"], "AR": ["argentina", "argentinian"], "CL": ["chile", "chilean"],
    "CO": ["colombia", "colombian"], "PE": ["peru", "peruvian"], "CU": ["cuba", "cuban"],
    "CN": ["china", "chinese"], "JP": ["japan", "japanese"], "KR": ["south korea", "korea", "korean"],
    "KP": ["north korea"], "TW": ["taiwan"], "HK": ["hong kong"],
    "DE": ["germany", "german"], "FR": ["france", "french"], "ES": ["spain", "spanish"],
    "IT": ["italy", "italian"], "PT": ["portugal", "portuguese"], "NL": ["netherlands", "dutch", "holland"],
    "BE": ["belgium", "belgian"], "CH": ["switzerland", "swiss"], "AT": ["austria", "austrian"],
    "SE": ["sweden", "swedish"], "NO": ["norway", "norwegian"], "DK": ["denmark", "danish"],
    "FI": ["finland", "finnish"], "IE": ["ireland", "irish"], "PL": ["poland", "polish"],
    "GR": ["greece", "greek"], "UA": ["ukraine", "ukrainian"], "RU": ["russia", "russian"],
    "TR": ["turkey", "turkish"], "IL": ["israel", "israeli"], "PS": ["palestine", "palestinian"],
    "SA": ["saudi arabia", "saudi"], "AE": ["uae", "u a e", "united arab emirates", "dubai"],
    "IR": ["iran", "iranian"], "IQ": ["iraq"], "EG": ["egypt", "egyptian"], "ZA": ["south africa"],
    "NG": ["nigeria", "nigerian"], "KE": ["kenya", "kenyan"], "PK": ["pakistan", "pakistani"],
    "BD": ["bangladesh"], "LK": ["sri lanka"], "NP": ["nepal"], "AF": ["afghanistan"],
    "ID": ["indonesia", "indonesian"], "MY": ["malaysia", "malaysian"], "SG": ["singapore"],
    "TH": ["thailand", "thai"], "VN": ["vietnam", "vietnamese"], "PH": ["philippines", "filipino"],
    "AU": ["australia", "australian"], "NZ": ["new zealand"],
    "EU": ["european union", "eu", "e u", "europe", "european"],
]

private let COUNT_WORDS: [String: Int] = [
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
    "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "double": 2, "triple": 3, "couple": 2,
]
private let MAX_EMOJI_REPEAT = 30
private let COUNT_RE =
    #"\d{1,2}|(?:twenty|thirty)(?:[\s-](?:one|two|three|four|five|six|seven|eight|nine))?|"# +
    #"one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|"# +
    #"sixteen|seventeen|eighteen|nineteen|double|triple|(?:a\s+)?couple(?:\s+of)?"#

private let EMOJI_BY_NAME: [String: String] = {
    var d: [String: String] = [:]
    for (e, names) in EMOJI_TABLE { for n in names { d[n] = e } }
    return d
}()
private let FLAG_BY_NAME: [String: String] = {
    var d: [String: String] = [:]
    for (code, names) in COUNTRIES { for n in names { d[n] = code } }
    return d
}()
private let EMOJI_NAMES_RE = longestFirst(Array(EMOJI_BY_NAME.keys)).map(phrase).joined(separator: "|")
private let FLAG_NAMES_RE = longestFirst(Array(FLAG_BY_NAME.keys)).map(phrase).joined(separator: "|")

private func flagOf(_ code: String) -> String {
    var scalars = String.UnicodeScalarView()
    for u in code.unicodeScalars { scalars.append(Unicode.Scalar(0x1F1E6 + u.value - 65)!) }
    return String(scalars)
}

private func parseCount(_ raw: String?) -> Int {
    guard var t = raw?.lowercased().trimmingCharacters(in: .whitespaces), !t.isEmpty else { return 1 }
    if t.hasPrefix("a ") { t = String(t.dropFirst(2)) }
    if t.hasSuffix(" of") { t = String(t.dropLast(3)) }
    if let n = Int(t) { return min(n, MAX_EMOJI_REPEAT) }
    let n = t.components(separatedBy: CharacterSet(charactersIn: " -")).reduce(0) { $0 + (COUNT_WORDS[$1] ?? 0) }
    return min(n == 0 ? 1 : n, MAX_EMOJI_REPEAT)
}

// Private-use sentinels so later steps never touch emoji we emitted.
private let OPEN = "\u{E000}"
private let CLOSE = "\u{E001}"

private let EMOJI_FAST_RX = rx(#"emoji|emoticon|flag"#)
private let EMOJI_RX = rx(#"(?:\b(\#(COUNT_RE))[\s-]+)?\b(\#(EMOJI_NAMES_RE))[\s-]+(?:emojis?|emoticons?)\b"#)
private let FLAG_RX = rx(#"(?:\b(\#(COUNT_RE))[\s-]+)?\b(\#(FLAG_NAMES_RE))[\s-]+flags?(?:[\s-]+(emojis?))?\b"#)
private let TRAIL_PUNCT_RX = rx(#"[.!?\s]+$"#, [])
private let ADJ_GROUPS_RX = rx(#"\#(CLOSE)\s+\#(OPEN)"#, [])
private let GROUP_RX = rx(#"\#(OPEN)[^\#(CLOSE)]*\#(CLOSE)"#, [])
private let PURE_RX = rx(#"^[\s.,!?;:\-–—]*$"#, [])
private let TRAIL_PERIOD_RX = rx(#"\#(CLOSE)\s*\.(\s*)$"#, [])

private func emojiPass(_ input: String) -> String {
    if !test(EMOJI_FAST_RX, input) { return input }
    let trimmed = subT(TRAIL_PUNCT_RX, input.trimmingCharacters(in: .whitespacesAndNewlines), "")

    var s = sub(EMOJI_RX, input) { m in
        guard let name = m.g(2), let e = EMOJI_BY_NAME[collapseSpaces(name)] else { return m.full }
        return OPEN + String(repeating: e, count: parseCount(m.g(1))) + CLOSE
    }
    s = sub(FLAG_RX, s) { m in
        // "US flag" alone is a command; inside a sentence it needs the word "emoji" (so "the US flag" stays text).
        let standalone = m.full.lowercased() == trimmed.lowercased()
        if m.g(3) == nil && !standalone { return m.full }
        guard let name = m.g(2), let code = FLAG_BY_NAME[collapseSpaces(name)] else { return m.full }
        return OPEN + String(repeating: flagOf(code), count: parseCount(m.g(1))) + CLOSE
    }
    if !s.contains(OPEN) { return s }

    s = subT(ADJ_GROUPS_RX, s, "") // adjacent emoji groups join with no space
    let ns = s as NSString
    let groups = GROUP_RX.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    let rest = subT(GROUP_RX, s, "")
    if test(PURE_RX, rest) { // pure emoji command: only the emoji, nothing else
        return groups.joined().replacingOccurrences(of: OPEN, with: "").replacingOccurrences(of: CLOSE, with: "")
    }
    s = sub(TRAIL_PERIOD_RX, s) { m in CLOSE + (m.g(1) ?? "") } // "... 😂." -> "... 😂"
    return s.replacingOccurrences(of: OPEN, with: "").replacingOccurrences(of: CLOSE, with: "")
}

// MARK: - Dev punctuation

private let TLD = "com|org|net|io|dev|ai|app|co|in|edu|gov|me|xyz|sh|so|tech|cloud|uk|us|ca|de|fr"
private let PROVIDERS_RX = rx(#"^(gmail|yahoo|outlook|hotmail|icloud|proton|protonmail|live|hey|fastmail)$"#)
private let PROTOCOL_RX = rx(#"\b(https?)\s+colon\s+slash\s+slash\s*"#)
private let EMAIL_RX = rx(#"\b([a-z0-9][\w-]*(?:\s+(?:dot|underscore|dash)\s+[a-z0-9][\w-]*)*)\s+at\s+((?:[a-z0-9-]+\s+dot\s+)+(?:\#(TLD)))\b"#)
private let LOCAL_SEP_RX = rx(#"\s+(?:dot|underscore)\s+"#)
private let DOT_RX = rx(#"\s+dot\s+"#)
private let UNDERSCORE_RX = rx(#"\s+underscore\s+"#)
private let DASH_RX = rx(#"\s+dash\s+"#)
private let DOMAIN_RX = rx(#"\b((?:[a-z0-9-]+\s+dot\s+)+(?:\#(TLD)))\b"#)
private let URL_PATH_RX = rx(#"\b([a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:\#(TLD)))((?:\s+slash\s+[\w.-]+)+)"#)
private let SLASH_RX = rx(#"\s+slash\s+"#)
private let HOST_PORT_RX = rx(#"\b(localhost|\d{1,3}(?:\.\d{1,3}){3}|[a-z0-9-]+(?:\.[a-z0-9-]+)+)\s+colon\s+(\d{2,5})\b"#)
private let DOUBLE_DASH_RX = rx(#"\b(?:double\s+dash|dash\s+dash)\s+([a-z][\w-]*)"#)
private let SINGLE_DASH_RX = rx(#"(^|\s)dash\s+([a-z])\b(?![\w-])"#)
private let UNDERSCORE_JOIN_RX = rx(#"(\w)\s+underscore\s+(\w)"#)

private func techPass(_ input: String) -> String {
    var s = subT(PROTOCOL_RX, input, "$1://")

    // "john dot smith at gmail dot com" -> john.smith@gmail.com
    s = sub(EMAIL_RX, s) { m in
        let local = m.g(1)!, domain = m.g(2)!
        let firstLabel = domain.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? domain
        if !test(PROVIDERS_RX, firstLabel) && !test(LOCAL_SEP_RX, local) { return m.full }
        var l = subT(DOT_RX, local, ".")
        l = subT(UNDERSCORE_RX, l, "_")
        l = subT(DASH_RX, l, "-")
        return (l + "@" + subT(DOT_RX, domain, ".")).lowercased()
    }
    // "github dot com" -> github.com
    s = sub(DOMAIN_RX, s) { m in subT(DOT_RX, m.full, ".").lowercased() }
    // "github.com slash anthropics slash claude" -> github.com/anthropics/claude
    s = sub(URL_PATH_RX, s) { m in m.g(1)! + subT(SLASH_RX, m.g(2)!, "/") }
    // "localhost colon 3000" -> localhost:3000
    s = subT(HOST_PORT_RX, s, "$1:$2")
    // "dash dash verbose" -> --verbose, "dash v" -> -v
    s = subT(DOUBLE_DASH_RX, s, "--$1")
    s = subT(SINGLE_DASH_RX, s, "$1-$2")
    // "my underscore var" -> my_var
    for _ in 0..<4 { s = subT(UNDERSCORE_JOIN_RX, s, "$1_$2") }
    return s
}