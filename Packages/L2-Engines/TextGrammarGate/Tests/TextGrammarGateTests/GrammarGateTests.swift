import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowTextGrammarGate

private actor TypoChecker: GrammarChecker {
    let typo: String
    let replacement: String
    private(set) var seenCustomWords: [String] = []

    init(typo: String = "teh", replacement: String = "the") {
        self.typo = typo
        self.replacement = replacement
    }

    func lint(_ text: String, customWords: [String]) async -> [GrammarLint] {
        seenCustomWords = customWords
        let ns = text as NSString
        var lints: [GrammarLint] = []
        var from = 0
        while from < ns.length {
            let r = ns.range(of: typo, options: [], range: NSRange(location: from, length: ns.length - from))
            guard r.location != NSNotFound else { break }
            lints.append(GrammarLint(utf16Start: r.location, utf16Length: r.length,
                                     kind: "spelling", suggestion: replacement))
            from = r.location + r.length
        }
        return lints
    }
}

final class GrammarGateTests: XCTestCase {
    private func stage(_ checker: any GrammarChecker,
                       policy: GrammarGatePolicy = GrammarGatePolicy()) -> GrammarGateStage {
        GrammarGateStage(checker: checker, policy: policy)
    }

    private func run(_ text: String, checker: any GrammarChecker,
                     policy: GrammarGatePolicy = GrammarGatePolicy(maxEditRatio: 1.0, timeCapMs: 500),
                     protected: Protected = Protected()) async -> TranscriptDraft {
        await stage(checker, policy: policy)
            .apply(TranscriptDraft(text: text, protected: protected), context: TextContext())
    }

    func testAppliesAllowedLint() async {
        let out = await run("teh cat sat on teh mat", checker: TypoChecker())
        XCTAssertEqual(out.text, "the cat sat on the mat")
        XCTAssertTrue(out.diagnostics.contains { $0.message.contains("applied 2 lints") })
    }

    func testIgnoresDisallowedKind() async {
        let checker = FakeGrammarChecker(lints: [
            GrammarLint(utf16Start: 0, utf16Length: 3, kind: "style", suggestion: "The"),
        ])
        let out = await run("teh cat", checker: checker)
        XCTAssertEqual(out.text, "teh cat")
        let calls = await checker.calls
        XCTAssertEqual(calls, 1)
    }

    func testSkipsProtectedSpans() async {
        let checker = FakeGrammarChecker(lints: [
            GrammarLint(utf16Start: 4, utf16Length: 4, kind: "spelling", suggestion: "code"),
        ])
        let out = await run("see https://exmple.com now", checker: checker)
        XCTAssertEqual(out.text, "see https://exmple.com now")
    }

    func testSkipsDictionaryTerms() async {
        let checker = FakeGrammarChecker(lints: [
            GrammarLint(utf16Start: 0, utf16Length: 10, kind: "spelling", suggestion: "Super flow"),
        ])
        let out = await run("Superflow ships today", checker: checker,
                            protected: Protected(literals: ["Superflow"]))
        XCTAssertEqual(out.text, "Superflow ships today")
    }

    func testEditBudgetAllowsSmallChange() async {
        let text = (1...100).map { $0 == 7 ? "teh" : "word\($0)" }.joined(separator: " ")
        let out = await run(text, checker: TypoChecker(), policy: GrammarGatePolicy())
        XCTAssertEqual(out.text, text.replacingOccurrences(of: "teh", with: "the"))
    }

    func testEditBudgetRejectsLargeChange() async {
        let text = (1...100).map { $0 % 25 == 0 ? "teh" : "word\($0)" }.joined(separator: " ")
        let out = await run(text, checker: TypoChecker(), policy: GrammarGatePolicy())
        XCTAssertEqual(out.text, text)
        XCTAssertTrue(out.diagnostics.contains { $0.message.contains("edit budget") })
    }

    func testTimeCapSkips() async {
        let checker = FakeGrammarChecker(lints: [
            GrammarLint(utf16Start: 0, utf16Length: 3, kind: "spelling", suggestion: "the"),
        ])
        await checker.setDelay(ms: 80)
        let policy = GrammarGatePolicy(maxEditRatio: 1.0, timeCapMs: 20)
        let out = await run("teh cat", checker: checker, policy: policy)
        XCTAssertEqual(out.text, "teh cat")
        XCTAssertTrue(out.diagnostics.contains { $0.message.contains("cap") })
    }

    func testIdempotentWithConvergingChecker() async {
        let checker = TypoChecker()
        let once = await run("teh cat and teh dog", checker: checker)
        let twice = await run(once.text, checker: checker)
        XCTAssertEqual(once.text, twice.text)
        XCTAssertEqual(once.text, "the cat and the dog")
    }

    func testEmptyAndWhitespaceUnchanged() async {
        let checker = FakeGrammarChecker()
        let empty = await run("", checker: checker)
        let spaces = await run("   \n ", checker: checker)
        XCTAssertEqual(empty.text, "")
        XCTAssertEqual(spaces.text, "   \n ")
    }

    func testOutOfBoundsAndOverlappingLintsAreIgnored() async {
        let checker = FakeGrammarChecker(lints: [
            GrammarLint(utf16Start: 999, utf16Length: 3, kind: "spelling", suggestion: "x"),
            GrammarLint(utf16Start: 0, utf16Length: 3, kind: "spelling", suggestion: "the"),
            GrammarLint(utf16Start: 1, utf16Length: 3, kind: "spelling", suggestion: "hey"),
        ])
        let out = await run("teh cat", checker: checker)
        XCTAssertEqual(out.text, "the cat")
    }

    func testPolicyResourceIsPinned() {
        let policy = GrammarGatePolicy.loadBundled()
        XCTAssertTrue(policy.enabled)
        XCTAssertEqual(policy.timeCapMs, 50)
        XCTAssertEqual(policy.maxEditRatio, 0.03, accuracy: 0.0001)
        XCTAssertEqual(policy.minimumPrecision, 0.98, accuracy: 0.0001)
        XCTAssertEqual(policy.allowedKinds, ["Spelling", "Agreement", "Repetition", "aOrAn"])
        XCTAssertTrue(policy.allows(kind: "Repeated Words"))
        XCTAssertTrue(policy.allows(kind: "repetition"))
        XCTAssertTrue(policy.allows(kind: "a/an"))
        XCTAssertFalse(policy.allows(kind: "style"))
        XCTAssertFalse(policy.allows(kind: "Miscellaneous"))
    }

    func testCanonicalKindAliases() {
        XCTAssertEqual(GrammarGatePolicy.canonical("Repeated Words"), "repetition")
        XCTAssertEqual(GrammarGatePolicy.canonical("repeatedWords"), "repetition")
        XCTAssertEqual(GrammarGatePolicy.canonical("Repetition"), "repetition")
        XCTAssertEqual(GrammarGatePolicy.canonical("AnA"), "aoran")
        XCTAssertEqual(GrammarGatePolicy.canonical("a/an"), "aoran")
        XCTAssertEqual(GrammarGatePolicy.canonical("aOrAn"), "aoran")
        XCTAssertEqual(GrammarGatePolicy.canonical("Spelling"), "spelling")
        XCTAssertEqual(GrammarGatePolicy.displayName("repetition"), "Repetition")
    }

    func testCustomWordsArePassedThrough() async {
        let checker = TypoChecker()
        _ = await run("Superflow and teh cat", checker: checker,
                      protected: Protected(literals: ["Superflow"]))
        let words = await checker.seenCustomWords
        XCTAssertEqual(words, ["Superflow"])
    }

    func testUnicodeOffsetsAreUTF16() async {
        let checker = FakeGrammarChecker(lints: [
            GrammarLint(utf16Start: 3, utf16Length: 3, kind: "spelling", suggestion: "the"),
        ])
        let out = await run("🙂 teh cat", checker: checker)
        XCTAssertEqual(out.text, "🙂 the cat")
    }
}
