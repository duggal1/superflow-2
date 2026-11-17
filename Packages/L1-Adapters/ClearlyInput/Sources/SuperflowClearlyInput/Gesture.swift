/// Pure, table-driven gesture logic for the two fixed input bindings.
///
/// This file deliberately has no OS imports. Timestamps are monotonic seconds
/// supplied by the caller, so every row of the gesture table can be exercised
/// with synthetic sequences. Right Option is the only push-to-talk key and Left
/// Control is the only meeting toggle; every other key is `interference`.
public enum Clearly {

    // MARK: - Inputs

    /// The five things the event tap is allowed to report.
    public enum RawKey: Sendable, Equatable {
        case rightOptionDown
        case rightOptionUp
        case leftControlDown
        case leftControlUp
        /// Any other key or click. Pressing Option+E must cancel a held PTT.
        case interference
    }

    public struct RawEvent: Sendable, Equatable {
        public var key: RawKey
        /// Monotonic seconds (system uptime), never wall clock.
        public var timestamp: Double
        public init(_ key: RawKey, at timestamp: Double) {
            self.key = key
            self.timestamp = timestamp
        }
    }

    // MARK: - Outputs

    public enum Gesture: Sendable, Equatable {
        case pttBegan
        /// Hold released (or latch timed out): finalize and send.
        case pttSend
        /// Interference while pressed: throw the audio away.
        case pttCancelled
        /// Quick tap: keep listening until the next press-and-release.
        case pttLatched
        case meetingToggle
    }

    // MARK: - States

    public enum PttState: Sendable, Equatable {
        case idle, pressed, latched, latchedDown
    }

    public enum CtrlState: Sendable, Equatable {
        case idle, pressed
    }

    // MARK: - Constants

    public struct Config: Sendable, Equatable {
        /// Hold at least this long to send on release; shorter taps latch.
        public var holdThreshold: Double = 0.25
        /// A Left Control tap longer than this is not a toggle.
        public var ctrlTapMax: Double = 0.5
        /// Minimum gap between two meeting toggles.
        public var ctrlDebounce: Double = 0.4
        /// A latched PTT is finalized automatically after this long.
        public var maxListen: Double = 120
        public init() {}
        public init(holdThreshold: Double, ctrlTapMax: Double,
                    ctrlDebounce: Double, maxListen: Double) {
            self.holdThreshold = holdThreshold
            self.ctrlTapMax = ctrlTapMax
            self.ctrlDebounce = ctrlDebounce
            self.maxListen = maxListen
        }
    }

    // MARK: - Recognizer

    public struct Recognizer: Sendable {
        /// Guards threshold comparisons against binary floating-point drift
        /// (e.g. 0.6 - 0.2 evaluating to 0.39999999999999997).
        private static let epsilon = 1e-9

        public private(set) var ptt: PttState = .idle
        public private(set) var ctrl: CtrlState = .idle
        public private(set) var config: Config

        private var pttDownAt: Double = 0
        private var pttLatchedAt: Double = 0
        private var ctrlDownAt: Double = 0
        private var lastToggleAt: Double = -Double.infinity

        public init(config: Config = Config()) {
            self.config = config
        }

        public mutating func update(config: Config) {
            self.config = config
        }

        /// Advances both independent state machines. PTT and meeting never
        /// block each other: a PTT can begin during a live meeting.
        public mutating func handle(_ event: RawEvent) -> [Gesture] {
            switch event.key {
            case .rightOptionDown: return rightOptionDown(at: event.timestamp)
            case .rightOptionUp: return rightOptionUp(at: event.timestamp)
            case .leftControlDown: leftControlDown(at: event.timestamp); return []
            case .leftControlUp: return leftControlUp(at: event.timestamp)
            case .interference: return interference()
            }
        }

        /// Fires the latched-PTT timeout. Call on a short timer with the same
        /// monotonic clock used for event timestamps.
        public mutating func tick(at now: Double) -> [Gesture] {
            guard ptt == .latched, now - pttLatchedAt + Self.epsilon >= config.maxListen else { return [] }
            ptt = .idle
            pttLatchedAt = 0
            return [.pttSend]
        }

        // MARK: PTT (Right Option)

        private mutating func rightOptionDown(at now: Double) -> [Gesture] {
            switch ptt {
            case .idle:
                ptt = .pressed
                pttDownAt = now
                return [.pttBegan]
            case .latched:
                // The next press of a latched mic arms the send; release sends.
                ptt = .latchedDown
                return []
            case .pressed, .latchedDown:
                return []
            }
        }

        private mutating func rightOptionUp(at now: Double) -> [Gesture] {
            switch ptt {
            case .pressed:
                let held = max(0, now - pttDownAt)
                ptt = .idle
                if held + Self.epsilon >= config.holdThreshold {
                    return [.pttSend]
                }
                ptt = .latched
                pttLatchedAt = now
                return [.pttLatched]
            case .latchedDown:
                ptt = .idle
                pttLatchedAt = 0
                return [.pttSend]
            case .idle, .latched:
                return []
            }
        }

        // MARK: Meeting (Left Control)

        private mutating func leftControlDown(at now: Double) {
            guard ctrl == .idle else { return }
            ctrl = .pressed
            ctrlDownAt = now
        }

        private mutating func leftControlUp(at now: Double) -> [Gesture] {
            guard ctrl == .pressed else { return [] }
            ctrl = .idle
            let held = max(0, now - ctrlDownAt)
            guard held < config.ctrlTapMax - Self.epsilon,
                  now - lastToggleAt + Self.epsilon >= config.ctrlDebounce else { return [] }
            lastToggleAt = now
            return [.meetingToggle]
        }

        // MARK: Cancellation

        private mutating func interference() -> [Gesture] {
            var result: [Gesture] = []
            if ptt == .pressed {
                ptt = .idle
                result.append(.pttCancelled)
            }
            // A latched mic survives interference by design: latched / latchedDown
            // stay unchanged so other typing does not end the utterance.
            if ctrl == .pressed { ctrl = .idle }
            return result
        }
    }
}
