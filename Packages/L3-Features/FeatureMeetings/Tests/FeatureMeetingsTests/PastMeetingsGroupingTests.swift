import Foundation
import SuperflowKernel
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureMeetings

@MainActor
final class PastMeetingsGroupingTests: XCTestCase {
    func testSelectingMissingMeetingClearsPreviousTranscriptAndReportsFailure() async throws {
        let repository = InMemoryRepository()
        let id = SessionID("existing")
        try await repository.createSession(SessionRecord(id: id, kind: .meeting, modelProfile: "base"))
        let model = PastMeetingsModel(repository: repository, inserter: RecordingInserter())
        await model.select(id)
        XCTAssertNotNil(model.selectedDocument)

        await model.select(SessionID("missing"))
        XCTAssertNil(model.selectedDocument)
        XCTAssertEqual(model.documentError, "Could not load this meeting.")
        XCTAssertFalse(model.isLoadingDocument)
    }

    func testSearchGroupsAndUndoRestoreMeetingOrder() async throws {
        let repository = InMemoryRepository()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        for (id, title, date, text) in [
            ("older", "Planning", yesterday, "Budget discussion"),
            ("newer", "Review", today, "Project update"),
        ] {
            let session = SessionID(id)
            try await repository.createSession(SessionRecord(id: session, kind: .meeting, startedAt: date,
                endedAt: date.addingTimeInterval(60), status: .complete, modelProfile: "base",
                durationMs: 60_000, wordCount: 2, cleanupState: .cleaned, title: title))
            try await repository.appendSegment(Segment(sessionID: session, index: 0, startMs: 0, endMs: 1000,
                speakerID: "self", source: .mic, rawText: text, cleanedText: text, cleanupState: .cleaned))
        }
        let model = PastMeetingsModel(repository: repository, inserter: RecordingInserter())
        await model.reload()
        XCTAssertEqual(model.groups.map(\.day), [today, yesterday])
        XCTAssertEqual(model.groups.flatMap(\.sessions).map(\.id.value), ["newer", "older"])

        model.query = "planning"
        await model.reload()
        XCTAssertEqual(model.sessions.map(\.id.value), ["older"])
        model.query = "project update"
        await model.reload()
        XCTAssertEqual(model.sessions.map(\.id.value), ["newer"])

        model.query = ""
        await model.reload()
        let document = try XCTUnwrap(model.selectedDocument)
        model.delete(document)
        XCTAssertEqual(model.sessions.map(\.id.value), ["older"])
        model.toast.performAction()
        XCTAssertEqual(model.sessions.map(\.id.value), ["newer", "older"])
    }
}
