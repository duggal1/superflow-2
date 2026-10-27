import XCTest
import SuperflowKernel
@testable import SuperflowTextNumbers

final class NumbersStageTests: XCTestCase {
    private func run(_ input: String, _ tweak: (inout AppSettings) -> Void = { _ in }) async -> String {
        var settings = AppSettings.default
        tweak(&settings)
        return await NumbersStage().apply(TranscriptDraft(text: input),
                                          context: TextContext(settings: settings)).text
    }

    func testCurrencyTableCoversLaunchCurrencies() {
        XCTAssertEqual(Set(NumberTables.currencies.values.map(\.symbol)), ["$", "€", "£", "₹"])
        XCTAssertEqual(NumberTables.group(500_000, grouping: .indian), "5,00,000")
        XCTAssertEqual(NumberTables.group(10_000_000, grouping: .indian), "1,00,00,000")
        XCTAssertEqual(NumberTables.group(500_000, grouping: .western), "500,000")
    }

    func testCurrencyGoldens() async {
        let cases: [(String, String)] = [
            ("fifty dollars", "$50"),
            ("fifty euros", "€50"),
            ("fifty pounds", "£50"),
            ("five hundred rupees", "₹500"),
            ("two hundred thousand dollars", "$200k"),
            ("two million dollars", "$2M"),
            ("two point five million dollars", "$2.5M"),
            ("a thousand dollars", "$1k"),
            ("nine hundred ninety nine thousand dollars", "$999k"),
            ("two thousand five hundred dollars", "$2,500"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testIndianGroupingAndLakhCrore() async {
        let lakh = await run("five lakh rupees")
        let crore = await run("ten crore rupees")
        let lakhFull = await run("five lakh rupees") { $0.numberStyle = .full }
        let croreFull = await run("ten crore rupees") { $0.numberStyle = .full }
        let mixedFull = await run("one lakh twenty thousand rupees") { $0.numberStyle = .full }
        XCTAssertEqual(lakh, "₹5L")
        XCTAssertEqual(crore, "₹10Cr")
        XCTAssertEqual(lakhFull, "₹5,00,000")
        XCTAssertEqual(croreFull, "₹10,00,00,000")
        XCTAssertEqual(mixedFull, "₹1,20,000")
    }

    func testFullNumberStyle() async {
        let dollars = await run("two hundred thousand dollars") { $0.numberStyle = .full }
        let millions = await run("two million") { $0.numberStyle = .full }
        let decimalMillions = await run("two point five million") { $0.numberStyle = .full }
        XCTAssertEqual(dollars, "$200,000")
        XCTAssertEqual(millions, "2,000,000")
        XCTAssertEqual(decimalMillions, "2,500,000")
    }

    func testPercentages() async {
        let cases: [(String, String)] = [
            ("a hundred percent", "100%"),
            ("fifty percent", "50%"),
            ("fifty per cent", "50%"),
            ("two point five percent", "2.5%"),
            ("zero percent", "0%"),
            ("one hundred percent", "100%"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testYears() async {
        let cases: [(String, String)] = [
            ("nineteen ninety nine", "1999"),
            ("in twenty twenty six we shipped", "in 2026 we shipped"),
            ("the year two thousand twenty six", "the year 2026"),
            ("twenty twenty", "2020"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testOrdinalsOnlyInContext() async {
        let cases: [(String, String)] = [
            ("march third", "march 3rd"),
            ("january second", "january 2nd"),
            ("the twenty first of march", "the 21st of march"),
            ("the third floor", "the 3rd floor"),
            ("twenty first century", "21st century"),
            ("the forty second attempt", "the 42nd attempt"),
            ("i was first", "i was first"),
            ("the first time", "the first time"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testDecimals() async {
        let cases: [(String, String)] = [
            ("three point one four", "3.14"),
            ("zero point five", "0.5"),
            ("two point oh five", "2.05"),
            ("two point five kilograms", "2.5 kilograms"),
            ("two point five million", "2.5M"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testZeroThroughNineStayWordsInProse() async {
        let cases = ["zero", "one apple", "nine apples", "i have two cats", "one two three"]
        for input in cases {
            let output = await run(input)
            XCTAssertEqual(output, input)
        }
        let degrees = await run("zero degrees")
        let percent = await run("nine percent")
        let dollar = await run("one dollar")
        let digits = await run("two cats") { $0.spellOutSmallNumbers = false }
        XCTAssertEqual(degrees, "0 degrees")
        XCTAssertEqual(percent, "9%")
        XCTAssertEqual(dollar, "$1")
        XCTAssertEqual(digits, "2 cats")
    }

    func testBareDigitGroupingAndExceptions() async {
        let cases: [(String, String)] = [
            ("we sold 1250000 units", "we sold 1,250,000 units"),
            ("we sold 90210 units", "we sold 90,210 units"),
            ("call 12345678 now", "call 12345678 now"),
            ("phone +15551234567", "phone +15551234567"),
            ("zip code 90210", "zip code 90210"),
            ("id 123456789", "id 123456789"),
            ("order 123456", "order 123456"),
            ("version 2.0", "version 2.0"),
            ("the year 2026", "the year 2026"),
            ("invoice 0012345", "invoice 0012345"),
            ("tracking 123456789012345", "tracking 123456789012345"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testNeverConvertsTokensThatAlreadyContainDigits() async {
        let input = "version 2.0 costs 5 dollars and 3 cats"
        let output = await run(input)
        XCTAssertEqual(output, input)
    }

    func testProtectedSpans() async {
        let url = "see https://example.com/2026 for two hundred dollars"
        let urlOutput = await run(url)
        XCTAssertEqual(urlOutput, "see https://example.com/2026 for $200")

        let phrase = "two hundred dollars"
        let literal = await NumbersStage().apply(
            TranscriptDraft(text: phrase, protected: Protected(literals: [phrase])),
            context: TextContext()).text
        XCTAssertEqual(literal, phrase)
    }

    func testWhitespaceOutsideSpansIsPreserved() async {
        let doubleSpace = await run("hello  world")
        let phrase = await run("two  hundred   dollars")
        let tab = await run("a\tb")
        XCTAssertEqual(doubleSpace, "hello  world")
        XCTAssertEqual(phrase, "$200")
        XCTAssertEqual(tab, "a\tb")
    }

    func testUnicodeAndEmoji() async {
        let emoji = await run("😀 two hundred dollars")
        let cjk = await run("这是 two hundred dollars")
        let accent = await run("café five dollars")
        XCTAssertEqual(emoji, "😀 $200")
        XCTAssertEqual(cjk, "这是 $200")
        XCTAssertEqual(accent, "café $5")
    }

    func testIdempotentCorpus() async {
        let corpus = [
            "two hundred thousand dollars today", "twenty twenty six was good",
            "call 12345678 now", "march third at two point five million",
            "five lakh rupees and ten crore rupees", "fifty per cent of 1250000",
            "😀 two point five percent", "the forty second attempt",
        ]
        for input in corpus {
            let once = await run(input)
            let twice = await run(once)
            XCTAssertEqual(once, twice, "input: \(input)")
        }
    }

    func testEmptyAndWhitespace() async {
        let empty = await run("")
        let spaces = await run("   ")
        let newlines = await run("\n\n")
        XCTAssertEqual(empty, "")
        XCTAssertEqual(spaces, "   ")
        XCTAssertEqual(newlines, "\n\n")
    }

    func testBoundedGrowthOnLargeInput() async {
        let input = String(repeating: "two hundred dollars and ", count: 2_000)
        let output = await run(input)
        XCTAssertLessThanOrEqual(output.count, input.count + 64)
        XCTAssertEqual(output.components(separatedBy: "$200").count - 1, 2_000)
    }
}
