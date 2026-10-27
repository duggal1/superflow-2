import Foundation
import SuperflowKernel
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureDictionary

@MainActor
final class DictionaryViewModelTests: XCTestCase {
    private var library: InMemoryLibrary!
    private var model: DictionaryViewModel!

    private let bundled = LexiconEntry(id: "bundled:Next.js", kind: .term,
                                       triggers: ["next js"], canonical: "Next.js",
                                       source: .bundled)
    private let userEntry = LexiconEntry(id: "user-1", kind: .correction,
                                         triggers: ["tan stack query"], canonical: "TanStack Query")

    override func setUp() async throws {
        library = InMemoryLibrary(lexicon: [bundled, userEntry])
        model = DictionaryViewModel(repository: library)
        await model.load()
    }

    func testLoadAndFilter() {
        XCTAssertEqual(model.entries.count, 2)
        XCTAssertEqual(model.userEntryCount, 1)
        XCTAssertEqual(model.visibleEntries.count, 2)

        model.filter = .terms
        XCTAssertEqual(model.visibleEntries.map(\.id), ["bundled:Next.js"])
        model.filter = .corrections
        XCTAssertEqual(model.visibleEntries.map(\.id), ["user-1"])

        model.filter = .all
        model.query = "tanstack"
        XCTAssertEqual(model.visibleEntries.map(\.id), ["user-1"])
        model.query = "next"
        XCTAssertEqual(model.visibleEntries.map(\.id), ["bundled:Next.js"])
        model.query = "nothing"
        XCTAssertTrue(model.visibleEntries.isEmpty)
        XCTAssertTrue(model.isEmpty)
    }

    func testSaveCreatesEntryAndValidates() async throws {
        var draft = LexiconDraft(kind: .term, triggers: ["supper flow"], canonical: "Superflow")
        let saved = await model.save(draft)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.entries.count, 3)
        XCTAssertTrue(model.entries.contains { $0.canonical == "Superflow" })

        draft.canonical = "   "
        let rejected = await model.save(draft)
        XCTAssertFalse(rejected)
        XCTAssertEqual(model.entries.count, 3)

        draft = LexiconDraft(kind: .term, triggers: ["next js"], canonical: "NextJS")
        let collision = await model.save(draft)
        XCTAssertFalse(collision)
        XCTAssertEqual(model.entries.count, 3)
    }

    func testValidationWarnsOnCommonWordsWithoutBlocking() {
        let draft = LexiconDraft(kind: .correction, triggers: ["next years"], canonical: "Next.js")
        let issues = LexiconValidation.issues(draft: draft, existing: [bundled])
        XCTAssertTrue(issues.contains(.commonWordTrigger("next years")))
        XCTAssertTrue(LexiconValidation.isValid(draft, existing: [bundled]))
    }

    func testValidationBlocksDuplicatesAndOverlongValues() {
        let draft = LexiconDraft(kind: .term, triggers: ["next.js", "next-js"], canonical: "Next.js")
        let issues = LexiconValidation.issues(draft: draft, existing: [bundled])
        XCTAssertTrue(issues.contains(.duplicateTrigger("next.js")))
        XCTAssertTrue(issues.contains(.duplicateTrigger("next-js")))
        XCTAssertFalse(LexiconValidation.isValid(draft, existing: [bundled]))

        let long = LexiconDraft(kind: .term, triggers: [String(repeating: "a", count: 81)],
                                canonical: String(repeating: "b", count: 201))
        let longIssues = LexiconValidation.issues(draft: long, existing: [])
        XCTAssertTrue(longIssues.contains(.triggerTooLong(String(repeating: "a", count: 81))))
        XCTAssertTrue(longIssues.contains(.canonicalTooLong))
    }

    func testToggleBundledEntryPersists() async throws {
        await model.toggle(bundled)
        let all = try await library.lexicon()
        let saved = all.first { $0.id == bundled.id }
        XCTAssertEqual(saved?.enabled, false)
        XCTAssertEqual(model.entries.first { $0.id == bundled.id }?.enabled, false)
    }

    func testDeleteAndUndo() async throws {
        await model.delete(userEntry)
        XCTAssertEqual(model.entries.count, 1)
        XCTAssertEqual(model.toast.current?.actionTitle, "Undo")

        await model.undoDelete()
        XCTAssertEqual(model.entries.count, 2)
        XCTAssertTrue(model.entries.contains { $0.id == userEntry.id })
    }

    func testBundledEntriesCannotBeDeleted() async throws {
        await model.delete(bundled)
        XCTAssertEqual(model.entries.count, 2)
        XCTAssertEqual(model.toast.current?.style, .warning)
    }

    func testExportContainsOnlyUserEntriesAndRoundTrips() throws {
        let data = try XCTUnwrap(model.exportData())
        let document = try LexiconDocument.decode(data)
        XCTAssertEqual(document.version, LexiconDocument.currentVersion)
        XCTAssertEqual(document.entries.map(\.id), ["user-1"])
        XCTAssertFalse(try document.encoded().isEmpty)
    }

    func testImportSkipsCollisionsAndAddsNewEntries() async throws {
        let incoming = [
            LexiconEntry(id: "new-1", kind: .term, triggers: ["next js"], canonical: "NextJS"),
            LexiconEntry(id: "new-2", kind: .term, triggers: ["ray cast"], canonical: "Raycast"),
            LexiconEntry(id: "new-3", kind: .term, triggers: ["next years"], canonical: "Next.js"),
            LexiconEntry(id: "new-4", kind: .term, triggers: ["ray cast"], canonical: "Duplicate"),
        ]
        let data = try LexiconDocument(entries: incoming).encoded()
        let result = await model.importData(data)

        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.skipped, 2)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(model.entries.count, 4)
        let imported = model.entries.filter { $0.source == .user }.map(\.canonical)
        XCTAssertTrue(imported.contains("Raycast"))
        XCTAssertTrue(imported.contains("Next.js"))
        XCTAssertFalse(imported.contains("NextJS"))
    }

    func testImportRejectsNewerSchema() async throws {
        let data = try LexiconDocument(version: 99,
                                       entries: [LexiconEntry(kind: .term, triggers: ["x"],
                                                              canonical: "X")]).encoded()
        let result = await model.importData(data)
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(model.toast.current?.style, .error)
        XCTAssertTrue(model.toast.current?.text.contains("newer version") ?? false)
    }

    func testImportAcceptsBareArray() async throws {
        let entries = [LexiconEntry(kind: .term, triggers: ["vite"], canonical: "Vite")]
        let data = try JSONEncoder().encode(entries)
        let result = await model.importData(data)
        XCTAssertEqual(result.imported, 1)
        XCTAssertTrue(model.entries.contains { $0.canonical == "Vite" })
    }
}
