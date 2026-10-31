import Foundation
import SuperflowKernel
import SuperflowPorts

/// Pure gesture logic: state plus key event plus timestamp in, actions out.
/// No OS dependencies, so every transition is testable with synthetic sequences.
public struct GestureRecognizer: Sendable {
    public private(set) var state: GestureState = .idle
    public private(set) var config: GestureConfig

    private var pendingKind: SessionKind?
    private var downAtNs: UInt64 = 0
    private var tapAtNs: UInt64 = 0
    private var holdAnnounced = false
    private var ignoreRightCmdUp = false

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    public mutating func update(config: GestureConfig) {
        self.config = config
    }

    public mutating func handle(_ event: KeyEvent) -> [GestureAction] {
        switch event.kind {
        case .fnDown: return fnDown(at: event.timestampNs)
        case .fnUp: return fnUp(at: event.timestampNs)
        case .rightCmdDown: return rightCmdDown(at: event.timestampNs)
        case .rightCmdUp: return rightCmdUp(at: event.timestampNs)
        case .enter: return enter(at: event.timestampNs)
        case .escape: return escape()
        case .otherKeyDown: return otherKey()
        }
    }

    /// The UI calls this on a short timer (or at the exact deadline) to fire hold and timeout edges.
    public mutating func tick(atNs now: UInt64) -> [GestureAction] {
        switch state {
        case .armed:
            if elapsedMs(now, since: downAtNs) >= config.holdMs {
                state = .pushToTalk
                return [.holdBegan(.dictation)]
            }
        case .meetingArmed:
            if !holdAnnounced, elapsedMs(now, since: downAtNs) >= config.meetingHoldMs {
                holdAnnounced = true
                return [.holdBegan(.meeting)]
            }
        case .awaitingSecondTap:
            if elapsedMs(now, since: tapAtNs) >= config.doubleTapMs, let kind = pendingKind {
                reset()
                return [.cancel(kind, .secondTapTimeout)]
            }
        case .idle, .pushToTalk, .handsFree, .meetingLatched:
            break
        }
        return []
    }

    // MARK: dictation

    private mutating func fnDown(at now: UInt64) -> [GestureAction] {
        switch state {
        case .idle:
            state = .armed
            pendingKind = .dictation
            downAtNs = now
            holdAnnounced = false
            return [.startSpeculative(.dictation)]
        case .awaitingSecondTap where pendingKind == .dictation:
            state = .handsFree
            pendingKind = .dictation
            holdAnnounced = true
            return [.beginHandsFree]
        case .handsFree:
            return submit(.dictation)
        case .armed, .pushToTalk, .meetingArmed, .meetingLatched, .awaitingSecondTap:
            return []
        }
    }

    private mutating func fnUp(at now: UInt64) -> [GestureAction] {
        switch state {
        case .armed, .pushToTalk:
            // A 10 ms tick can promote `.armed` to `.pushToTalk` just before the
            // release is delivered. The event timestamp, not the tick clock, says
            // whether the key was really held; otherwise a short first tap of a
            // double-tap submitted the session instead of waiting for the second.
            if elapsedMs(now, since: downAtNs) >= config.holdMs {
                return submit(.dictation)
            }
            state = .awaitingSecondTap
            pendingKind = .dictation
            tapAtNs = now
            return []
        case .awaitingSecondTap, .handsFree, .meetingArmed, .meetingLatched, .idle:
            return []
        }
    }

    // MARK: meeting

    private mutating func rightCmdDown(at now: UInt64) -> [GestureAction] {
        switch state {
        case .idle:
            state = .meetingArmed
            pendingKind = .meeting
            downAtNs = now
            holdAnnounced = false
            return [.startSpeculative(.meeting)]
        case .awaitingSecondTap where pendingKind == .meeting:
            state = .meetingLatched
            pendingKind = .meeting
            holdAnnounced = true
            return [.latchMeeting]
        case .meetingLatched:
            ignoreRightCmdUp = true
            return submit(.meeting)
        case .armed, .pushToTalk, .handsFree, .meetingArmed, .awaitingSecondTap:
            return []
        }
    }

    private mutating func rightCmdUp(at now: UInt64) -> [GestureAction] {
        if ignoreRightCmdUp {
            ignoreRightCmdUp = false
            return []
        }
        switch state {
        case .meetingArmed:
            if elapsedMs(now, since: downAtNs) >= config.meetingHoldMs {
                state = .meetingLatched
                pendingKind = .meeting
                return [.latchMeeting]
            }
            state = .awaitingSecondTap
            pendingKind = .meeting
            tapAtNs = now
            return []
        case .meetingLatched, .awaitingSecondTap, .idle, .armed, .pushToTalk, .handsFree:
            return []
        }
    }

    // MARK: shared keys

    private mutating func enter(at now: UInt64) -> [GestureAction] {
        switch state {
        case .handsFree:
            return submit(.dictation)
        case .meetingLatched:
            return submit(.meeting)
        case .armed, .pushToTalk:
            return cancel(.dictation, .otherKey)
        case .meetingArmed:
            return cancel(.meeting, .otherKey)
        case .awaitingSecondTap:
            if let kind = pendingKind { return cancel(kind, .otherKey) }
            return []
        case .idle:
            return []
        }
    }

    private mutating func escape() -> [GestureAction] {
        switch state {
        case .idle:
            return []
        case .armed, .pushToTalk:
            return cancel(.dictation, .escape)
        case .awaitingSecondTap:
            guard let kind = pendingKind else { reset(); return [] }
            return cancel(kind, .escape)
        case .handsFree:
            return cancel(.dictation, .escape)
        case .meetingArmed, .meetingLatched:
            return cancel(.meeting, .escape)
        }
    }

    private mutating func otherKey() -> [GestureAction] {
        switch state {
        case .armed, .pushToTalk:
            return cancel(.dictation, .otherKey)
        case .meetingArmed:
            return cancel(.meeting, .otherKey)
        case .awaitingSecondTap:
            guard let kind = pendingKind else { reset(); return [] }
            return cancel(kind, .otherKey)
        case .idle, .handsFree, .meetingLatched:
            return []
        }
    }

    // MARK: helpers

    private mutating func submit(_ kind: SessionKind) -> [GestureAction] {
        reset()
        return [.submit(kind)]
    }

    private mutating func cancel(_ kind: SessionKind, _ reason: GestureCancelReason) -> [GestureAction] {
        reset()
        return [.cancel(kind, reason)]
    }

    private mutating func reset() {
        state = .idle
        pendingKind = nil
        downAtNs = 0
        tapAtNs = 0
        holdAnnounced = false
        ignoreRightCmdUp = false
    }

    private func elapsedMs(_ now: UInt64, since start: UInt64) -> Int {
        guard now >= start else { return 0 }
        return Int((now - start) / 1_000_000)
    }
}
