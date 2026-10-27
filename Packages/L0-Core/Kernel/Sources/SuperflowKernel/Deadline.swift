import Foundation

/// Resolves a continuation exactly once from whichever of two racing sources finishes first.
/// The continuation is cleared on settle, so a late second caller is a no-op instead of a
/// double-resume crash.
private final class DeadlineGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    func arm(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func settle(_ result: Result<T, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

/// Returns when `operation` finishes or `limit` elapses, whichever comes first, throwing
/// `SuperflowError.timeout(label)` on the deadline.
///
/// A Core ML prediction cannot be cancelled, so a stuck model call keeps running in the
/// background and is simply abandoned. That is the whole point: a structured `TaskGroup`
/// (even one that calls `cancelAll()`) still waits for its children on scope exit, so a hung
/// prediction would block the caller forever. This detects the stall and lets the caller
/// rebuild or continue; only a separate process could actually kill the stuck call.
public func withDeadline<T: Sendable>(
    _ limit: Duration,
    label: String,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let gate = DeadlineGate<T>()
    return try await withCheckedThrowingContinuation { continuation in
        gate.arm(continuation)
        let timer = Task {
            try? await Task.sleep(for: limit)
            if !Task.isCancelled { gate.settle(.failure(SuperflowError.timeout(label))) }
        }
        Task {
            do {
                gate.settle(.success(try await operation()))
            } catch {
                gate.settle(.failure(error))
            }
            timer.cancel()
        }
    }
}
