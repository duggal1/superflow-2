import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowTextCleanup

final class FormatGuardTests: XCTestCase {
    func testMarkersAndPunctuationIgnored() {
        XCTAssertTrue(FormatGuard.preserves("my list 1. milk 2. eggs 3. bread",
                                           "my list\n1. milk\n2. eggs\n3. bread"))
        XCTAssertTrue(FormatGuard.preserves("he said hello world", "he said \"hello world\""))
        XCTAssertTrue(FormatGuard.preserves("a) one\nb", "a) one b"))
        XCTAssertTrue(FormatGuard.preserves("it’s done", "it's done"))
        XCTAssertFalse(FormatGuard.preserves("it’s done", "IT'S DONE"))
    }

    func testWordChangeDetected() {
        XCTAssertFalse(FormatGuard.preserves("save the file properly", "save the file probably"))
        XCTAssertFalse(FormatGuard.preserves("one two three", "one two"))
        XCTAssertFalse(FormatGuard.preserves("", "added"))
    }

    func testDecimalsAndYearsAreWords() {
        XCTAssertFalse(FormatGuard.preserves("version 3.5 shipped", "version shipped"))
        XCTAssertTrue(FormatGuard.preserves("version 3.5 shipped", "version 3.5\nshipped"))
        XCTAssertTrue(FormatGuard.preserves("in 2026 we ship", "in 2026 we ship."))
    }

    func testMarkerLikeDecimalsStaySignificant() {
        XCTAssertFalse(FormatGuard.preserves("costs 3.50 today", "costs today"))
        XCTAssertFalse(FormatGuard.preserves("weights 1.5 kg", "weights kg"))
    }
}

final class ListShaperTests: XCTestCase {
    func testSplitsInlineRun() {
        XCTAssertEqual(ListShaper.apply("My list 1. milk 2. eggs 3. bread"),
                       "My list\n1. milk\n2. eggs\n3. bread")
        XCTAssertEqual(ListShaper.apply("Steps: 1) mix 2) bake 3) eat"),
                       "Steps:\n1. mix\n2. bake\n3. eat")
    }

    func testRenumbersAndUnifiesBullets() {
        XCTAssertEqual(ListShaper.apply("1. a\n3. b\n7. c"), "1. a\n2. b\n3. c")
        XCTAssertEqual(ListShaper.apply("* a\n• b\n- c"), "- a\n- b\n- c")
    }

    func testParenStyleAndBulletOption() {
        var options = ListShaper.Options()
        options.numberStyle = .paren
        options.bullet = "*"
        XCTAssertEqual(ListShaper.apply("4. a\n9. b", options: options), "1) a\n2) b")
        XCTAssertEqual(ListShaper.apply("• a\n- b", options: options), "* a\n* b")
    }

    func testNonListsUntouched() {
        XCTAssertEqual(ListShaper.apply("We shipped version 2. Then we left."),
                       "We shipped version 2. Then we left.")
        XCTAssertEqual(ListShaper.apply("It costs 3.5 dollars."), "It costs 3.5 dollars.")
        XCTAssertEqual(ListShaper.apply("1. only one item"), "1. only one item")
        XCTAssertEqual(ListShaper.apply("Items 1. a 3. b 4. c"), "Items 1. a 3. b 4. c")
        XCTAssertEqual(ListShaper.apply("- lone bullet"), "- lone bullet")
        XCTAssertEqual(ListShaper.apply("a\n\n4. x\n9. y"), "a\n\n1. x\n2. y")
    }

    func testIdempotent() {
        for input in ["My list 1. milk 2. eggs 3. bread", "1. a\n3. b\n7. c", "* a\n• b\n- c"] {
            let once = ListShaper.apply(input)
            XCTAssertEqual(ListShaper.apply(once), once, input)
        }
    }

    func testWordPreservationAcrossShapes() {
        for input in [
            "My list 1. milk 2. eggs 3. bread",
            "Steps: 1) mix 2) bake 3) eat",
            "1. a\n3. b\n7. c",
            "We shipped version 2. Then we left.",
            "It costs 3.5 dollars.",
        ] {
            XCTAssertTrue(FormatGuard.preserves(input, ListShaper.apply(input)), input)
        }
    }
}

final class EnumerationDetectorTests: XCTestCase {
    func testPositive() {
        XCTAssertEqual(EnumerationDetector.detect("First fix the bug. Second write tests. Third ship it."),
                       .list(items: 3))
        XCTAssertEqual(EnumerationDetector.detect("Number one, milk. Number two, eggs. Number three, bread."),
                       .list(items: 3))
        XCTAssertEqual(EnumerationDetector.detect("my list. One, milk. Two, eggs. Three, bread."),
                       .list(items: 3))
        XCTAssertEqual(EnumerationDetector.detect("Step one: plan. Step two: build. Step three: test."),
                       .list(items: 3))
    }

    func testNegative() {
        XCTAssertEqual(EnumerationDetector.detect("I bought one apple two oranges and three pears"), .none)
        XCTAssertEqual(EnumerationDetector.detect("it was the first time and the second attempt went fine"), .none)
        XCTAssertEqual(EnumerationDetector.detect(""), .none)
        XCTAssertEqual(EnumerationDetector.detect("one two"), .none)
        XCTAssertEqual(EnumerationDetector.detect("First. Third. Fifth."), .none)
    }

    func testSeamDetection() {
        let left = "here is the plan. First install the app"
        let right = "Second grant access. Third start dictation."
        XCTAssertEqual(EnumerationDetector.detect(left), .none)
        XCTAssertEqual(EnumerationDetector.detect(right), .none)
        XCTAssertTrue(EnumerationDetector.straddles(left, right))
        XCTAssertFalse(EnumerationDetector.straddles("First a. Second b. Third c.", right))
    }

    func testSeamDetectionAfterACompleteList() {
        let left = "First a. Second b. Third c."
        let right = "Fourth d."
        XCTAssertEqual(EnumerationDetector.detect(left), .list(items: 3))
        XCTAssertTrue(EnumerationDetector.straddles(left, right))
        XCTAssertFalse(EnumerationDetector.straddles(left, "Something else entirely."))
    }

    func testStructureMappingUsesModelCardValues() {
        let mapping = S1MiniStructureMapping()
        XCTAssertEqual(mapping.structure(for: .list(items: 3), base: "prose"), "lists")
        XCTAssertEqual(mapping.structure(for: .none, base: "prose"), "prose")
        XCTAssertEqual(mapping.structure(for: .list(items: 2), base: "lists"), "lists")
        XCTAssertEqual(mapping.structure(for: .list(items: 3), base: "custom"), "custom")
    }
}

final class SpokenEnumerationShaperTests: XCTestCase {
    func testDictatedOrdinalsBecomeNumberedLines() {
        let input = "First fix the authentication bug, second run all the tests, third push the changes."
        XCTAssertEqual(SpokenEnumerationShaper.apply(input),
                       "1. fix the authentication bug,\\n2. run all the tests,\\n3. push the changes.")
    }

    func testKeepsProseAndFormattedListsIntact() {
        for text in [
            "I met him for the first time, and the second attempt was better.",
            "First I went to work, second I went home.",
            "First. Third. Fifth.",
            "1. fix the bug\\n2. run the tests",
        ] {
            XCTAssertEqual(SpokenEnumerationShaper.apply(text), text, text)
        }
    }

    func testS1MiniFormattedListIsStable() {
        let list = "1. fix the bug\\n2. run the tests\\n3. deploy the fix"
        XCTAssertEqual(SpokenEnumerationShaper.apply(list), list)
    }

    func testFormattingStageUsesExplicitOrdinals() async {
        let input = "First fix the authentication bug, second run all the tests, third push the changes."
        let result = await FormattingStage().apply(TranscriptDraft(text: input), context: TextContext())
        XCTAssertTrue(result.text.contains("\\n2. run all the tests"), result.text)
        XCTAssertTrue(result.text.contains("\\n3. push the changes"), result.text)
    }
}

final class SpokenQuotesTests: XCTestCase {
    func testBasic() {
        XCTAssertEqual(SpokenQuotes.apply("he said quote we ship friday unquote and left"),
                       "he said \"we ship friday\" and left")
    }

    func testPunctuationPlacement() {
        XCTAssertEqual(SpokenQuotes.apply("she wrote quote hello world, unquote."),
                       "she wrote \"hello world,\".")
    }

    func testNounUseUntouched() {
        XCTAssertEqual(SpokenQuotes.apply("that is a great quote from Lincoln"),
                       "that is a great quote from Lincoln")
        XCTAssertEqual(SpokenQuotes.apply("quote me on this"), "quote me on this")
        XCTAssertEqual(SpokenQuotes.apply("a quote"), "a quote")
    }

    func testMultiWordCommands() {
        XCTAssertEqual(SpokenQuotes.apply("open quote hi there close quote"), "\"hi there\"")
        XCTAssertEqual(SpokenQuotes.apply("begin quote hi end quote"), "\"hi\"")
        XCTAssertEqual(SpokenQuotes.apply("quote hi end of quote"), "\"hi\"")
        XCTAssertEqual(SpokenQuotes.apply("hello", style: .curly), "hello")
        XCTAssertEqual(SpokenQuotes.apply("quote hello unquote", style: .curly), "“hello”")
    }

    func testMultipleAndMultiline() {
        XCTAssertEqual(SpokenQuotes.apply("quote one unquote then quote two unquote"),
                       "\"one\" then \"two\"")
        // Commands are line-scoped: a quote command never spans a hard newline.
        XCTAssertEqual(SpokenQuotes.apply("quote a\nb unquote"), "quote a\nb unquote")
    }

    func testQuoteGateCountsMarks() {
        XCTAssertTrue(QuoteGate.preserved(input: "\"a b\"", output: "“a b”"))
        XCTAssertFalse(QuoteGate.preserved(input: "\"a b\"", output: "a b"))
    }
}

final class ParagraphShaperTests: XCTestCase {
    private let sentence = "This is a sentence with exactly ten words in it ok."

    func testShortTextUntouched() { XCTAssertEqual(ParagraphShaper.apply(sentence), sentence) }

    func testSplitsLongBlockAtSentenceEnds() {
        let long = Array(repeating: sentence, count: 8).joined(separator: " ")
        let out = ParagraphShaper.apply(long)
        XCTAssertTrue(out.contains("\n\n"))
        XCTAssertTrue(FormatGuard.preserves(long, out))
        XCTAssertEqual(ParagraphShaper.apply(out), out)
        XCTAssertGreaterThan(wordCount(out.components(separatedBy: "\n\n")[0]), 0)
    }

    func testListsAndCodeUntouched() {
        let list = Array(repeating: "1. " + sentence, count: 8).joined(separator: "\n")
        XCTAssertEqual(ParagraphShaper.apply(list), list)
        let code = "```swift\n" + Array(repeating: sentence, count: 8).joined(separator: " ") + "\n```"
        XCTAssertEqual(ParagraphShaper.apply(code), code)
    }

    func testTinyTailMergesBack() {
        let head = Array(repeating: sentence, count: 5).joined(separator: " ")
        let long = head + " " + sentence
        let out = ParagraphShaper.apply(long)
        for block in out.components(separatedBy: "\n\n") {
            XCTAssertGreaterThanOrEqual(wordCount(block), 8, block)
        }
    }
}

final class WhitespaceTests: XCTestCase {
    func testTidyIsStructural() {
        XCTAssertEqual(Whitespace.tidy("  a  \n\n\n\n b\t\n"), "a\n\n b")
        XCTAssertEqual(Whitespace.tidy("a\n\n\nb"), "a\n\nb")
        XCTAssertEqual(Whitespace.tidy(Whitespace.tidy("a\n\n\nb")), "a\n\nb")
    }
}

final class ShapeOutputTests: XCTestCase {
    func testWhitespaceGuardRejectsWordLoss() {
        var counters = FormatCounters()
        XCTAssertEqual(guardWhitespace("keep every word", "keep word", counters: &counters), "keep every word")
        XCTAssertEqual(counters.whitespaceReverts, 1)
    }
    func testFormatsInlineListWithoutReverts() {
        var counters = FormatCounters()
        let out = shapeOutput("My list 1. milk 2. eggs 3. bread",
                              config: .defaults(for: .writing), counters: &counters)
        XCTAssertEqual(out, "My list\n1. milk\n2. eggs\n3. bread")
        XCTAssertEqual(counters.listReverts, 0)
        XCTAssertEqual(counters.paragraphReverts, 0)
        XCTAssertEqual(counters.listsFormatted, 1)
    }

    func testChatContextDoesNotSplitParagraphs() {
        let sentence = "This is a sentence with exactly ten words in it ok."
        let long = Array(repeating: sentence, count: 8).joined(separator: " ")
        var counters = FormatCounters()
        XCTAssertEqual(shapeOutput(long, config: .defaults(for: .chat), counters: &counters), long)
        XCTAssertEqual(counters.paragraphsSplit, 0)
    }

    func testWritingContextSplitsParagraphs() {
        let sentence = "This is a sentence with exactly ten words in it ok."
        let long = Array(repeating: sentence, count: 8).joined(separator: " ")
        var counters = FormatCounters()
        let out = shapeOutput(long, config: .defaults(for: .writing), counters: &counters)
        XCTAssertTrue(out.contains("\n\n"))
        XCTAssertEqual(counters.paragraphReverts, 0)
        XCTAssertEqual(counters.paragraphsSplit, 1)
    }

    func testIdempotent() {
        let sentence = "This is a sentence with exactly ten words in it ok."
        let inputs = [
            "My list 1. milk 2. eggs 3. bread",
            Array(repeating: sentence, count: 8).joined(separator: " "),
            "1. a\n3. b\n7. c",
        ]
        for input in inputs {
            var first = FormatCounters()
            let once = shapeOutput(input, config: .defaults(for: .writing), counters: &first)
            var second = FormatCounters()
            let twice = shapeOutput(once, config: .defaults(for: .writing), counters: &second)
            XCTAssertEqual(once, twice, input)
            XCTAssertEqual(second.listReverts, 0, input)
            XCTAssertEqual(second.paragraphReverts, 0, input)
        }
    }

    func testRandomWordSequencesArePreserved() {
        let words = ["alpha", "beta", "gamma", "1.", "2.", "3.5", "it's", "2026", "done."]
        var state: UInt64 = 0x5eed
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return Int((state >> 33) % UInt64(words.count))
        }
        for _ in 0..<60 {
            let input = (0..<24).map { _ in words[next()] }.joined(separator: " ")
            var counters = FormatCounters()
            let out = shapeOutput(input, config: .defaults(for: .writing), counters: &counters)
            XCTAssertTrue(FormatGuard.preserves(input, out), input)
        }
    }

    func testFormattingStageSkipsFencedCodeAndEmpty() async {
        let stage = FormattingStage()
        let code = "```\nfirst a second b third c\n```"
        let draft = await stage.apply(TranscriptDraft(text: code), context: TextContext())
        XCTAssertEqual(draft.text, code)
        let empty = await stage.apply(TranscriptDraft(text: ""), context: TextContext())
        XCTAssertEqual(empty.text, "")
    }

    func testFormattingStageUsesCleanupContext() async {
        var settings = AppSettings.default
        settings.cleanupContext = "chat"
        let sentence = "This is a sentence with exactly ten words in it ok."
        let long = Array(repeating: sentence, count: 8).joined(separator: " ")
        let stage = FormattingStage()
        let draft = await stage.apply(TranscriptDraft(text: long),
                                      context: TextContext(settings: settings))
        XCTAssertEqual(draft.text, long)
        XCTAssertEqual(FormatConfig.kind(for: TextContext(settings: settings)), .chat)
    }
}

final class FormattingPipelineIntegrationTests: XCTestCase {
    func testCleanupRoutesSpokenEnumerationIntoStructureField() async {
        let fake = FakeTextCleaner(.identity)
        let service = CleanupService(cleaner: fake)
        _ = await service.clean("One, milk. Two, eggs. Three, bread.",
                                context: TextContext())
        let options = await fake.lastOptions
        XCTAssertEqual(options?.structure, "lists")
    }

    func testCleanupLeavesOrdinaryProseAsProse() async {
        let fake = FakeTextCleaner(.identity)
        let service = CleanupService(cleaner: fake)
        var settings = AppSettings()
        settings.cleanupStructure = "prose"
        _ = await service.clean("I bought one apple two oranges and three pears",
                                context: TextContext(settings: settings))
        let options = await fake.lastOptions
        XCTAssertEqual(options?.structure, "prose")
    }

    func testSpokenQuotesRunBeforeTheModel() async {
        let fake = FakeTextCleaner(.identity)
        var config = CleanupConfig()
        config.format.spokenQuotes = true
        let service = CleanupService(cleaner: fake, config: config)
        let outcome = await service.clean("he said quote we ship friday unquote and left",
                                          context: TextContext())
        XCTAssertEqual(outcome.text, "he said \"we ship friday\" and left")
        XCTAssertEqual(outcome.state, .cleaned)
        let options = await fake.lastOptions
        XCTAssertNotNil(options)
    }

    func testQuoteLossIsRejectedAndFallsBackToSafeText() async {
        let cleaner = DropQuoteCleaner()
        var config = CleanupConfig()
        config.format.spokenQuotes = true
        let service = CleanupService(cleaner: cleaner, config: config)
        let outcome = await service.clean("he said quote keep this unquote",
                                          context: TextContext())
        XCTAssertEqual(outcome.state, .fallback)
        XCTAssertEqual(outcome.text, "he said quote keep this unquote")
        XCTAssertEqual(outcome.chunks.first?.reason, "quoteChanged")
    }

    func testProtectedLiteralDisablesSpokenQuotes() async {
        var config = CleanupConfig()
        config.format.spokenQuotes = true
        let service = CleanupService(cleaner: FakeTextCleaner(.identity), config: config)
        let outcome = await service.clean("he said quote ACME unquote",
                                          protected: Protected(literals: ["ACME"]),
                                          context: TextContext())
        XCTAssertEqual(outcome.text, "he said quote ACME unquote")
        XCTAssertEqual(outcome.state, .cleaned)
    }

    func testModelListOutputIsRenumberedByFormattingLayer() async {
        let input = "Grocery list\n1. milk\n1. eggs\n1. bread"
        let service = CleanupService(cleaner: FakeTextCleaner(.identity))
        let outcome = await service.clean(input, context: TextContext())
        XCTAssertEqual(outcome.text, input)
        var counters = FormatCounters()
        let shaped = shapeOutput(outcome.text, config: .defaults(for: .writing), counters: &counters)
        XCTAssertEqual(shaped, "Grocery list\n1. milk\n2. eggs\n3. bread")
        XCTAssertEqual(counters.listReverts, 0)
    }
}

private actor DropQuoteCleaner: TextCleaner {
    var isReady: Bool { true }
    func countTokens(_ text: String) async -> Int {
        max(1, Tokenizer.words(in: text).count)
    }
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        CleanResult(text: text.replacingOccurrences(of: "\"", with: ""),
                    tokensIn: 1, tokensOut: 1, hitTokenCap: false, latencyMs: 1)
    }
}
