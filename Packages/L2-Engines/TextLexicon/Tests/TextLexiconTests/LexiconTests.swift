import XCTest
import SuperflowKernel
@testable import SuperflowTextLexicon

final class LexiconTests: XCTestCase {
    private func run(_ input: String, _ entries: [LexiconEntry]) async -> String {
        await LexiconStage(entries: entries).apply(TranscriptDraft(text: input), context: TextContext()).text
    }

    func testTermsMatchLooseForms() async {
        let entries = BundledLexicon.load()
        let cases = [
            ("i use next js daily", "i use Next.js daily"),
            ("open vs code now.", "open VS Code now."),
            ("we love tan stack query", "we love TanStack Query"),
            ("next dot js rocks", "Next.js rocks"),
            ("deploy to git hub", "deploy to GitHub"),
        ]
        for (input, expected) in cases {
            let actual = await run(input, entries)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testUserCorrectionWins() async {
        let entries = [LexiconEntry(kind: .correction, triggers: ["super flow"], canonical: "Superflow")]
            + BundledLexicon.load()
        let actual = await run("try super flow today", entries)
        XCTAssertEqual(actual, "try Superflow today")
    }

    func testFalsePositiveCorpusIsUntouched() async {
        let entries = BundledLexicon.load()
        XCTAssertFalse(entries.isEmpty)
        for sentence in BundledLexicon.falsePositiveCorpus() {
            let actual = await run(sentence, entries)
            XCTAssertEqual(actual, sentence, "false positive on: \(sentence)")
        }
    }

    func testIdempotent() async {
        let entries = BundledLexicon.load()
        let once = await run("use next js with git hub", entries)
        let twice = await run(once, entries)
        XCTAssertEqual(once, twice)
    }

    func testProtectsURLs() async {
        let entries = [LexiconEntry(kind: .term, triggers: ["example"], canonical: "EXAMPLE")]
        let input = "visit https://example.com/example now"
        let actual = await run(input, entries)
        XCTAssertEqual(actual, input)
    }

    func testCommonWordWarning() {
        XCTAssertTrue(CommonWords.isRisky(trigger: "next years"))
        XCTAssertFalse(CommonWords.isRisky(trigger: "tanstack"))
    }

    func testCanonicalCasing() async {
        let entries = [LexiconEntry(kind: .term, triggers: ["iphone"], canonical: "iPhone")]
        let actual = await run("my iphone is here", entries)
        XCTAssertEqual(actual, "my iPhone is here")
    }
}
