import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextPipeline

final class ReferenceCleanupTests: XCTestCase {
    private func settings() -> AppSettings {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.spellOutSmallNumbers = false
        settings.numberStyle = .full
        settings.lineFormat.capitalize = false
        settings.lineFormat.finalPeriod = false
        return settings
    }

    func testReferenceCodingDictationTier0() async {
        let raw = "okay so um I I I need you to open the the the file hero dot t s x no wait hero.tsx in the components folder then go to lib backend folder and fix the prospect main engine the path should be lib slash backend slash main slash engine slash router slash prospect-main-engine dot t s and change the status code from five hundred to four two nine when the rate limit is hit also update the constant MAX_RETRY_COUNT from three to five"
        let expected = "okay so I need you to open the file hero.tsx in the components folder then go to lib backend folder and fix the prospect main engine the path should be lib/backend/main/engine/router/prospect-main-engine.ts and change the status code from 500 to 429 when the rate limit is hit also update the constant MAX_RETRY_COUNT from 3 to 5"
        let pipeline = TextPipelineBuilder.make(settings: settings())
        let result = await pipeline.run(raw, context: TextContext(settings: settings()))
        XCTAssertEqual(result.text.replacingOccurrences(of: "\n", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " "), expected)
        XCTAssertTrue(result.draft.protected.literals.contains("hero.tsx"))
        XCTAssertTrue(result.draft.protected.literals.contains("429"))
    }

    func testReferenceDisfluencyTier0() async {
        let raw = "I I I was thinking about the the the performance and um it keeps saying warming the GPU or warming the CPU and that is really bad"
        let pipeline = TextPipelineBuilder.make(settings: settings())
        let result = await pipeline.run(raw, context: TextContext(settings: settings()))
        XCTAssertEqual(result.text.replacingOccurrences(of: "\n", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " "),
                       "I was thinking about the performance and it keeps saying warming the GPU or warming the CPU and that is really bad")
    }

    func testReferenceListHasIndependentItemsAndTail() async {
        var settings = settings()
        settings.cleanupEnabled = true
        let cleaner = CleanupService(cleaner: FakeTextCleaner(.identity))
        let pipeline = TextPipelineBuilder.make(settings: settings, dependencies: TextPipelineDependencies(cleaner: cleaner))
        let raw = "alright so the things we still need to do are first first the text disfluency stage second the code aware path resolution third make sure streaming is forced on fourth the adaptive clipboard restore and fifth the content verification instead of just character count um I I think that’s everything for now"
        let result = await pipeline.run(raw, context: TextContext(settings: settings))
        XCTAssertEqual(result.text, "alright so the things we still need to do are:\n- the text disfluency stage\n- the code aware path resolution\n- make sure streaming is forced on\n- the adaptive clipboard restore\n- the content verification instead of just character count\n\nI think that’s everything for now")
    }
}
