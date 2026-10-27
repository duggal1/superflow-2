import Foundation

/// A live reading of one model download: how many bytes have landed, how fast,
/// and, when the server gave a length, how much is left. The rate is measured
/// from bytes actually received, never estimated from the progress fraction.
public struct TransferSnapshot: Sendable, Equatable {
    public var label: String
    public var receivedBytes: Int64
    public var totalBytes: Int64?
    public var bytesPerSecond: Double

    public init(label: String, receivedBytes: Int64, totalBytes: Int64?,
                bytesPerSecond: Double) {
        self.label = label
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
    }

    /// Fraction in 0...1 when the total is known.
    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }
}

/// One process-wide meter shared by the transfer layer and the screens that
/// show it. Downloads are serialized by the app, so a single active reading is
/// enough and no keys are needed. Every value is guarded by a lock: transfers
/// report from URLSession delegate queues while SwiftUI reads on the main actor.
public final class DownloadTelemetry: @unchecked Sendable {
    public static let shared = DownloadTelemetry()

    private struct State {
        var label = ""
        var totalBytes: Int64?
        var receivedBytes: Int64 = 0
        var bytesPerSecond: Double = 0
        var lastSampleNanos: UInt64 = 0
        var lastSampleBytes: Int64 = 0
        var active = false
    }

    private let lock = NSLock()
    private var state = State()

    public init() {}

    public func begin(label: String, totalBytes: Int64? = nil) {
        lock.withLock {
            state = State()
            state.label = label
            state.totalBytes = totalBytes
            state.active = true
            state.lastSampleNanos = DispatchTime.now().uptimeNanoseconds
        }
    }

    /// Fills in a total discovered after the transfer started.
    public func expect(totalBytes: Int64) {
        guard totalBytes > 0 else { return }
        lock.withLock { state.totalBytes = totalBytes }
    }

    /// Absolute bytes received so far. Safe to call from any queue; sampling is
    /// throttled to four readings a second so a fast transfer cannot flood the
    /// main actor.
    public func record(receivedBytes: Int64) {
        lock.withLock {
            guard state.active else { return }
            state.receivedBytes = max(0, receivedBytes)
            let now = DispatchTime.now().uptimeNanoseconds
            let elapsed = Double(now &- state.lastSampleNanos) / 1_000_000_000
            guard elapsed >= 0.25 else { return }
            let delta = state.receivedBytes - state.lastSampleBytes
            let instant = delta > 0 ? Double(delta) / elapsed : 0
            // Exponential moving average, so one stalled sample does not pin a
            // stale rate on screen and a burst does not spike it.
            state.bytesPerSecond = state.bytesPerSecond == 0
                ? instant
                : state.bytesPerSecond * 0.6 + instant * 0.4
            state.lastSampleNanos = now
            state.lastSampleBytes = state.receivedBytes
        }
    }

    public func end() {
        lock.withLock {
            state.active = false
            state.bytesPerSecond = 0
        }
    }

    /// The active reading, or nil when nothing is downloading.
    public func snapshot() -> TransferSnapshot? {
        lock.withLock {
            guard state.active else { return nil }
            return TransferSnapshot(label: state.label,
                                    receivedBytes: state.receivedBytes,
                                    totalBytes: state.totalBytes,
                                    bytesPerSecond: state.bytesPerSecond)
        }
    }
}
