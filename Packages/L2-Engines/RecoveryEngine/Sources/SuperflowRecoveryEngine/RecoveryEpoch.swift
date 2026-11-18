import Foundation

/// A monotonic generation stamp for one recovery owner. Callbacks that carry a token from a
/// closed generation are stale: by the time they arrive, that run has been cancelled, rearmed,
/// or superseded, so its result must never mutate fresh state.
///
/// This is the portable, local-only form of a capture generation fence. It carries no platform
/// handles, no timestamps from input devices and no network identity — just an ordering.
public struct RecoveryEpoch: Sendable, Equatable, Comparable {
    public let value: UInt64
    public static let initial = RecoveryEpoch(0)

    init(_ value: UInt64) { self.value = value }

    public static func < (lhs: RecoveryEpoch, rhs: RecoveryEpoch) -> Bool {
        lhs.value < rhs.value
    }
}

/// Actor-isolated generation counter. `advance()` closes the current generation; every callback
/// stamped with an older token is fenced without it needing to be told it was cancelled.
public actor RecoveryEpochFence {
    private var current: UInt64

    public init(initial: UInt64 = 0) { self.current = initial }

    public var token: RecoveryEpoch { RecoveryEpoch(current) }

    @discardableResult
    public func advance() -> RecoveryEpoch {
        current &+= 1
        return RecoveryEpoch(current)
    }

    public func isCurrent(_ epoch: RecoveryEpoch) -> Bool { epoch.value == current }
}
