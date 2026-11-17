import XCTest
import SuperflowKernel
import SuperflowMeetingIntelligence
@testable import SuperflowFeatureIntelligence

@MainActor
final class IntelligenceModelTests: XCTestCase {
    private func makeModel(
        service: FakeAnswerService = FakeAnswerService(),
        store: FakeHistoryStore = FakeHistoryStore(items: []),
        copied: @escaping @MainActor (String) -> Void = { _ in }
    ) -> IntelligenceIslandModel {
        IntelligenceIslandModel(answerService: service, historyStore: store,
                                copy: copied, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    // MARK: compose -> streamed answer -> copy

    func testComposeToAnswerStreamsAndCopies() async throws {
        let service = FakeAnswerService()
        service.script = [.thinking, .delta("Use "), .delta("Swift."),
                          .finished("stop")]
        var copied = ""
        let model = makeModel(service: service) { copied = $0 }

        XCTAssertEqual(model.slot, .compose)
        await model.submit("what should I use")
        XCTAssertEqual(model.slot, .answer)
        XCTAssertEqual(model.answer, "Use Swift.")
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(service.requests.first?.question, "what should I use")
        XCTAssertTrue(service.requests.first?.transcript.isEmpty == true)

        await model.copy()
        XCTAssertEqual(copied, "Use Swift.")
    }

    func testSubmitRejectsBlankInput() async throws {
        let service = FakeAnswerService()
        let model = makeModel(service: service)
        await model.submit("  \n ")
        XCTAssertEqual(model.slot, .compose)
        XCTAssertTrue(service.requests.isEmpty)
    }

    func testMessyTranscriptUsesSharedBlockInRequestTask() async throws {
        let service = FakeAnswerService()
        service.script = [.delta("ok"), .finished("stop")]
        let model = makeModel(service: service)
        await model.ingestMeetingUtterance("um so cooper netties how do we scale")
        await model.submit("how do we scale?")

        let request = try XCTUnwrap(service.requests.first)
        XCTAssertTrue(request.task.contains(IntelligencePrompts.messyTranscriptBlock))
        XCTAssertTrue(request.transcript.contains("cooper netties"))
    }

    func testDetectedMeetingQuestionIsQueued() async throws {
        let model = makeModel()
        await model.ingestMeetingUtterance("what is the deployment window")
        XCTAssertEqual(model.pendingDetectedQuestion, "what is the deployment window")
    }

    // MARK: settings / prompt selection persistence

    func testThemeSelectionPersists() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = FakeAnswerService()
        let model = IntelligenceIslandModel(answerService: service,
                                            historyStore: FakeHistoryStore(items: []),
                                            copy: { _ in }, defaults: defaults)
        XCTAssertTrue(model.screenAware, "Screen context defaults on")
        let coding = try XCTUnwrap(IntelligenceTheme.allFromSource().first { $0.id == "codingInterview" })
        model.selectTheme(coding)
        XCTAssertEqual(model.selectedTheme.id, "codingInterview")
        XCTAssertEqual(defaults.string(forKey: "intelligence.mode"), "codingInterview")

        let restored = IntelligenceIslandModel(answerService: service,
                                               historyStore: FakeHistoryStore(items: []),
                                               copy: { _ in }, defaults: defaults)
        XCTAssertEqual(restored.selectedTheme.id, "codingInterview")
        restored.setScreenAware(false)
        let restoredAgain = IntelligenceIslandModel(answerService: service,
                                                    historyStore: FakeHistoryStore(items: []),
                                                    copy: { _ in }, defaults: defaults)
        XCTAssertFalse(restoredAgain.screenAware)
    }

    func testSettingsExpandInPlace() throws {
        let model = makeModel()
        XCTAssertFalse(model.settingsExpanded)
        model.toggleSettings()
        XCTAssertTrue(model.settingsExpanded)
        XCTAssertEqual(model.slot, .settings)
        model.toggleSettings()
        XCTAssertFalse(model.settingsExpanded)
    }

    // MARK: history CRUD / search

    func testHistoryListSearchOpenDeleteAndCopy() async throws {
        let now = Date()
        let items = [
            IntelligenceHistoryItem(id: SessionID("a"), title: "Kubernetes scale",
                                    preview: "cooper netties", date: now, wordCount: 3,
                                    fullText: "cooper netties scale", answers: []),
            IntelligenceHistoryItem(id: SessionID("b"), title: "Groceries",
                                    preview: "milk and eggs", date: now, wordCount: 3,
                                    fullText: "milk and eggs", answers: []),
        ]
        let store = FakeHistoryStore(items: items)
        var copied = ""
        let model = makeModel(store: store) { copied = $0 }

        await model.loadHistory(query: nil)
        XCTAssertEqual(model.history.count, 2)

        await model.loadHistory(query: "kubernetes")
        XCTAssertEqual(model.history.count, 1)
        XCTAssertEqual(model.history.first?.id.value, "a")

        await model.openHistoryItem(SessionID("a"))
        XCTAssertEqual(model.selectedHistory?.fullText, "cooper netties scale")
        await model.copyHistoryItem(SessionID("a"))
        XCTAssertEqual(copied, "cooper netties scale")

        try? await model.deleteHistoryItem(SessionID("a"))
        await model.loadHistory(query: nil)
        XCTAssertEqual(model.history.count, 1)
        XCTAssertEqual(model.history.first?.id.value, "b")
    }

    // MARK: post-meeting suggestions

    func testMeetingEndProducesClickableSuggestionsThatAnswer() async throws {
        let service = FakeAnswerService()
        service.script = [.delta("1) What is the deadline?\n2) Who owns the rollout?\n3) Any blockers?"),
                          .finished("stop")]
        let model = makeModel(service: service)
        await model.generateSuggestions()
        XCTAssertEqual(model.suggestions.count, 3)
        XCTAssertEqual(model.slot, .suggestions)
        XCTAssertTrue(service.requests.first?.task.contains(IntelligencePrompts.messyTranscriptBlock) == true)

        service.script = [.delta("Friday."), .finished("stop")]
        await model.askSuggestion(model.suggestions[0])
        XCTAssertEqual(model.answer, "Friday.")
        XCTAssertEqual(model.slot, .answer)
    }
}
