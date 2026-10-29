import Foundation
import SuperflowFeatureIsland

/// Lock-protected backing store for the Island port. `IslandModel` reads it on
/// the main actor; the bridge writes it there too, but the port is nonisolated
/// and `Sendable`, so its few values are guarded.
final class IslandFeedBox: @unchecked Sendable {
    let events: AsyncStream<IslandEvent>
    let levels: AsyncStream<Float>
    let live: AsyncStream<LiveText>
    let pulses: AsyncStream<MeetingPulse>

    private let lock = NSLock()
    private var transcript: IslandTranscript?
    private var recent: [IslandTranscript] = []
    private var todayWords = 0
    private var stores = true
    private let eventContinuation: AsyncStream<IslandEvent>.Continuation
    private let levelContinuation: AsyncStream<Float>.Continuation
    private let liveContinuation: AsyncStream<LiveText>.Continuation
    private let pulseContinuation: AsyncStream<MeetingPulse>.Continuation

    init() {
        let eventPair = AsyncStream<IslandEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        events = eventPair.stream
        eventContinuation = eventPair.continuation

        let levelPair = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(8))
        levels = levelPair.stream
        levelContinuation = levelPair.continuation

        // Partials are worthless once a newer one lands; the newest is the truth.
        let livePair = AsyncStream<LiveText>.makeStream(bufferingPolicy: .bufferingNewest(1))
        live = livePair.stream
        liveContinuation = livePair.continuation

        let pulsePair = AsyncStream<MeetingPulse>.makeStream(bufferingPolicy: .bufferingNewest(1))
        pulses = pulsePair.stream
        pulseContinuation = pulsePair.continuation
    }

    func send(_ event: IslandEvent) {
        eventContinuation.yield(event)
    }

    func level(_ value: Float) {
        levelContinuation.yield(value)
    }

    func partial(_ text: String, isFinal: Bool = false) {
        liveContinuation.yield(LiveText(text: text, isFinal: isFinal))
    }

    /// The capture ended, so the shelf must not keep the last sentence.
    func clearLive() {
        liveContinuation.yield(.empty)
    }

    func pulse(_ pulse: MeetingPulse) {
        pulseContinuation.yield(pulse)
    }

    var lastTranscript: IslandTranscript? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return transcript
        }
        set {
            lock.lock()
            transcript = newValue
            lock.unlock()
        }
    }

    var history: [IslandTranscript] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return recent
        }
        set {
            lock.lock()
            recent = newValue
            lock.unlock()
        }
    }

    var today: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return todayWords
        }
        set {
            lock.lock()
            todayWords = newValue
            lock.unlock()
        }
    }

    var storesTranscripts: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stores
        }
        set {
            lock.lock()
            stores = newValue
            if !newValue {
                transcript = nil
                recent = []
            }
            lock.unlock()
        }
    }
}

/// The Island's read-only port, backed by the app's existing session repository
/// and the workspace's frontmost app. It adds no second source of truth.
struct IslandFeedAdapter: IslandFeed {
    let box: IslandFeedBox

    var events: AsyncStream<IslandEvent> { box.events }
    var levels: AsyncStream<Float> { box.levels }
    var live: AsyncStream<LiveText> { box.live }
    var pulses: AsyncStream<MeetingPulse> { box.pulses }
    func lastTranscript() -> IslandTranscript? { box.lastTranscript }
    func history(limit: Int) -> [IslandTranscript] { Array(box.history.prefix(limit)) }
    func wordsToday() -> Int { box.today }
    var storesTranscripts: Bool { box.storesTranscripts }
}
