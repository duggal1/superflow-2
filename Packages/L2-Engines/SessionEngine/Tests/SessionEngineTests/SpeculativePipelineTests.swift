import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
@testable import SuperflowSessionEngine

@MainActor
final class SpeculativePipelineTests: XCTestCase {
    private actor Stage: SuperflowPorts.TextStage {
        nonisolated let id = "speculation-fixture"
        nonisolated let started: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation
        private let gate: AsyncGate?
        private(set) var calls = 0

        init(gate: AsyncGate? = nil) {
            (started, continuation) = AsyncStream.makeStream()
            self.gate = gate
        }

        func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
            calls += 1
            continuation.yield(())
            await gate?.wait()
            var result = draft
            result.text = draft.text.uppercased()
            result.cleanupState = .cleaned
            return result
        }
    }

    func testExactInputReusesTheExistingPipelineResult() async throws {
        let cache = SpeculativePipeline()
        let stage = Stage()
        let pipeline = TextPipeline(stages: [stage])
        let key = SpeculativePipeline.Key(session: SessionID(), revision: UUID(), text: "keep every word")
        await cache.schedule(key, pipeline: pipeline, context: TextContext())
        let result = await cache.take(key)
        XCTAssertEqual(result?.text, "KEEP EVERY WORD")
        let calls = await stage.calls
        XCTAssertEqual(calls, 1)
    }

    func testTextSessionAndPipelineRevisionsMustAllMatch() async {
        let cache = SpeculativePipeline()
        let key = SpeculativePipeline.Key(session: SessionID(), revision: UUID(), text: "the original sentence")
        await cache.schedule(key, pipeline: TextPipeline(stages: []), context: TextContext())
        for revised in [SpeculativePipeline.Key(session: key.session, revision: key.revision, text: "the revised sentence"),
                        .init(session: SessionID(), revision: key.revision, text: key.text),
                        .init(session: key.session, revision: UUID(), text: key.text)] {
            let result = await cache.take(revised)
            XCTAssertNil(result)
        }
        await cache.cancel()
    }

    func testCancellationRejectsResultsAndKeepsInferenceBounded() async {
        let gate = AsyncGate()
        let stage = Stage(gate: gate)
        let cache = SpeculativePipeline()
        let key = SpeculativePipeline.Key(session: SessionID(), revision: UUID(), text: "original")
        let pipeline = TextPipeline(stages: [stage])
        await cache.schedule(key, pipeline: pipeline, context: TextContext())
        var started = stage.started.makeAsyncIterator()
        _ = await started.next()
        await cache.cancel()
        let result = await cache.take(key)
        XCTAssertNil(result)
        for _ in 0..<20 {
            await cache.schedule(.init(session: key.session, revision: UUID(), text: "replacement"),
                                 pipeline: pipeline, context: TextContext())
        }
        let calls = await stage.calls
        XCTAssertEqual(calls, 1)
        await gate.open()
    }

    func testSpeculationMatchesWholeInputProcessingAcrossFixtures() async {
        let cache = SpeculativePipeline()
        let pipeline = TextPipeline(stages: [Stage()])
        for index in 0..<100 {
            let key = SpeculativePipeline.Key(session: SessionID(), revision: UUID(),
                                               text: "Keep path src/main.swift and value \(index) in this complete sentence.")
            await cache.schedule(key, pipeline: pipeline, context: TextContext())
            let speculative = await cache.take(key)
            let baseline = await pipeline.run(key.text, context: TextContext())
            XCTAssertEqual(speculative?.draft, baseline.draft)
        }
    }
}
