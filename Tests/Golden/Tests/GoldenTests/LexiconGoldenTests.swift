import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextLexicon
import XCTest

final class LexiconGoldenTests: XCTestCase {
    private func fixture() throws -> LexiconFixture {
        try Golden.load("lexicon/cases.json")
    }

    private func run(_ input: String, entries: [LexiconEntry], settings: AppSettings) async -> TranscriptDraft {
        let stage = LexiconStage(entries: entries)
        return await stage.apply(TranscriptDraft(text: input),
                                 context: TextContext(settings: settings))
    }

    func testLexiconCorpus() async throws {
        let fixture = try fixture()
        let entries = fixture.entries.map(\.entry)
        let settings = Golden.stageSettings()
        for c in fixture.cases {
            let result = await run(c.input, entries: entries, settings: settings)
            assertGolden(result.text, c.expected, name: c.name)
        }
    }

    func testIdempotence() async throws {
        let fixture = try fixture()
        let entries = fixture.entries.map(\.entry)
        let settings = Golden.stageSettings()
        for c in fixture.cases {
            let once = await run(c.input, entries: entries, settings: settings)
            let twice = await run(once.text, entries: entries, settings: settings)
            XCTAssertEqual(once.text, twice.text, "lexicon stage is not idempotent for \(c.name)")
        }
    }

    func testDisabledEntriesAreIgnored() async throws {
        let fixture = try fixture()
        var entries = fixture.entries.map(\.entry)
        entries.append(LexiconEntry(kind: .term, triggers: ["flow"], canonical: "DISABLED", enabled: false))
        let settings = Golden.stageSettings()
        let result = await run("the flow", entries: entries, settings: settings)
        XCTAssertEqual(result.text, "the FLOW", "a disabled entry must not win over an enabled one")
    }

    func testCanonicalFormsBecomeProtectedSpans() async throws {
        let fixture = try fixture()
        let entries = fixture.entries.map(\.entry)
        let settings = Golden.stageSettings()
        let result = await run("I use super flow and jason", entries: entries, settings: settings)
        XCTAssertTrue(result.protected.literals.contains("Superflow"))
        XCTAssertTrue(result.protected.literals.contains("JSON"))
    }

    func testProtectedSpansAreNotRewritten() async throws {
        let entries = [LexiconEntry(kind: .term, triggers: ["flow"], canonical: "FLOW")]
        let stage = LexiconStage(entries: entries)
        let draft = TranscriptDraft(text: "the flow", protected: Protected(literals: ["the flow"]))
        let result = await stage.apply(draft, context: TextContext(settings: Golden.stageSettings()))
        XCTAssertEqual(result.text, "the flow")
    }

    func testEmptyInputIsStable() async throws {
        let fixture = try fixture()
        let entries = fixture.entries.map(\.entry)
        let settings = Golden.stageSettings()
        for input in ["", "   ", "\n"] {
            let result = await run(input, entries: entries, settings: settings)
            XCTAssertEqual(result.text, input)
        }
    }

    func testLongestMatchWinsRegardlessOfEntryOrder() async throws {
        let settings = Golden.stageSettings()
        let shortFirst = [
            LexiconEntry(kind: .term, triggers: ["flow"], canonical: "FLOW"),
            LexiconEntry(kind: .correction, triggers: ["super flow"], canonical: "Superflow"),
        ]
        let result = await run("super flow", entries: shortFirst, settings: settings)
        XCTAssertEqual(result.text, "Superflow")
    }
}
