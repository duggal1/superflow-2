import Foundation
import SuperflowAppCore
import SuperflowKernel
import SuperflowPorts
import SuperflowStorageSQLite
import XCTest

final class AppCompositionTests: XCTestCase {
    @MainActor
    func testEngineEventRelayBroadcastsToIndependentConsumers() async {
        let relay = EngineEventRelay<Int>()
        let firstStream = relay.subscribe()
        let secondStream = relay.subscribe()
        relay.publish(42)

        var firstIterator = firstStream.makeAsyncIterator()
        var secondIterator = secondStream.makeAsyncIterator()
        let first = await firstIterator.next()
        let second = await secondIterator.next()

        XCTAssertEqual(first, 42)
        XCTAssertEqual(second, 42)
    }

    func testNoTranscriptStorageSuppressesSegmentsAndCanBeChangedAtRuntime() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuperflowIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try SQLiteStore(path: directory.appendingPathComponent("test.sqlite").path)
        let repository = PrivacyRepository(base: database, noTranscriptStorage: true)
        let session = SessionRecord(kind: .dictation, modelProfile: "integration")
        try await repository.createSession(session)
        try await repository.appendSegment(Segment(
            sessionID: session.id,
            index: 0,
            startMs: 0,
            endMs: 1_000,
            rawText: "private transcript"
        ))

        let privateSegments = try await repository.segments(session: session.id)
        let processingSegments = try await repository.segmentsForProcessing(session: session.id)
        let persistedSegments = try await database.segments(session: session.id)
        XCTAssertTrue(privateSegments.isEmpty)
        XCTAssertEqual(processingSegments.map(\.rawText), ["private transcript"])
        XCTAssertTrue(persistedSegments.isEmpty)

        try await repository.updateCleaned(session: session.id, index: 0,
                                           cleaned: "Private transcript.", state: .cleaned)
        let cleanedForProcessing = try await repository.segmentForProcessing(session: session.id,
                                                                             index: 0)
        XCTAssertEqual(cleanedForProcessing?.bestText, "Private transcript.")

        await repository.setNoTranscriptStorage(false)
        try await repository.appendSegment(Segment(
            sessionID: session.id,
            index: 1,
            startMs: 1_000,
            endMs: 2_000,
            rawText: "retained transcript"
        ))

        let stored = try await repository.segments(session: session.id)
        XCTAssertEqual(stored.map(\.rawText), ["retained transcript"])
    }

    /// The session engine only writes the archived clip's duration and peaks when
    /// the repository it holds conforms to `AudioMetadataStore`. The privacy
    /// wrapper is that repository, so it has to forward instead of swallowing.
    func testPrivacyWrapperForwardsAudioMetadataToTheStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuperflowAudioMetadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try SQLiteStore(path: directory.appendingPathComponent("test.sqlite").path)
        let repository = PrivacyRepository(base: database)
        let session = SessionRecord(kind: .dictation, modelProfile: "integration")
        try await repository.createSession(session)

        let store: any AudioMetadataStore = repository
        try await store.setAudio(session: session.id, duration: 12.5, peaks: Data([1, 2, 3]))
        var withAudio = try await store.sessionsWithAudio()
        XCTAssertEqual(withAudio, [session.id])
        let stored = try await database.session(session.id)
        XCTAssertEqual(stored?.audioDuration, 12.5)
        XCTAssertEqual(stored?.audioPeaks, Data([1, 2, 3]))

        try await store.clearAudio(session: session.id)
        withAudio = try await store.sessionsWithAudio()
        XCTAssertTrue(withAudio.isEmpty)
    }

    @MainActor
    func testAppEnvironmentBuildsPipelineFromPersistedConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuperflowEnvironment-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let environment = try AppEnvironment(applicationSupportDirectory: directory)
        var settings = AppSettings.default
        settings.commandsEnabled = false
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        let pipeline = await environment.makePipeline(settings: settings)

        XCTAssertEqual(pipeline.stageIDs,
                       ["disfluency", "spokenCode", "numbers", "lexicon", "codeAware",
                        "polish", "lineformat"])
    }
}
