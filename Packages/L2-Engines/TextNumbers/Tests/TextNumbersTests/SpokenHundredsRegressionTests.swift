import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextNumbers

/// Regression for fact corruption found by the aggressive transcription corpus:
/// spoken implied hundreds ("one forty" = 140) must render as digits, not as
/// "one 40". This matters most in medical dictation (blood pressure) where a
/// split number is a clinical error, not a formatting nit.
///
/// These tests exercise the LIVE production number path: `NumberCleanupStage`
/// is the stage `Tier0Adapters.NumbersAdapter` actually installs in the real
/// pipeline (after the legacy `NumbersStage` was retired). Nothing here uses
/// the dead adapter, and no assertion accepts the corrupted caliber "556".
final class SpokenHundredsRegressionTests: XCTestCase {
    private func clean(_ raw: String) async -> String {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.spellOutSmallNumbers = false
        let draft = TranscriptDraft(text: raw)
        return await NumberCleanupStage().apply(draft, context: TextContext(settings: settings)).text
    }

    func testSpokenImpliedHundredsRenderAsOneNumber() async {
        // (input, required exact output, split/corrupted negative)
        let cases: [(String, String, String)] = [
            ("blood pressure one forty over ninety", "blood pressure 140/90", "one 40"),
            ("one thirty over eighty", "130 over 80", "one 30"),
            ("two fifty dollars", "$250", "two 50"),
            ("weight is one ninety five kilograms", "weight is 195 kilograms", "one 95"),
        ]
        for (input, expected, corrupted) in cases {
            let out = await clean(input)
            XCTAssertEqual(out, expected,
                           "spoken implied hundreds corrupted: \"\(input)\" -> \"\(out)\" (wanted \(expected))")
            XCTAssertFalse(out.contains(corrupted),
                           "number left split/corrupted in \"\(out)\" (forbidden \(corrupted))")
        }
    }

    func testFillerBetweenNumberHalvesDoesNotSplitTheFact() async {
        let out = await clean("the sample temperature was thirty you know seven degrees Celsius")
        XCTAssertEqual(out, "the sample temperature was 37 degrees Celsius")
        XCTAssertFalse(out.contains("you know 7"), "filler left inside number: \(out)")
    }

    func testOrdinaryProseKeepsItsWords() async {
        let out = await clean("I know you mean well but the thirty seven degrees was measured")
        XCTAssertEqual(out, "I know you mean well but the 37 degrees was measured")
        XCTAssertTrue(out.lowercased().contains("know"), "ordinary word dropped: \(out)")
    }

    func testSpokenCaliberIsNotCollapsedToCorruptedInteger() async {
        // D3: a spoken digit run in a calibre context ("... five five six rounds")
        // is a decimal calibre (5.56), never the integer 556.
        let out = await clean("do you have any five five six rounds")
        XCTAssertEqual(out, "do you have any 5.56 rounds")
        XCTAssertFalse(out.contains("500"), out)
        XCTAssertFalse(out.contains("556"), out)
    }
}
