import XCTest
import SuperflowKernel
@testable import SuperflowTextCleanup

final class DictationRemediationTests: XCTestCase {
    func testExplicitCardinalCommands() {
        XCTAssertEqual(SpokenEnumerationShaper.explicitCardinals("one fix the bug two run tests"),
                       "1. fix the bug\n2. run tests")
        XCTAssertEqual(SpokenEnumerationShaper.explicitCardinals("Steps: number one, fix it number two, test it"),
                       "Steps:\n1. fix it\n2. test it")
        XCTAssertEqual(SpokenEnumerationShaper.explicitCardinals("1. fix it 2. test it"),
                       "1. fix it\n2. test it")
    }

    func testOrdinaryNumbersRemainProse() {
        for input in ["one apple two oranges", "1.5 liters and 2.0 liters",
                      "I bought one apple two oranges", "one two three", "version 1.2.3"] {
            XCTAssertEqual(SpokenEnumerationShaper.explicitCardinals(input), input)
        }
    }

    func testExplicitTwoItemListThroughFormattingStage() async {
        var settings = AppSettings.default
        settings.cleanupStructure = "prose"
        let result = await FormattingStage().apply(
            TranscriptDraft(text: "1 fix the bug 2 run tests"),
            context: TextContext(settings: settings))
        XCTAssertEqual(result.text, "1. fix the bug\n2. run tests")
    }

    func testShortProseFragmentsJoinWithoutTouchingLists() {
        XCTAssertEqual(ParagraphShaper.apply("This is fine.\nWe can ship.\nTest it first."),
                       "This is fine. We can ship. Test it first.")
        XCTAssertEqual(ParagraphShaper.apply("Steps:\n1. fix it\n2. test it"),
                       "Steps:\n1. fix it\n2. test it")
        XCTAssertEqual(ParagraphShaper.apply("First paragraph.\n\nSecond paragraph."),
                       "First paragraph.\n\nSecond paragraph.")
    }
}
