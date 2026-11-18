import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureDictionary

private actor FailingLibrary: LibraryRepository {
    enum Failure: Error { case load, save }
    var failOn: Failure?
    var stored: [LexiconEntry] = []
    func setFailure(_ failure: Failure?) { failOn = failure }
    func lexicon() async throws -> [LexiconEntry] {
        if failOn == .load { throw Failure.load }
        return stored
    }
    func saveLexicon(_ e: LexiconEntry) async throws {
        if failOn == .save { throw Failure.save }
        stored.removeAll { $0.id == e.id }
        stored.append(e)
    }
    func deleteLexicon(id: String) async throws { stored.removeAll { $0.id == id } }
    func shortcuts() async throws -> [ShortcutEntry] { [] }
    func saveShortcut(_ e: ShortcutEntry) async throws {}
    func deleteShortcut(id: String) async throws {}
}

@MainActor
final class KnowledgeBackEndTests: XCTestCase {
    private func makeModel(_ entries: [LexiconEntry] = [],
                           repository: (any LibraryRepository)? = nil) async -> DictionaryViewModel {
        let repo = repository ?? InMemoryLibrary(lexicon: entries)
        let model = DictionaryViewModel(repository: repo)
        await model.load()
        return model
    }

    func testFullTextSearchIsTokenizedRankedAndDeterministic() async throws {
        let entries = [
            LexiconEntry(id: "1", kind: .term, triggers: ["next js"], canonical: "Next.js"),
            LexiconEntry(id: "2", kind: .correction, triggers: ["item potency"],
                         canonical: "idempotency"),
            LexiconEntry(id: "3", kind: .term, triggers: ["CAFÉ 東京"], canonical: "Café Guide"),
        ]
        let model = await makeModel(entries)

        XCTAssertEqual(model.search("NEXT").map(\.id), ["1"])
        XCTAssertEqual(model.search("js").map(\.id), ["1"])
        XCTAssertEqual(model.search("item potency").map(\.id), ["2"])
        XCTAssertEqual(model.search("café 東京").map(\.id), ["3"])
        XCTAssertEqual(model.search("next js").map(\.id), ["1"])
        XCTAssertTrue(model.search("NEXT CAFÉ").isEmpty, "multiple terms are ANDed")
        XCTAssertTrue(model.search("nothing").isEmpty)
        XCTAssertEqual(model.search("   ").count, 3, "empty search returns every entry")
    }

    func testPlainTextExportIsDeterministicAndRoundTrips() async throws {
        let entries = [
            LexiconEntry(id: "1", kind: .term, triggers: ["next js", "next, js"],
                         canonical: "Next.js"),
            LexiconEntry(id: "2", kind: .correction, triggers: ["café 東京"],
                         canonical: "Café => 東京\nLine"),
        ]
        let model = await makeModel(entries)
        let text = model.exportPlainText()
        XCTAssertEqual(text, model.exportPlainText(), "export must be deterministic")
        XCTAssertTrue(text.contains("=>"), "export uses the documented delimiter")
        XCTAssertFalse(text.contains("\r"), "export uses LF only")

        let fresh = await makeModel()
        let result = await fresh.importPlainText(text)
        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(Set(fresh.entries.map(\.canonical)), Set(entries.map(\.canonical)))
        let correction = try XCTUnwrap(fresh.entries.first { $0.kind == .correction })
        XCTAssertEqual(correction.canonical, "Café => 東京\nLine")
        XCTAssertEqual(correction.triggers, ["café 東京"])
    }

    func testPlainTextImportSkipsMalformedDuplicatesAndReportsWarnings() async throws {
        let long = String(repeating: "a", count: 81)
        let text = """
        # a comment

        malformed line without delimiter
        one => One
        alias, other => Two
        \(long) => Too Long Trigger
        dup => First
        dup => Second
        next years => Next.js
        """
        let model = await makeModel()
        let result = await model.importPlainText(text)
        XCTAssertEqual(result.imported, 4, "One, Two, First and Next.js are valid")
        XCTAssertGreaterThanOrEqual(result.skipped, 3)
        XCTAssertTrue(result.warnings.contains { $0.contains("common words") })
        XCTAssertTrue(model.entries.contains { $0.canonical == "Next.js" })
        XCTAssertEqual(model.entries.filter { $0.triggers.contains("dup") }.count, 1)
    }

    func testPlainTextImportIsIdempotentWhenRepeated() async throws {
        let text = "one => One\ncafé 東京 => Café Guide\n"
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
        let repo = FailingLibrary()
        await repo.setFailure(.load)
        let model = await makeModel(repository: repo)
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertTrue(model.isEmpty)

        await repo.setFailure(nil)
        try await repo.saveLexicon(LexiconEntry(kind: .term, triggers: ["ok"], canonical: "OK"))
        await model.load()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.entries.count, 1)
    }

    func testSaveFailureDoesNotMutateLocalState() async throws {
        let repo = FailingLibrary()
        let model = await makeModel(repository: repo)
        await repo.setFailure(.save)
        let ok = await model.save(LexiconDraft(kind: .term, triggers: ["new"], canonical: "New"))
        XCTAssertFalse(ok)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(model.toast.current?.style, .error)
    }

    func testUnicodeAndVeryLongValuesAreHandled() async throws {
        let model = await makeModel()
        let draft = LexiconDraft(kind: .correction,
                                 triggers: ["日本語 ☕ café"],
                                 canonical: String(repeating: "価格", count: 100))
        let saved = await model.save(draft)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.entries.first?.canonical, String(repeating: "価格", count: 100))
        XCTAssertEqual(model.search("日本語").count, 1)

        let overlong = LexiconDraft(kind: .term, triggers: ["x"], canonical: String(repeating: "a", count: 201))
        let rejected = await model.save(overlong)
        XCTAssertFalse(rejected)
        XCTAssertEqual(model.entries.count, 1)
    }
}
