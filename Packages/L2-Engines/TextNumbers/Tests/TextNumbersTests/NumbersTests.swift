import XCTest
import SuperflowKernel
@testable import SuperflowTextNumbers

final class NumbersTests: XCTestCase {
    private func run(_ input: String, _ tweak: (inout AppSettings) -> Void = { _ in }) async -> String {
        var settings = AppSettings.default
        tweak(&settings)
        return await NumbersStage().apply(TranscriptDraft(text: input),
                                          context: TextContext(settings: settings)).text
    }

    func testGolden() async {
        let cases: [(String, String)] = [
            ("two hundred dollars", "$200"),
            ("two hundred thousand dollars", "$200k"),
            ("two million", "2M"),
            ("two point five million", "2.5M"),
            ("one thousand two hundred fifty dollars", "$1,250"),
            ("a hundred percent", "100%"),
            ("twenty twenty six", "2026"),
            ("I have two cats", "I have two cats"),
            ("five kilograms of rice", "5 kilograms of rice"),
            ("twenty five", "25"),
            ("it costs fifty dollars.", "it costs $50."),
            ("march third", "march 3rd"),
            ("one two three", "one two three"),
            ("twenty five thousand", "25k"),
            ("two hundred and five", "205"),
            ("three point one four", "3.14"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testFullStyle() async {
        let actual = await run("two hundred thousand dollars") { $0.numberStyle = .full }
        XCTAssertEqual(actual, "$200,000")
    }

    func testSmallNumberSettingOff() async {
        let actual = await run("I have two cats") { $0.spellOutSmallNumbers = false }
        XCTAssertEqual(actual, "I have 2 cats")
    }

    func testIdempotent() async {
        for input in ["two hundred thousand dollars today", "twenty twenty six was good",
                      "call 12345678 now", "march third at two point five million"] {
            let once = await run(input)
            let twice = await run(once)
            XCTAssertEqual(once, twice, "input: \(input)")
        }
    }

    func testBareDigits() async {
        let actual = await run("we sold 1250000 units")
        XCTAssertEqual(actual, "we sold 1,250,000 units")
    }

    func testProtectedURL() async {
        let input = "see https://example.com/2026 for two hundred dollars"
        let actual = await run(input)
        XCTAssertEqual(actual, "see https://example.com/2026 for $200")
    }

    func testNeverTouchesExistingDigits() async {
        let actual = await run("version 2.0 costs 5 dollars")
        XCTAssertEqual(actual, "version 2.0 costs 5 dollars")
    }

    func testEmpty() async {
        let empty = await run("")
        let spaces = await run("   ")
        XCTAssertEqual(empty, "")
        XCTAssertEqual(spaces, "   ")
    }

    // MARK: Large scales

    func testTrillionAbbreviatesAndFullExpands() async {
        let actual = await run("three trillion dollars")
        XCTAssertEqual(actual, "$3T")
        let full = await run("three trillion dollars") { $0.numberStyle = .full }
        XCTAssertEqual(full, "$3,000,000,000,000")
        let round = await run("two trillion") { $0.numberStyle = .full }
        XCTAssertEqual(round, "2,000,000,000,000")
    }

    func testQuadrillionAbbreviatesAndFullExpands() async {
        let full = await run("two point five quadrillion") { $0.numberStyle = .full }
        XCTAssertEqual(full, "2,500,000,000,000,000")
        let abbrev = await run("one quadrillion")
        XCTAssertEqual(abbrev, "1Qa")
    }

    func testFullBillion() async {
        let actual = await run("two billion dollars") { $0.numberStyle = .full }
        XCTAssertEqual(actual, "$2,000,000,000")
    }

    // MARK: Spoken identifier runs

    func testSpokenCodeRunNeedsCodeContext() async {
        let status = await run("the status code is four two nine")
        XCTAssertEqual(status, "the status code is 429")
        let exit = await run("the exit code was five nine")
        XCTAssertEqual(exit, "the exit code was 59")
        // Counting and enumeration speech has no code context and stays words.
        XCTAssertEqual(await run("one two three"), "one two three")
        let prose = await run("the answer four two nine nobody knows")
        XCTAssertEqual(prose, "the answer four two nine nobody knows")
        // Interior punctuation breaks the run: it is a list, not an identifier.
        let listed = await run("the error code values are four, two nine")
        XCTAssertEqual(listed, "the error code values are four, two nine")
    }

    // MARK: Spoken small ranges

    func testSpokenFromToRangeStaysDigitsUnderSpellOut() async {
        let range = await run("set the retry count from three to five")
        XCTAssertEqual(range, "set the retry count from 3 to 5")
        // Not a range shape: "three to five" without "from" keeps the words.
        let words = await run("three to five options")
        XCTAssertEqual(words, "three to five options")
    }

    // MARK: Euro currency

    func testEuroCurrency() async {
        let cost = await run("it costs twenty five euros")
        XCTAssertEqual(cost, "it costs €25")
        let bare = await run("ten euros")
        XCTAssertEqual(bare, "€10")
    }
}
