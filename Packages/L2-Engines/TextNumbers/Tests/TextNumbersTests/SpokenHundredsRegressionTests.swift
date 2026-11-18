import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextNumbers

/// Regression for fact corruption found by the aggressive transcription corpus:
/// spoken implied hundreds ("one forty" = 140) must render as digits, not as
/// "one 40". This matters most in medical dictation (blood pressure) where a
/// split number is a clinical error, not a formatting nit.
final class SpokenHundredsRegressionTests: XCTestCase {
    private func clean(_ raw: String) async -> String {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.spellOutSmallNumbers = false
        let draft = TranscriptDraft(text: raw)
        return await NumbersStage().apply(draft, context: TextContext(settings: settings)).text
    }

    func testSpokenImpliedHundredsRenderAsOneNumber() async {
        let cases: [(String, String)] = [
            ("blood pressure one forty over ninety", "140"),
            ("one thirty over eighty", "130"),
            ("two fifty dollars", "250"),
            ("weight is one ninety five pounds", "195"),
        ]
        for (input, expected) in cases {
            let out = await clean(input)
            XCTAssertTrue(out.contains(expected),
                          "spoken implied hundreds corrupted: \"\(input)\" -> \"\(out)\" (wanted \(expected))")
            XCTAssertFalse(out.contains("one \(expected.dropFirst())"),
                           "number left split in \"\(out)\"")
        }
    }

    func testDigitRunsAreStillSeparateNumbers() async {
        // "five five six" is a digit run, not implied hundreds — a decade word
        // is required for the hundreds rule. Keep the original behaviour.
        let out = await clean("do you have any five five six rounds")
        XCTAssertFalse(out.contains("500"), out)
        XCTAssertFalse(out.contains("56"), out)
    }
}
