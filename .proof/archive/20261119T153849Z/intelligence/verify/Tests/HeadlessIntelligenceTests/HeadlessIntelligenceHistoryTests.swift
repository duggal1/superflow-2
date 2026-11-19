import XCTest
import SuperflowFeatureIntelligence
import SuperflowKernel

@MainActor
final class HeadlessIntelligenceHistoryTests: XCTestCase {
    private func items() -> [IntelligenceHistoryItem] {
        let now = Date()
        return [
            IntelligenceHistoryItem(id: SessionID("h1"), title: "Sprint planning",
                                    preview: "deadline is Friday", date: now, wordCount: 4,
                                    fullText: "The deadline is Friday"),
            IntelligenceHistoryItem(id: SessionID("h2"), title: "Groceries",
                                    preview: "milk and eggs", date: now, wordCount: 3,
                                    fullText: "milk and eggs"),
        ]
    }

    func testHistoryListOpenSearchDeleteCopy() async throws {
        let store = HeadlessHistoryClient(items: items())
        var copied = ""
        let model = headlessModel(store: store) { copied = $0 }

        await model.loadHistory(query: nil)
        XCTAssertEqual(model.history.count, 2)

        await model.loadHistory(query: "deadline")
        XCTAssertEqual(model.history.count, 1)
        XCTAssertEqual(try XCTUnwrap(model.history.first).id.value, "h1")

        await model.openHistoryItem(SessionID("h1"))
        XCTAssertEqual(try XCTUnwrap(model.selectedHistory).fullText, "The deadline is Friday")
        XCTAssertEqual(model.slot, .history)

        await model.copyHistoryItem(SessionID("h1"))
        XCTAssertEqual(copied, "The deadline is Friday")

        try await model.deleteHistoryItem(SessionID("h1"))
        XCTAssertNil(model.selectedHistory)
        await model.loadHistory(query: nil)
        XCTAssertEqual(model.history.count, 1)
        XCTAssertEqual(try XCTUnwrap(model.history.first).id.value, "h2")
    }

    func testSearchIsCaseInsensitiveAndEmptyQueryRestoresAll() async {
        let store = HeadlessHistoryClient(items: items())
        let model = headlessModel(store: store)
        await model.loadHistory(query: "SPRINT")
        XCTAssertEqual(model.history.count, 1)
        await model.loadHistory(query: "   ")
        XCTAssertEqual(model.history.count, 2)
    }

    func testOpenMissingItemLeavesStateUntouched() async {
        let store = HeadlessHistoryClient(items: items())
        let model = headlessModel(store: store)
        await model.openHistoryItem(SessionID("missing"))
        XCTAssertNil(model.selectedHistory)
        XCTAssertEqual(model.slot, .compose)
    }

    func testCloseHistoryReturnsToPriorSlot() async {
        let store = HeadlessHistoryClient(items: items())
        let model = headlessModel(store: store)
        model.show(.answer)
        await model.openHistoryItem(SessionID("h1"))
        XCTAssertEqual(model.slot, .history)
        model.closeHistory()
        XCTAssertEqual(model.slot, .answer)
    }

    func testCopyMissingHistoryItemIsNoop() async {
        var copied = ""
        let model = headlessModel(store: HeadlessHistoryClient(items: [])) { copied = $0 }
        await model.copyHistoryItem(SessionID("gone"))
        XCTAssertEqual(copied, "")
    }
}
