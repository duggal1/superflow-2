import Foundation
import XCTest
import SuperflowKernel
@testable import SuperflowTextNumbers

/// Exact-form guards for the official S1-mini v1 examples and the fact-bearing
/// numbers called out in the quality sweep. Every assertion here runs the LIVE
/// production path (`NumberCleanupStage` -> `TextNumbers.apply`), never the
/// retired `NumbersStage` adapter. A split year ("20 22"), a corrupted calibre
/// ("556"), or a split blood pressure ("140 over 90") is a FAIL, not an
/// acceptable alternative form.
final class OfficialExampleExactTests: XCTestCase {
    private func clean(_ raw: String) async -> String {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.spellOutSmallNumbers = false
        return await NumberCleanupStage().apply(
            TranscriptDraft(text: raw),
            context: TextContext(settings: settings)
        ).text
    }

    /// Mirrors the two deterministic number stages `Tier0Adapters.NumbersAdapter`
    /// installs in the real pipeline: `NumberCleanupStage` followed by
    /// `TextNumbersStage`. A fact that survives only the first stage is not
    /// enough — the second must not re-split it.
    private func fullNumbers(_ raw: String) async -> String {
        let first = await clean(raw)
        var config = TextNumbersConfig()
        config.smallNumberThreshold = 0
        var words = Tokenizer.words(first)
        for index in words.indices {
            let core = words[index].core
            let numeric = core.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
                && core.contains(where: \.isNumber)
            if numeric { words[index].isProtected = false }
            words[index].glue = false
        }
        return TextNumbersStage(config: config).apply(TextDraft(words: words)).text
    }

    func testFactsSurviveBothLiveNumberStages() async {
        let pressure = await fullNumbers("blood pressure one forty over ninety")
        let coordinate = await fullNumbers("at three seven point four north")
        let year = await fullNumbers("twenty twenty two")
        let calibre = await fullNumbers("do you have any five five six rounds")
        let invoice = await fullNumbers("the invoice came to twenty three thousand four hundred and fifty dollars")
        XCTAssertEqual(pressure, "blood pressure 140/90")
        XCTAssertEqual(coordinate, "at 37.4 north")
        XCTAssertEqual(year, "2022")
        XCTAssertEqual(calibre, "do you have any 5.56 rounds")
        XCTAssertEqual(invoice, "the invoice came to $23,450")
    }

    // MARK: Official example 1 — invoice, date and year

    func testOfficialInvoiceExampleExact() async {
        let out = await clean("the invoice came to twenty three thousand four hundred and fifty dollars and it's due on march third twenty twenty six")
        XCTAssertEqual(out, "the invoice came to $23,450 and it's due on march 3 2026")
        // The clause comma and sentence casing belong to S1-mini / final polish;
        // the deterministic numbered facts must already be exact here:
        // "$23,450", "3", "2026" — never "23450", "third", "20 22" or "20 26".
        XCTAssertFalse(out.contains("20 22"))
        XCTAssertFalse(out.contains("20 26"))
        XCTAssertFalse(out.contains("23450"))
    }

    // MARK: Official example 2 — time revision

    func testOfficialTimeExampleExact() async {
        let spoken = await clean("let's meet at three fifteen p m tomorrow")
        XCTAssertEqual(spoken, "let's meet at 3:15pm tomorrow")

        // SelfCorrectionStage (upstream, not owned here) drops the abandoned
        // "half past two ... actually make it". Once only the final time
        // reaches the number stage it must render exactly once — never a
        // second "2:30" alongside the corrected "3:15pm".
        let corrected = await clean("let's meet at 3:15pm tomorrow")
        XCTAssertEqual(corrected, "let's meet at 3:15pm tomorrow")
        XCTAssertEqual(corrected.components(separatedBy: ":").count - 1, 1)
        XCTAssertFalse(corrected.contains("2:30"))
        XCTAssertFalse(corrected.contains("3:15pm:"))
    }

    // MARK: Official example 4 — self-corrected answer

    func testOfficialSelfCorrectionExampleExact() async {
        // The number stage digitizes both spoken answers; S1-mini discards the
        // abandoned "42 no sorry". Neither value may ever stay spelled out.
        let raw = await clean("i think the answer is forty two no sorry forty three")
        XCTAssertEqual(raw, "i think the answer is 42 no sorry 43")

        let corrected = await clean("i think the answer is 43")
        XCTAssertEqual(corrected, "i think the answer is 43")
    }

    // MARK: Requirement 1 — years never split

    func testBareYearIsOneTokenExact() async {
        let cases: [(String, String)] = [
            ("twenty twenty two", "2022"),
            ("nineteen eighty four", "1984"),
            ("in twenty twenty six we shipped", "in 2026 we shipped"),
            ("the year was twenty twenty two.", "the year was 2022."),
        ]
        for (input, expected) in cases {
            let out = await clean(input)
            XCTAssertEqual(out, expected, "input: \(input)")
            XCTAssertFalse(out.contains("20 22"), "split year in: \(input) -> \(out)")
        }
    }

    // MARK: Requirement 2 — medical and coordinate facts

    func testBloodPressureExact() async {
        let out = await clean("blood pressure one forty over ninety")
        let withIs = await clean("blood pressure is one thirty over eighty")
        XCTAssertEqual(out, "blood pressure 140/90")
        XCTAssertEqual(withIs, "blood pressure is 130/80")
        XCTAssertFalse(out.contains("one 40"))
        XCTAssertFalse(out.contains("one 30"))
    }

    func testCoordinateDecimalsExact() async {
        let out = await clean("at three seven point four north one one two point eight east")
        XCTAssertEqual(out, "at 37.4 north 112.8 east")
        XCTAssertFalse(out.contains("3 7.4"))
        XCTAssertFalse(out.contains("1 one 2.8"))
    }

    // MARK: Requirement 3 — calibre decimal, other digit runs intact

    func testCalibreDecimalExactWithoutDigitRunRegression() async {
        let rounds = await clean("do you have any five five six rounds")
        let ammo = await clean("i've got five five six ammo")
        // Unrelated digit runs keep their deterministic integer rendering.
        let status = await clean("the status code is four two nine")
        let port = await clean("port four zero three")
        let code = await clean("four oh four")
        XCTAssertEqual(rounds, "do you have any 5.56 rounds")
        XCTAssertEqual(ammo, "i've got 5.56 ammo")
        XCTAssertEqual(status, "the status code is 429")
        XCTAssertEqual(port, "port 403")
        XCTAssertEqual(code, "404")
    }
}
