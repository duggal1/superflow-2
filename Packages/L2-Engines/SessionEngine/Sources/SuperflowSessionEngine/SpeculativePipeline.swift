import Foundation
import SuperflowKernel
import SuperflowTextPipeline

actor SpeculativePipeline {
    struct Key: Sendable, Equatable {
        let session: SessionID
        let revision: UUID
        let text: String
    }

    private struct Entry {
        let id: UUID
        let key: Key
        let generation: Int
        let task: Task<PipelineResult, Never>
    }

    private var active: Entry?
    private var completed: (key: Key, result: PipelineResult)?
    private var generation = 0

    func schedule(_ key: Key, pipeline: TextPipeline, context: TextContext) {
        guard active == nil, completed?.key != key else { return }
        let id = UUID()
        let generation = generation
        let task = Task(priority: .utility) { await pipeline.run(key.text, context: context) }
        active = Entry(id: id, key: key, generation: generation, task: task)
        Task {
            let result = await task.value
            finish(id: id, generation: generation, key: key, result: result)
        }
    }

    func take(_ key: Key) async -> PipelineResult? {
        if let completed, completed.key == key {
            self.completed = nil
            return completed.result
        }
        guard let active, active.key == key, active.generation == generation else { return nil }
        let generation = generation
        let result = await active.task.value
        guard generation == self.generation else { return nil }
        finish(id: active.id, generation: generation, key: key, result: result)
        completed = nil
        return result
    }

    func cancel() {
        generation += 1
        completed = nil
        active?.task.cancel()
        // Keep the active slot occupied until it returns: cancellation must not
        // spawn an unbounded series of abandoned inference requests.
    }

    private func finish(id: UUID, generation: Int, key: Key, result: PipelineResult) {
        guard active?.id == id else { return }
        active = nil
        if generation == self.generation { completed = (key, result) }
    }
}
