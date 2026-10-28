import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextDisfluency

final class DisfluencyTests: XCTestCase {
    private func run(_ input: String, protected: Protected = Protected(),
                     settings: DisfluencySettings = DisfluencySettings()) async -> String {
        await DisfluencyStage(settings: settings)
            .apply(TranscriptDraft(text: input, protected: protected), context: TextContext()).text
    }

    func testCollapsesExactDuplicates() async {
        let cases: [(String, String)] = [
            ("the the the cat", "the cat"),
            ("I I I think so", "I think so"),
            ("very very good", "very good"),
            ("this is is fine", "this is fine"),
            ("no duplicates here", "no duplicates here"),
            ("a a", "a"),
            ("I I don't don't know", "I don't know"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testThresholdIsConfigurable() async {
        var settings = DisfluencySettings()
        settings.duplicateThreshold = 3
        let doubled = await run("very very good", settings: settings)
        XCTAssertEqual(doubled, "very very good")
        let tripled = await run("very very very good", settings: settings)
        XCTAssertEqual(tripled, "very good")
    }

    func testPunctuationOnlyTokensNeverCollapse() async {
        let actual = await run("wait . . . what")
        XCTAssertEqual(actual, "wait . . . what")
    }

    func testPunctuationBreaksADuplicateRun() async {
        let actual = await run("the . the cat")
        XCTAssertEqual(actual, "the . the cat")
    }

    func testProtectedSpanBreaksADuplicateRun() async {
        let protected = Protected(literals: ["and"])
        let actual = await run("the and the", protected: protected)
        XCTAssertEqual(actual, "the and the")
    }

    func testNoEditsPreserveWhitespaceExactly() async {
        let input = "hello   world\tand   more"
        let actual = await run(input)
        XCTAssertEqual(actual, input)
    }

    func testFillerPrepassIsOptIn() async {
        var settings = DisfluencySettings()
        settings.fillerPrepass = true
        let simple = await run("um hello uh world", settings: settings)
        XCTAssertEqual(simple, "hello world")
        let punctuated = await run("um, hello, uh, world", settings: settings)
        XCTAssertEqual(punctuated, "hello, world")
        let elongated = await run("ummm ahh hmmm okay", settings: settings)
        XCTAssertEqual(elongated, "okay")
        let contentWords = await run("like you know I mean well so", settings: settings)
        XCTAssertEqual(contentWords, "like you know I mean well so")
        let ahHa = await run("ah ha", settings: settings)
        XCTAssertEqual(ahHa, "ah ha")
    }

    func testFillerPrepassOffLeavesFillers() async {
        let actual = await run("um hello")
        XCTAssertEqual(actual, "um hello")
    }

    func testProtectedSpansAreNeverTouched() async {
        let protected = Protected(literals: ["the the", "um"])
        let duplicate = await run("the the cat", protected: protected)
        XCTAssertEqual(duplicate, "the the cat")
        var settings = DisfluencySettings()
        settings.fillerPrepass = true
        let filler = await run("um hello", protected: protected, settings: settings)
        XCTAssertEqual(filler, "um hello")
    }

    func testIdempotent() async {
        var settings = DisfluencySettings()
        settings.fillerPrepass = true
        let inputs = [
            "the the the cat",
            "um hello uh world",
            "I I don't don't know",
            "very very good",
            "no duplicates here",
            ".. . .",
        ]
        for input in inputs {
            let once = await run(input, settings: settings)
            let twice = await run(once, settings: settings)
            XCTAssertEqual(once, twice, "input: \(input)")
        }
    }

    func testWhitespaceAndEmptyAreStable() async {
        let empty = await run("")
        XCTAssertEqual(empty, "")
        let whitespace = await run("   \n\t\n")
        XCTAssertEqual(whitespace, "   \n\t\n")
        let fillerOnly = await run("um")
        XCTAssertEqual(fillerOnly, "um")
    }

    func testExplainNamesTheRule() async {
        var settings = DisfluencySettings()
        settings.fillerPrepass = true
        let before = TranscriptDraft(text: "I um I I think the the")
        let stage = DisfluencyStage(settings: settings)
        let after = await stage.apply(before, context: TextContext())
        let edits = await stage.explainEdits(before: before, after: after, context: TextContext())
        XCTAssertEqual(after.text, "I think the")
        XCTAssertEqual(edits?.map(\.ruleID), ["filler", "duplicate", "duplicate", "duplicate"])
    }

    func testPropertyNeverInventsOrLosesNonDuplicateWords() async {
        var state: UInt64 = 0x5EED
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let vocabulary = ["the", "cat", "I", "think", "very", "good", "and", "to"]
        for _ in 0..<300 {
            let count = 1 + next(18)
            let words = (0..<count).map { _ in vocabulary[next(vocabulary.count)] }
            let input = words.joined(separator: " ")
            let once = await run(input)
            let twice = await run(once)
            XCTAssertEqual(once, twice, "not idempotent: \(input)")
            let outputWords = once.split(separator: " ").map(String.init)
            XCTAssertFalse(outputWords.isEmpty, "erased: \(input)")
            XCTAssertLessThanOrEqual(outputWords.count, words.count)
            XCTAssertLessThanOrEqual(once.utf8.count, input.utf8.count)
            let inputWords = Set(words)
            XCTAssertTrue(outputWords.allSatisfy(inputWords.contains),
                          "invented a word: \(input) -> \(once)")
        }
    }
}
