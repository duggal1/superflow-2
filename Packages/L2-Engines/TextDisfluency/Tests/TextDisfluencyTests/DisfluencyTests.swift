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

    func testTierAWordsCollapseAtTwo() async {
        let cases: [(String, String)] = [
            ("the the cat", "the cat"),
            ("I I think so", "I think so"),
            ("we need to to check", "we need to check"),
            ("the the the cat", "the cat"),
            ("a a", "a"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testTierBWordsNeedThree() async {
        let preserved = [
            "very very good",
            "this is is fine",
            "that that works",
            "we had had enough",
            "what it is is fine",
            "no no that is wrong",
        ]
        for input in preserved {
            let actual = await run(input)
            XCTAssertEqual(actual, input, "input: \(input)")
        }
        let collapsed: [(String, String)] = [
            ("very very very good", "very good"),
            ("that that that is the point", "that is the point"),
        ]
        for (input, expected) in collapsed {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testLegitimateDoublesAndPhrasesSurvive() async {
        let cases = [
            "bye bye now",
            "ha ha",
            "what it is is fine",
            "we had had lunch",
        ]
        for input in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, input, "input: \(input)")
        }
    }

    func testUnknownRepeatedWordsAreLeftForTheModel() async {
        let cases = [
            "the cat cat sat",
            "I don't don't know",
            "this works works",
        ]
        for input in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, input, "input: \(input)")
        }
    }

    func testRepeatedTwoAndThreeWordPhrasesCollapse() async {
        let cases: [(String, String)] = [
            ("we need to we need to go", "we need to go"),
            ("check the tests check the tests now", "check the tests now"),
            ("a b a b a b", "a b"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testThresholdIsConfigurable() async {
        var tierA = DisfluencySettings()
        tierA.tierAThreshold = 3
        let doubledA = await run("the the cat", settings: tierA)
        XCTAssertEqual(doubledA, "the the cat")
        let tripledA = await run("the the the cat", settings: tierA)
        XCTAssertEqual(tripledA, "the cat")

        var tierB = DisfluencySettings()
        tierB.tierBThreshold = 4
        let tripledB = await run("very very very good", settings: tierB)
        XCTAssertEqual(tripledB, "very very very good")
        let quadrupledB = await run("very very very very good", settings: tierB)
        XCTAssertEqual(quadrupledB, "very good")
    }

    func testLegacyThresholdAliasCannotGoBelowThree() {
        var settings = DisfluencySettings()
        settings.duplicateThreshold = 3
        XCTAssertEqual(settings.tierBThreshold, 3)
        settings.duplicateThreshold = 1
        XCTAssertEqual(settings.tierBThreshold, 3)
    }

    func testNumberWordsAreNeverCollapsed() async {
        let cases = [
            "twenty twenty-six",
            "one one two",
            "five five five",
        ]
        for input in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, input, "input: \(input)")
        }
    }

    func testCodeLikeTokensAndEmailsAreBoundaries() async {
        let cases = [
            "ping foo@example.com foo@example.com now",
            "run /usr/local/bin /usr/local/bin again",
            "edit foo_bar foo_bar please",
            "twenty-six twenty-six",
        ]
        for input in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, input, "input: \(input)")
        }
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

    func testFillerPrepassRunsByDefault() async {
        let simple = await run("um hello uh world")
        XCTAssertEqual(simple, "hello world")
        let punctuated = await run("um, hello, uh, world")
        XCTAssertEqual(punctuated, "hello, world")
        let elongated = await run("ummm ahh hmmm okay")
        XCTAssertEqual(elongated, "okay")
        let contentWords = await run("like you know I mean well so")
        XCTAssertEqual(contentWords, "like you know I mean well so")
        let ahHa = await run("ah ha")
        XCTAssertEqual(ahHa, "ah ha")
    }

    func testFillerPrepassCanBeDisabled() async {
        var settings = DisfluencySettings()
        settings.fillerPrepass = false
        let actual = await run("um hello", settings: settings)
        XCTAssertEqual(actual, "um hello")
    }

    func testProtectedSpansAreNeverTouched() async {
        let protected = Protected(literals: ["the the", "um"])
        let duplicate = await run("the the cat", protected: protected)
        XCTAssertEqual(duplicate, "the the cat")
        let filler = await run("um hello", protected: protected)
        XCTAssertEqual(filler, "um hello")
    }

    func testIdempotent() async {
        let inputs = [
            "the the the cat",
            "um hello uh world",
            "I I don't don't know",
            "very very good",
            "we need to we need to go",
            "a b a b a b",
            "no duplicates here",
            ".. . .",
        ]
        for input in inputs {
            let once = await run(input)
            let twice = await run(once)
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
        let before = TranscriptDraft(text: "I um I I think the the")
        let stage = DisfluencyStage()
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
        let vocabulary = ["the", "cat", "I", "think", "very", "good", "and", "to", "had", "bye"]
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
