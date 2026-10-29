import XCTest
import SuperflowKernel
@testable import SuperflowTextDisfluency

final class MechanicalDisfluencyTests: XCTestCase {
    private func clean(_ text: String) -> String {
        Tokenizer.join(TextDisfluency.apply(Tokenizer.words(text)))
    }

    func testUseCaseOneMechanicalInput() {
        XCTAssertEqual(clean("okay so um I I I need you to open the the the file hero dot t s x"),
                       "okay so I need you to open the file hero dot t s x")
    }

    func testUseCaseThree() {
        XCTAssertEqual(clean("I I I was thinking about the the the performance and um it keeps saying warming the GPU or warming the CPU and that is really bad"),
                       "I was thinking about the performance and it keeps saying warming the GPU or warming the CPU and that is really bad")
    }

    func testLegitimateDoublesNumbersAndSentencesSurvive() {
        for text in ["had had", "four four", "four two four two", "No. No.", "like you know so well", "ah yes"] {
            XCTAssertEqual(clean(text), text)
        }
    }

    func testProtectedAndGluedWordsAreUntouched() {
        var words = Tokenizer.words("um um the the")
        words[0].protected = true
        words[0].glue = true
        words[2].glue = true
        XCTAssertEqual(TextDisfluency.apply(words), words)
    }

    func testPunctuationAndPauseSurviveDeletions() {
        XCTAssertEqual(clean("hello um."), "hello.")
        XCTAssertEqual(clean("hello, um,"), "hello,")
        XCTAssertEqual(clean("ummm ahh hmmm okay"), "okay")
        XCTAssertEqual(clean("the the."), "the.")
        XCTAssertEqual(clean("(um hello)"), "(hello)")
        var words = Tokenizer.words("hello um")
        words[1].pause = true
        XCTAssertTrue(TextDisfluency.apply(words)[0].pause)
    }

    func testIdempotenceAndOnlyOccurrencesAcrossGeneratedSequences() {
        let alphabet = ["I", "think", "the", "um", "four"]
        for seed in 0..<1_000 {
            var value = seed
            let input = (0..<8).map { _ -> String in
                defer { value = (value * 17 + 11) % 997 }
                return alphabet[value % alphabet.count]
            }.joined(separator: " ")
            let once = clean(input)
            XCTAssertEqual(clean(once), once, input)
            let initial = Set(Tokenizer.words(input).map(\.key)).subtracting(["um"])
            let final = Set(Tokenizer.words(once).map(\.key))
            XCTAssertEqual(initial, final, input)
        }
    }

    func testStageHonorsDuplicateThresholdsAndPhraseToggle() async {
        var settings = DisfluencySettings()
        settings.tierAThreshold = 3
        settings.collapseRepeatedPhrases = false
        let stage = MechanicalDisfluencyStage(settings: settings)
        let doubled = await stage.apply(TranscriptDraft(text: "the the cat"), context: TextContext())
        XCTAssertEqual(doubled.text, "the the cat")
        let tripled = await stage.apply(TranscriptDraft(text: "the the the cat"), context: TextContext())
        XCTAssertEqual(tripled.text, "the cat")
        let phrase = await stage.apply(TranscriptDraft(text: "we need to we need to go"), context: TextContext())
        XCTAssertEqual(phrase.text, "we need to we need to go")
        settings.fillerPrepass = false
        let fillers = await MechanicalDisfluencyStage(settings: settings)
            .apply(TranscriptDraft(text: "um hello"), context: TextContext())
        XCTAssertEqual(fillers.text, "um hello")
    }

    func testStageAllowsFillerOnlyEmptyAndRespectsSettingsAndNewlines() async {
        let stage = MechanicalDisfluencyStage()
        let empty = await stage.apply(TranscriptDraft(text: "um uh"), context: TextContext())
        XCTAssertEqual(empty.text, "")
        XCTAssertEqual(empty.cleanupState, .cleaned)
        let lines = await stage.apply(TranscriptDraft(text: "the\nthe the"), context: TextContext())
        XCTAssertEqual(lines.text, "the\nthe")
        var settings = DisfluencySettings()
        settings.enabled = false
        let disabled = await MechanicalDisfluencyStage(settings: settings)
            .apply(TranscriptDraft(text: "um I I"), context: TextContext())
        XCTAssertEqual(disabled.text, "um I I")
    }
}
