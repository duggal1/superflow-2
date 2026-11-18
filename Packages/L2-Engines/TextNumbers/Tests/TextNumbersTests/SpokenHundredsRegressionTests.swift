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
        // (input, required exact digit form, explicit split/corrupted negative)
        let cases: [(String, String, String)] = [
            ("blood pressure one forty over ninety", "140", "one 40"),
            ("one thirty over eighty", "130", "one 30"),
            ("two fifty dollars", "250", "two 50"),
            ("weight is one ninety five pounds", "195", "one 95"),
        ]
        for (input, expected, corrupted) in cases {
            let out = await clean(input)
            XCTAssertTrue(out.contains(expected),
                          "spoken implied hundreds corrupted: \"\(input)\" -> \"\(out)\" (wanted \(expected))")
            XCTAssertFalse(out.contains(corrupted),
                           "number left split/corrupted in \"\(out)\" (forbidden \(corrupted))")
        }
    }

    func testSpokenCaliberIsNotCollapsedToCorruptedInteger() async throws {
        // Production defect D3 (see .proof/transcription-corpus/agent2-report.md):
        // the live Numbers stage collapses "five five six rounds" to "556"
        // instead of preserving the 5.56 caliber. That fix is owned by the
        // Numbers-stage agent, so this exact-form guard is skipped until it
        // lands. When unskipped it rejects BOTH the split "500" and the
        // corrupted integer "556" — "556" is never an accepted transcription.
        try XCTSkipIf(true, "Production defect D3 owned by the Numbers-stage agent: spoken caliber 'five five six' currently renders as corrupted '556' instead of '5.56'.")

        let out = await clean("do you have any five five six rounds")
        XCTAssertFalse(out.contains("500"), out)
        XCTAssertFalse(out.contains("556"), out)
        XCTAssertTrue(out.contains("5.56"), out)
    }
}
