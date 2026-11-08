import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTextCleanup
@testable import SuperflowTextPipeline

private actor WiredCleaner: TextCleaner {
    private(set) var inputs: [String] = []
    var isReady: Bool { true }
    func countTokens(_ text: String) async -> Int { text.split(separator: " ").count }
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        inputs.append(text)
        return CleanResult(text: "Please send the report tomorrow.", tokensIn: 9,
                           tokensOut: 7, hitTokenCap: false, latencyMs: 0)
    }
}

final class CleanupWiringTests: XCTestCase {
    func testMainPipelineAcceptsModelRemovalOfTrailingFiller() async {
        let cleaner = WiredCleaner()
        let settings = AppSettings.default
        let pipeline = TextPipelineBuilder.make(settings: settings,
            dependencies: TextPipelineDependencies(cleaner: CleanupService(cleaner: cleaner)))
        let result = await pipeline.run("please send the report tomorrow um",
                                        context: TextContext(settings: settings))
        let inputs = await cleaner.inputs
        XCTAssertEqual(inputs, ["please send the report tomorrow"])
        XCTAssertEqual(result.draft.cleanupState, .cleaned)
        XCTAssertEqual(result.text, "Please send the report tomorrow.")
        XCTAssertEqual(result.timings.first?.id, "preCleanupRepair")
        XCTAssertEqual(result.timings.last?.id, "techDictionary")
    }

    func testMainPipelineUsesBundledModelVocabulary() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        for (input, expected) in [
            ("use gpt six astra", "GPT-6 Astra"),
            ("use chatgpt six sol", "GPT-6 Sol"),
            ("use opus five point nine", "Claude Opus 5.9"),
            ("use hugging phase", "Hugging Face"),
        ] {
            let result = await pipeline.run(input, context: TextContext(settings: settings))
            XCTAssertTrue(result.text.contains(expected), result.text)
            XCTAssertEqual(result.timings.last?.id, "techDictionary")
        }
    }
}
