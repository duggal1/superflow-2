import Foundation
import SuperflowPorts

public actor WorkerPool<Resource: Sendable> {
    public enum Failure: Error { case exhausted, empty }
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Resource, any Error>
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

    public func acquire(_ priority: CleanPriority) async throws -> Resource {
        try Task.checkCancellation()
        guard hasResources else { throw Failure.empty }
        if let resource = free.popLast() { return resource }
        guard waitingCount < capacity else { throw Failure.exhausted }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let waiter = Waiter(id: id, continuation: continuation)
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
            interactive.removeFirst().continuation.resume(returning: resource)
        } else if !background.isEmpty {
            background.removeFirst().continuation.resume(returning: resource)
        } else {
            free.append(resource)
        }
    }

    public func use<Value: Sendable>(
        _ priority: CleanPriority,
        operation: @Sendable (Resource) async throws -> Value
    ) async throws -> Value {
        let resource = try await acquire(priority)
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
            interactive.remove(at: index).continuation.resume(throwing: CancellationError())
        } else if let index = background.firstIndex(where: { $0.id == id }) {
            background.remove(at: index).continuation.resume(throwing: CancellationError())
        }
    }
}
