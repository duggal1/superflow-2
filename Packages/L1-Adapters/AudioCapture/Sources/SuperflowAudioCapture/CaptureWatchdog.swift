import Foundation

/// Each failure mode is a separate, observable flag. A device can be stalled
/// without being silent, silent without being stalled, and an overflow can
/// happen on an otherwise healthy route; folding them into one error string
/// hides which watchdog actually fired.
public struct CaptureHealth: Sendable, Equatable {
    /// No samples have arrived within `stalledAfter`.
    public var stalled = false
    /// Samples keep arriving but none of them carry signal.
    public var alwaysZero = false
    /// The ring dropped samples at least once since the last reset.
    public var overflowed = false
    /// A device switch is currently being rebuilt.
    public var rebuildingRoute = false
    /// A route rebuild did not finish within `rebuildTimeout`.
    public var rebuildTimedOut = false

    public init() {}
}

/// Pure watchdog logic over a monotonic nanosecond clock. Timestamps are passed
/// in so every threshold and transition can be tested without a microphone or
/// a real wait.
public struct CaptureWatchdog: Sendable, Equatable {
    public var health: CaptureHealth
    public private(set) var lastProgress: UInt64
    public private(set) var lastSignal: UInt64
    public private(set) var rebuildStarted: UInt64?

    public let stalledAfter: UInt64
    public let zeroAfter: UInt64
    public let rebuildTimeout: UInt64

    public init(
        now: UInt64,
        stalledAfter: UInt64 = 1_500_000_000,
        zeroAfter: UInt64 = 2_000_000_000,
        rebuildTimeout: UInt64 = 1_000_000_000
    ) {
        health = CaptureHealth()
        lastProgress = now
        lastSignal = now
        self.stalledAfter = stalledAfter
        self.zeroAfter = zeroAfter
        self.rebuildTimeout = rebuildTimeout
    }

    /// Records one delivered batch. Progress and signal are deliberately
    /// independent: a muted device still advances progress, so it is
    /// `alwaysZero` but never `stalled`.
    public mutating func observe(samples: [Float], dropped: Int, now: UInt64) {
        if !samples.isEmpty {
            lastProgress = now
            health.stalled = false
            if samples.contains(where: { $0 != 0 }) {
                lastSignal = now
                health.alwaysZero = false
            }
        }
        if dropped > 0 { health.overflowed = true }
        check(now: now)
    }

    public mutating func beginRebuild(now: UInt64) {
        rebuildStarted = now
        health.rebuildingRoute = true
        health.rebuildTimedOut = false
    }

    /// A successful rebuild clears the time-based flags: the new device gets a
    /// fresh silence and progress window instead of inheriting the old one's.
    public mutating func endRebuild(now: UInt64) {
        rebuildStarted = nil
        health.rebuildingRoute = false
        health.rebuildTimedOut = false
        lastProgress = now
        lastSignal = now
        health.stalled = false
        health.alwaysZero = false
    }

    /// Re-evaluates thresholds that depend only on elapsed time.
    public mutating func check(now: UInt64) {
        if now &- lastProgress >= stalledAfter { health.stalled = true }
        if now &- lastSignal >= zeroAfter { health.alwaysZero = true }
        if let started = rebuildStarted, now &- started >= rebuildTimeout {
            health.rebuildTimedOut = true
        }
    }

    public mutating func reset(now: UInt64) {
        health = CaptureHealth()
        lastProgress = now
        lastSignal = now
        rebuildStarted = nil
    }
}

/// Launch-time versus first-key-down lifecycle. `prepare()` sets up delivery
/// infrastructure but must never set `mayOpenDevice`; only `start()` does.
public struct CaptureLifecycle: Sendable, Equatable {
    public private(set) var isPrepared = false
    public private(set) var isLive = false

    public init() {}

    public mutating func prepare() {
        isPrepared = true
    }

    public mutating func start() {
        isPrepared = true
        isLive = true
    }

    public mutating func stop() {
        isLive = false
        isPrepared = false
    }

    public var mayOpenDevice: Bool { isLive }
}
