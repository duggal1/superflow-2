import Foundation
import SuperflowKernel
import SuperflowStorageSQLite
import SuperflowTestKit
import SuperflowTextPipeline
import XCTest

final class PipelineStorageInsertionTests: XCTestCase {
    func testCommittedTranscriptIsPersistedCleanedAndInserted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuperflowPipelineIntegration-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SQLiteStore(path: directory.appendingPathComponent("history.sqlite").path)
        let session = SessionRecord(kind: .dictation, modelProfile: "integration")
        let rawText = "i need two hundred dollars for next js"
        try await store.createSession(session)
        try await store.appendSegment(Segment(
            sessionID: session.id,
            index: 0,
            startMs: 0,
            endMs: 1_800,
            rawText: rawText
        ))

        let journaled = try await store.segments(session: session.id)
        XCTAssertEqual(journaled.map(\.rawText), [rawText])
        XCTAssertNil(journaled.first?.cleanedText)

        var settings = AppSettings.default
        settings.commandsEnabled = false
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        let pipeline = TextPipelineBuilder.make(
            settings: settings,
            dependencies: TextPipelineDependencies(lexiconEntries: [
                LexiconEntry(kind: .term, triggers: ["next js"], canonical: "Next.js"),
            ])
        )
        let result = await pipeline.run(rawText, context: TextContext(settings: settings))
        XCTAssertTrue(result.text.contains("$200"), result.text)
        XCTAssertTrue(result.text.contains("Next.js"), result.text)

        let inserter = RecordingInserter()
        let outcome = try await inserter.insert(result.text, strategy: .auto)
        XCTAssertEqual(outcome, .pasted)
        try await store.updateCleaned(session: session.id, index: 0,
                                      cleaned: result.text, state: .cleaned)
        try await store.finalizeSession(session.id, endedAt: Date(), status: .complete,
                                        durationMs: 1_800, wordCount: 8, cleanupState: .cleaned)

        let persisted = try await store.segments(session: session.id)
        XCTAssertEqual(persisted.first?.rawText, rawText)
        XCTAssertEqual(persisted.first?.cleanedText, result.text)
        XCTAssertEqual(persisted.first?.bestText, result.text)
        let inserted = await inserter.inserted
        XCTAssertEqual(inserted, [result.text])
        let finalized = try await store.session(session.id)
        XCTAssertEqual(finalized?.status, .complete)
        XCTAssertEqual(finalized?.cleanupState, .cleaned)
    }
}
