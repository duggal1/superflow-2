import XCTest
import SuperflowKernel
import SuperflowTestKit
import SuperflowTextCleanup
@testable import SuperflowTextPipeline

final class PostDedupeTests: XCTestCase {
    func testExplanationReportsProductionOrder() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        let cleaner = CleanupService(cleaner: FakeTextCleaner(.identity))
        let pipeline = TextPipelineBuilder.make(settings: settings, dependencies: .init(cleaner: cleaner))
        let explanation = await pipeline.explain("we we can continue", context: TextContext(settings: settings))
        let ids = explanation.stages.map(\.stageID)
        XCTAssertEqual(ids, ["disfluency", "cleanup", "dedupe", "format", "commands", "spokenCode", "codingLanguage", "numbers", "lexicon", "codeAware", "lineformat", "normalize", "modelNames", "techDictionary"])
        XCTAssertTrue(ids.contains("disfluency"))
        XCTAssertFalse(ids.contains("polish"))
        XCTAssertFalse(ids.contains("structure"))
        XCTAssertFalse(ids.contains("grammar"))
        XCTAssertGreaterThan(ids.firstIndex(of: "numbers") ?? 0, 0)
        XCTAssertGreaterThan(ids.firstIndex(of: "lexicon") ?? 0, 0)
    }

    func testRepeatedWordsAndPhrases() {
        XCTAssertEqual(PostDedupe.apply("please review review the report"), "please review the report")
        XCTAssertEqual(PostDedupe.apply("we need to finish this project before friday we need to finish this project before friday please"), "we need to finish this project before friday please")
        XCTAssertEqual(PostDedupe.apply("it was doing that it was doing that because earlier"), "it was doing that because earlier")
        XCTAssertEqual(PostDedupe.apply("I tried to I tried to go back"), "I tried to go back")
        XCTAssertEqual(PostDedupe.apply("what what exactly changed"), "what exactly changed")
        XCTAssertEqual(PostDedupe.apply("we must we must we must fix the back end"), "we must fix the back end")
        XCTAssertEqual(PostDedupe.apply("must must fix the tech stack"), "must fix the tech stack")
        XCTAssertEqual(PostDedupe.apply("the back end uses the tech stack"), "the back end uses the tech stack")
    }
    func testProtectsMeaningAndFormatting() {
        for input in ["call five five five one two one two", "the code is 7 7 3", "a very very big file", "he said that that was wrong", "I had had enough", "bye bye", "we flew to New York New York is huge", "open src/app.swift src/app.swift now", "it wasn't wasn't there"] {
            XCTAssertEqual(PostDedupe.apply(input), input)
        }
        XCTAssertEqual(PostDedupe.apply("First point.\n\n- item one\n- item two\nthe the end"), "First point.\n\n- item one\n- item two\nthe end")
    }
    func testProtectedPhraseSurvives() {
        XCTAssertEqual(PostDedupe.apply("we need we need help", protected: Protected(literals: ["we need"])), "we need we need help")
    }
}
