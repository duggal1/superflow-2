import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

extension SessionEngine {
    public func warmUp() async -> Bool {
        guard state == .idle else { return false }
        transition(.warming)
        let result = await prewarm()
        transition(.idle)
        return result
    }

    /// Loads the model without entering `.warming`. Launch uses this so the UI
    /// never claims a model load the owner did not ask for. A press during the
    /// load still starts a session: `start` awaits the same serialized load and
    /// only enters `.warming` if the model is genuinely not resident yet.
    @discardableResult
    public func prewarm() async -> Bool {
        if let warmTask { return await warmTask.task.value }
        let id = UUID()
        let task = Task { await self.performWarmUp() }
        warmTask = (id, task)
        let result = await task.value
        if warmTask?.id == id { warmTask = nil }
        return result
    }

    func performWarmUp() async -> Bool {
        let recognizer = self.recognizer
        let profile = settings.asrProfile
        let enhancer = settings.speechEnhancementEnabled ? self.enhancer : nil
        let deadline = modelDeadline
        let enhancement = enhancer.map { enhancer in
            Task {
                try? await withDeadline(deadline, label: "enhancement warm-up") {
                    try await enhancer.prepare()
                }
            }
        }
        do {
            try await withDeadline(modelDeadline, label: "model warm-up") {
                try await recognizer.warmUp(profile: profile)
            }
            await enhancement?.value
            return true
        } catch {
            enhancement?.cancel()
            emit(.notice("Model warm-up failed: \(error.localizedDescription)"))
            return false
        }
    }

    public func start(mode: SessionMode = .dictation) async throws -> SessionID {
        guard !isStarting else {
            throw SuperflowError.invalidState("session already starting")
        }
        switch state {
        case .idle, .complete, .cancelled, .failed: break
        case .warming, .recording, .finalizing, .inserting:
            throw SuperflowError.invalidState("session already active: \(state.label)")
        }

        isStarting = true
        defer { isStarting = false }
        await speculative.cancel()

        // A new dictation supersedes any text still waiting on a permission
        // grant; it is already in History, so keeping two would paste stale
        // words later.
        pendingInsertion = nil
        let bundleID = await inserter.frontmostBundleID()
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
        recognitionFeed = nil
        recognitionDrainTask = nil

        // `isReady` says only that *some* profile is resident, so a session could pass
        // the check and then throw from `makeStream`. A resident profile also must not
        // flash "Warming up": only a real model load gets that state.
        let recognizer = self.recognizer
        let profile = newRecord.modelProfile

        do {
            // Journal first: a failure here is the one condition that must fail
            // the start before the microphone opens.
            let journalWriter = try await journals.openWriter(session: newRecord.id, source: .mic,
                                                              startingSample: 0)
            writer = journalWriter
            await reportJournalIfDegraded(journalWriter)
            // The clip is exactly what the recognizer heard, written from the same
            // buffers. "Don't store transcripts" means nothing is ever written.
            let clip = await openArchive(for: newRecord.id)
            archiveWriter = clip
            // Open capture before the model wait. The capture stream buffers while
            // the model specializes, so levels, journaling and the archive start
            // immediately instead of freezing the whole session on inference.
            let streams = try await startCapture()
            // Noise suppression is optional. A missing or broken model degrades
            // this session to raw audio with a truthful notice; it must never
            // fail the start after the microphone is already open.
            if settings.speechEnhancementEnabled, let enhancer {
                do {
                    try await enhancer.begin()
                    enhancementActive = true
                } catch {
                    enhancementActive = false
                    emit(.notice("Noise suppression is unavailable; using the raw microphone. \(error.localizedDescription)"))
                }
            }
            // Let Chromium/Electron build their Accessibility tree while the user
            // speaks; the microphone is already live.
            await inserter.prepareForInsertion()

            if !(await recognizer.isPrepared(profile: profile)) { transition(.warming) }
            try await withDeadline(modelDeadline, label: "model warm-up") {
                try await recognizer.warmUp(profile: profile)
            }
            try Task.checkCancellation()
            let recognition = try await withDeadline(modelDeadline, label: "recognition stream") {
                try await recognizer.makeStream(profile: profile, source: .mic)
            }
            recognitionStream = recognition

            // Inference runs on its own lane. A stalled call drops the oldest
            // queued audio instead of stopping capture, levels and journaling.
            let (feedStream, feed) = AsyncStream<AudioChunk>.makeStream(
                bufferingPolicy: .bufferingNewest(4096))
            recognitionFeed = feed
            recognitionDrainTask = Task {
                for await chunk in feedStream {
                    await feedRecognition(recognition, chunk: chunk)
                }
            }

            let eventContinuation = continuation
            let cleanup = SessionCleanupCoordinator(repository: repository, sessionID: newRecord.id,
                                                    emit: { event in
                eventContinuation.yield(event)
            })
            await cleanup.start(workerCount: settings.cleanupWorkers)
            cleanupCoordinator = cleanup
            try Task.checkCancellation()
            transition(.recording(mode))

            let id = newRecord.id
            recognitionTask = Task { [weak self] in
                await self?.consumeRecognition(recognition, session: id)
            }
            sampleTask = Task { [weak self] in
                await self?.consumeAudio(streams.samples, writer: journalWriter,
                                         archive: clip, feed: feed)
            }
            eventTask = Task { [weak self] in
                await self?.consumeAudioEvents(streams.events)
            }
            newRecord.status = .recording
            return id
        } catch {
            await cleanupCoordinator?.cancel()
            cleanupCoordinator = nil
            await audio.stop()
            recognitionFeed?.finish()
            recognitionFeed = nil
            recognitionDrainTask?.cancel()
            recognitionDrainTask = nil
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
        if let sampleTask {
            let task = sampleTask
            _ = try? await withDeadline(finishDeadline, label: "capture drain") { await task.value }
            task.cancel()
        }
        sampleTask = nil
        recognitionFeed?.finish()
        recognitionFeed = nil
        if let recognitionDrainTask {
            let task = recognitionDrainTask
            _ = try? await withDeadline(finishDeadline, label: "recognition drain") { await task.value }
            task.cancel()
        }
        recognitionDrainTask = nil
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

        if Task.isCancelled {
            await cancel()
            return nil
        }
        let cleanupState = await cleanupCoordinator?.finish() ?? .skipped
        cleanupCoordinator = nil
        let assembledText = await finalText(session: record.id)
        let text = assembledText ?? ""
        let words = wordCount(text)
        let duration = max(lastEndMs, Int(clock.now().timeIntervalSince(record.startedAt) * 1000))

        metrics.record("session.stop.ms", valueMs: Double((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000))

        var insertion: InsertionOutcome?
        guard self.record?.id == record.id else { return nil }
        if Task.isCancelled {
            await cancel()
            return nil
        }
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
        if let insertion, case .permissionRequired = insertion {
            pendingInsertion = text
        }

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

        var finalized = false
        if assembledText != nil {
            let finalizeStarted = DispatchTime.now().uptimeNanoseconds
            do {
                try await repository.finalizeSession(record.id, endedAt: clock.now(), status: .complete,
                                                      durationMs: duration, wordCount: words,
                                                      cleanupState: cleanupState)
                finalized = true
            } catch {
                emit(.notice("Could not finalize the session in History: \(error.localizedDescription)"))
            }
            metrics.record("session.finalize.ms",
                           valueMs: Double((DispatchTime.now().uptimeNanoseconds - finalizeStarted) / 1_000_000))
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
        await speculative.cancel()
        sampleTask?.cancel()
        recognitionTask?.cancel()
        recognitionFeed?.finish()
        recognitionFeed = nil
        recognitionDrainTask?.cancel()
        recognitionDrainTask = nil
        eventTask?.cancel()
        await cleanupCoordinator?.cancel()
        cleanupCoordinator = nil
        await audio.stop()
        await recognitionStream?.finish()
        _ = await writer?.close()
        let duration = record.map { max(lastEndMs, Int(clock.now().timeIntervalSince($0.startedAt) * 1000)) } ?? 0
        let keep = settings.keepAudio && !settings.noTranscriptStorage && duration > 30_000
        let archived = keep ? await archiveWriter?.finish() : nil
        if !keep { await archiveWriter?.discard() }
        archiveWriter = nil
        if let id {
            if let archived {
                if let metadata = repository as? any AudioMetadataStore {
                    try? await metadata.setAudio(session: id, duration: archived.duration, peaks: Data(archived.peaks))
                }
                try? await repository.finalizeSession(id, endedAt: clock.now(), status: .cancelled,
                                                     durationMs: duration, wordCount: 0, cleanupState: .skipped)
            } else {
                await archive?.delete(session: id)
                try? await repository.deleteSession(id)
            }
            await journals.delete(session: id)
            emit(.finished(id, .cancelled))
        }
        sampleTask = nil
        recognitionTask = nil
        eventTask = nil
        record = nil
        resetBuffers()
    }

    func consumeRecognition(_ stream: any RecognitionStream, session: SessionID) async {
        for await event in stream.events {
            switch event {
            case .partial(let text):
                emit(.partial(text))
                await speculate(text, session: session)
            case .committed(let segment):
                await persist(segment, session: session)
            case .endpoint:
                break
            case .failure(let message):
                emit(.notice("Recognition problem: \(message)"))
            }
        }
    }

    func persist(_ raw: RawSegment, session: SessionID) async {
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
        let revision = pipelineRevision
        var precomputed = speculativeCleanupEnabled && index == 0 && interactive && raw.words.isEmpty
            ? await speculative.take(.init(session: session, revision: revision, text: raw.text)) : nil
        if revision != pipelineRevision { precomputed = nil }
        await cleanupCoordinator?.submit(index: index, interactive: interactive,
                                          pipeline: pipeline, settings: settings,
                                          project: project, wordTimings: raw.words, precomputed: precomputed)
    }

}
