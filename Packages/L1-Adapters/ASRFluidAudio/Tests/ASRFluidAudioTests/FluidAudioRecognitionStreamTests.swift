import Foundation
import SuperflowKernel
import SuperflowPorts
import XCTest
@testable import SuperflowASRFluidAudio

final class FluidAudioRecognitionStreamTests: XCTestCase {
    private func makeStream(engine: FakeEngine, vad: FakeVoiceActivity, spy: EngineSpy,
                            source: AudioSourceKind = .mic) async -> FluidAudioRecognitionStream {
        let stream = FluidAudioRecognitionStream(
            profileID: ModelProfile.parakeetEOU120M.id,
            source: source,
            manager: engine,
            modelDirectory: FileManager.default.temporaryDirectory,
            engineFactory: { _, _ in try await spy.make() },
            voiceActivity: vad,
            returnEngine: { _ in })
        await stream.configure()
        return stream
    }

    func testPartialEventsAreForwarded() async {
        let engine = FakeEngine()
        let stream = await makeStream(engine: engine, vad: FakeVoiceActivity(), spy: EngineSpy())
        await stream.feed(chunk(seconds: 1, startSample: 0))
        await engine.emitPartial("hello")

        let events = await collectEvents(stream, count: 1)
        XCTAssertEqual(events, [.partial("hello")])
        await stream.finish()
    }

    func testFinishCommitsRemainingTextAndIsIdempotent() async {
        let engine = FakeEngine(text: "  final text  ")
        await engine.setAutoPartial(true)
        let stream = await makeStream(engine: engine, vad: FakeVoiceActivity(), spy: EngineSpy())
        await stream.feed(chunk(seconds: 2, startSample: 0))

        await stream.finish()
        await stream.finish()

        var events: [RecognitionEvent] = []
        for await event in stream.events { events.append(event) }
        let committed = events.compactMap { event -> RawSegment? in
            if case .committed(let segment) = event { return segment }
            return nil
        }
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed.first?.text, "final text")
        XCTAssertEqual(committed.first?.startSample, 0)
        XCTAssertEqual(committed.first?.endSample, Int64(2 * sampleRate))
        XCTAssertEqual(committed.first?.source, .mic)
        let finishCount = await engine.finishCount
        XCTAssertEqual(finishCount, 1)
    }

    func testSourceMismatchFailsWithoutAppendingAudio() async {
        let engine = FakeEngine()
        let stream = await makeStream(engine: engine, vad: FakeVoiceActivity(), spy: EngineSpy())
        await stream.feed(chunk(seconds: 1, startSample: 0, source: .system))

        let events = await collectEvents(stream, count: 1)
        guard let first = events.first, case .failure(let message) = first else {
            return XCTFail("expected failure, got \(events)")
        }
        XCTAssertTrue(message.contains("source"))
        let appended = await engine.appendedSamples
        XCTAssertEqual(appended, 0)
        await stream.finish()
    }

    func testPauseAfterThirtySecondsCommitsAndResets() async {
        let engine = FakeEngine()
        await engine.setAutoPartial(true)
        let vad = FakeVoiceActivity()
        let stream = await makeStream(engine: engine, vad: vad, spy: EngineSpy())

        for second in 0..<30 {
            await stream.feed(chunk(seconds: 1, startSample: Int64(second * sampleRate)))
        }
        await vad.setSpeech(false)
        await stream.feed(chunk(seconds: 1, startSample: Int64(30 * sampleRate)))

        let events = await collectEvents(stream, count: 33)
        let committed = events.compactMap { event -> RawSegment? in
            if case .committed(let segment) = event { return segment }
            return nil
        }
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed.first?.startSample, 0)
        XCTAssertEqual(committed.first?.endSample, Int64(30 * sampleRate))
        XCTAssertTrue(events.contains(.endpoint(Int64(30 * sampleRate))))
        let finishCount = await engine.finishCount
        let resetCount = await engine.resetCount
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(resetCount, 1)
        await stream.finish()
    }

    func testHardCapAtOneHundredTwentySeconds() async {
        let engine = FakeEngine()
        await engine.setAutoPartial(true)
        let stream = await makeStream(engine: engine, vad: FakeVoiceActivity(), spy: EngineSpy())

        for second in 0..<120 {
            await stream.feed(chunk(seconds: 1, startSample: Int64(second * sampleRate)))
        }

        let events = await collectEvents(stream, count: 122)
        let committed = events.compactMap { event -> RawSegment? in
            if case .committed(let segment) = event { return segment }
            return nil
        }
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed.first?.endSample, Int64(120 * sampleRate))
        let finishCount = await engine.finishCount
        XCTAssertEqual(finishCount, 1)
        await stream.finish()
    }

    func testWatchdogRebuildsEngineAndReplaysUncommittedAudio() async throws {
        let engine = FakeEngine()
        let spy = EngineSpy()
        let stream = await makeStream(engine: engine, vad: FakeVoiceActivity(), spy: spy)

        for second in 0..<8 {
            await stream.feed(chunk(seconds: 1, startSample: Int64(second * sampleRate)))
        }

        let created = await spy.count
        XCTAssertEqual(created, 1)
        let maybeReplacement = await spy.engine(at: 0)
        let replacement = try XCTUnwrap(maybeReplacement)
        let replayed = await replacement.appendedSamples
        XCTAssertEqual(replayed, 8 * sampleRate)
        let cleaned = await engine.cleanupCount
        XCTAssertEqual(cleaned, 1)

        await stream.finish()
        let finished = await replacement.finishCount
        XCTAssertEqual(finished, 1)
    }

    func testWatchdogCapsRecoveryAttempts() async {
        let engine = FakeEngine()
        let spy = EngineSpy()
        let stream = await makeStream(engine: engine, vad: FakeVoiceActivity(), spy: spy)

        for second in 0..<40 {
            await stream.feed(chunk(seconds: 1, startSample: Int64(second * sampleRate)))
        }

        let created = await spy.count
        XCTAssertEqual(created, 2, "only two rebuilds are allowed per segment")
        await stream.finish()
    }

    func testWatchdogReportsRebuildFailure() async {
        let engine = FakeEngine()
        let spy = EngineSpy()
        await spy.setFailure(SuperflowError.modelUnavailable("gone"))
        let stream = await makeStream(engine: engine, vad: FakeVoiceActivity(), spy: spy)

        for second in 0..<8 {
            await stream.feed(chunk(seconds: 1, startSample: Int64(second * sampleRate)))
        }

        let events = await collectEvents(stream, count: 1)
        guard let first = events.first, case .failure(let message) = first else {
            return XCTFail("expected failure, got \(events)")
        }
        XCTAssertTrue(message.contains("Could not rebuild"))
        await stream.finish()
    }

    func testReplayBufferStaysBounded() {
        var buffer = ReplayBuffer(limit: 5 * sampleRate)
        for second in 0..<10 {
            buffer.append(Array(repeating: Float(second), count: sampleRate))
        }
        XCTAssertEqual(buffer.samples.count, 5 * sampleRate)
        XCTAssertEqual(buffer.samples.first, 5, "the oldest seconds are dropped")
        buffer.removeAll()
        XCTAssertTrue(buffer.samples.isEmpty)
    }

    func testEnergyVoiceActivitySeparatesSpeechFromSilence() async {
        let activity = EnergyVoiceActivity()
        let silence = await activity.classify(Array(repeating: 0, count: sampleRate))
        let speech = await activity.classify(Array(repeating: 0.25, count: sampleRate))
        XCTAssertEqual(silence, 0)
        XCTAssertEqual(speech, sampleRate)
    }
}
