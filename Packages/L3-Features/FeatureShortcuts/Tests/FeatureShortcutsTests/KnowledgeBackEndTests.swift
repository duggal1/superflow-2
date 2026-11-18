import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureShortcuts

private actor FailingShortcutLibrary: LibraryRepository {
    enum Failure: Error { case load, save }
    var failOn: Failure?
    var stored: [ShortcutEntry] = []
    func setFailure(_ failure: Failure?) { failOn = failure }
    func lexicon() async throws -> [LexiconEntry] { [] }
    func saveLexicon(_ e: LexiconEntry) async throws {}
    func deleteLexicon(id: String) async throws {}
    func shortcuts() async throws -> [ShortcutEntry] {
        if failOn == .load { throw Failure.load }
        return stored
    }
    func saveShortcut(_ e: ShortcutEntry) async throws {
        if failOn == .save { throw Failure.save }
        stored.removeAll { $0.id == e.id }
        stored.append(e)
    }
    func deleteShortcut(id: String) async throws { stored.removeAll { $0.id == id } }
}

@MainActor
final class KnowledgeBackEndTests: XCTestCase {
    private func makeModel(_ entries: [ShortcutEntry] = [],
                           repository: (any LibraryRepository)? = nil) async -> ShortcutsViewModel {
        let repo = repository ?? InMemoryLibrary(shortcuts: entries)
        let model = ShortcutsViewModel(repository: repo)
        await model.load()
        return model
    }

    func testFullTextSearchAcrossTriggerAndContent() async throws {
        let entries = [
            ShortcutEntry(id: "1", trigger: "my calendar link", content: "https://cal.com/me"),
            ShortcutEntry(id: "2", trigger: "standup notes", content: "## Standup\n- Yesterday"),
            ShortcutEntry(id: "3", trigger: "café 東京", content: "Bonjour | 世界"),
        ]
        let model = await makeModel(entries)
        XCTAssertEqual(model.search("CALENDAR").map(\.id), ["1"])
        XCTAssertEqual(model.search("yesterday").map(\.id), ["2"])
        XCTAssertEqual(model.search("café 世界").map(\.id), ["3"])
        XCTAssertEqual(model.search("calendar link").map(\.id), ["1"])
        XCTAssertTrue(model.search("standup calendar").isEmpty, "multiple terms are ANDed")
        XCTAssertTrue(model.search("nothing").isEmpty)
        XCTAssertEqual(model.search("   ").count, 3)
    }

    func testPlainTextExportIsDeterministicAndRoundTrips() async throws {
        let entries = [
            ShortcutEntry(id: "1", trigger: "calendar link",
                          content: "Line one\nLine two | with pipe", match: .wholeUtterance),
            ShortcutEntry(id: "2", trigger: "café 東京", content: "=> escaped",
                          match: .inline),
        ]
        let model = await makeModel(entries)
        let text = model.exportPlainText()
        XCTAssertEqual(text, model.exportPlainText())
        XCTAssertFalse(text.contains("\r"))

        let fresh = await makeModel()
        let result = await fresh.importPlainText(text)
        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.skipped, 0)
        // Plain text carries data, not ids: records get fresh ids on import.
        let first = try XCTUnwrap(fresh.entries.first { $0.trigger == "calendar link" })
        XCTAssertEqual(first.content, entries[0].content)
        XCTAssertEqual(first.match, .wholeUtterance)
        let second = try XCTUnwrap(fresh.entries.first { $0.trigger == "café 東京" })
        XCTAssertEqual(second.content, "=> escaped")
        XCTAssertEqual(second.match, .inline)
    }

    func testPlainTextImportSkipsMalformedDuplicatesAndOversized() async throws {
        let oversized = String(repeating: "z", count: 200 * 1024 + 1)
        let text = """
        # comment
        no delimiter here

        one => wholeUtterance | One
        two => inline | Two
        dup => wholeUtterance | First
        dup => inline | Second
        huge => wholeUtterance | \(oversized)
        next years => inline | Next steps:
        """
        let model = await makeModel()
        let result = await model.importPlainText(text)
        XCTAssertEqual(result.imported, 4, "One, Two, First and Next steps are valid")
        XCTAssertGreaterThanOrEqual(result.skipped, 3)
        XCTAssertTrue(result.warnings.contains { $0.contains("common words") })
        XCTAssertEqual(model.entries.filter { $0.trigger == "dup" }.count, 1)
    }

    func testPlainTextImportIsIdempotentWhenRepeated() async throws {
        let text = "calendar link => wholeUtterance | https://cal.com/me\ncode => inline | ```swift\n"
        let model = await makeModel()
        let first = await model.importPlainText(text)
        let second = await model.importPlainText(text)
        let third = await model.importPlainText(text)
        XCTAssertEqual(first.imported, 2)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(third.imported, 0)
        XCTAssertEqual(model.entries.count, 2, "re-import must not duplicate rows")
    }

    func testLoadFailureSetsHonestErrorAndKeepsStateEmpty() async throws {
        let repo = FailingShortcutLibrary()
        await repo.setFailure(.load)
        let model = await makeModel(repository: repo)
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.isEmpty)

        await repo.setFailure(nil)
        try await repo.saveShortcut(ShortcutEntry(trigger: "ok", content: "OK"))
        await model.load()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.entries.count, 1)
    }

    func testUnicodeAndVeryLongTriggerAreHandled() async throws {
        let model = await makeModel()
        let draft = ShortcutDraft(trigger: "日本語 ☕ café",
                                  content: String(repeating: "é", count: 4_000))
        let saved = await model.save(draft)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.entries.first?.content.count, 4_000)
        XCTAssertEqual(model.search("日本語").count, 1)

        let overlong = ShortcutDraft(trigger: String(repeating: "a", count: 81), content: "x")
        let rejected = await model.save(overlong)
        XCTAssertFalse(rejected)
        XCTAssertEqual(model.entries.count, 1)
    }
}
