import Foundation
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowTextInsertion

@MainActor
private struct AdapterHarness {
    let inserter: SystemTextInserter
    let focus: FakeFocusInspector
    let target: FakeTarget
    let clipboard: FakeClipboard
    let poster: FakePoster
    let apps: FakeApps
    let scheduler: InlineRestoreScheduler
    let menu: FakeMenuPaster
}

@MainActor
private func makeAdapter(focus: InsertionFocus = .editable(role: "AXTextArea"),
                         count: Int? = 0,
                         pasteValue: String = "",
                         posterResult: Bool = true,
                         posterIncrements: Bool = true,
                         frontmost: pid_t? = 77,
                         ownPID: pid_t = 999,
                         menuResult: MenuPasteResult = .notFound,
                         menuPastes: Bool = false) -> AdapterHarness {
    let countBox = Box(count)
    let target = FakeTarget(count: countBox)
    let focusInspector = FakeFocusInspector(focus: focus, target: target)
    let clipboard = FakeClipboard()
    let poster = FakePoster(result: posterResult, increments: posterIncrements, box: countBox)
    let apps = FakeApps(frontmost: frontmost, ownPID: ownPID)
    let scheduler = InlineRestoreScheduler()
    let menu = FakeMenuPaster(result: menuResult,
                              box: menuPastes ? countBox : nil,
                              pasteValue: menuPastes ? pasteValue : "")
    let service = TextInsertionService(
        focus: focusInspector,
        clipboard: clipboard,
        poster: poster,
        keyResolver: FakeKeyResolver(code: 9),
        apps: apps,
        menuPaster: menu,
        restoreScheduler: scheduler,
        secureInput: { false },
        axTrusted: { true },
        sleep: { _ in })
    return AdapterHarness(inserter: SystemTextInserter(service: service), focus: focusInspector,
                          target: target, clipboard: clipboard, poster: poster, apps: apps,
                          scheduler: scheduler, menu: menu)
}

@MainActor
final class SystemTextInserterTests: XCTestCase {
    func testEmptyTextIsANoOp() async throws {
        let harness = makeAdapter()
        let outcome = try await harness.inserter.insert("", strategy: .auto)
        XCTAssertEqual(outcome, .pasted)
        let writes = await harness.clipboard.writes
        XCTAssertEqual(writes, 0)
    }

    func testSecureFieldIsBlockedAndClipboardUntouched() async throws {
        let harness = makeAdapter(focus: .secure)
        for strategy in InsertionStrategy.allCases {
            let outcome = try await harness.inserter.insert("secret", strategy: strategy)
            XCTAssertEqual(outcome, .blockedSecureField, "\(strategy)")
        }
        let writes = await harness.clipboard.writes
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(harness.target.insertedTexts.isEmpty)
    }

    func testAutoPastesForEditableFields() async throws {
        let harness = makeAdapter()
        let outcome = try await harness.inserter.insert("paste first", strategy: .auto)
        XCTAssertEqual(outcome, .pasted)
        let writes = await harness.clipboard.writes
        XCTAssertEqual(writes, 1)
        let posts = await harness.poster.posts
        XCTAssertEqual(posts, 1)
        XCTAssertTrue(harness.menu.pressedPIDs.isEmpty, "no menu fallback after a confirmed chord")
    }

    /// A host that ignores the synthetic chord may still honour Edit > Paste.
    func testAutoUsesMenuPasteWhenTheChordIsIgnored() async throws {
        let harness = makeAdapter(focus: .unknown(reason: "role-AXGroup"),
                                  pasteValue: "hello",
                                  posterResult: false,
                                  menuResult: .pressed,
                                  menuPastes: true)
        let outcome = try await harness.inserter.insert("hello", strategy: .auto)
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(harness.menu.pressedPIDs, [77])
    }

    func testPasteSuccessReturnsPastedAndRestores() async throws {
        let harness = makeAdapter(focus: .unknown(reason: "role-AXGroup"))
        let outcome = try await harness.inserter.insert("dictated", strategy: .auto)
        XCTAssertEqual(outcome, .pasted)
        await harness.scheduler.runPending()
        let restores = await harness.clipboard.restores
        XCTAssertEqual(restores, 1)
    }

    /// Web editors may accept Cmd+V while exposing no AX value or count.
    /// The adapter must not tell the Island that this was a definite failure.
    func testUnverifiablePostedPasteStaysSilentAndKeepsRecoveryClipboard() async throws {
        let harness = makeAdapter(focus: .unknown(reason: "role-AXGroup"), count: nil)
        let outcome = try await harness.inserter.insert("already pasted", strategy: .auto)
        XCTAssertEqual(outcome, .pasted)
        let text = await harness.clipboard.text
        XCTAssertEqual(text, "already pasted")
        let posts = await harness.poster.posts
        XCTAssertEqual(posts, 1, "Never send a second mutation when AX is stale")
        XCTAssertTrue(harness.scheduler.delays.isEmpty)
    }

    func testAutoFallsBackToAccessibility() async throws {
        let harness = makeAdapter(focus: .unknown(reason: "role-AXGroup"), posterResult: false)
        let outcome = try await harness.inserter.insert("fallback", strategy: .auto)
        XCTAssertEqual(outcome, .accessibility)
        XCTAssertEqual(harness.target.insertedTexts, ["fallback"])
    }

    func testPasteboardStrategyDoesNotFallBackToAX() async throws {
        let harness = makeAdapter(posterResult: false)
        let outcome = try await harness.inserter.insert("keep me", strategy: .pasteboard)
        guard case .clipboardOnly = outcome else { return XCTFail("expected clipboardOnly, got \(outcome)") }
        XCTAssertTrue(harness.target.insertedTexts.isEmpty)
        let text = await harness.clipboard.text
        XCTAssertEqual(text, "keep me")
    }

    func testAccessibilityStrategySkipsTheChord() async throws {
        let harness = makeAdapter()
        let outcome = try await harness.inserter.insert("ax only", strategy: .accessibility)
        XCTAssertEqual(outcome, .accessibility)
        let posts = await harness.poster.posts
        XCTAssertEqual(posts, 0)
    }

    func testAutoFallsBackToClipboardWhenBothFail() async throws {
        let harness = makeAdapter(posterResult: false)
        harness.target.accepts = false
        let outcome = try await harness.inserter.insert("keep me", strategy: .auto)
        guard case .clipboardOnly = outcome else { return XCTFail("expected clipboardOnly") }
        let text = await harness.clipboard.text
        XCTAssertEqual(text, "keep me")
    }

    func testClipboardOnlyWritesTheText() async throws {
        let harness = makeAdapter()
        let outcome = try await harness.inserter.insert("copy me", strategy: .clipboardOnly)
        guard case .clipboardOnly(let reason) = outcome else { return XCTFail("expected clipboardOnly") }
        XCTAssertTrue(reason.contains("clipboard"))
        let text = await harness.clipboard.text
        XCTAssertEqual(text, "copy me")
        let posts = await harness.poster.posts
        XCTAssertEqual(posts, 0)
    }

    func testStrategyOptions() {
        let auto = SystemTextInserter.options(for: .auto)
        XCTAssertTrue(auto.allowPaste)
        XCTAssertTrue(auto.allowAccessibilityFallback)
        XCTAssertFalse(auto.preferAccessibilityForEditable)
        XCTAssertTrue(auto.preferMenuPaste)

        let pasteboard = SystemTextInserter.options(for: .pasteboard)
        XCTAssertTrue(pasteboard.allowPaste)
        XCTAssertFalse(pasteboard.allowAccessibilityFallback)
        XCTAssertFalse(pasteboard.preferAccessibilityForEditable)
        XCTAssertFalse(pasteboard.preferMenuPaste)

        let accessibility = SystemTextInserter.options(for: .accessibility)
        XCTAssertFalse(accessibility.allowPaste)
        XCTAssertTrue(accessibility.preferAccessibility)

        let clipboardOnly = SystemTextInserter.options(for: .clipboardOnly)
        XCTAssertFalse(clipboardOnly.allowPaste)
        XCTAssertFalse(clipboardOnly.allowAccessibilityFallback)
        XCTAssertFalse(clipboardOnly.preferAccessibilityForEditable)
        XCTAssertFalse(clipboardOnly.restoreClipboard)
    }

    func testPrepareForInsertionUsesTheFrontmostPID() async {
        let harness = makeAdapter(frontmost: 88)
        await harness.inserter.prepareForInsertion()
        XCTAssertEqual(harness.focus.preparedPIDs, [88])
    }

    func testSystemInserterSatisfiesTextInserterContract() async throws {
        let harness = makeAdapter(focus: .notEditable(reason: "role-AXWindow"))
        try await TextInserterContract().verify(harness.inserter)
    }
}
