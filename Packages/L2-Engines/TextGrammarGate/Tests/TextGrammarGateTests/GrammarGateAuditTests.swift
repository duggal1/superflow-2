import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowTextGrammarGate

final class GrammarGateAuditTests: XCTestCase {
    private let fastPolicy = GrammarGatePolicy(maxEditRatio: 1.0, timeCapMs: 500)

    func testGoldenCorpusIsLargeEnough() {
        XCTAssertGreaterThanOrEqual(GrammarGoldens.cases.count, 200)
        XCTAssertGreaterThanOrEqual(GrammarGoldens.cases.filter { $0.input == $0.expected }.count, 40)
    }

    func testGoldenCorpusRecall() async {
        let checker = PatternGrammarChecker()
        for golden in GrammarGoldens.cases {
            let lints = await checker.lint(golden.input, customWords: [])
            let edits = GrammarGateStage.acceptedEdits(lints, in: golden.input,
                                                       policy: fastPolicy,
                                                       protected: golden.protected)
            let applied = GrammarGateStage.apply(edits, to: golden.input)
            XCTAssertEqual(applied, golden.expected, "input: \(golden.input)")
        }
    }

    func testGoldenCorpusIsIdempotent() async {
        let checker = PatternGrammarChecker()
        for golden in GrammarGoldens.cases {
            let lints = await checker.lint(golden.expected, customWords: [])
            XCTAssertTrue(lints.isEmpty,
                          "idempotence failed on \(golden.expected): \(lints.map(\.kind))")
        }
    }

    func testGoldenCorpusPrecisionClearsThreshold() async {
        let report = await GrammarGateStage.audit(GrammarGoldens.cases,
                                                  checker: PatternGrammarChecker())
        XCTAssertEqual(report.caseCount, GrammarGoldens.cases.count)
        for kind in GrammarGatePolicy.shippingKinds {
            guard let category = report.category(kind) else {
                return XCTFail("missing category \(kind): \(report.summary())")
            }
            XCTAssertGreaterThan(category.proposed, 0, kind)
            XCTAssertGreaterThanOrEqual(category.precision, 0.98,
                                        "\(kind): \(report.summary())")
            XCTAssertTrue(report.ships(kind), kind)
        }
        XCTAssertTrue(report.disabledKinds.isEmpty, report.summary())
    }

    func testLowPrecisionCategoryShipsDisabled() async {
        let cases = [
            GrammarGoldenCase("they is ready", "they are ready"),
            GrammarGoldenCase("we is ready", "we are ready"),
            GrammarGoldenCase("they is late", "they are late"),
            GrammarGoldenCase("we is late", "we are late"),
        ]
        let report = await GrammarGateStage.audit(cases, checker: NoisyAgreementChecker())
        guard let agreement = report.category("agreement") else {
            return XCTFail("missing agreement category")
        }
        XCTAssertEqual(agreement.proposed, 4)
        XCTAssertEqual(agreement.correct, 2)
        XCTAssertLessThan(agreement.precision, 0.98)
        let policy = GrammarGatePolicy().qualified(by: report)
        XCTAssertFalse(policy.allows(kind: "agreement"))
    }

    func testQualifiedPolicyKeepsMeasuredCategories() async {
        let report = await GrammarGateStage.audit(GrammarGoldens.cases,
                                                  checker: PatternGrammarChecker())
        let policy = GrammarGatePolicy().qualified(by: report)
        for kind in GrammarGatePolicy.shippingKinds {
            XCTAssertTrue(policy.allows(kind: kind), kind)
        }
        XCTAssertFalse(policy.allows(kind: "style"))
        XCTAssertFalse(policy.allows(kind: "wordChoice"))
    }

    func testUnmeasuredCategoryNeverShips() {
        let report = GrammarCategoryReport()
        XCTAssertFalse(report.ships("Spelling"))
        XCTAssertNil(report.category("spelling"))
        let empty = GrammarCategoryReport.Category(kind: "Spelling", proposed: 0, correct: 0)
        XCTAssertEqual(empty.precision, 0)
        let good = GrammarCategoryReport.Category(kind: "Spelling", proposed: 100, correct: 98)
        XCTAssertEqual(good.precision, 0.98, accuracy: 0.0001)
    }

    func testAuditIgnoresProtectedSpans() async {
        let checker = PatternGrammarChecker()
        let golden = GrammarGoldenCase("teh Superflow client", "the Superflow client",
                                       protected: Protected(literals: ["Superflow"]))
        let report = await GrammarGateStage.audit([golden], checker: checker)
        XCTAssertEqual(report.category("spelling")?.correct, 1)
        // A lint inside a protected span must not count as evidence.
        let guarded = GrammarGoldenCase("keep Superflow", "keep Superflow",
                                        protected: Protected(literals: ["Superflow"]))
        let blocked = await GrammarGateStage.audit([guarded], checker: checker)
        XCTAssertNil(blocked.category("spelling"))
    }

    func testAuditIgnoresOverlappingLints() async {
        let checker = FakeGrammarChecker(lints: [
            GrammarLint(utf16Start: 0, utf16Length: 3, kind: "Spelling", suggestion: "the"),
            GrammarLint(utf16Start: 1, utf16Length: 2, kind: "Spelling", suggestion: "he"),
        ])
        let report = await GrammarGateStage.audit([GrammarGoldenCase("teh", "the")],
                                                  checker: checker)
        XCTAssertEqual(report.category("spelling")?.proposed, 1)
    }
}
