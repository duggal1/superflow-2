import XCTest
import SuperflowKernel
@testable import SuperflowTextCommands

final class CommandsTests: XCTestCase {
    private func run(_ s: String) async -> String {
        await CommandsStage().apply(TranscriptDraft(text: s), context: TextContext()).text
    }

    func testNewLineAtEnd() async {
        let out = await run("hello there new line")
        XCTAssertEqual(out, "hello there\n")
    }

    func testNewParagraphAfterPunctuation() async {
        let out = await run("Done. New paragraph next topic")
        XCTAssertEqual(out, "Done.\n\nnext topic")
    }

    func testMidSentenceUntouched() async {
        let out = await run("I need a new line of credit")
        XCTAssertEqual(out, "I need a new line of credit")
    }

    func testNewlineSingleToken() async {
        let out = await run("one. newline two")
        XCTAssertEqual(out, "one.\ntwo")
    }

    func testDisabled() async {
        var settings = AppSettings.default
        settings.commandsEnabled = false
        let out = await CommandsStage().apply(TranscriptDraft(text: "one new line two"),
                                              context: TextContext(settings: settings)).text
        XCTAssertEqual(out, "one new line two")
    }

    func testIdempotent() async {
        let once = await run("one new line two new paragraph three")
        let twice = await run(once)
        XCTAssertEqual(once, twice)
    }
}
