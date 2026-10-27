import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

/// Two-source meeting capture on one sample clock. The mic is always labeled as self; only the
/// system channel is diarized. System audio failure degrades to microphone-only with a gap marker.
///
/// Memory is bounded while recording: the engine keeps only the most recent turns for the live
/// view and echo dedupe. The final document is rebuilt from the repository, so a three hour
/// meeting does not retain every turn in memory.
public actor MeetingEngine {
    /// Turns kept for live rendering and overlap-based echo detection. Older turns stay in the
    /// repository and are restored when the meeting is finalized.
    static let residentTurnLimit = 512
    static let noticeLimit = 50
    static let droppedIndexLimit = 512

    let mic: any AudioSource
    let system: (any AudioSource)?
    let recognizer: any SpeechRecognizer
    let diarizer: (any SpeakerDiarizer)?
    var pipeline: TextPipeline
    let repository: any TranscriptRepository
    let journals: any JournalStore
    var settings: AppSettings
    let clock: TimeSource

    public nonisolated let events: AsyncStream<MeetingEvent>
    private let continuation: AsyncStream<MeetingEvent>.Continuation

    var state: MeetingState = .idle
    var record: SessionRecord?
    var recognitionStreams: [AudioSourceKind: any RecognitionStream] = [:]
    var writers: [AudioSourceKind: any AudioJournalWriter] = [:]
    var sampleTasks: [AudioSourceKind: Task<Void, Never>] = [:]
    var recognitionTasks: [AudioSourceKind: Task<Void, Never>] = [:]
    var eventTasks: [AudioSourceKind: Task<Void, Never>] = [:]
    var pipelineTasks: [Int: Task<Void, Never>] = [:]
    var residentTurns: [MeetingTurn] = []
    var droppedIndexes: Set<Int> = []
    var nextIndex = 0
    var lastEndMs = 0
    var notices: [String] = []
    var speakerNames: [String: String] = [:]
    var systemOffsetSamples: Int64 = 0
    var systemAvailable = false
    var lastDocument: MeetingDocument?
    var micOriginNs: UInt64?

    public init(mic: any AudioSource, system: (any AudioSource)?, recognizer: any SpeechRecognizer,
                diarizer: (any SpeakerDiarizer)? = nil, pipeline: TextPipeline,
                repository: any TranscriptRepository, journals: any JournalStore,
                settings: AppSettings = .default, clock: TimeSource = SystemTimeSource()) {
        self.mic = mic
        self.system = system
        self.recognizer = recognizer
        self.diarizer = diarizer
        self.pipeline = pipeline
        self.repository = repository
        self.journals = journals
        self.settings = settings
        self.clock = clock
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    public var currentState: MeetingState { state }

    /// Live document for the current meeting. After `stop()` this is the repository-backed final
    /// document. While recording it contains the bounded resident window, not the whole meeting.
    public var currentDocument: MeetingDocument? {
        if let lastDocument, !state.isActive { return lastDocument }
        guard let record else { return nil }
        return liveDocument(record: record)
    }

    /// Settings and pipeline changes apply to the next committed segment. An
    /// active meeting keeps recording while the new stages take effect.
    public func update(pipeline: TextPipeline, settings: AppSettings) {
        self.pipeline = pipeline
        self.settings = settings
    }

    public func start() async throws -> SessionID {
        guard !state.isActive else {
            throw SuperflowError.invalidState("meeting already active")
        }
        var newRecord = SessionRecord(kind: .meeting, status: .recording,
                                      modelProfile: settings.asrProfile)
        try await repository.createSession(newRecord)
        record = newRecord
        lastDocument = nil
        reset()
        transition(.warming)
        do {
            if await !recognizer.isReady {
                try await recognizer.warmUp(profile: newRecord.modelProfile)
            }
            await diarizer?.beginSession()
            if let diarizer, await !diarizer.isReady() {
                emit(.notice("Speaker separation is not installed. Download the meeting model in Settings; recording can continue with one remote speaker label."))
            }
            micOriginNs = clock.monotonicNs()
            try await startSource(.mic, audio: mic, session: newRecord.id)
            if let system {
                let origin = clock.monotonicNs()
                systemOffsetSamples = Self.offsetSamples(from: micOriginNs, to: origin)
                do {
                    try await startSource(.system, audio: system, session: newRecord.id)
                    systemAvailable = true
                } catch SuperflowError.diskFull {
                    // A full disk is global, not a per-source glitch: fail the whole meeting start
                    // instead of recording the microphone with no durable journal.
                    throw SuperflowError.diskFull
                } catch {
                    await systemUnavailable(error.localizedDescription, session: newRecord.id)
                }
            } else {
                await systemUnavailable("System audio was not enabled.", session: newRecord.id)
            }
            transition(.recording)
            newRecord.status = .recording
            return newRecord.id
        } catch {
            // Tear down any lane that did start (for example the microphone when the system lane
            // hits a full disk) before reporting the failure, or capture would keep running.
            await finishCapture()
            transition(.failed(error.localizedDescription))
            try? await repository.finalizeSession(newRecord.id, endedAt: clock.now(), status: .failed,
                                                  durationMs: lastEndMs, wordCount: 0,
                                                  cleanupState: .skipped)
            throw error
        }
    }

    public func stop() async -> MeetingDocument? {
        guard state == .recording, let record else { return nil }
        transition(.finalizing)
        await finishCapture()
        let endedAt = clock.now()
        let document = await repositoryDocument(endedAt: endedAt)
        let words = document.turns.reduce(0) { $0 + wordCount($1.text) }
        let cleanup = await cleanupStateFromRepository()
        try? await repository.finalizeSession(record.id, endedAt: endedAt, status: .complete,
                                              durationMs: document.durationMs, wordCount: words,
                                              cleanupState: cleanup)
        if !settings.keepJournals { await journals.delete(session: record.id) }
        lastDocument = document
        transition(.complete(record.id))
        emit(.finished(record.id, document))
        return document
    }

    public func cancel() async {
        guard state.isActive || state == .idle else { return }
        let id = record?.id
        transition(.cancelled(id))
        for task in sampleTasks.values { task.cancel() }
        for task in recognitionTasks.values { task.cancel() }
        for task in eventTasks.values { task.cancel() }
        for task in pipelineTasks.values { task.cancel() }
        for source in [mic, system].compactMap({ $0 }) { await source.stop() }
        for task in sampleTasks.values { await task.value }
        for stream in recognitionStreams.values { await stream.finish() }
        for task in recognitionTasks.values { await task.value }
        for writer in writers.values { _ = await writer.close() }
        if let id {
            await journals.delete(session: id)
            try? await repository.deleteSession(id)
        }
        sampleTasks.removeAll()
        recognitionTasks.removeAll()
        eventTasks.removeAll()
        pipelineTasks.removeAll()
        recognitionStreams.removeAll()
        writers.removeAll()
        record = nil
        lastDocument = nil
        reset()
    }

    public func renameSpeaker(id: String, label: String) async {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        speakerNames[id] = name
        for index in residentTurns.indices where residentTurns[index].speakerID == id {
            residentTurns[index].speakerName = name
        }
        if var document = lastDocument {
            for index in document.speakers.indices where document.speakers[index].id == id {
                document.speakers[index].name = name
            }
            for index in document.turns.indices where document.turns[index].speakerID == id {
                document.turns[index].speakerName = name
            }
            lastDocument = document
        }
        if let record {
            try? await repository.renameSpeaker(session: record.id, id: id, label: name)
        }
    }

    // MARK: - State helpers

    func transition(_ next: MeetingState) {
        state = next
        emit(.state(next))
    }

    func emit(_ event: MeetingEvent) {
        continuation.yield(event)
    }

    func addNotice(_ message: String) {
        if notices.count >= Self.noticeLimit { notices.removeFirst(notices.count - Self.noticeLimit + 1) }
        notices.append(message)
        emit(.notice(message))
    }

    func reset() {
        recognitionStreams.removeAll()
        writers.removeAll()
        sampleTasks.removeAll()
        recognitionTasks.removeAll()
        eventTasks.removeAll()
        pipelineTasks.removeAll()
        residentTurns.removeAll()
        droppedIndexes.removeAll()
        nextIndex = 0
        lastEndMs = 0
        notices.removeAll()
        speakerNames.removeAll()
        systemOffsetSamples = 0
        systemAvailable = false
        micOriginNs = nil
    }

    static func offsetSamples(from micOrigin: UInt64?, to systemOrigin: UInt64) -> Int64 {
        guard let micOrigin, systemOrigin > micOrigin else { return 0 }
        let deltaNs = systemOrigin - micOrigin
        return Int64((Double(deltaNs) / 1_000_000_000 * Double(sampleRate)).rounded())
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return min(1, (sum / Float(samples.count)).squareRoot() * 6)
    }
}
