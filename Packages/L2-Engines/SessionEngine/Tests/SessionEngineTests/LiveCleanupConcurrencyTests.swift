import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
@testable import SuperflowSessionEngine

final class LiveCleanupConcurrencyTests: XCTestCase {
    private actor Gate: SuperflowPorts.TextStage {
        nonisolated let id = "gate"
        private var active = 0
        private var maximum = 0
        private var released = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
            active += 1
            maximum = max(maximum, active)
            if active == 2 {
                for waiter in waiters { waiter.resume() }
                waiters.removeAll()
            } else if !released {
                await withCheckedContinuation { waiters.append($0) }
            }
            active -= 1
            var result = draft
            result.cleanupState = .cleaned
            return result
        }
        func hasConcurrentWork() -> Bool { maximum >= 2 }
        func release() {
            released = true
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    func testTwoCleanupRequestsRunWhileRecording() async throws {
        let repository = InMemoryRepository()
        let session = SessionRecord(kind: .dictation, modelProfile: "test")
        try await repository.createSession(session)
        for index in 0..<2 {
            try await repository.appendSegment(Segment(sessionID: session.id, index: index,
                startMs: index * 1000, endMs: (index + 1) * 1000, source: .mic, rawText: "hello"))
        }
        let gate = Gate()
        let coordinator = SessionCleanupCoordinator(repository: repository, sessionID: session.id, emit: { _ in })
        await coordinator.start(workerCount: 2)
        for index in 0..<2 {
            await coordinator.submit(index: index, interactive: false, pipeline: TextPipeline(stages: [gate]), settings: .default)
        }
        try await Task.sleep(for: .milliseconds(200))
        let parallel = await gate.hasConcurrentWork()
        await gate.release()
        _ = await coordinator.finish()
        XCTAssertTrue(parallel, "The second cleanup must start before recording stops")
    }
}
