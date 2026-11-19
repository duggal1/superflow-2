import XCTest
import SuperflowFeatureIntelligence
import SuperflowKernel

@MainActor
final class HeadlessIntelligenceComposeTests: XCTestCase {
    func testTypedComposeStreamsAnswerAndCopy() async throws {
        let service = HeadlessAnswerClient()
        service.script = [.thinking, .delta("First "), .delta("answer."), .finished("stop")]
        var copied = ""
        let model = headlessModel(service: service) { copied = $0 }

        XCTAssertEqual(model.slot, .compose)
        await model.submit("what changed")
        XCTAssertEqual(model.slot, .answer)
        XCTAssertEqual(model.answer, "First answer.")
        XCTAssertEqual(model.phase, .done)
        await model.copy()
        XCTAssertEqual(copied, "First answer.")
    }

    func testEnterWithEmptyInputDoesNotCallNetwork() async {
        let service = HeadlessAnswerClient()
        let model = headlessModel(service: service)
        await model.submit("   ")
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertEqual(model.slot, .compose)
    }

    func testCancelReturnsToComposeAndStopsService() async {
        let service = HeadlessAnswerClient()
        service.script = [.thinking]
        let model = headlessModel(service: service)
        await model.submit("hello")
        model.cancel()
        XCTAssertEqual(service.cancellations, 1)
        XCTAssertEqual(model.slot, .compose)
        XCTAssertEqual(model.phase, .idle)
    }

    func testFailedAnswerSurfacesMessageAndRetry() async {
        let service = HeadlessAnswerClient()
        service.script = [.failed("No key saved")]
        let model = headlessModel(service: service)
        await model.submit("question")
        XCTAssertEqual(model.phase, .failed("No key saved"))
        XCTAssertEqual(model.lastError, "No key saved")
    }

    func testSuggestionAnswerReplacesPriorAnswer() async throws {
        let service = HeadlessAnswerClient()
        service.script = [.delta("1) A?\n2) B?"), .finished("stop")]
        let model = headlessModel(service: service)
        await model.generateSuggestions()
        XCTAssertEqual(model.suggestions, ["A?", "B?"])

        service.script = [.delta("Direct."), .finished("stop")]
        await model.askSuggestion("A?")
        XCTAssertEqual(model.answer, "Direct.")
        XCTAssertEqual(model.slot, .answer)
    }
}
