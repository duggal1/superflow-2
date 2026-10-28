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

    init(_ value: Int) { self.value = max(1, value); capacity = max(16, value * 8) }

    func acquire(priority: CleanPriority) async throws {
        try Task.checkCancellation()
        if value > 0 { value -= 1; return }
        guard waiters.count < capacity else { throw QueueFull() }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, priority: priority, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
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
