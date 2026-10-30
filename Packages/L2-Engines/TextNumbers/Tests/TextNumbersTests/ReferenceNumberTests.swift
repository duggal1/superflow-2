import XCTest
import SuperflowKernel
@testable import SuperflowTextNumbers

final class ReferenceNumberTests: XCTestCase {
    func testNumericScalesAndProtectedValues() async {
        var settings = AppSettings.default
        settings.numberStyle = .abbreviated
        let stage = NumberCleanupStage()
        for (input, expected) in [("0.6 billion", "0.6B"), ("2.2 trillion", "2.2T"),
                                  ("half 1M", "0.5M")] {
            let output = await stage.apply(TranscriptDraft(text: input), context: TextContext(settings: settings))
            XCTAssertEqual(output.text, expected, input)
        }
        let input = "0.6 billion"
        let output = await stage.apply(TranscriptDraft(text: input, protected: Protected(literals: [input])),
                                       context: TextContext(settings: settings))
        XCTAssertEqual(output.text, input)
    }
    func testCompactTechnicalQuantities() {
        var options = NumberOptions()
        options.largeNumberStyle = .abbreviated
        for (input, expected) in [("zero point six billion", "0.6B"),
                                  ("half a million", "0.5M"),
                                  ("half a million dollars", "$0.5M"),
                                  ("six hundred million parameter model", "600M parameter model")] {
            XCTAssertEqual(render(input, options: options), expected, input)
        }
    }
    private func render(_ input: String, options: NumberOptions = .init()) -> String {
        Tokenizer.join(TextNumbers.apply(Tokenizer.words(input), options))
    }

    func testReferenceTableAndExtendedGoldens() {
        var cases: [(String, String)] = [
            ("five hundred", "500"), ("four two nine", "429"), ("four oh four", "404"),
            ("one billion", "1,000,000,000"), ("three trillion", "3,000,000,000,000"),
            ("twenty three thousand four hundred and fifty dollars", "$23,450"),
            ("twenty euros", "€20"), ("fifty percent", "50%"), ("three point five", "3.5"),
            ("version two point one point three", "version 2.1.3"), ("a hundred and one", "101"),
            ("one point five million dollars", "$1.5 million"),
            ("ten dollars and fifty cents", "$10.50"), ("march third twenty twenty six", "march 3 2026"),
            ("three fifteen p m", "3:15pm"), ("no one knows", "no one knows"),
            ("the first one", "the first one"), ("twenty first", "21st"),
            ("six hundred twenty megabytes", "620 MB"),
        ]
        let amounts = [
            ("zero", "0"), ("one", "1"), ("two", "2"), ("nine", "9"), ("ten", "10"),
            ("eleven", "11"), ("twelve", "12"), ("nineteen", "19"), ("twenty", "20"),
            ("twenty one", "21"), ("thirty two", "32"), ("forty three", "43"),
            ("fifty four", "54"), ("sixty five", "65"), ("seventy six", "76"),
            ("eighty seven", "87"), ("ninety eight", "98"), ("ninety nine", "99"),
            ("one hundred", "100"), ("one hundred and one", "101"),
            ("two hundred fifty", "250"), ("nine hundred ninety nine", "999"),
            ("one thousand", "1,000"), ("two thousand five hundred", "2,500"),
            ("one million", "1,000,000"),
        ]
        for (spoken, written) in amounts {
            cases.append((spoken, written))
            for (currency, symbol) in [("dollars", "$"), ("euros", "€"), ("pounds", "£"), ("rupees", "₹"), ("yen", "¥")] {
                cases.append(("pay " + spoken + " " + currency, "pay " + symbol + written))
            }
        }
        cases += [
            ("january first", "january 1"), ("february second", "february 2"),
            ("march tenth", "march 10"), ("april eleventh", "april 11"),
            ("may twelfth", "may 12"), ("june thirteenth", "june 13"),
            ("july twentieth", "july 20"), ("august twenty first", "august 21"),
            ("september twenty second", "september 22"), ("october twenty third", "october 23"),
            ("november thirtieth", "november 30"), ("december thirty first", "december 31"),
            ("in nineteen ninety nine", "in 1999"), ("since twenty oh five", "since 2005"),
            ("year twenty twenty six", "year 2026"), ("in two thousand twenty six", "in 2026"),
            ("three am", "3am"), ("twelve p m", "12pm"), ("nine oh five am", "9:05am"),
            ("eleven fifty nine pm", "11:59pm"), ("one ten a m", "1:10am"),
            ("version one point zero point two", "version 1.0.2"),
            ("version zero point nine", "version 0.9"), ("zero point zero five", "0.05"),
            ("one dollar and one cent", "$1.01"), ("two euros and nine cents", "€2.09"),
            ("nine pounds and ninety nine cents", "£9.99"),
            ("four gigabytes", "4 GB"), ("two kilobytes", "2 KB"), ("three terabytes", "3 TB"),
            ("five milliseconds", "5 ms"), ("ten hertz", "10 Hz"),
            ("six kilohertz", "6 kHz"), ("seven megahertz", "7 MHz"), ("eight gigahertz", "8 GHz"),
            ("no one", "no one"), ("one of us", "one of us"), ("one more time", "one more time"),
            ("each one", "each one"), ("one day", "one day"), ("the first", "the first"),
            ("second opinion", "second opinion"), ("third choice", "third choice"),
            ("eleventh", "11th"), ("twelfth", "12th"), ("thirteenth", "13th"),
            ("twenty second", "22nd"), ("twenty third", "23rd"), ("thirty first", "31st"),
            ("three point one four", "3.14"), ("two point five billion", "2.5 billion"),
            ("five crore", "50,000,000"), ("five lakhs", "500,000"),
        ]
        XCTAssertGreaterThanOrEqual(cases.count, 200)
        for (input, expected) in cases { XCTAssertEqual(render(input), expected, input) }
    }

    func testOptionsAndIndianGrouping() {
        var options = NumberOptions()
        options.grouping = .indian
        XCTAssertEqual(render("five lakh rupees", options: options), "₹5,00,000")
        XCTAssertEqual(render("ten crore", options: options), "10,00,00,000")
        options.small = .words
        XCTAssertEqual(render("three apples and five euros", options: options), "three apples and €5")
        options.largeNumberStyle = .abbreviated
        XCTAssertEqual(render("two million dollars", options: options), "$2M")
    }

    func testProtectedAndGluedWordsSurvive() {
        var words = Tokenizer.words("one hundred three point five")
        words[0].protected = true
        words[0].glue = true
        words[1].protected = true
        let actual = TextNumbers.apply(words)
        XCTAssertEqual(Tokenizer.join(actual), "one hundred 3.5")
        XCTAssertEqual(Array(actual.prefix(2)), Array(words.prefix(2)))
        XCTAssertEqual(render("MAX_RETRY_COUNT 429 hero.tsx $23,450"), "MAX_RETRY_COUNT 429 hero.tsx $23,450")
    }

    func testPunctuationStopsNumbersAndSuffixConsumption() {
        let cases = [
            ("one. hundred", "1. hundred"), ("three. fifteen pm", "3. 15 pm"),
            ("ten, dollars", "10, dollars"), ("three point one, point two", "3.1, point 2"),
            ("four, two nine", "4, 2 9"), ("ten dollars. and fifty cents", "$10. and 50 cents"),
        ]
        for (input, expected) in cases { XCTAssertEqual(render(input), expected, input) }
    }

    func testIdempotenceAndProducedProtection() {
        for input in ["version two point one point three", "ten dollars and fifty cents", "four two nine", "five lakh rupees"] {
            let words = TextNumbers.apply(Tokenizer.words(input))
            XCTAssertEqual(TextNumbers.apply(words), words)
            XCTAssertEqual(render(Tokenizer.join(words)), Tokenizer.join(words))
            XCTAssertTrue(words.contains(where: \.protected))
        }
    }

    func testOverflowAndMalformedMagnitudeNeverTrap() {
        let huge = "nineteen hundred quadrillion nine hundred trillion"
        XCTAssertFalse(render(huge).isEmpty)
        let repeated = Array(repeating: "nine hundred", count: 200).joined(separator: " ")
        XCTAssertFalse(render(repeated).isEmpty)
        XCTAssertEqual(render("one hundred hundred"), "100 hundred")
        XCTAssertEqual(render("one quadrillion"), "1,000,000,000,000,000")
    }

    func testListMarkersStayUnprotectedForListPlanner() async {
        let input = "tasks number one fix the parser number two check the input number three update the tests"
        let words = TextNumbers.apply(Tokenizer.words(input))
        XCTAssertEqual(Tokenizer.join(words), input)
        for index in words.indices where ["one", "two", "three"].contains(words[index].key) {
            XCTAssertFalse(words[index].protected)
        }
        var settings = AppSettings.default
        settings.spellOutSmallNumbers = false
        let result = await NumberCleanupStage().apply(TranscriptDraft(text: input),
                                                       context: TextContext(settings: settings))
        XCTAssertEqual(result.text, input)
        XCTAssertFalse(result.protected.literals.contains("one"))
        XCTAssertFalse(result.protected.literals.contains("two"))
        XCTAssertFalse(result.protected.literals.contains("three"))
        XCTAssertEqual(render("number one hundred"), "number 100")
        XCTAssertEqual(render("number one two three"), "number 123")
    }
}
