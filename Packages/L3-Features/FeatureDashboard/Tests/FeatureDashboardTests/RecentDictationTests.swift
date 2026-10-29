import Foundation
import SuperflowKernel
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureDashboard

@MainActor
final class RecentDictationTests: XCTestCase {
    func testRecentLoadsOnlyFiveDictationsWithRealText() async throws {
        let repository = InMemoryRepository()
        for index in 0..<8 {
            let record = SessionRecord(kind: .dictation, startedAt: Date(timeIntervalSince1970: Double(index)),
                                       status: .complete, modelProfile: "test", wordCount: 2)
            try await repository.createSession(record)
            try await repository.appendSegment(Segment(sessionID: record.id, index: 0, startMs: 0,
                endMs: 1000, rawText: "raw \(index)", cleanedText: "clean \(index)", cleanupState: .cleaned))
        }
        try await repository.createSession(SessionRecord(kind: .meeting, modelProfile: "test"))
        let model = RecentDictationViewModel(repository: repository)
        await model.load(settings: .default)
        XCTAssertEqual(model.entries.count, 5)
        XCTAssertEqual(model.entries.first?.cleaned, "clean 7")
        XCTAssertEqual(model.entries.first?.raw, "raw 7")
        XCTAssertTrue(model.entries.allSatisfy { $0.record.kind == .dictation })
    }

    func testPrivacyRemovesRealRowsAndPlayback() async throws {
        let repository = InMemoryRepository()
        let record = SessionRecord(kind: .dictation, status: .complete,
                                   modelProfile: "test", wordCount: 2)
        try await repository.createSession(record)
        let model = RecentDictationViewModel(repository: repository)
        await model.load(settings: .default)
        XCTAssertEqual(model.entries.count, 1)
        var settings = AppSettings.default
        settings.noTranscriptStorage = true
        await model.load(settings: settings)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertNil(model.playingID)
    }

    func testUndoKeepsRepositoryRecordAndRestoresRow() async throws {
        let repository = InMemoryRepository()
        let record = SessionRecord(kind: .dictation, status: .complete,
                                   modelProfile: "test", wordCount: 2)
        try await repository.createSession(record)
        let model = RecentDictationViewModel(repository: repository)
        await model.load(settings: .default)
        let entry = try XCTUnwrap(model.entries.first)
        model.delete(entry)
        XCTAssertTrue(model.entries.isEmpty)
        let stored = try await repository.session(record.id)
        XCTAssertNotNil(stored)
        model.toast.performAction()
        XCTAssertEqual(model.entries.first?.id, record.id)
    }


    func testInProgressTakesAreNotListedWhileRecording() async throws {
        let repository = InMemoryRepository()
        let recording = SessionRecord(kind: .dictation, status: .recording,
                                      modelProfile: "test", wordCount: 0)
        try await repository.createSession(recording)
        let model = RecentDictationViewModel(repository: repository)
        await model.load(settings: .default)
        XCTAssertTrue(model.entries.isEmpty)
    }

    func testZeroWordCompleteSessionsAreHiddenButFailedAndCancelledRemain() async throws {
        let repository = InMemoryRepository()
        let zero = SessionRecord(kind: .dictation, status: .complete, modelProfile: "test", wordCount: 0)
        try await repository.createSession(zero)
        let failed = SessionRecord(kind: .dictation, status: .failed, modelProfile: "test", wordCount: 0)
        try await repository.createSession(failed)
        let cancelled = SessionRecord(kind: .dictation, status: .cancelled, modelProfile: "test", wordCount: 0)
        try await repository.createSession(cancelled)
        let model = RecentDictationViewModel(repository: repository)
        await model.load(settings: .default)
        XCTAssertEqual(model.entries.count, 2)
        XCTAssertTrue(model.entries.contains { $0.record.status == .failed })
        XCTAssertTrue(model.entries.contains { $0.record.status == .cancelled })
    }

}
