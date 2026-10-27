import AppKit
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowTextInsertion

private actor FakeAccessibility: AccessibilityInserting {
    var secure = false
    var accepts = true
    private(set) var inserted: [String] = []

    func setSecure(_ value: Bool) { secure = value }
    func setAccepts(_ value: Bool) { accepts = value }

    func isSecureField() async -> Bool { secure }

    func insert(_ text: String) async throws -> Bool {
        guard accepts else { return false }
        inserted.append(text)
        return true
    }
}

private struct FakePoster: KeyEventPosting {
    var isTrusted = true
    var result = true
    func paste() -> Bool { result }
}

final class TextInsertionTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.superflow.tests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    private func inserter(accessibility: FakeAccessibility, poster: FakePoster) -> SystemTextInserter {
        SystemTextInserter(pasteboard: pasteboard, accessibility: accessibility,
                           eventPoster: poster, sleep: { _ in })
    }

    func testPasteboardSnapshotRestoresAllTypes() {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(Data([1, 2, 3]), forType: .png)
        pasteboard.writeObjects([item])
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("transient", forType: .string)
        let expected = pasteboard.changeCount
        snapshot.restore(into: pasteboard, onlyIfChangeCount: expected)

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: .png), Data([1, 2, 3]))
    }

    func testSnapshotRefusesToClobberNewerWrite() {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("someone else", forType: .string)
        snapshot.restore(into: pasteboard, onlyIfChangeCount: pasteboard.changeCount - 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "someone else")
    }

    func testClipboardOnlyWritesTransientConcealedText() async throws {
        let accessibility = FakeAccessibility()
        let outcome = try await inserter(accessibility: accessibility, poster: FakePoster())
            .insert("hello", strategy: .clipboardOnly)
        guard case .clipboardOnly = outcome else { return XCTFail("expected clipboardOnly") }
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
        XCTAssertEqual(pasteboard.string(forType: .superflowTransient), "")
        XCTAssertEqual(pasteboard.string(forType: .superflowConcealed), "")
    }

    func testAutoFallsBackToAccessibility() async throws {
        let accessibility = FakeAccessibility()
        let outcome = try await inserter(accessibility: accessibility, poster: FakePoster(isTrusted: false))
            .insert("fallback", strategy: .auto)
        XCTAssertEqual(outcome, .accessibility)
        let inserted = await accessibility.inserted
        XCTAssertEqual(inserted, ["fallback"])
    }

    func testAutoFallsBackToClipboardWhenBothFail() async throws {
        let accessibility = FakeAccessibility()
        await accessibility.setAccepts(false)
        let outcome = try await inserter(accessibility: accessibility, poster: FakePoster(result: false))
            .insert("keep me", strategy: .auto)
        guard case .clipboardOnly = outcome else { return XCTFail("expected clipboardOnly") }
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
    }

    func testSecureFieldIsNeverTouched() async throws {
        let accessibility = FakeAccessibility()
        await accessibility.setSecure(true)
        let outcome = try await inserter(accessibility: accessibility, poster: FakePoster())
            .insert("secret", strategy: .auto)
        XCTAssertEqual(outcome, .blockedSecureField)
        let inserted = await accessibility.inserted
        XCTAssertTrue(inserted.isEmpty)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testPasteRestoresClipboardAfterSuccess() async throws {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let outcome = try await inserter(accessibility: FakeAccessibility(), poster: FakePoster())
            .insert("dictated", strategy: .pasteboard)
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testEmptyTextIsANoOp() async throws {
        let outcome = try await inserter(accessibility: FakeAccessibility(), poster: FakePoster())
            .insert("", strategy: .auto)
        XCTAssertEqual(outcome, .pasted)
    }

    func testSystemInserterSatisfiesTextInserterContract() async throws {
        let inserter = inserter(accessibility: FakeAccessibility(), poster: FakePoster())
        try await TextInserterContract().verify(inserter)
    }
}
