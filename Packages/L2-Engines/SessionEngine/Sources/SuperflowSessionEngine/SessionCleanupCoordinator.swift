import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

private struct CleanupRequest: Sendable {
    let index: Int
    let interactive: Bool
    let pipeline: TextPipeline
    let settings: AppSettings
    let wordTimings: [WordTiming]
    let activeAppBundleID: String?
    /// Explicitly injected project scope for this session, if the user selected
    /// one. Nil keeps filename-only cleanup with no path resolution.
    let project: ProjectContext?
    let precomputed: PipelineResult?
}

/// Drains persisted transcript rows through a fixed worker pool and bounded queue.
public actor SessionCleanupCoordinator {
    private let repository: any TranscriptRepository
    private let sessionID: SessionID
    private let metrics: any MetricsSink
    private let emit: @Sendable (SessionEvent) -> Void
    private var workerTasks: [Task<Void, Never>] = []
    private var requests: [CleanupRequest] = []
    private var workerWaiters: [CheckedContinuation<CleanupRequest?, Never>] = []
    private var submittedCount = 0
    private var completedCount = 0
    private var cleanedCount = 0
    private var fallbackCount = 0
    // Requests contain only metadata, not audio. Pending work is capped so
    // prolonged inference stalls cannot grow memory without bound.
    private static let maximumPendingSegments = 128
    private var isFinished = false
    private var abandoned = false

    public init(repository: any TranscriptRepository, sessionID: SessionID,
                metrics: any MetricsSink = NoopMetrics(), emit: @escaping @Sendable (SessionEvent) -> Void) {
        self.repository = repository
        self.sessionID = sessionID
        self.metrics = metrics
        self.emit = emit
    }

    public func start(workerCount: Int) {
        guard workerTasks.isEmpty else { return }
        // Match the helper's two inference contexts. Extra coordinator workers
        // cannot improve throughput and create an additional hidden queue.
        let count = min(2, max(1, workerCount))
        workerTasks = (0..<count).map { _ in Task { await self.runWorker() } }
    }

    /// Never wait for S1-mini from the recognition event consumer. A blocking
    /// submit used to stop reading live ASR events when the cleanup queue filled.
    /// The raw row is already persisted; when saturated, return false so its
    /// caller can mark that row as a safe raw-text fallback.
    ///
    /// Interactive requests retain priority over background cleanup.
    @discardableResult
    public func submit(index: Int, interactive: Bool, pipeline: TextPipeline,
                       settings: AppSettings, project: ProjectContext? = nil,
                       wordTimings: [WordTiming] = [], activeAppBundleID: String? = nil,
                       precomputed: PipelineResult? = nil) async -> Bool {
        submittedCount = max(submittedCount, index + 1)
        guard !isFinished, requests.count < Self.maximumPendingSegments else {
            complete(.fallback)
            metrics.event("session.cleanup.queue_full", ["pending": String(requests.count)])
            return false
        }
        let request = CleanupRequest(index: index, interactive: interactive,
                                     pipeline: pipeline, settings: settings, wordTimings: wordTimings,
                                     activeAppBundleID: activeAppBundleID, project: project,
                                     precomputed: precomputed)
        if let waiter = workerWaiters.popLast() {
            waiter.resume(returning: request)
        } else {
            let queueIndex = CleanupQueuePolicy.insertionIndex(
                isInteractive: interactive, queued: requests.map(\.interactive))
            requests.insert(request, at: queueIndex)
        }
        return true
    }

    /// Final insertion gets a bounded cleanup tail, not an unbounded backlog.
    /// Any unfinished segments retain their durable raw ASR text.
    public func finish(maximumWaitMs: Int = 2_500) async -> CleanupState {
        isFinished = true
        resumeWorkersIfFinished()
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(max(0, maximumWaitMs)))
        while completedCount < submittedCount && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
            if Task.isCancelled { break }
        }
        if completedCount < submittedCount {
            let unfinished = submittedCount - completedCount
            abandoned = true
            fallbackCount += unfinished
            metrics.event("session.cleanup.finish_deadline", ["unfinished": String(unfinished)])
            requests.removeAll()
            for waiter in workerWaiters { waiter.resume(returning: nil) }
            workerWaiters.removeAll()
            for task in workerTasks { task.cancel() }
            // The helper may take time to observe cancellation; do not block
            // paste waiting for it. Abandoned workers cannot update rows.
            workerTasks.removeAll()
            return .fallback
        }
        for task in workerTasks { await task.value }
        workerTasks.removeAll()
        return aggregateState
    }

    public func cancel() async {
        isFinished = true
        abandoned = true
        requests.removeAll()
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
                                     settings: request.settings, project: request.project,
                                     wordTimings: request.wordTimings,
                                     activeAppBundleID: request.activeAppBundleID)
            let result: PipelineResult
            if let precomputed = request.precomputed { result = precomputed }
            else { result = await request.pipeline.run(segment.rawText, context: context) }
            for timing in result.timings {
                metrics.record("session.text." + timing.id + ".ms", valueMs: Double(timing.ms))
            }
            metrics.event("session.cleanup", [
                "segment": String(request.index),
                "interactive": String(request.interactive),
                "state": String(describing: result.draft.cleanupState),
                "fallbackCount": String(result.draft.diagnostics.filter { $0.stage.hasPrefix("cleanup") }.count),
            ])
            let cleaned = result.draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // A filler-only dictation cleans to a valid empty string. Preserve
            // that result; only an empty non-cleaned result is a failure that
            // needs the raw text restored.
            let failedEmpty = cleaned.isEmpty && result.draft.cleanupState != .cleaned
            let resolved = failedEmpty ? segment.rawText : cleaned
            resultState = failedEmpty ? .fallback : result.draft.cleanupState
            // A timed-out cleanup may finish after insertion. Never allow it
            // to silently rewrite a transcript the owner has already pasted.
            guard !abandoned, !Task.isCancelled else { return }
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
