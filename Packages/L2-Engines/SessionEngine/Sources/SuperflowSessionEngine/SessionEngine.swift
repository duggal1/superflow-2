import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

/// Dictation session state machine and orchestration. Raw segments are persisted the moment
/// ASR commits them; cleanup runs per segment in the background and only the final insert waits.
public actor SessionEngine {
    private let audio: any AudioSource
    private let recognizer: any SpeechRecognizer
    private var pipeline: TextPipeline
    private let repository: any TranscriptRepository
    private let journals: any JournalStore
    /// Internal so `SessionEngine+AudioPath` can open the archive lane.
    let archive: (any AudioArchiveStore)?
    private let inserter: any TextInserter
    private let metrics: MetricsSink
    private let clock: TimeSource
    var settings: AppSettings
    /// Session-scoped project passed to the pipeline context. Never discovered by
    /// the text stages; nil means no filesystem scope is exposed.
    private var project: ProjectContext?

    public nonisolated let events: AsyncStream<SessionEvent>
    private let continuation: AsyncStream<SessionEvent>.Continuation

    private var state: SessionState = .idle
    private var record: SessionRecord?
    private var recognitionStream: (any RecognitionStream)?
    private var writer: (any AudioJournalWriter)?
    private var archiveWriter: (any AudioArchiveWriter)?
    private var sampleTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?
    private var cleanupCoordinator: SessionCleanupCoordinator?
    private var nextIndex = 0
    private var lastEndMs = 0
    private var cumulativeTokenCount = 0
    var levelCounter = 0
    var journalWarned = false
    /// Worst case: modifier wait + key resolution + verify + AX fallback + re-verify.
    private let insertionDeadline: Duration
    /// Bounded model waits. A Core ML call cannot be cancelled, so a deadline abandons the call
    /// and lets the session continue instead of wedging in `warming`/`finalizing` forever. The
    /// warm-up bound is generous because the first prediction on a cold machine pays the ANE
    /// specialization cost.
    private let modelDeadline: Duration = .seconds(120)
    private let finishDeadline: Duration = .seconds(20)

    public init(audio: any AudioSource, recognizer: any SpeechRecognizer, pipeline: TextPipeline,
                repository: any TranscriptRepository, journals: any JournalStore,
                inserter: any TextInserter, archive: (any AudioArchiveStore)? = nil,
                settings: AppSettings = .default, project: ProjectContext? = nil,
                metrics: MetricsSink = NoopMetrics(), clock: TimeSource = SystemTimeSource(),
                insertionDeadline: Duration = .seconds(8)) {
        self.audio = audio
        self.recognizer = recognizer
        self.pipeline = pipeline
        self.repository = repository
        self.journals = journals
        self.archive = archive
        self.inserter = inserter
        self.settings = settings
        self.project = project
        self.metrics = metrics
        self.clock = clock
        self.insertionDeadline = insertionDeadline
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    public var currentState: SessionState { state }
    public var currentSession: SessionRecord? { record }

    public func update(settings: AppSettings) async {
        self.settings = settings
    }

    /// Replaces the explicit project scope for the rest of the session. Cleanup
    /// rows already queued keep the scope they captured.
    public func update(project: ProjectContext?) async {
        self.project = project
    }

    /// Replaces the pipeline after a settings, dictionary or shortcut change.
    /// Segments already being cleaned keep the pipeline they captured.
    public func update(pipeline: TextPipeline, settings: AppSettings) async {
        self.pipeline = pipeline
        self.settings = settings
    }

    /// Promotes a speculative push-to-talk session to hands-free without
    /// interrupting capture.
    public func setMode(_ mode: SessionMode) {
        guard case .recording = state else { return }
        transition(.recording(mode))
    }

    /// Called at launch. A failed warm-up leaves the engine idle and reports a notice.
    @discardableResult
    public func warmUp() async -> Bool {
        guard state == .idle else { return false }
        transition(.warming)
        do {
            let recognizer = self.recognizer
            let profile = settings.asrProfile
            try await withDeadline(modelDeadline, label: "model warm-up") {
                try await recognizer.warmUp(profile: profile)
            }
            transition(.idle)
            return true
        } catch {
            transition(.idle)
            emit(.notice("Model warm-up failed: \(error.localizedDescription)"))
            return false
        }
    }

    public func start(mode: SessionMode = .dictation) async throws -> SessionID {
        switch state {
        case .idle, .complete, .cancelled, .failed: break
        case .warming, .recording, .finalizing, .inserting:
            throw SuperflowError.invalidState("session already active: \(state.label)")
        }

        let bundleID = await inserter.frontmostBundleID()
        // Let Chromium/Electron build their Accessibility tree while the user speaks.
        await inserter.prepareForInsertion()
        var newRecord = SessionRecord(kind: .dictation, status: .recording,
                                      frontmostBundleID: bundleID, modelProfile: settings.asrProfile)
        try await repository.createSession(newRecord)
        record = newRecord
        resetBuffers()
        recognitionStream = nil
        writer = nil
        archiveWriter = nil
        sampleTask = nil
        eventTask = nil
        recognitionTask = nil

        // `isReady` says only that *some* profile is resident, so a session could pass
        // the check and then throw from `makeStream`. A resident profile also must not
        // flash "Warming up": only a real model load gets that state.
        let recognizer = self.recognizer
        let profile = newRecord.modelProfile
        if !(await recognizer.isPrepared(profile: profile)) { transition(.warming) }

        do {
            try await withDeadline(modelDeadline, label: "model warm-up") {
                try await recognizer.warmUp(profile: profile)
            }
            // A low disk no longer blocks recording. The lane opens degraded (no journal, no
            // crash recovery) and the session reports it instead of refusing to start.
            let journalWriter = try await journals.openWriter(session: newRecord.id, source: .mic,
                                                              startingSample: 0)
            writer = journalWriter
            await reportJournalIfDegraded(journalWriter)
            // The clip is exactly what the recognizer heard, written from the same
            // buffers. "Don't store transcripts" means nothing is ever written.
            let clip = await openArchive(for: newRecord.id)
            archiveWriter = clip
            let streams = try await audio.start()
            let recognition = try await withDeadline(modelDeadline, label: "recognition stream") {
                try await recognizer.makeStream(profile: profile, source: .mic)
            }
            recognitionStream = recognition
            let eventContinuation = continuation
            let cleanup = SessionCleanupCoordinator(repository: repository, sessionID: newRecord.id,
                                                    emit: { event in
                eventContinuation.yield(event)
            })
            await cleanup.start(workerCount: settings.cleanupWorkers)
            cleanupCoordinator = cleanup
            transition(.recording(mode))

            let id = newRecord.id
            recognitionTask = Task { [weak self] in
                await self?.consumeRecognition(recognition, session: id)
            }
            sampleTask = Task { [weak self] in
                await self?.consumeAudio(streams.samples, writer: journalWriter,
                                         archive: clip, stream: recognition)
            }
            eventTask = Task { [weak self] in
                await self?.consumeAudioEvents(streams.events)
            }
            newRecord.status = .recording
            return id
        } catch {
            await audio.stop()
            await recognitionStream?.finish()
            recognitionStream = nil
            _ = await writer?.close()
            writer = nil
            await archiveWriter?.discard()
            archiveWriter = nil
            await archive?.delete(session: newRecord.id)
            if !settings.keepJournals { await journals.delete(session: newRecord.id) }
            try? await repository.finalizeSession(newRecord.id, endedAt: clock.now(), status: .failed,
                                                  durationMs: 0, wordCount: 0, cleanupState: .skipped)
            transition(.failed(newRecord.id, error.localizedDescription))
            emit(.notice("Could not start recording: \(error.localizedDescription)"))
            record = nil
            throw error
        }
    }

    /// Drains capture and recognition, resolves every cleanup task, inserts the final text and
    /// finalizes the session. Returns nil when there is no active recording.
    public func stop() async -> SessionOutcome? {
        guard case .recording = state, let record else { return nil }
        transition(.finalizing)
        let started = DispatchTime.now().uptimeNanoseconds

        await audio.stop()
        // Both consumers touch the model, so both are bounded: a stuck prediction must not hold
        // the session in `finalizing` forever. The abandoned call keeps running and is dropped.
        if let sampleTask {
            let task = sampleTask
            _ = try? await withDeadline(finishDeadline, label: "capture drain") { await task.value }
            task.cancel()
        }
        sampleTask = nil
        if let stream = recognitionStream {
            _ = try? await withDeadline(finishDeadline, label: "recognition finish") {
                await stream.finish()
            }
        }
        if let recognitionTask {
            let task = recognitionTask
            _ = try? await withDeadline(finishDeadline, label: "recognition drain") { await task.value }
            task.cancel()
        }
        recognitionTask = nil
        let journalSummary = await writer?.close()
        writer = nil
        recognitionStream = nil
        eventTask?.cancel()
        eventTask = nil
        if journalSummary?.degraded == true, !journalWarned {
            journalWarned = true
            emit(.notice("Crash recovery was off for this session: the audio journal stopped (low disk). Dictation still worked and the transcript is saved."))
        }

        let cleanupState = await cleanupCoordinator?.finish() ?? .skipped
        cleanupCoordinator = nil
        let assembledText = await finalText(session: record.id)
        let text = assembledText ?? ""
        let words = wordCount(text)
        let duration = max(lastEndMs, Int(clock.now().timeIntervalSince(record.startedAt) * 1000))

        // No speech means no clip worth keeping: discard it rather than spend rows
        // on a player for silence.
        if let clip = archiveWriter {
            archiveWriter = nil
            if words == 0 {
                await clip.discard()
            } else if let archived = await clip.finish(),
                      let store = repository as? any AudioMetadataStore {
                try? await store.setAudio(session: record.id, duration: archived.duration,
                                          peaks: Data(archived.peaks))
            }
        }
        metrics.record("session.stop.ms", valueMs: Double((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000))

        var finalized = false
        if assembledText != nil {
            do {
                try await repository.finalizeSession(record.id, endedAt: clock.now(), status: .complete,
                                                      durationMs: duration, wordCount: words,
                                                      cleanupState: cleanupState)
                finalized = true
            } catch {
                emit(.notice("Could not finalize the session in History: \(error.localizedDescription)"))
            }
        }
        var insertion: InsertionOutcome?
        if !text.isEmpty {
            transition(.inserting)
            do {
                insertion = try await withDeadline(insertionDeadline, label: "insertion") { [inserter] in
                    try await inserter.insert(text, strategy: .auto)
                }
                if let insertion { emit(.inserted(insertion)) }
            } catch {
                emit(.notice("Could not insert automatically. The text is on the clipboard and in History."))
                // Make the notice true: the deadline may have fired before the adapter
                // had a chance to leave the transcript on the clipboard.
                let fallback = try? await inserter.insert(text, strategy: .clipboardOnly)
                insertion = fallback ?? .clipboardOnly(reason: error.localizedDescription)
                if let fallback { emit(.inserted(fallback)) }
            }
        }
        if !settings.keepJournals, finalized { await journals.delete(session: record.id) }
        if finalized {
            transition(.complete(record.id))
            emit(.finished(record.id, .complete))
        } else {
            transition(.failed(record.id, "Transcript could not be finalized."))
            emit(.finished(record.id, .failed))
        }
        self.record = nil
        return SessionOutcome(sessionID: record.id, text: text, wordCount: words,
                              cleanupState: cleanupState, insertion: insertion)
    }

    public func cancel() async {
        guard state.isActive || state == .idle else { return }
        let id = record?.id
        transition(.cancelled(id))
        sampleTask?.cancel()
        recognitionTask?.cancel()
        eventTask?.cancel()
        await cleanupCoordinator?.cancel()
        cleanupCoordinator = nil
        await audio.stop()
        await recognitionStream?.finish()
        _ = await writer?.close()
        await archiveWriter?.discard()
        archiveWriter = nil
        if let id {
            await archive?.delete(session: id)
            await journals.delete(session: id)
            try? await repository.deleteSession(id)
            emit(.finished(id, .cancelled))
        }
        sampleTask = nil
        recognitionTask = nil
        eventTask = nil
        record = nil
        resetBuffers()
    }

    private func consumeRecognition(_ stream: any RecognitionStream, session: SessionID) async {
        for await event in stream.events {
            switch event {
            case .partial(let text):
                emit(.partial(text))
            case .committed(let segment):
                await persist(segment, session: session)
            case .endpoint:
                break
            case .failure(let message):
                emit(.notice("Recognition problem: \(message)"))
            }
        }
    }

    private func persist(_ raw: RawSegment, session: SessionID) async {
        guard state.isActive else { return }
        let index = nextIndex
        nextIndex += 1
        lastEndMs = max(lastEndMs, raw.endMs)
        let row = Segment(sessionID: session, index: index, startMs: raw.startMs, endMs: raw.endMs,
                          source: raw.source, rawText: raw.text, cleanupState: .pending)
        do {
            try await repository.appendSegment(row)
        } catch {
            emit(.notice("Could not persist raw segment \(index): \(error.localizedDescription)"))
        }
        let tokens = await pipeline.countTokens(raw.text)
        let withinInteractiveBudget = tokens.map { cumulativeTokenCount + $0 <= 600 } ?? true
        if let tokens { cumulativeTokenCount += tokens }
        let interactive = raw.endMs <= 30_000 && withinInteractiveBudget
        await cleanupCoordinator?.submit(index: index, interactive: interactive,
                                          pipeline: pipeline, settings: settings,
                                          project: project)
    }

    // MARK: assembly

    private func finalText(session: SessionID) async -> String? {
        do {
            return try await repository.transcriptTextForProcessing(session: session)
        } catch {
            emit(.notice("Could not load the final transcript: \(error.localizedDescription)"))
            return nil
        }
    }

    private func resetBuffers() {
        nextIndex = 0
        lastEndMs = 0
        cumulativeTokenCount = 0
        levelCounter = 0
        journalWarned = false
        cleanupCoordinator = nil
    }

    private func transition(_ next: SessionState) {
        state = next
        emit(.state(next))
    }

    func emit(_ event: SessionEvent) {
        continuation.yield(event)
    }

}
