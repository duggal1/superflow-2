import Foundation

enum NumberGrouping: Sendable {
    case western
    case indian
}

struct CurrencySpec: Sendable, Equatable {
    let symbol: String
    let grouping: NumberGrouping
}

enum NumberTables {
    static let units: [String: Int64] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19,
    ]
    static let tens: [String: Int64] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    static let scales: [String: Int64] = [
        "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000,
        "lakh": 100_000, "crore": 10_000_000,
    ]
    /// Only a phrase that ends on the scale word abbreviates, so
    /// "one thousand two hundred fifty" stays "$1,250".
    static let abbrevSuffix: [String: String] = [
        "thousand": "k", "million": "M", "billion": "B", "lakh": "L", "crore": "Cr",
    ]

    /// Data-driven currency table. Add words here, not in the parser.
    static let currencies: [String: CurrencySpec] = [
        "dollar": CurrencySpec(symbol: "$", grouping: .western),
        "dollars": CurrencySpec(symbol: "$", grouping: .western),
        "buck": CurrencySpec(symbol: "$", grouping: .western),
        "bucks": CurrencySpec(symbol: "$", grouping: .western),
        "usd": CurrencySpec(symbol: "$", grouping: .western),
        "euro": CurrencySpec(symbol: "€", grouping: .western),
        "euros": CurrencySpec(symbol: "€", grouping: .western),
        "eur": CurrencySpec(symbol: "€", grouping: .western),
        "pound": CurrencySpec(symbol: "£", grouping: .western),
        "pounds": CurrencySpec(symbol: "£", grouping: .western),
        "quid": CurrencySpec(symbol: "£", grouping: .western),
        "gbp": CurrencySpec(symbol: "£", grouping: .western),
        "rupee": CurrencySpec(symbol: "₹", grouping: .indian),
        "rupees": CurrencySpec(symbol: "₹", grouping: .indian),
        "inr": CurrencySpec(symbol: "₹", grouping: .indian),
    ]
    static let measures: Set<String> = [
        "kilometer", "kilometers", "kilometre", "kilometres", "kilogram", "kilograms",
        "gram", "grams", "mile", "miles", "meter", "meters", "metre", "metres",
        "feet", "foot", "inch", "inches", "yard", "yards", "pound", "pounds",
        "gigabyte", "gigabytes", "megabyte", "megabytes", "kilobyte", "kilobytes",
        "terabyte", "terabytes", "byte", "bytes", "millisecond", "milliseconds",
        "second", "seconds", "minute", "minutes", "hour", "hours", "day", "days",
        "week", "weeks", "month", "months", "year", "years", "degrees", "degree",
        "mph", "kph", "kg", "km", "cm", "mm", "gb", "mb", "tb", "ms", "hz", "ghz",
        "mhz", "watts", "watt", "volts", "volt", "amps", "amp", "calories", "calorie",
        "liters", "liter", "litres", "litre", "milliliters", "milliliter", "ounces",
        "ounce", "cups", "cup", "tablespoons", "tablespoon", "teaspoons", "teaspoon",
    ]
    static let months: Set<String> = [
        "january", "february", "march", "april", "may", "june", "july",
        "august", "september", "october", "november", "december",
    ]
    /// Ordinals only become digits in a date or counting context, so
    /// "I was first" and "the first time" stay prose.
    static let ordinalFollowers: Set<String> = months.union([
        "century", "centuries", "floor", "place", "grade", "avenue", "street",
        "chapter", "part", "section", "quarter", "attempt", "edition", "anniversary",
        "birthday", "prize", "position", "rank", "seat", "base", "half", "round",
    ])
    static let ordinalUnits: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6,
        "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10, "eleventh": 11,
        "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15,
        "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
        "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50,
        "sixtieth": 60, "seventieth": 70, "eightieth": 80, "ninetieth": 90,
        "hundredth": 100, "thousandth": 1_000,
    ]
    /// A digit run that follows one of these words is an identifier, not an amount.
    static let skipSeparatorAfter: Set<String> = [
        "zip", "zipcode", "code", "id", "number", "no", "pin", "ref", "reference",
        "ticket", "order", "invoice", "phone", "call", "version", "v", "isbn", "ssn",
        "ext", "extension", "account", "acct", "serial", "imei", "tracking",
        "confirmation", "booking", "flight", "room", "seat", "gate", "model", "year",
        "roll", "registration", "license", "licence", "passport", "policy",
    ]

    static func isNumberWord(_ w: String) -> Bool {
        units[w] != nil || tens[w] != nil || scales[w] != nil || w == "hundred"
    }

    static func ordinalSuffix(_ n: Int) -> String {
        let mod100 = n % 100
        if (11...13).contains(mod100) { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    static func group(_ n: Int64, grouping: NumberGrouping = .western) -> String {
        let negative = n < 0
        var digits = String(n.magnitude)
        var out = ""
        switch grouping {
        case .western:
            while digits.count > 3 {
                out = "," + digits.suffix(3) + out
                digits.removeLast(3)
            }
        case .indian:
            if digits.count > 3 {
                out = "," + digits.suffix(3) + out
                digits.removeLast(3)
                while digits.count > 2 {
                    out = "," + digits.suffix(2) + out
                    digits.removeLast(2)
                }
            }
        }
        return (negative ? "-" : "") + digits + out
    }
}
