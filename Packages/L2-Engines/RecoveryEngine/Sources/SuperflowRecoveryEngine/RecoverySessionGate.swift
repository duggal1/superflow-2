import Foundation

public enum RecoveryPhase: String, Sendable, Equatable {
    case idle, recovering, cancelled
}

/// Owns the lifecycle of the recovery owner. Every public transition is bookkeeping only: the
/// gate never creates a session, appends a segment, or deletes a journal. Callbacks stamped with a
/// closed epoch are rejected, so cancel + rearm cannot produce phantom work or duplicate rows.
public actor RecoverySessionGate {
    private let fence: RecoveryEpochFence
    private var phase: RecoveryPhase = .idle
    private var claimedSegments: Set<String> = []

    public init(fence: RecoveryEpochFence = RecoveryEpochFence()) { self.fence = fence }

    public var currentPhase: RecoveryPhase { phase }

    /// Opens a new run. Returns nil while a run is already active, so a second caller cannot start
    /// a duplicate recovery. Advancing the epoch fences callbacks from every abandoned run.
    @discardableResult
    public func begin() async -> RecoveryEpoch? {
        guard phase != .recovering else { return nil }
        // Reserve the phase before crossing an actor boundary.
        phase = .recovering
        claimedSegments.removeAll()
        return await fence.advance()
    }

    /// Closes the active run. Later callbacks carrying its epoch become stale. Durable state is
    /// untouched: a cancelled recovery keeps its journal and leaves its session unfinished.
    public func cancel() async {
        guard phase == .recovering else { return }
        phase = .cancelled
        await fence.advance()
    }

    /// Rearms bookkeeping after a cancel (or an idle run). It emits no capture actions: no
    /// session, no segment, no journal deletion. Returns the epoch the next run must carry.
    @discardableResult
    public func rearm() async -> RecoveryEpoch {
        if phase == .recovering {
            phase = .cancelled
            await fence.advance()
        }
        phase = .idle
        claimedSegments.removeAll()
        return await fence.advance()
    }

    /// A run is active only while it has not been cancelled or rearmed and its epoch is current.
    public func isActive(_ epoch: RecoveryEpoch) async -> Bool {
        guard phase == .recovering else { return false }
        return await fence.isCurrent(epoch)
    }

    /// Idempotent per-run claim. Returns true only the first time a segment key is claimed, so a
    /// retry or a late callback cannot append the same row twice. A rearm clears the claim set,
    /// but the repository's own duplicate check still protects committed rows.
    public func claimSegment(_ key: String) -> Bool {
        guard phase == .recovering else { return false }
        return claimedSegments.insert(key).inserted
    }

    /// A superseded recovery must not finish a newer run.
    public func finish(epoch: RecoveryEpoch) async {
        guard await isActive(epoch), phase == .recovering else { return }
        phase = .idle
    }

    /// Marks an active run finished. A cancelled run is never silently promoted to finished.
    public func finish() {
        guard phase == .recovering else { return }
        phase = .idle
    }
}
