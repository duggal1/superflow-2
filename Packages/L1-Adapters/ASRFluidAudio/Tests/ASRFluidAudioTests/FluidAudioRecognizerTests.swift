import Foundation
import SuperflowKernel
import SuperflowPorts
import XCTest
@testable import SuperflowASRFluidAudio

final class FluidAudioRecognizerTests: XCTestCase {
    func testConcurrentWarmupsDoNotPoolTheSameEngineTwice() async throws {
        let profile = ModelProfile.parakeetEOU120M.id
        let root = try makeModelCache(profileID: profile)
        let spy = EngineSpy()
        let recognizer = FluidAudioRecognizer(modelCacheRoot: root, engineFactory: { _, _ in
            try await Task.sleep(for: .milliseconds(100))
            return try await spy.make()
        }, voiceActivityFactory: { FakeVoiceActivity() })
        async let first: Void = recognizer.warmUp(profile: profile)
        async let second: Void = recognizer.warmUp(profile: profile)
        _ = try await (first, second)
        let mic = try await recognizer.makeStream(profile: profile, source: .mic)
        let system = try await recognizer.makeStream(profile: profile, source: .system)
        let count = await spy.count
        XCTAssertEqual(count, 2, "two simultaneous streams require distinct engines")
        await mic.finish()
        await system.finish()
    }

    func testProfileIsNotReadyUntilPrimedEngineIsInThePool() async throws {
        let profile = ModelProfile.parakeetEOU120M.id
        let root = try makeModelCache(profileID: profile)
        let spy = EngineSpy()
        let recognizer = FluidAudioRecognizer(modelCacheRoot: root, engineFactory: { _, _ in
            let engine = try await spy.make()
            await engine.setHangProcessing(true)
            return engine
        }, voiceActivityFactory: { FakeVoiceActivity() })
        let warming = Task { try await recognizer.warmUp(profile: profile) }
        for _ in 0..<100 {
            if let engine = await spy.engine(at: 0), await engine.appendedSamples > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let created = await spy.engine(at: 0)
        let engine = try XCTUnwrap(created)
        let received = await engine.appendedSamples
        XCTAssertGreaterThan(received, 0)
        let readyDuringPrediction = await recognizer.isPrepared(profile: profile)
        XCTAssertFalse(readyDuringPrediction, "the warm engine is not yet available for a session")
        try await warming.value
        let stream = try await recognizer.makeStream(profile: profile, source: .mic)
        let count = await spy.count
        XCTAssertEqual(count, 1, "a warm launch must reuse the primed engine")
        await stream.finish()
    }

    func testCatalogMapsEveryStreamingRegistryProfile() {
        for profile in ModelProfile.all where profile.supportsLiveDictation {
            XCTAssertTrue(FluidAudioCatalog.supports(profile.id), profile.id)
        }
        XCTAssertFalse(FluidAudioCatalog.supports(ModelProfile.parakeetTDTV3.id),
                       "batch-only TDT is not a streaming profile")
        XCTAssertFalse(FluidAudioCatalog.supports("nope"))

        XCTAssertEqual(FluidAudioCatalog.variant(for: ModelProfile.parakeetEOU120M.id),
                       .parakeetEou320ms)
        XCTAssertEqual(FluidAudioCatalog.variant(for: ModelProfile.nemotronStreaming.id),
                       .nemotron560ms)
        XCTAssertEqual(FluidAudioCatalog.variant(for: ModelProfile.parakeetUnified.id),
                       .parakeetUnified640ms)
        XCTAssertNil(FluidAudioCatalog.variant(for: ModelProfile.nemotron35Streaming.id))
        XCTAssertEqual(FluidAudioCatalog.profile(for: ModelProfile.nemotron35Streaming.id)?.engine,
                       .nemotronMultilingual(languageDirectory: "latin", chunkMs: 2_240))
    }

    func testMultilingualProfileUsesFluidAudioLanguageTierDirectory() throws {
        let root = URL(fileURLWithPath: "/tmp/superflow-asr-catalog")
        let profile = try XCTUnwrap(
            FluidAudioCatalog.profile(for: ModelProfile.nemotron35Streaming.id))
        XCTAssertEqual(FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: root).path,
                       "/tmp/superflow-asr-catalog/nemotron-multilingual/latin/2240ms")
    }

    func testAvailabilityRequiresEveryArtifact() async throws {
        let root = try makeModelCache(profileID: ModelProfile.parakeetEOU120M.id)
        let recognizer = FluidAudioRecognizer(modelCacheRoot: root)
        let ready = await recognizer.isAvailable(profileID: ModelProfile.parakeetEOU120M.id)
        XCTAssertTrue(ready)

        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent("asr-empty-\(UUID().uuidString)")
        let missing = FluidAudioRecognizer(modelCacheRoot: other)
        let unavailable = await missing.isAvailable(profileID: ModelProfile.parakeetEOU120M.id)
        XCTAssertFalse(unavailable)
    }

    func testPrepareFailsBeforeLoadingWhenArtifactsAreMissing() async {
        let recognizer = FluidAudioRecognizer(
            modelCacheRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString))
        do {
            try await recognizer.warmUp(profile: ModelProfile.parakeetEOU120M.id)
            XCTFail("expected modelUnavailable")
        } catch let error as SuperflowError {
            guard case .modelUnavailable(let message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(message.contains("not downloaded"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testUnsupportedProfileFailsBeforeTouchingDisk() async {
        let recognizer = FluidAudioRecognizer(modelCacheRoot: FileManager.default.temporaryDirectory)
        do {
            try await recognizer.warmUp(profile: "unknown-profile")
            XCTFail("expected modelUnavailable")
        } catch let error as SuperflowError {
            guard case .modelUnavailable(let message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(message.contains("Unsupported ASR profile"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testMakeStreamRequiresWarmUp() async {
        let recognizer = FluidAudioRecognizer(modelCacheRoot: FileManager.default.temporaryDirectory)
        do {
            _ = try await recognizer.makeStream(profile: ModelProfile.parakeetEOU120M.id, source: .mic)
            XCTFail("expected invalidState")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .invalidState("prepare(profileID:) must succeed before makeStream"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testPoolReusesEnginesAcrossTwoStreams() async throws {
        let root = try makeModelCache(profileID: ModelProfile.parakeetEOU120M.id)
        let spy = EngineSpy()
        let voice = FakeVoiceActivity()
        let recognizer = FluidAudioRecognizer(
            modelCacheRoot: root,
            engineFactory: { _, _ in try await spy.make() },
            voiceActivityFactory: { voice })

        try await recognizer.warmUp(profile: ModelProfile.parakeetEOU120M.id)
        let first = try await recognizer.makeStream(profile: ModelProfile.parakeetEOU120M.id,
                                                    source: .mic)
        let second = try await recognizer.makeStream(profile: ModelProfile.parakeetEOU120M.id,
                                                     source: .system)
        let created = await spy.count
        XCTAssertEqual(created, 2, "two concurrent streams need two engines")

        await first.finish()
        await second.finish()
        let third = try await recognizer.makeStream(profile: ModelProfile.parakeetEOU120M.id,
                                                    source: .mic)
        let afterReuse = await spy.count
        XCTAssertEqual(afterReuse, 2, "a returned engine must be reused")
        await third.finish()
    }

    func testUnavailableRecognizerIsNotReadyAndExplains() async {
        let recognizer = UnavailableSpeechRecognizer()
        let ready = await recognizer.isReady
        XCTAssertFalse(ready)
        do {
            try await recognizer.warmUp(profile: ModelProfile.parakeetEOU120M.id)
            XCTFail("expected modelUnavailable")
        } catch let error as SuperflowError {
            guard case .modelUnavailable(let message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
