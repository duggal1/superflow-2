import XCTest
import SuperflowKernel
@testable import SuperflowTextLexicon

final class LexiconTests: XCTestCase {
    /// A trimmed fixture: the real catalog is exercised end to end in
    /// TextPipelineTests/DictionaryEvalTests.
    private let bundled = [
        LexiconEntry(kind: .term, triggers: ["next js", "nextjs"], canonical: "Next.js"),
        LexiconEntry(kind: .term, triggers: ["vs code", "v s code"], canonical: "VS Code"),
        LexiconEntry(kind: .term, triggers: ["tan stack query", "tanstack query"],
                     canonical: "TanStack Query"),
        LexiconEntry(kind: .term, triggers: ["git hub"], canonical: "GitHub"),
        LexiconEntry(kind: .term, triggers: ["iphone"], canonical: "iPhone"),
    ]

    private func run(_ input: String, _ entries: [LexiconEntry]) async -> String {
        await LexiconStage(entries: entries).apply(TranscriptDraft(text: input), context: TextContext()).text
    }

    func testTermsMatchLooseForms() async {
        let cases = [
            ("i use next js daily", "i use Next.js daily"),
            ("open vs code now.", "open VS Code now."),
            ("we love tan stack query", "we love TanStack Query"),
            ("next dot js rocks", "Next.js rocks"),
            ("deploy to git hub", "deploy to GitHub"),
        ]
        for (input, expected) in cases {
            let actual = await run(input, bundled)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testUserCorrectionWins() async {
        let entries = [LexiconEntry(kind: .correction, triggers: ["super flow"], canonical: "Superflow")]
            + bundled
        let actual = await run("try super flow today", entries)
        XCTAssertEqual(actual, "try Superflow today")
    }

    func testAppScopedCorrectionOverridesGlobalOnlyInMatchingApp() async {
        let general = LexiconEntry(kind: .correction, triggers: ["item potency"],
                                   canonical: "item potency")
        let scoped = LexiconEntry(kind: .correction, triggers: ["item potency"],
                                  canonical: "idempotency", appScope: "com.microsoft.VSCode")
        let stage = LexiconStage(entries: [general, scoped])
        let raw = TranscriptDraft(text: "check item potency today")
        let coding = await stage.apply(raw, context: TextContext(
            activeAppBundleID: "com.microsoft.VSCode"))
        XCTAssertEqual(coding.text, "check idempotency today")
        let prose = await stage.apply(raw, context: TextContext(
            activeAppBundleID: "com.apple.TextEdit"))
        XCTAssertEqual(prose.text, "check item potency today")
        let missing = await stage.apply(raw, context: TextContext())
        XCTAssertEqual(missing.text, "check item potency today")
    }

    func testScopedRuleWithoutGlobalMatchDoesNotLeakIntoOtherApps() async {
        let scoped = LexiconEntry(kind: .correction, triggers: ["item potency"],
                                  canonical: "idempotency", appScope: "com.microsoft.VSCode")
        let stage = LexiconStage(entries: [scoped])
        let raw = TranscriptDraft(text: "item potency")
        XCTAssertEqual((await stage.apply(raw, context: TextContext())).text, "item potency")
        XCTAssertEqual((await stage.apply(raw, context: TextContext(
            activeAppBundleID: "com.microsoft.VSCode"))).text, "idempotency")
    }

    func testIdempotent() async {
        let once = await run("use next js with git hub", bundled)
        let twice = await run(once, bundled)
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
        let actual = await run("my iphone is here", bundled)
        XCTAssertEqual(actual, "my iPhone is here")
    }
}
