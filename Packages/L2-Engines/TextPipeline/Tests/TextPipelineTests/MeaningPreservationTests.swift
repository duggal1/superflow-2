import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextPipeline

/// Fact-preservation gates from the accuracy contract. These run the real
/// deterministic pipeline without a cleanup model: no stage may change a
/// negation, number, status code, deadline, name or explicit self-correction.
final class MeaningPreservationTests: XCTestCase {
    private func output(_ input: String) async -> String {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        return await pipeline.run(input, context: TextContext(settings: settings)).text
    }

    func testNegationAndNumbersSurvive() async {
        let text = await output("do not send the five hundred dollar invoice on Friday")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("not"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("friday"), text)
    }

    func testStatusCodesAndVersionsSurvive() async {
        let text = await output("oauth two point zero returned 503 and 403 but not 500")
        for token in ["503", "403", "500"] { XCTAssertTrue(text.contains(token), text) }
        XCTAssertTrue(text.localizedCaseInsensitiveContains("not"), text)
    }

    func testExplicitSelfCorrectionKeepsFinalChoice() async {
        let text = await output("move the meeting to Thursday actually no Wednesday at three thirty")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("wednesday"), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("thursday"), text)
    }

    func testCompressedTokenNeverLosesContent() async {
        let text = await output("The rediscache and validation is broken")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("cache"), text)
    }

    func testOrdinaryActuallyNoIsNeverDeleted() async {
        let text = await output("I actually no longer need the report tomorrow")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("actually no"), text)
    }

    func testOrdinaryHomophonesAreNotTechnicalized() async {
        for input in ["see you next year", "I need some cash tomorrow", "open the website please"] {
            let text = await output(input)
            XCTAssertFalse(text.contains("Next.js"), text)
            XCTAssertFalse(text.contains("OpenAI"), text)
            XCTAssertFalse(text.contains("WebSocket"), text)
        }
    }
}
