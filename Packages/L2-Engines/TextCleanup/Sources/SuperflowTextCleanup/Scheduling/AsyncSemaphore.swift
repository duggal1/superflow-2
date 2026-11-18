import Foundation
import SuperflowPorts

actor AsyncSemaphore {
    private struct Waiter {
        let id: UUID
        let priority: CleanPriority
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var value: Int
    private var waiters: [Waiter] = []
    private let capacity: Int

    init(_ value: Int) { self.value = max(1, value); capacity = max(256, value * 16) }

    func acquire(priority: CleanPriority) async throws {
        try Task.checkCancellation()
        // A free permit is handed straight to the caller. `release()` always
        // hands its permit to a queued waiter first, so value > 0 implies no
        // waiter is starving — priority is preserved without a queue hop.
        if value > 0 { value -= 1; return }
        guard waiters.count < capacity else { throw QueueFull() }
        let id = UUID()
        do {
            // Only `release()` resumes the continuation normally, and it does
            // so by transferring its permit. `cancel(id)` resumes it with an
            // error and grants nothing. Keeping these paths distinct prevents
            // a cancelled waiter from minting a permit nobody returned — the
            // leak that let more tasks enter the model than there are sessions.
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiters.append(Waiter(id: id, priority: priority, continuation: continuation))
                }
            } onCancel: {
                Task { await self.cancel(id) }
            }
        } catch {
            throw error // cancelled before a permit was granted: nothing to return
        }
        // The permit was granted while this task was also cancelled. Return it
        // to the queue (priority-first) instead of consuming a session twice.
        if Task.isCancelled { release(); throw CancellationError() }
    }

    func release() {
        if let index = waiters.firstIndex(where: { $0.priority == .interactive }) ?? waiters.indices.first {
            waiters.remove(at: index).continuation.resume()
        } else { value += 1 }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
    private struct QueueFull: Error {}
}
