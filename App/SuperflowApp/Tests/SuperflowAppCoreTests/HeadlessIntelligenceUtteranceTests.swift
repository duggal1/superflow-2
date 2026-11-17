import XCTest
import SuperflowFeatureIntelligence

@MainActor
final class HeadlessIntelligenceUtteranceTests: XCTestCase {
    func testSensitivityConstantIsPublicAndStable() {
        let a = IntelligenceQuestionDetector.sensitivity
        XCTAssertGreaterThan(a, 0)
        XCTAssertLessThanOrEqual(a, 1)
    }

    func testMessyUtteranceIntentExtractionQueuesQuestion() async {
        let service = HeadlessAnswerClient()
        service.script = [.delta("Deploy Friday."), .finished("stop")]
        let model = headlessModel(service: service)
        await model.ingestMeetingUtterance("um so what time is the deploy")
        XCTAssertEqual(model.pendingDetectedQuestion, "um so what time is the deploy")
        await model.askDetectedQuestion()
        XCTAssertEqual(model.answer, "Deploy Friday.")
        let request = try? XCTUnwrap(service.requests.first)
        XCTAssertTrue(request?.task.contains(IntelligencePrompts.messyTranscriptBlock) == true)
    }

    func testSilenceAndFillersProduceNothing() async {
        let service = HeadlessAnswerClient()
        let model = headlessModel(service: service)
        for text in ["", "   \n", "uh", "um, you know", "..."] {
            await model.ingestMeetingUtterance(text)
        }
        XCTAssertNil(model.pendingDetectedQuestion)
        XCTAssertTrue(model.meetingTranscript.isEmpty)
        XCTAssertTrue(service.requests.isEmpty)
    }

    func testStatementIsNotAQuestion() async {
        let model = headlessModel()
        await model.ingestMeetingUtterance("the build finished last night")
        XCTAssertNil(model.pendingDetectedQuestion)
    }

    func testSensitivityThresholdIsHonored() {
        let text = "what about tests"
        XCTAssertTrue(IntelligenceQuestionDetector.looksLikeQuestion(text, sensitivity: 0.2))
        XCTAssertFalse(IntelligenceQuestionDetector.looksLikeQuestion(text, sensitivity: 1.0))
    }

    func testRepeatedUtterancesBoundTheTranscript() async {
        let model = headlessModel()
        for _ in 0..<20 {
            await model.ingestMeetingUtterance("a fairly long filler statement that is not a question")
        }
        XCTAssertLessThanOrEqual(model.meetingTranscript.count, 7_000)
    }
}
