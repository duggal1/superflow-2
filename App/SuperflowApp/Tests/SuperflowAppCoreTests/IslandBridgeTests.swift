import Foundation
import SuperflowFeatureIsland
import SuperflowKernel
import SuperflowPorts
import SuperflowSessionEngine
import SuperflowTestKit
import XCTest
@testable import SuperflowAppCore

/// Collects Island events from the feed's stream without racing a captured var.
private actor EventSink {
    private(set) var events: [IslandEvent] = []

    func append(_ event: IslandEvent) {
        events.append(event)
    }
}

@MainActor
final class IslandBridgeTests: XCTestCase {
    private func session(in repository: InMemoryRepository,
                         wordCount: Int = 0) async throws -> SessionRecord {
        let record = SessionRecord(kind: .dictation, modelProfile: "test", wordCount: wordCount)
        try await repository.createSession(record)
        return record
    }

    /// The copy card is built when the session is finalized, so it must quote
    /// the cleaned, complete transcript - never the last partial segment that
    /// happened to be on screen when insertion failed.
    func testPasteFailureCardUsesTheFinalizedTranscript() async throws {
        let repository = InMemoryRepository()
        let record = try await session(in: repository, wordCount: 2)
        try await repository.appendSegment(Segment(
            sessionID: record.id, index: 0, startMs: 0, endMs: 500, rawText: "hello"))
        try await repository.appendSegment(Segment(
            sessionID: record.id, index: 1, startMs: 500, endMs: 1_000, rawText: "world"))
        try await repository.updateCleaned(session: record.id, index: 0,
                                           cleaned: "Hello,", state: .cleaned)
        try await repository.updateCleaned(session: record.id, index: 1,
                                           cleaned: "world.", state: .cleaned)

        let bridge = IslandBridge(transcripts: repository)
        let sink = EventSink()
        let failure = expectation(description: "pasteFailed")
        let reader = Task {
            for await event in bridge.feed.events {
                await sink.append(event)
                if case .pasteFailed = event {
                    failure.fulfill()
                    return
                }
            }
        }

        let input = AsyncStream<SessionEvent>.makeStream()
        bridge.start(events: input.stream)
        input.continuation.yield(.state(.inserting))
        input.continuation.yield(.partial("hello wor"))
        input.continuation.yield(.inserted(.clipboardOnly(reason: "No editable field is focused.")))
        input.continuation.yield(.finished(record.id, .complete))
        input.continuation.finish()

        await fulfillment(of: [failure], timeout: 3)
        reader.cancel()

        let events = await sink.events
        guard case .pasteFailed(let transcript)? = events.last else {
            return XCTFail("expected a pasteFailed card, got \(events)")
        }
        XCTAssertEqual(transcript.text, "Hello, world.")
        XCTAssertEqual(transcript.words, 2)
        XCTAssertEqual(events.filter { if case .pasteFailed = $0 { true } else { false } }.count, 1,
                       "the card must be emitted once, from the finalized record")
    }

    func testBlockedSecureFieldAlsoWaitsForTheFinalizedTranscript() async throws {
        let repository = InMemoryRepository()
        let record = try await session(in: repository)
        try await repository.appendSegment(Segment(
            sessionID: record.id, index: 0, startMs: 0, endMs: 500, rawText: "final text"))

        let bridge = IslandBridge(transcripts: repository)
        let sink = EventSink()
        let failure = expectation(description: "pasteFailed")
        let reader = Task {
            for await event in bridge.feed.events {
                await sink.append(event)
                if case .pasteFailed = event {
                    failure.fulfill()
                    return
                }
            }
        }

        let input = AsyncStream<SessionEvent>.makeStream()
        bridge.start(events: input.stream)
        input.continuation.yield(.state(.inserting))
        input.continuation.yield(.partial("fin"))
        input.continuation.yield(.inserted(.blockedSecureField))
        input.continuation.yield(.finished(record.id, .complete))
        input.continuation.finish()

        await fulfillment(of: [failure], timeout: 3)
        reader.cancel()

        let events = await sink.events
        guard case .pasteFailed(let transcript)? = events.last else {
            return XCTFail("expected a pasteFailed card, got \(events)")
        }
        XCTAssertEqual(transcript.text, "final text")
    }

    func testLandedInsertionShowsWordsAndNoFailureCard() async throws {
        let repository = InMemoryRepository()
        let record = try await session(in: repository)
        try await repository.appendSegment(Segment(
            sessionID: record.id, index: 0, startMs: 0, endMs: 500, rawText: "hi there"))

        let bridge = IslandBridge(transcripts: repository)
        let sink = EventSink()
        let landed = expectation(description: "landed")
        let reader = Task {
            for await event in bridge.feed.events {
                await sink.append(event)
                if case .landed = event {
                    landed.fulfill()
                    return
                }
            }
        }

        let input = AsyncStream<SessionEvent>.makeStream()
        bridge.start(events: input.stream)
        input.continuation.yield(.state(.inserting))
        input.continuation.yield(.partial("hi there"))
        input.continuation.yield(.inserted(.pasted))
        input.continuation.yield(.finished(record.id, .complete))
        input.continuation.finish()

        await fulfillment(of: [landed], timeout: 3)
        reader.cancel()

        let events = await sink.events
        XCTAssertEqual(events.last, .landed(words: 2))
        XCTAssertFalse(events.contains { if case .pasteFailed = $0 { true } else { false } })
    }

    /// Nothing was inserted and the engine never reached `.inserting`, so the
    /// Island retracts instead of offering a copy card for text that never
    /// existed.
    func testCompletionWithoutInsertionRetracts() async throws {
        let repository = InMemoryRepository()
        let record = try await session(in: repository)

        let bridge = IslandBridge(transcripts: repository)
        let sink = EventSink()
        let cancelled = expectation(description: "cancelled")
        let reader = Task {
            for await event in bridge.feed.events {
                await sink.append(event)
                if case .cancelled = event {
                    cancelled.fulfill()
                    return
                }
            }
        }

        let input = AsyncStream<SessionEvent>.makeStream()
        bridge.start(events: input.stream)
        input.continuation.yield(.state(.finalizing))
        input.continuation.yield(.finished(record.id, .complete))
        input.continuation.finish()

        await fulfillment(of: [cancelled], timeout: 3)
        reader.cancel()

        let events = await sink.events
        XCTAssertEqual(events, [.cancelled])
    }
}
