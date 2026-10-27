import Foundation

@MainActor
public final class EngineEventRelay<Element: Sendable> {
    private var subscribers: [UUID: AsyncStream<Element>.Continuation] = [:]

    public init() {}

    public func subscribe() -> AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.removeSubscriber(id) }
        }
        return stream
    }

    public func publish(_ element: Element) {
        for continuation in subscribers.values {
            continuation.yield(element)
        }
    }

    public func finish() {
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}
