import Foundation
import SuperflowPorts

public actor WorkerPool<Resource: Sendable> {
    public enum Failure: Error { case exhausted, empty, timedOut }
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Resource, any Error>
        let timeout: Task<Void, Never>?
    }
    private var free: [Resource]
    private var interactive: [Waiter] = []
    private var background: [Waiter] = []
    private let capacity: Int
    private let hasResources: Bool

    public init(_ resources: [Resource], capacity: Int = 64) {
        free = resources
        hasResources = !resources.isEmpty
        self.capacity = max(0, capacity)
    }

    public var waitingCount: Int { interactive.count + background.count }

    public func acquire(_ priority: CleanPriority,
                        deadline: ContinuousClock.Instant? = nil) async throws -> Resource {
        try Task.checkCancellation()
        guard hasResources else { throw Failure.empty }
        if let deadline, ContinuousClock.now >= deadline { throw Failure.timedOut }
        if let resource = free.popLast() { return resource }
        guard waitingCount < capacity else { throw Failure.exhausted }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Cancellation may arrive just before the continuation is
                // registered; in that case no waiter should be left behind.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let timeout: Task<Void, Never>? = deadline.map { limit in
                    Task.detached { [weak self] in
                        let remaining = ContinuousClock.now.duration(to: limit)
                        if remaining > .zero { try? await Task.sleep(for: remaining) }
                        if !Task.isCancelled { await self?.expire(id) }
                    }
                }
                let waiter = Waiter(id: id, continuation: continuation, timeout: timeout)
                switch priority {
                case .interactive: interactive.append(waiter)
                case .background: background.append(waiter)
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    public func release(_ resource: Resource) {
        if !interactive.isEmpty {
            let waiter = interactive.removeFirst()
            waiter.timeout?.cancel()
            waiter.continuation.resume(returning: resource)
        } else if !background.isEmpty {
            let waiter = background.removeFirst()
            waiter.timeout?.cancel()
            waiter.continuation.resume(returning: resource)
        } else {
            free.append(resource)
        }
    }

    public func use<Value: Sendable>(
        _ priority: CleanPriority,
        deadline: ContinuousClock.Instant? = nil,
        operation: @Sendable (Resource) async throws -> Value
    ) async throws -> Value {
        let resource = try await acquire(priority, deadline: deadline)
        do {
            try Task.checkCancellation()
            let value = try await operation(resource)
            release(resource)
            return value
        } catch {
            release(resource)
            throw error
        }
    }

    private func cancel(_ id: UUID) {
        if let index = interactive.firstIndex(where: { $0.id == id }) {
            let waiter = interactive.remove(at: index)
            waiter.timeout?.cancel()
            waiter.continuation.resume(throwing: CancellationError())
        } else if let index = background.firstIndex(where: { $0.id == id }) {
            let waiter = background.remove(at: index)
            waiter.timeout?.cancel()
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    private func expire(_ id: UUID) {
        if let index = interactive.firstIndex(where: { $0.id == id }) {
            let waiter = interactive.remove(at: index)
            waiter.continuation.resume(throwing: Failure.timedOut)
        } else if let index = background.firstIndex(where: { $0.id == id }) {
            let waiter = background.remove(at: index)
            waiter.continuation.resume(throwing: Failure.timedOut)
        }
    }
}
