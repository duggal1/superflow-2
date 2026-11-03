import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
@testable import SuperflowMeetingEngine

final class MeetingDurabilityTests: XCTestCase {
    func testStorageFailuresKeepAudioAndDoNotReportCompletion() async throws {
        for failure in [InMemoryRepository.Failure.append, .update, .read, .finalize] {
            let repo = InMemoryRepository()
            let journal = FakeJournalStore()
            let mic = ScriptedAudioSource(samples: Array(repeating: 0.2, count: 80_000), kind: .mic)
            let recognizer = FakeSpeechRecognizer(script: ["hello world"], samplesPerSegment: 80_000)
            var settings = AppSettings.default
            settings.cleanupEnabled = false
            let engine = MeetingEngine(mic: mic, system: nil, recognizer: recognizer,
                                       pipeline: TextPipelineBuilder.make(settings: settings),
                                       repository: repo, journals: journal, settings: settings)
            let id = try await engine.start()
            await repo.setFailure(failure)
            let result = await engine.stop()
            let state = await engine.currentState
            let samples = await journal.sampleCount(session: id, source: .mic)
            XCTAssertNil(result, "\(failure)")
            guard case .failed = state else { XCTFail("\(failure): \(state)"); continue }
            XCTAssertGreaterThan(samples, 0, "\(failure)")
            let session = try await repo.session(id)
            XCTAssertNotEqual(session?.status, .complete, "\(failure)")
        }
    }
}
