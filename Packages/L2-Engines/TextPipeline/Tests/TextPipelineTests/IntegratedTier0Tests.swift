import XCTest
import SuperflowKernel
import SuperflowTextPipeline

final class IntegratedTier0Tests: XCTestCase {
    func testLongPausePreservesRepeatedEmphasis() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.lineFormat.capitalize = false
        settings.lineFormat.finalPeriod = false
        let context = TextContext(settings: settings, wordTimings: [
            WordTiming(word: "very", startMs: 0, endMs: 100),
            WordTiming(word: "very", startMs: 900, endMs: 1_000),
            WordTiming(word: "good", startMs: 1_050, endMs: 1_200),
        ])
        let result = await TextPipelineBuilder.make(settings: settings).run("very very good", context: context)
        XCTAssertEqual(result.text, "very very good")
    }

    func testProductionPipelineUsesNewStagesAndPreservesProtectedText() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.commandsEnabled = false
        settings.harperEnabled = false
        settings.lineFormat.capitalize = false
        settings.lineFormat.finalPeriod = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let context = TextContext(settings: settings)
        let cases: [(String, String)] = [
            ("extremely extremely extremely important", "extremely important"),
            ("he had had enough", "he had had enough"),
            ("a six hundred million-parameter model", "a 600M-parameter model"),
            ("half a million", "0.5M"),
            ("half 1M", "0.5M"),
            ("2.2 trillion", "2.2T"),
            ("zero point six billion parameters", "0.6B parameters"),
        ]
        for (input, expected) in cases {
            let result = await pipeline.run(input, context: context)
            XCTAssertEqual(result.text, expected, input)
        }
        let input = "Go Go and 0.6 billion"
        let protected = Protected(literals: ["Go Go", "0.6 billion"])
        let result = await pipeline.run(input, context: context, protected: protected)
        XCTAssertEqual(result.text, input)
    }
}
