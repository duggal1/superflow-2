import SuperflowKernel

enum NumberLex {
    static let units = NumberTables.units.mapValues(UInt64.init)
    static let tens = NumberTables.tens.mapValues(UInt64.init)
    static let scales: [String: UInt64] = [
        "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000,
        "trillion": 1_000_000_000_000, "quadrillion": 1_000_000_000_000_000,
        "lakh": 100_000, "lakhs": 100_000, "crore": 10_000_000, "crores": 10_000_000,
    ]
    static let ordinals = NumberTables.ordinalUnits.mapValues(UInt64.init)

    static func isNumberToken(_ key: String) -> Bool {
        units[key] != nil || tens[key] != nil || scales[key] != nil || key == "hundred" || key == "oh"
    }

    static func add(_ a: UInt64, _ b: UInt64) -> UInt64? {
        let (result, overflow) = a.addingReportingOverflow(b)
        return overflow ? nil : result
    }

    static func multiply(_ a: UInt64, _ b: UInt64) -> UInt64? {
        let (result, overflow) = a.multipliedReportingOverflow(by: b)
        return overflow ? nil : result
    }

    static func editable(_ words: [Word], _ index: Int) -> Bool {
        words.indices.contains(index) && !words[index].protected && !words[index].glue
            && (index == 0 || !words[index - 1].glue)
    }

    struct Parsed {
        var value: UInt64
        var used: Int
        var ordinal = false
        var big = false
    }

    static func parseCardinal(_ words: [Word], _ start: Int) -> Parsed? {
        enum Last { case start, unit, teen, tens, tensUnit, hundred, scale }
        guard editable(words, start) else { return nil }
        var last = Last.start
        var total: UInt64 = 0
        var current: UInt64 = 0
        var lastScale = UInt64.max
        var i = start
        var end = start
        var ordinal = false
        var big = false
        if i + 1 < words.count, ["a", "an"].contains(words[i].key), !words[i].hardBreak,
           words[i + 1].key == "hundred" || scales[words[i + 1].key] != nil {
            current = 1
            last = .unit
            i += 1
        }
        loop: while editable(words, i) {
            let key = words[i].key
            if let unit = units[key] {
                if unit == 0 {
                    guard i == start, last == .start else { break loop }
                    end = i + 1
                    break loop
                }
                if unit >= 10 {
                    guard [.start, .hundred, .scale].contains(last) else { break loop }
                    last = .teen
                } else {
                    guard [.start, .tens, .hundred, .scale].contains(last) else { break loop }
                    last = last == .tens ? .tensUnit : .unit
                }
                guard let next = add(current, unit) else { return nil }
                current = next
            } else if let ten = tens[key] {
                guard [.start, .hundred, .scale].contains(last), let next = add(current, ten) else { break loop }
                current = next
                last = .tens
            } else if key == "hundred" {
                guard [.unit, .teen].contains(last), current < 100,
                      let next = multiply(current, 100) else { break loop }
                current = next
                last = .hundred
                big = true
            } else if let scale = scales[key] {
                guard [.unit, .teen, .tens, .tensUnit, .hundred].contains(last), scale < lastScale else { break loop }
                guard let scaled = multiply(current, scale), let next = add(total, scaled) else { return nil }
                total = next
                current = 0
                lastScale = scale
                last = .scale
                big = true
            } else if let value = ordinals[key], value < 100 {
                let allowed: [Last] = value >= 10 ? [.start, .hundred, .scale] : [.start, .tens, .hundred, .scale]
                guard allowed.contains(last), let next = add(current, value) else { break loop }
                current = next
                ordinal = true
                end = i + 1
                break loop
            } else if key == "and", [.hundred, .scale].contains(last),
                      editable(words, i + 1), isNumberToken(words[i + 1].key), !words[i].hardBreak {
                i += 1
                continue loop
            } else { break loop }
            end = i + 1
            if words[i].hardBreak { break loop }
            i += 1
        }
        guard end > start, let value = add(total, current) else { return nil }
        return Parsed(value: value, used: end - start, ordinal: ordinal, big: big)
    }
}
