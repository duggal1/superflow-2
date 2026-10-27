import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextGrammarGate
import XCTest

final class GrammarGoldenTests: XCTestCase {
    private func fixture() throws -> GrammarFixture {
        try Golden.load("grammar/cases.json")
    }

    private func lints(for c: GrammarCase, in text: String) -> [GrammarLint] {
        c.lints.compactMap { $0.lint(in: text) }
    }

    /// Maps each accepted edit back to the fixture lint index so precision can be
    /// measured per category. Identical duplicate lints are matched once each.
    private func acceptedIndices(for c: GrammarCase, policy: GrammarGatePolicy) -> [Int] {
        let text = c.input
        let resolved = lints(for: c, in: text)
        let accepted = GrammarGateStage.acceptedEdits(resolved, in: text, policy: policy,
                                                      protected: Protected(literals: Set(c.protectedLiterals ?? [])))
        var used = Set<Int>()
        var indices: [Int] = []
        for edit in accepted {
            if let index = resolved.indices.first(where: { index in
                guard !used.contains(index) else { return false }
                let lint = resolved[index]
                let ns = text as NSString
                guard lint.utf16Start >= 0, lint.utf16Length > 0,
                      lint.utf16Start + lint.utf16Length <= ns.length else { return false }
                return NSRange(location: lint.utf16Start, length: lint.utf16Length) == edit.range
                    && lint.suggestion == edit.replacement
            }) {
                used.insert(index)
                indices.append(index)
            } else {
                // An edit that cannot be traced back to a fixture lint is a gate bug.
                indices.append(-1)
            }
        }
        return indices
    }

    func testGrammarCorpusAndPerCategoryPrecision() async throws {
        let fixture = try fixture()
        let policy = fixture.policy.policy()
        var truePositives: [String: Int] = [:]
        var falsePositives: [String: Int] = [:]

        for c in fixture.cases {
            let resolved = lints(for: c, in: c.input)
            XCTAssertEqual(resolved.count, c.lints.count, "fixture lint did not resolve for \(c.name)")
            let accepted = acceptedIndices(for: c, policy: policy)
            XCTAssertEqual(accepted, c.expectedAccepted,
                           "accepted lints differ for \(c.name): \(accepted) vs \(c.expectedAccepted)")

            let checker = FakeGrammarChecker(lints: resolved)
            let stage = GrammarGateStage(checker: checker, policy: policy)
            let draft = TranscriptDraft(text: c.input,
                                        protected: Protected(literals: Set(c.protectedLiterals ?? [])))
            let result = await stage.apply(draft, context: TextContext(settings: Golden.stageSettings()))
            assertGolden(result.text, c.expectedFinal, name: c.name)

            for index in accepted {
                if c.expectedAccepted.contains(index) {
                    truePositives[c.category, default: 0] += 1
                } else {
                    falsePositives[c.category, default: 0] += 1
                }
            }
        }

        for category in Set(fixture.cases.map(\.category)) {
            let tp = truePositives[category, default: 0]
            let fp = falsePositives[category, default: 0]
            let precision = Double(tp) / Double(max(1, tp + fp))
            XCTAssertGreaterThanOrEqual(precision, 0.98,
                                        "\(category) precision \(precision) is below the 98 percent gate (tp=\(tp), fp=\(fp))")
        }
    }

    func testGateIsIdempotentOnItsOwnOutput() async throws {
        let fixture = try fixture()
        let policy = fixture.policy.policy()
        for c in fixture.cases {
            // A case with two identical lints deliberately models a checker that
            // reports the same edit twice. After the first pass the duplicate is
            // re-located at the next occurrence, so re-running it is expected to
            // edit again; that is the overlap decoy, not an idempotence failure.
            let signatures = c.lints.map { "\($0.find ?? "")|\($0.replace ?? "")|\($0.kind)" }
            if Set(signatures).count != signatures.count { continue }

            let resolved = lints(for: c, in: c.input)
            let stage = GrammarGateStage(checker: FakeGrammarChecker(lints: resolved), policy: policy)
            let draft = TranscriptDraft(text: c.input,
                                        protected: Protected(literals: Set(c.protectedLiterals ?? [])))
            let once = await stage.apply(draft, context: TextContext(settings: Golden.stageSettings()))

            let relints = c.lints.compactMap { $0.lint(in: once.text) }
            let second = await GrammarGateStage(checker: FakeGrammarChecker(lints: relints), policy: policy)
                .apply(TranscriptDraft(text: once.text,
                                       protected: Protected(literals: Set(c.protectedLiterals ?? []))),
                       context: TextContext(settings: Golden.stageSettings()))
            XCTAssertEqual(second.text, once.text, "grammar gate changed its own output for \(c.name)")
        }
    }

    func testTimeCapSkipsSlowChecker() async {
        let checker = FakeGrammarChecker(lints: [
            GrammarLint(utf16Start: 2, utf16Length: 7, kind: "spelling", suggestion: "receive"),
        ])
        await checker.setDelay(ms: 80)
        let policy = GrammarGatePolicy(timeCapMs: 50)
        let stage = GrammarGateStage(checker: checker, policy: policy)
        let result = await stage.apply(TranscriptDraft(text: "I recieve it"),
                                       context: TextContext(settings: Golden.stageSettings()))
        XCTAssertEqual(result.text, "I recieve it")
        XCTAssertTrue(result.diagnostics.contains { $0.message.contains("skipped: lint took") })
    }

    func testDefaultEditBudgetRejectsLargeRewrites() async {
        let short = "The list of pending items are on the shared drive."
        let ns = short as NSString
        let lint = GrammarLint(utf16Start: ns.range(of: "are").location,
                               utf16Length: 3, kind: "agreement", suggestion: "is")
        let stage = GrammarGateStage(checker: FakeGrammarChecker(lints: [lint]), policy: .default)
        let result = await stage.apply(TranscriptDraft(text: short),
                                       context: TextContext(settings: Golden.stageSettings()))
        XCTAssertEqual(result.text, short, "a 1-in-10-word edit exceeds the 3 percent budget")
        XCTAssertTrue(result.diagnostics.contains { $0.message.contains("skipped: edit budget") })
    }

    func testDefaultEditBudgetAllowsOneEditInFortyWords() async {
        let words = (1...39).map { "word\($0)" }
        let text = (words + ["are", "ready"]).joined(separator: " ")
        let ns = text as NSString
        let lint = GrammarLint(utf16Start: ns.range(of: "are").location,
                               utf16Length: 3, kind: "agreement", suggestion: "is")
        let stage = GrammarGateStage(checker: FakeGrammarChecker(lints: [lint]), policy: .default)
        let result = await stage.apply(TranscriptDraft(text: text),
                                       context: TextContext(settings: Golden.stageSettings()))
        XCTAssertEqual(result.text, text.replacingOccurrences(of: " are ", with: " is "))
    }

    func testDisabledPolicyLeavesTextUntouched() async {
        let text = "I recieve it."
        let ns = text as NSString
        let lint = GrammarLint(utf16Start: ns.range(of: "recieve").location,
                               utf16Length: 7, kind: "spelling", suggestion: "receive")
        let policy = GrammarGatePolicy(enabled: false)
        let stage = GrammarGateStage(checker: FakeGrammarChecker(lints: [lint]), policy: policy)
        let result = await stage.apply(TranscriptDraft(text: text),
                                       context: TextContext(settings: Golden.stageSettings()))
        XCTAssertEqual(result.text, text)
    }

    func testProtectedSpansAreNeverEdited() async {
        let text = "The Superflow release is ready."
        let ns = text as NSString
        let lint = GrammarLint(utf16Start: ns.range(of: "Superflow").location,
                               utf16Length: 9, kind: "spelling", suggestion: "Super flow")
        let stage = GrammarGateStage(checker: FakeGrammarChecker(lints: [lint]),
                                     policy: GrammarGatePolicy(maxEditRatio: 1))
        let result = await stage.apply(TranscriptDraft(text: text,
                                                       protected: Protected(literals: ["Superflow"])),
                                       context: TextContext(settings: Golden.stageSettings()))
        XCTAssertEqual(result.text, text)
    }

    func testEmptyInputIsStable() async {
        let stage = GrammarGateStage(checker: FakeGrammarChecker(lints: []))
        for input in ["", "   ", "\n"] {
            let result = await stage.apply(TranscriptDraft(text: input),
                                           context: TextContext(settings: Golden.stageSettings()))
            XCTAssertEqual(result.text, input)
        }
    }
}
