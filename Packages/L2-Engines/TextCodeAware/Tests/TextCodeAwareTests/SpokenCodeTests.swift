import XCTest
import SuperflowKernel
@testable import SuperflowTextCodeAware

final class SpokenCodeTests: XCTestCase {
    func testExplicitCodeWithoutAProject() {
        let cases = [
            ("open hero dot t s x", "open hero.tsx"),
            ("open (hero dot t s x).", "open (hero.tsx)."),
            ("lib slash backend slash main slash engine slash router slash prospect-main-engine dot t s", "lib/backend/main/engine/router/prospect-main-engine.ts"),
            ("MAX underscore RETRY underscore COUNT", "MAX_RETRY_COUNT"),
            ("hero dot t s x no wait hero.tsx", "hero.tsx"),
            ("hero dot t s x no wait banner dot t s x", "banner.tsx"),
            ("hero dot t s x hero.tsx", "hero.tsx"),
            ("hero.tsx no wait banner.tsx no sorry widget.tsx", "widget.tsx"),
            ("MAX_RETRY_COUNT no wait MAX_COUNT", "MAX_COUNT"),
            ("send to support at superwhisper dot com", "send to support@superwhisper.com"),
            ("send to support at example dot co dot io.", "send to support@example.co.io."),
            ("open  hero dot t s x\nthen config dot json.", "open  hero.tsx\nthen config.json."),
        ]
        for (raw, expected) in cases {
            let result = SpokenCodeRewriter.rewrite(raw)
            XCTAssertEqual(result.text, expected, raw)
            XCTAssertEqual(SpokenCodeRewriter.rewrite(result.text).text, expected, raw)
        }
    }

    func testBoundariesAndAmbiguousProse() {
        let cases = [
            "this slash that", "well at home", "hero dot t. s x", "hero. dot tsx",
            "hero.tsx no wait config.json", "open hero dot unknown", "hero dot\nt s x",
        ]
        for raw in cases { XCTAssertEqual(SpokenCodeRewriter.rewrite(raw).text, raw) }
    }

    func testDictionaryLiteralsAreNotRewritten() {
        let raw = "open hero dot t s x"
        let result = SpokenCodeRewriter.rewrite(raw, protected: Protected(literals: ["hero dot t s x"]))
        XCTAssertEqual(result.text, raw)
        XCTAssertTrue(result.edits.isEmpty)
    }

    func testPreservesCaseAndProtectsProducedAndExistingCode() {
        let result = SpokenCodeRewriter.rewrite("Open Hero dot tsx and MAX_RETRY_COUNT")
        XCTAssertEqual(result.text, "Open Hero.tsx and MAX_RETRY_COUNT")
        XCTAssertEqual(result.protected, ["Hero.tsx", "MAX_RETRY_COUNT"])
    }

    func testProvenancePointsAtTheActualReplacement() {
        let raw = "open hero dot t s x\nthen config dot json"
        let result = SpokenCodeRewriter.rewrite(raw)
        XCTAssertEqual(result.edits.count, 2)
        XCTAssertEqual(result.edits.map { (raw as NSString).substring(with: $0.input.nsRange) },
                       ["hero dot t s x", "config dot json"])
        XCTAssertEqual(result.edits.map { (result.text as NSString).substring(with: $0.output.nsRange) },
                       ["hero.tsx", "config.json"])
    }
}
