import Foundation
import SuperflowAudioJournal
import SuperflowKernel
import SuperflowSessionEngine
import SuperflowStorageSQLite
import SuperflowTestKit
import SuperflowTextPipeline
import SuperflowUIComponents
import XCTest

final class AudioArchivePlaybackTests: XCTestCase {
    @MainActor
    func testFinishedDictationPersistsAPlayableAudioClip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-dictation-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStoreFactory.open(url: directory.appendingPathComponent("history.sqlite"))
        let archive = AudioArchiveAdapter(directory: directory.appendingPathComponent("Audio"))
        let samples = (0..<16_000).map { Float(sin(Double($0) * 0.1) * 0.05) }
        var settings = AppSettings.default
        settings.keepAudio = true
        settings.noTranscriptStorage = false
        settings.speechEnhancementEnabled = false
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        let engine = SessionEngine(audio: ScriptedAudioSource(samples: samples),
                                   recognizer: FakeSpeechRecognizer(script: ["hello world"], samplesPerSegment: 8_000),
                                   pipeline: TextPipelineBuilder.make(settings: settings),
                                   repository: store, journals: FakeJournalStore(),
                                   inserter: RecordingInserter(), archive: archive, settings: settings)
        let id = try await engine.start()
        let outcome = await engine.stop()
        XCTAssertGreaterThan(outcome?.wordCount ?? 0, 0)
        let record = try await store.session(id)
        XCTAssertGreaterThan(record?.audioDuration ?? 0, 0)
        let url = directory.appendingPathComponent("Audio/\(id.value).m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let loaded = await RowClipLoader.load(url)
        let clip = try XCTUnwrap(loaded)
        let player = ClipPlayer()
        player.load(clip)
        player.play()
        guard case .playing = player.state else { return XCTFail("Recorded audio did not start") }
        player.pause()
        guard case .paused = player.state else { return XCTFail("Recorded audio did not pause") }
        player.stop()
    }

    @MainActor
    func testArchivedDictationAudioCanPlayAndPause() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-playback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = SessionID("playback")
        let archive = AudioArchiveAdapter(directory: directory)
        let writer = try await archive.makeWriter(session: id)
        let samples = (0..<16_000).map { Float(sin(Double($0) * 0.1) * 0.05) }
        await writer.append(AudioChunk(samples: samples, startSample: 0, source: .mic))
        let result = await writer.finish()
        let archived = try XCTUnwrap(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archived.url.path))
        XCTAssertGreaterThan(archived.duration, 0)
        let loaded = await RowClipLoader.load(archived.url)
        let clip = try XCTUnwrap(loaded)
        let player = ClipPlayer()
        player.load(clip)
        player.play()
        guard case .playing = player.state else { return XCTFail("Audio did not start") }
        player.pause()
        guard case .paused = player.state else { return XCTFail("Audio did not pause") }
        player.stop()
    }
}
