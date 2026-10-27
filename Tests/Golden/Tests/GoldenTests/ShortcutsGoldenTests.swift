import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextShortcuts
import XCTest

final class ShortcutsGoldenTests: XCTestCase {
    private func fixture() throws -> ShortcutFixture {
        try Golden.load("shortcuts/cases.json")
    }

    private func run(_ input: String, entries: [ShortcutEntry]) async -> TranscriptDraft {
        let stage = ShortcutsStage(entries: entries)
        return await stage.apply(TranscriptDraft(text: input),
                                 context: TextContext(settings: Golden.stageSettings()))
    }

    func testShortcutCorpus() async throws {
        let fixture = try fixture()
        let entries = fixture.entries.map(\.entry)
        for c in fixture.cases {
            let result = await run(c.input, entries: entries)
            assertGolden(result.text, c.expected, name: c.name)
        }
    }

    func testWholeUtteranceShortCircuits() async throws {
        let fixture = try fixture()
        let entries = fixture.entries.map(\.entry)
        let result = await run("sign off", entries: entries)
        XCTAssertTrue(result.shortCircuit)
        XCTAssertEqual(result.text, "# Notes\n\n- one\n- two")
        XCTAssertTrue(result.protected.literals.contains("# Notes\n\n- one\n- two"))
        XCTAssertTrue(result.diagnostics.contains { $0.message == "expanded shortcut" })
    }

    func testInlineMatchDoesNotShortCircuit() async throws {
        let fixture = try fixture()
        let entries = fixture.entries.map(\.entry)
        let result = await run("for the standup tomorrow", entries: entries)
        XCTAssertFalse(result.shortCircuit)
        XCTAssertEqual(result.text, "for the Daily standup notes tomorrow")
    }

    func testNormalization() {
        XCTAssertEqual(ShortcutsStage.normalize("Sign Off."), "sign off")
        XCTAssertEqual(ShortcutsStage.normalize("  design   dot   md  "), "design.md")
        XCTAssertEqual(ShortcutsStage.normalize("a slash b"), "a/b")
        XCTAssertEqual(ShortcutsStage.normalize("a dash b"), "a-b")
        XCTAssertEqual(ShortcutsStage.normalize("\"my email\""), "my email")
    }

    func testDisabledAndEmptyEntriesAreIgnored() async throws {
        let entries = [
            ShortcutEntry(trigger: "sign off", content: "disabled", enabled: false),
            ShortcutEntry(trigger: "sign off", content: ""),
            ShortcutEntry(trigger: "", content: "empty trigger"),
        ]
        let result = await run("sign off", entries: entries)
        XCTAssertEqual(result.text, "sign off")
        XCTAssertFalse(result.shortCircuit)
    }

    func testFirstMatchingEntryWins() async throws {
        let entries = [
            ShortcutEntry(trigger: "sign off", content: "first"),
            ShortcutEntry(trigger: "sign off", content: "second"),
        ]
        let result = await run("sign off", entries: entries)
        XCTAssertEqual(result.text, "first")
    }

    func testContentOverLimitIsRejectedWithDiagnostic() async throws {
        let huge = String(repeating: "a", count: ShortcutsStage.maxContentBytes + 1)
        let result = await run("sign off", entries: [ShortcutEntry(trigger: "sign off", content: huge)])
        XCTAssertEqual(result.text, "sign off")
        XCTAssertFalse(result.shortCircuit)
        XCTAssertTrue(result.diagnostics.contains { $0.message.contains("exceeds 200 KB") })
    }

    func testContentAtLimitIsAccepted() async throws {
        let limit = String(repeating: "b", count: ShortcutsStage.maxContentBytes)
        let result = await run("sign off", entries: [ShortcutEntry(trigger: "sign off", content: limit)])
        XCTAssertEqual(result.text, limit)
        XCTAssertTrue(result.shortCircuit)
    }

    func testEmptyInputIsStable() async throws {
        let fixture = try fixture()
        let entries = fixture.entries.map(\.entry)
        let result = await run("", entries: entries)
        XCTAssertEqual(result.text, "")
        XCTAssertFalse(result.shortCircuit)
    }

    func testIdempotenceForNonMatchingText() async throws {
        let fixture = try fixture()
        let entries = fixture.entries.map(\.entry)
        // Inline expansion is intentionally not idempotent (it re-expands its own
        // output), so only text that does not contain a trigger is checked here.
        for input in ["just some words", "", "nothing to expand"] {
            let once = await run(input, entries: entries)
            let twice = await run(once.text, entries: entries)
            XCTAssertEqual(once.text, twice.text, "shortcut stage changed its own output for \(input)")
        }
    }
}
