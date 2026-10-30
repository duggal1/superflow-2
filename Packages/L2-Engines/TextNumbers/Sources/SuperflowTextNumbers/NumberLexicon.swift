enum NumberLexicon {
    static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    static let ordinalUnits: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
        "eighth": 8, "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13,
        "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17,
        "eighteenth": 18, "nineteenth": 19,
    ]
    static let ordinalTens: [String: Int] = [
        "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50,
        "sixtieth": 60, "seventieth": 70, "eightieth": 80, "ninetieth": 90,
    ]
    static let scales: [String: UInt64] = [
        "thousand": 1_000, "lakh": 100_000, "lakhs": 100_000, "million": 1_000_000,
        "crore": 10_000_000, "crores": 10_000_000, "billion": 1_000_000_000, "trillion": 1_000_000_000_000,
    ]
    static let indianScaleNames: [UInt64: String] = [100_000: "lakh", 10_000_000: "crore"]
    static let indianScales: Set<UInt64> = [100_000, 10_000_000]
    static let compactSuffixes: [Character: UInt64] = ["k": 1_000, "m": 1_000_000, "b": 1_000_000_000, "t": 1_000_000_000_000]
    static let abbreviations: [(scale: UInt64, label: String)] = [
        (1_000_000_000_000, "T"), (1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K"),
    ]
    static let centuries: [String: Int] = ["seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20]
    static let currencies: [String: String] = [
        "dollar": "$", "dollars": "$", "buck": "$", "bucks": "$",
        "euro": "€", "euros": "€", "rupee": "₹", "rupees": "₹", "quid": "£",
    ]
    static let currencySymbols: Set<Character> = ["$", "€", "£", "₹"]
    static let modelNouns: Set<String> = ["parameter", "parameters", "param", "params", "model", "models"]
    static let yearCues: Set<String> = ["in", "since", "year", "until", "till", "during", "circa", "by"]
}
