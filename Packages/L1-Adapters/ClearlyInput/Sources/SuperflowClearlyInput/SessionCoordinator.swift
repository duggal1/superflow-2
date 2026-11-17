import Foundation

/// What the coordinator is allowed to ask the existing backends to do.
/// The closures are supplied by the composition root; this module never imports
/// a session engine, a MeetingIntelligence bridge or an Island view.
public struct IntelligenceSessionActions: Sendable {
    public var pttBegan: @Sendable () async -> Void
    /// Shown after a short clean hold so Option+key chords do not flicker the Island.
    public var pttWaveform: @Sendable () async -> Void
    public var pttCancelled: @Sendable () async -> Void
    public var pttLatched: @Sendable () async -> Void
    public var pttSend: @Sendable () async -> Void
    /// true = start the continuous meeting, false = end it.
    public var meetingToggle: @Sendable (Bool) async -> Void
    /// Suppress the live question detector for a PTT utterance inside a meeting.
    public var suppressQuestionDetector: @Sendable (Bool) async -> Void
    public var secureInputChanged: @Sendable (Bool) async -> Void

    public init(
        pttBegan: @escaping @Sendable () async -> Void = {},
        pttWaveform: @escaping @Sendable () async -> Void = {},
        pttCancelled: @escaping @Sendable () async -> Void = {},
        pttLatched: @escaping @Sendable () async -> Void = {},
        pttSend: @escaping @Sendable () async -> Void = {},
        meetingToggle: @escaping @Sendable (Bool) async -> Void = { _ in },
        suppressQuestionDetector: @escaping @Sendable (Bool) async -> Void = { _ in },
        secureInputChanged: @escaping @Sendable (Bool) async -> Void = { _ in }
    ) {
        self.pttBegan = pttBegan
        self.pttWaveform = pttWaveform
        self.pttCancelled = pttCancelled
        self.pttLatched = pttLatched
        self.pttSend = pttSend
        self.meetingToggle = meetingToggle
        self.suppressQuestionDetector = suppressQuestionDetector
        self.secureInputChanged = secureInputChanged
    }
}

public struct ClearlySessionState: Sendable, Equatable {
    public var meetingLive = false
    public var pttActive = false
    public var pttLatched = false
    public init() {}
}

/// Owns session state and drives the existing backends. PTT is an overlay:
/// it can start and finish while a meeting is live.
public actor SessionCoordinator {
    public private(set) var state = ClearlySessionState()

    private var recognizer: Clearly.Recognizer
    private let actions: IntelligenceSessionActions
    private let clock: @Sendable () -> Double
    private let waveformDelayNs: UInt64
    private var waveformTask: Task<Void, Never>?

    public init(
        actions: IntelligenceSessionActions,
        config: Clearly.Config = Clearly.Config(),
        clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
        waveformDelay: Double = 0.12
    ) {
        self.actions = actions
        self.recognizer = Clearly.Recognizer(config: config)
        self.clock = clock
        self.waveformDelayNs = UInt64(max(0, waveformDelay) * 1_000_000_000)
    }

    public func handle(_ event: Clearly.RawEvent) async {
        await apply(recognizer.handle(event))
    }

    public func tick() async {
        await apply(recognizer.tick(at: clock()))
    }

    public func secureInputChanged(_ paused: Bool) async {
        await actions.secureInputChanged(paused)
    }

    private func apply(_ gestures: [Clearly.Gesture]) async {
        for gesture in gestures {
            switch gesture {
            case .pttBegan:
                state.pttActive = true
                if state.meetingLive { await actions.suppressQuestionDetector(true) }
                let delay = waveformDelayNs
                waveformTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: delay)
                    guard !Task.isCancelled else { return }
                    await self?.showWaveform()
                }
                await actions.pttBegan()

            case .pttLatched:
                state.pttLatched = true
                cancelWaveform()
                await showWaveform()
                await actions.pttLatched()

            case .pttCancelled:
                cancelWaveform()
                await endPtt()
                await actions.pttCancelled()

            case .pttSend:
                cancelWaveform()
                await endPtt()
                await actions.pttSend()

            case .meetingToggle:
                state.meetingLive.toggle()
                await actions.meetingToggle(state.meetingLive)
            }
        }
    }

    private func showWaveform() async {
        guard state.pttActive else { return }
        await actions.pttWaveform()
    }

    private func endPtt() async {
        state.pttActive = false
        state.pttLatched = false
        if state.meetingLive {
            await actions.suppressQuestionDetector(false)
        }
    }

    private func cancelWaveform() {
        waveformTask?.cancel()
        waveformTask = nil
    }
}
