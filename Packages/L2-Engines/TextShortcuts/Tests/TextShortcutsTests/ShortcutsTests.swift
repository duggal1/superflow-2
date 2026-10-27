import XCTest
import SuperflowKernel
@testable import SuperflowTextShortcuts

final class ShortcutsTests: XCTestCase {
    func testSpokenDotMatchesBothForms() async {
        let stage = ShortcutsStage(entries: [ShortcutEntry(trigger: "design.md", content: "# DESIGN\n- a\n- b")])
        for input in ["design dot md", "design.md", "Design dot MD."] {
            let out = await stage.apply(TranscriptDraft(text: input), context: TextContext())
            XCTAssertEqual(out.text, "# DESIGN\n- a\n- b")
            XCTAssertTrue(out.shortCircuit)
        }
    }

    func testWholeUtteranceOnly() async {
        let stage = ShortcutsStage(entries: [ShortcutEntry(trigger: "my email", content: "a@b.co")])
        let out = await stage.apply(TranscriptDraft(text: "send my email later"), context: TextContext())
        XCTAssertFalse(out.shortCircuit)
        XCTAssertEqual(out.text, "send my email later")
    }

    func testInlineWordBoundary() async {
        let stage = ShortcutsStage(entries: [ShortcutEntry(trigger: "my email", content: "me@x.co", match: .inline)])
        let out = await stage.apply(TranscriptDraft(text: "send my email now"), context: TextContext())
        XCTAssertEqual(out.text, "send me@x.co now")
    }

    func testOversizeRefused() async {
        let big = String(repeating: "a", count: ShortcutsStage.maxContentBytes + 1)
        let stage = ShortcutsStage(entries: [ShortcutEntry(trigger: "big", content: big)])
        let out = await stage.apply(TranscriptDraft(text: "big"), context: TextContext())
        XCTAssertEqual(out.text, "big")
        XCTAssertFalse(out.shortCircuit)
    }
}
