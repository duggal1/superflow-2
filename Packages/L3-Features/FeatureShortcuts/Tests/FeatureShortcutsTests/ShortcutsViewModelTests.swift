import Foundation
import SuperflowKernel
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureShortcuts

@MainActor
final class ShortcutsViewModelTests: XCTestCase {
    private var library: InMemoryLibrary!
    private var model: ShortcutsViewModel!

    private let whole = ShortcutEntry(id: "whole", trigger: "my calendar link",
                                      content: "https://cal.com/me", match: .wholeUtterance)
    private let inline = ShortcutEntry(id: "inline", trigger: "design dot md",
                                       content: "**design.md**", match: .inline)

    override func setUp() async throws {
        library = InMemoryLibrary(shortcuts: [whole, inline])
        model = ShortcutsViewModel(repository: library)
        await model.load()
    }

    func testLoadFilterAndSearch() {
        XCTAssertEqual(model.entries.count, 2)
        XCTAssertEqual(model.visibleEntries.count, 2)

        model.filter = .wholeUtterance
        XCTAssertEqual(model.visibleEntries.map(\.id), ["whole"])
        model.filter = .inline
        XCTAssertEqual(model.visibleEntries.map(\.id), ["inline"])

        model.filter = .all
        model.query = "cal.com"
        XCTAssertEqual(model.visibleEntries.map(\.id), ["whole"])
        model.query = "nothing"
        XCTAssertTrue(model.isEmpty)
    }

    func testSaveCreatesShortcut() async throws {
        let draft = ShortcutDraft(trigger: "standup notes",
                                  content: "## Standup\n- Yesterday\n- Today")
        let saved = await model.save(draft)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.entries.count, 3)
        XCTAssertEqual(model.entries.first { $0.trigger == "standup notes" }?.content,
                       "## Standup\n- Yesterday\n- Today")
    }

    func testValidationBlocksDuplicateAfterNormalization() {
        let draft = ShortcutDraft(trigger: "design.md", content: "replacement", match: .inline)
        let issues = ShortcutValidation.issues(draft: draft, existing: [whole, inline])
        XCTAssertTrue(issues.contains(.duplicateTrigger("design.md")))
        XCTAssertFalse(ShortcutValidation.isValid(draft, existing: [whole, inline]))
    }

    func testValidationBlocksOversizedContent() {
        let draft = ShortcutDraft(trigger: "big", content: String(repeating: "a", count: 200 * 1024 + 1))
        let issues = ShortcutValidation.issues(draft: draft, existing: [])
        XCTAssertTrue(issues.contains(.contentTooLarge(200 * 1024 + 1)))
        XCTAssertFalse(ShortcutValidation.isValid(draft, existing: []))
    }

    func testCommonWordsWarnWithoutBlocking() {
        let draft = ShortcutDraft(trigger: "next time", content: "Next steps:", match: .inline)
        let issues = ShortcutValidation.issues(draft: draft, existing: [])
        XCTAssertTrue(issues.contains(.commonWordTrigger("next time")))
        XCTAssertTrue(ShortcutValidation.isValid(draft, existing: []))
    }

    func testToggleAndDeleteUndo() async throws {
        await model.toggle(whole)
        let all = try await library.shortcuts()
        XCTAssertEqual(all.first { $0.id == "whole" }?.enabled, false)

        await model.delete(inline)
        XCTAssertEqual(model.entries.count, 1)
        await model.undoDelete()
        XCTAssertEqual(model.entries.count, 2)
        XCTAssertTrue(model.entries.contains { $0.id == "inline" })
    }

    func testPreviewRunsWholeUtteranceAndInlineStages() async throws {
        let wholePreview = await model.preview("My calendar link.")
        XCTAssertEqual(wholePreview, "https://cal.com/me")

        let inlinePreview = await model.preview("open design dot md please")
        XCTAssertEqual(inlinePreview, "open **design.md** please")

        let unchanged = await model.preview("something else entirely")
        XCTAssertEqual(unchanged, "something else entirely")
    }

    func testDisabledShortcutDoesNotPreviewUnlessForced() async throws {
        await model.toggle(whole)
        let disabledPreview = await model.preview("my calendar link")
        XCTAssertEqual(disabledPreview, "my calendar link")

        let forced = await model.preview("my calendar link", using: [whole])
        XCTAssertEqual(forced, "https://cal.com/me")
    }

    func testExportAndImportRoundTrip() async throws {
        let data = try XCTUnwrap(model.exportData())
        let document = try ShortcutDocument.decode(data)
        XCTAssertEqual(document.entries.count, 2)

        let incoming = [
            ShortcutEntry(id: "dup", trigger: "my calendar link", content: "other"),
            ShortcutEntry(id: "new", trigger: "standup notes", content: "- done"),
            ShortcutEntry(id: "empty", trigger: "empty", content: "   "),
        ]
        let importData = try ShortcutDocument(entries: incoming).encoded()
        let result = await model.importData(importData)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 2)
        XCTAssertTrue(model.entries.contains { $0.trigger == "standup notes" })
    }

    func testImportRejectsNewerSchemaAndAcceptsBareArray() async throws {
        let newer = try ShortcutDocument(version: 99,
                                         entries: [ShortcutEntry(trigger: "x", content: "X")]).encoded()
        let rejected = await model.importData(newer)
        XCTAssertEqual(rejected.imported, 0)
        XCTAssertEqual(model.toast.current?.style, .error)

        let bare = try JSONEncoder().encode([ShortcutEntry(trigger: "vite", content: "Vite")])
        let accepted = await model.importData(bare)
        XCTAssertEqual(accepted.imported, 1)
    }
}
