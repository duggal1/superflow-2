import Synchronization

/// A monotonic route/device generation token. A capture callback is tagged with
/// the generation that created it; after a switch the token advances and every
/// callback from the previous route is rejected instead of feeding the new
/// stream. This is what makes a late IOProc from a device that was just
/// unplugged harmless.
public final class GenerationGate: @unchecked Sendable {
    private let current: Atomic<UInt64>

    public init(start: UInt64 = 0) {
        current = Atomic(start)
    }

    public var generation: UInt64 { current.load(ordering: .acquiring) }

    public func isCurrent(_ generation: UInt64) -> Bool {
        current.load(ordering: .acquiring) == generation
    }

    /// Invalidates every previously issued generation and returns the new one.
    @discardableResult
    public func advance() -> UInt64 {
        let result = current.wrappingAdd(1, ordering: .acquiringAndReleasing)
        return result.newValue
    }
}
