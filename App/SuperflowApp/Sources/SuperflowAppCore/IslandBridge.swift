import AppKit
import Foundation
import SuperflowFeatureIsland
import SuperflowKernel
import SuperflowPorts
import SuperflowSessionEngine
import SuperflowMeetingEngine

/// Translates the app's session events into the Island's vocabulary. The only
/// place that decides what "the paste did not land" means today:
///
/// - `InsertionOutcome.pasted` / `.accessibility` -> landed.
/// - `.clipboardOnly` / `.blockedSecureField` -> the text never reached the
///   field, so the failure card appears with the transcript.
/// - An insertion that throws emits no `.inserted` at all; the engine reports
///   `.finished(.complete)` after entering `.inserting`. That is also a failure.
/// - No text at all (empty transcript) -> the Island simply retracts.
@MainActor
final class IslandBridge {
    let feed: IslandFeedAdapter

    let box: IslandFeedBox
    let transcripts: any TranscriptRepository

    private var task: Task<Void, Never>?
    private var sawInserting = false
    private var didLand = false
    var latestText = ""
    private var target: IslandTarget?
    var pulseTask: Task<Void, Never>?
    var meetingStarted: Date?
    var meetingTask: Task<Void, Never>?
    var meetingEngine: MeetingEngine?
    var meetingMeter = MeetingPulseTracker()

    init(transcripts: any TranscriptRepository) {
        box = IslandFeedBox()
        feed = IslandFeedAdapter(box: box)
        self.transcripts = transcripts
    }

    func start(events: AsyncStream<SessionEvent>) {
        guard task == nil else { return }
        task = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    // MARK: settings and cache

    func setStoresTranscripts(_ stores: Bool) {
        box.storesTranscripts = stores
        if !stores { box.lastTranscript = nil }
    }

    func refreshLastTranscript() async {
        guard box.storesTranscripts else {
            box.lastTranscript = nil
            box.history = []
            return
        }
        await refreshHistory()
        await refreshToday()
        guard let record = try? await transcripts.sessions(kind: .dictation, query: nil,
                                                           limit: 1, offset: 0).first else {
            box.lastTranscript = nil
            return
        }
        box.lastTranscript = await makeTranscript(record)
    }

    // MARK: gesture edges

    /// fn down, or hands-free engaged. Opens the Island immediately; the target
    /// app is resolved after the first frame so nothing waits on the OS.
    func holdBegan() {
        begin { .holdBegan($0) }
    }

    /// A double-tap latched the microphone open. The session is already running,
    /// so this only changes what the notch says, never the audio path.
    func handsFreeBegan() {
        begin { .handsFreeBegan($0) }
    }

    /// A latched meeting. Same rule: presentation only.
    func meetingBegan() {
        begin { .meetingBegan($0) }
        startPulses()
    }

    private func begin(_ make: (IslandTarget?) -> IslandEvent) {
        sawInserting = false
        didLand = false
        latestText = ""
        target = Self.frontmostTarget()
        box.send(make(target))
    }

    func holdEnded() {
        box.send(.holdEnded)
    }

    func cancelled() {
        box.send(.cancelled)
        reset()
    }

    /// Escape while recording. The recognizer's partial text rides along so a
    /// long dictation can still be kept if the Escape was a mistake.
    func escaped() {
        box.send(.escapeCancelled(text: latestText))
        reset()
    }

    /// Escape during a latched meeting. The meeting engine discards the take, so
    /// there is nothing to undo; the card says that instead of the notch blinking
    /// out as if the key had failed.
    func meetingEscaped() {
        reset()
        box.send(.notice(IslandNotice(kind: .info,
                                      title: "Meeting stopped.",
                                      detail: "Nothing was saved. Start again with a right-⌘ hold.")))
    }

    /// An OS-style notice in the notch.
    func notice(_ notice: IslandNotice) {
        box.send(.notice(notice))
    }

    /// The session refused to open — the model is still loading, the microphone
    /// is gone, a meeting is running. Retracting to nothing reads as a dead key,
    /// so the notch says why instead.
    func refused(_ message: String) {
        box.send(.notice(IslandNotice(kind: .info,
                                      title: "Can't listen yet.",
                                      detail: message)))
    }

    // MARK: session events

    private func handle(_ event: SessionEvent) async {
        switch event {
        case .level(let level):
            box.level(Self.meter(level))
        case .partial(let text):
            latestText = text
            box.partial(text)
        case .state(let state):
            if case .inserting = state { sawInserting = true }
            if case .failed = state { box.send(.cancelled) }
        case .inserted(let outcome):
            switch outcome {
            case .pasted, .accessibility:
                didLand = true
                box.send(.landed(words: Self.words(latestText)))
            case .clipboardOnly, .blockedSecureField:
                // The copy card must quote the finalized transcript, so the
                // failure card is built on `.finished`, not from the last
                // (possibly partial) segment seen here.
                didLand = false
            }
        case .finished(let id, let status):
            switch status {
            case .complete:
                if !didLand {
                    if sawInserting {
                        await fail(id: id)
                    } else {
                        box.send(.cancelled)
                    }
                }
                box.partial(latestText, isFinal: true)
                await cacheLastTranscript(id)
            case .cancelled, .failed:
                box.send(.cancelled)
            default:
                break
            }
            reset()
        case .progress, .notice:
            break
        }
    }

    private func fail(id: SessionID?) async {
        guard let transcript = await failureTranscript(id: id) else {
            box.send(.cancelled)
            return
        }
        box.send(.pasteFailed(transcript))
    }

    private func failureTranscript(id: SessionID?) async -> IslandTranscript? {
        if let id, let record = try? await transcripts.session(id) {
            if let stored = await makeTranscript(record) {
                return stored
            }
        }
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return IslandTranscript(text: text,
                                bundleID: target?.bundleID,
                                appName: target?.name,
                                date: Date(),
                                words: Self.words(text))
    }

    func makeTranscript(_ record: SessionRecord) async -> IslandTranscript? {
        let segments = (try? await transcripts.segments(session: record.id)) ?? []
        let text = segments.map(\.bestText).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return IslandTranscript(text: text,
                                bundleID: record.frontmostBundleID,
                                appName: Self.appName(for: record.frontmostBundleID),
                                date: record.startedAt,
                                words: record.wordCount)
    }

    private func cacheLastTranscript(_ id: SessionID) async {
        guard box.storesTranscripts else { return }
        guard let record = try? await transcripts.session(id) else { return }
        if let transcript = await makeTranscript(record) {
            box.lastTranscript = transcript
        }
        await refreshHistory()
        await refreshToday()
        await announceProgress()
    }

    private func reset() {
        sawInserting = false
        didLand = false
        stopPulses()
        box.clearLive()
    }

    // MARK: helpers

    /// -50...0 dBFS maps to 0...1, as the port promises.
    static func meter(_ rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-6))
        return min(1, max(0, (db + 50) / 50))
    }

    static func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// The app the text will land in, read at the instant fn goes down. Same
    /// source the inserter uses: the workspace's frontmost application.
    static func frontmostTarget() -> IslandTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }
        return IslandTarget(bundleID: bundleID,
                            name: app.localizedName ?? appName(for: bundleID))
    }

    static func appName(for bundleID: String?) -> String? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
