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
}
