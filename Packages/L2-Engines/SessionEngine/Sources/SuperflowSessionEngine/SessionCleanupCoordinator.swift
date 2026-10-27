import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

private struct CleanupRequest: Sendable {
    let index: Int
    let interactive: Bool
    let pipeline: TextPipeline
    let settings: AppSettings
}

/// Drains persisted transcript rows through a fixed worker pool and bounded queue.
public actor SessionCleanupCoordinator {
    private let repository: any TranscriptRepository
    private let sessionID: SessionID
    private let emit: @Sendable (SessionEvent) -> Void
    private var workerTasks: [Task<Void, Never>] = []
    private var requests: [CleanupRequest] = []
    private var workerWaiters: [CheckedContinuation<CleanupRequest?, Never>] = []
    private var submitWaiters: [CheckedContinuation<Void, Never>] = []
    private var submittedCount = 0
    private var completedCount = 0
    private var cleanedCount = 0
    private var fallbackCount = 0
    private var queueCapacity = 1
    private var isFinished = false

    public init(repository: any TranscriptRepository, sessionID: SessionID,
                emit: @escaping @Sendable (SessionEvent) -> Void) {
        self.repository = repository
        self.sessionID = sessionID
        self.emit = emit
    }

    public func start(workerCount: Int) {
        guard workerTasks.isEmpty else { return }
        let count = min(8, max(1, workerCount))
        queueCapacity = count
        workerTasks = (0..<count).map { _ in
            Task { await self.runWorker() }
        }
    }

    /// Backpressure keeps queued work bounded. The caller persists each row before submitting it.
    public func submit(index: Int, interactive: Bool, pipeline: TextPipeline,
                       settings: AppSettings) async {
        submittedCount = max(submittedCount, index + 1)
        while requests.count >= queueCapacity, !isFinished {
            await withCheckedContinuation { continuation in
                submitWaiters.append(continuation)
            }
        }
        guard !isFinished else { return }
        let request = CleanupRequest(index: index, interactive: interactive,
                                     pipeline: pipeline, settings: settings)
        if let waiter = workerWaiters.popLast() {
            waiter.resume(returning: request)
        } else {
            requests.append(request)
        }
    }

    public func finish() async -> CleanupState {
        isFinished = true
        resumeWorkersIfFinished()
        let tasks = workerTasks
        for task in tasks { await task.value }
        workerTasks.removeAll()
        return aggregateState
    }

    public func cancel() async {
        isFinished = true
        requests.removeAll()
        for waiter in submitWaiters { waiter.resume() }
        submitWaiters.removeAll()
        resumeWorkersIfFinished()
        for task in workerTasks { task.cancel() }
        let tasks = workerTasks
        for task in tasks { await task.value }
        workerTasks.removeAll()
    }

    private var aggregateState: CleanupState {
        if fallbackCount > 0 { return .fallback }
        return cleanedCount > 0 ? .cleaned : .skipped
    }

    private func runWorker() async {
        while let request = await nextRequest() {
            await resolve(request)
        }
    }

    private func nextRequest() async -> CleanupRequest? {
        if !requests.isEmpty {
            let request = requests.removeFirst()
            if let waiter = submitWaiters.first {
                submitWaiters.removeFirst()
                waiter.resume()
            }
            return request
        }
        if isFinished { return nil }
        return await withCheckedContinuation { continuation in
            workerWaiters.append(continuation)
        }
    }

    private func resolve(_ request: CleanupRequest) async {
        let resultState: CleanupState
        do {
            guard let segment = try await repository.segmentForProcessing(session: sessionID,
                                                                          index: request.index) else {
                emit(.notice("Transcript segment \(request.index) was unavailable for cleanup."))
                complete(.fallback)
                return
            }
            let context = TextContext(source: segment.source, interactive: request.interactive,
                                     settings: request.settings)
            let result = await request.pipeline.run(segment.rawText, context: context)
            let cleaned = result.draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = cleaned.isEmpty ? segment.rawText : cleaned
            resultState = cleaned.isEmpty ? .fallback : result.draft.cleanupState
            do {
                try await repository.updateCleaned(session: segment.sessionID, index: segment.index,
                                                   cleaned: resolved, state: resultState)
            } catch {
                emit(.notice("Could not save cleaned segment \(request.index): \(error.localizedDescription)"))
                complete(.fallback)
                return
            }
            complete(resultState)
        } catch {
            emit(.notice("Could not load transcript segment \(request.index): \(error.localizedDescription)"))
            complete(.fallback)
        }
    }

    private func complete(_ state: CleanupState) {
        completedCount += 1
        if state == .cleaned { cleanedCount += 1 }
        if state == .fallback { fallbackCount += 1 }
        emit(.progress(Double(completedCount) / Double(max(1, submittedCount))))
        resumeWorkersIfFinished()
    }

    private func resumeWorkersIfFinished() {
        guard isFinished, requests.isEmpty else { return }
        for waiter in workerWaiters { waiter.resume(returning: nil) }
        workerWaiters.removeAll()
    }
}
