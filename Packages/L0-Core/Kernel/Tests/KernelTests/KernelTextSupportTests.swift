import Foundation
import SuperflowKernel
import XCTest

final class KernelTextSupportTests: XCTestCase {
    func testProtectedDetectsURLsEmailsCodeCamelCaseAndDigits() {
        let text = "Visit https://example.com or mail a@b.co, run snake_case, use nextJS and v2."
        let ranges = Protected().ranges(in: text)
        let covered = ranges.map { String(text[$0]) }
        XCTAssertTrue(covered.contains { $0.contains("https://example.com") })
        XCTAssertTrue(covered.contains { $0.contains("a@b.co") })
        XCTAssertTrue(covered.contains { $0.contains("snake_case") })
        XCTAssertTrue(covered.contains { $0.contains("nextJS") })
        XCTAssertTrue(covered.contains { $0.contains("v2") })
    }

    func testProtectedLiteralsAndOverlap() {
        let text = "Use Superflow every day."
        let protected = Protected(literals: ["Superflow"])
        let range = text.range(of: "Superflow")!
        XCTAssertTrue(protected.overlaps(range, in: text))
        XCTAssertFalse(protected.overlaps(text.range(of: "day")!, in: text))
        XCTAssertTrue(Protected(literals: ["day"]).overlaps(text.range(of: "day")!, in: text))
    }

    func testTokenizerSeparatesLeadingAndTrailingPunctuation() {
        let tokens = Tokenizer.tokens(in: "(Hello), world! 200 50")
        XCTAssertEqual(tokens.map(\.core), ["Hello", "world", "200", "50"])
        XCTAssertEqual(tokens[0].lead, "(")
        XCTAssertEqual(tokens[0].trail, "),")
        XCTAssertEqual(tokens[1].trail, "!")
        XCTAssertTrue(tokens[2].isNumber)
        XCTAssertTrue(tokens[3].isNumber)
        XCTAssertFalse(tokens[0].isNumber)

        let currency = Tokenizer.tokens(in: "$200")
        XCTAssertEqual(currency.first?.core, "$200")
        XCTAssertEqual(currency.first?.lead, "")
    }

    func testSentenceSplitterKeepsAbbreviationsAndDecimals() {
        let (complete, remainder) = SentenceSplitter.split(
            "Dr. Smith paid 3.50 dollars. Then he left! Really? ")
        XCTAssertEqual(complete, ["Dr. Smith paid 3.50 dollars.", "Then he left!", "Really?"])
        XCTAssertEqual(remainder, "")
        XCTAssertTrue(SentenceSplitter.endsSentence("Hello."))
        XCTAssertFalse(SentenceSplitter.endsSentence("Dr."))
        XCTAssertFalse(SentenceSplitter.endsSentence("hello"))
    }

    func testCapitalizationHandlesSentenceStartsAndStandaloneI() {
        XCTAssertEqual(TextCapitalization.capitalizeFirst("hello"), "Hello")
        XCTAssertEqual(TextCapitalization.capitalizeFirst("Hello"), "Hello")
        XCTAssertEqual(TextCapitalization.capitalizeFirst(""), "")
        XCTAssertEqual(TextCapitalization.capitalizeSentences("hello. world\nagain"),
                       "Hello. World\nAgain")
    }

    func testDraftAndContextDefaults() {
        let draft = TranscriptDraft(text: "hello")
        XCTAssertEqual(draft.text, "hello")
        XCTAssertTrue(draft.protected.literals.isEmpty)
        XCTAssertTrue(draft.diagnostics.isEmpty)
        XCTAssertFalse(draft.shortCircuit)
        XCTAssertEqual(draft.cleanupState, .pending)

        let context = TextContext()
        XCTAssertEqual(context.source, .mic)
        XCTAssertNil(context.speakerID)
        XCTAssertTrue(context.interactive)
        XCTAssertEqual(context.settings, .default)
    }
}
