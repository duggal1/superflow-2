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

    private func makeStream(engine: FakeEngine, spy: EngineSpy,
                            deadlines: FluidAudioRecognitionStream.Deadlines,
                            returns: EngineReturnLog) async -> FluidAudioRecognitionStream {
        let stream = FluidAudioRecognitionStream(
            profileID: ModelProfile.parakeetEOU120M.id,
            source: .mic,
            manager: engine,
            modelDirectory: FileManager.default.temporaryDirectory,
            engineFactory: { _, _ in try await spy.make() },
            voiceActivity: FakeVoiceActivity(),
            deadlines: deadlines,
            returnEngine: { manager in await returns.record(manager) })
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

    func testPushDeadlineRebuildsAndReplaysTheUncommittedSegment() async {
        let stalled = FakeEngine()
        await stalled.setHangProcessing(true)
        let spy = EngineSpy()
        let returns = EngineReturnLog()
        let stream = await makeStream(
            engine: stalled, spy: spy,
            deadlines: .init(push: .milliseconds(50), retire: .milliseconds(50)),
            returns: returns)

        await stream.feed(chunk(seconds: 1, startSample: 0))

        let replacement = await spy.engine(at: 0)
        let replayed = await replacement?.appendedSamples
        XCTAssertEqual(replayed, sampleRate, "the fresh engine must receive the whole segment")
        let stalledReturned = await returns.contains(stalled)
        XCTAssertFalse(stalledReturned, "a stalled manager must never go back to the pool")

        await stream.finish()
    }

    func testFinishDeadlineRebuildsAndStillCommitsTheTail() async {
        let stalled = FakeEngine(text: "stalled")
        await stalled.setHangFinish(true)
        let spy = EngineSpy()
        let returns = EngineReturnLog()
        let stream = await makeStream(
            engine: stalled, spy: spy,
            deadlines: .init(finish: .milliseconds(50), retire: .milliseconds(50)),
            returns: returns)
        await stream.feed(chunk(seconds: 1, startSample: 0))

        let started = ContinuousClock.now
        await stream.finish()
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1.5),
                          "finish must not wait for a wedged model call")

        var events: [RecognitionEvent] = []
        for await event in stream.events { events.append(event) }
        let committed = events.compactMap { event -> RawSegment? in
            if case .committed(let segment) = event { return segment }
            return nil
        }
        XCTAssertEqual(committed.count, 1, "the rebuilt engine still produces the final text")
        XCTAssertEqual(committed.first?.text, "hello world")

        let replacement = await spy.engine(at: 0)
        let finished = await replacement?.finishCount
        XCTAssertEqual(finished, 1)
        let returned = await returns.count
        XCTAssertEqual(returned, 1, "only the healthy replacement goes back to the pool")
        let stalledReturned = await returns.contains(stalled)
        XCTAssertFalse(stalledReturned)
    }

    func testCallbacksFromAnAbandonedEngineAreIgnored() async {
        let stalled = FakeEngine()
        await stalled.setHangProcessing(true)
        let spy = EngineSpy()
        let stream = await makeStream(
            engine: stalled, spy: spy,
            deadlines: .init(push: .milliseconds(50), retire: .milliseconds(50)),
            returns: EngineReturnLog())

        await stream.feed(chunk(seconds: 1, startSample: 0))
        // The old manager was abandoned mid-call; a late callback must not leak in.
        await stalled.emitPartial("stale")

        let events = await collectEvents(stream, count: 1)
        XCTAssertFalse(events.contains(.partial("stale")))
        await stream.finish()
    }

    func testEnergyVoiceActivitySeparatesSpeechFromSilence() async {
        let activity = EnergyVoiceActivity()
        let silence = await activity.classify(Array(repeating: 0, count: sampleRate))
        let speech = await activity.classify(Array(repeating: 0.25, count: sampleRate))
        XCTAssertEqual(silence, 0)
        XCTAssertEqual(speech, sampleRate)
    }
}
