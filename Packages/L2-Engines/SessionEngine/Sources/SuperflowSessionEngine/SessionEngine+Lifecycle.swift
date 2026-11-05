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
        do {
            try await withDeadline(modelDeadline, label: "model warm-up") {
                try await recognizer.warmUp(profile: profile)
            }
            return true
        } catch {
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
        captureStopRequested = false
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
        metrics.event("session.cleanup.start", [
            "enabled": String(settings.cleanupEnabled),
            "model": settings.reflectionCleanupEnabled ? "reflection" : "s1-mini",
        ])
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
            let feedStream = consumeCapture(streams, writer: journalWriter, archive: clip)
            if captureStopRequested { await audio.stop() }

            // AX preparation may require a slow Chromium accessibility tree.
            // It is an optional paste optimization, never a prerequisite for
            // streaming ASR. Begin it concurrently while the user speaks.
            Task { [inserter] in await inserter.prepareForInsertion() }

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
            recognitionDrainTask = Task {
                for await chunk in feedStream {
                    await feedRecognition(recognition, chunk: chunk)
                }
            }

            let eventContinuation = continuation
            let cleanup = SessionCleanupCoordinator(repository: repository, sessionID: newRecord.id,
                                                    metrics: metrics, emit: { event in
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
            newRecord.status = .recording
            return id
        } catch {
            await cleanupCoordinator?.cancel()
            cleanupCoordinator = nil
            await audio.stop()
            sampleTask?.cancel()
            await sampleTask?.value
            sampleTask = nil
            eventTask?.cancel()
            eventTask = nil
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
            emit(.finished(newRecord.id, .failed))
            record = nil
            throw error
        }
    }

    /// Drains capture and recognition, resolves every cleanup task, inserts the final text and
    /// finalizes the session. Returns nil when there is no active recording.
    public func stopCaptureWhileStarting() async {
        guard isStarting else { return }
        captureStopRequested = true
        await audio.stop()
    }

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
        let cleanupStarted = DispatchTime.now().uptimeNanoseconds
        let cleanupState = await cleanupCoordinator?.finish() ?? .skipped
        metrics.record("session.stop.cleanup_wait.ms",
                       valueMs: Double((DispatchTime.now().uptimeNanoseconds - cleanupStarted) / 1_000_000))
        cleanupCoordinator = nil
        // A delayed model cannot hold up paste, but raw ASR still deserves
        // deterministic dedupe, list/paragraph formatting and punctuation.
        // Save that fallback before assembling text for the target editor.
        if cleanupState == .fallback && !recognitionOverflow {
            await repairFallbackText(session: record.id)
        }
        metrics.event("session.cleanup.result", [
            "state": cleanupState.rawValue,
            "model": settings.reflectionCleanupEnabled ? "reflection" : "s1-mini",
        ])
        if settings.cleanupEnabled && cleanupState == .fallback {
            emit(.notice("S1-mini cleanup was unavailable; deterministic formatting was applied."))
        }
        let assembledText = recognitionOverflow ? nil : await finalText(session: record.id)
        let joined = assembledText ?? ""
        // The paragraph formatter trims each persisted block. A deliberately
        // enabled trailing space belongs to paste output, not stored history.
        let text = settings.lineFormat.trailingSpace && !joined.isEmpty && !joined.hasSuffix(" ")
            ? joined + " " : joined
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
            if words == 0 && !recognitionOverflow {
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
            transition(.failed(record.id, recognitionOverflow ? "Recognition failed or fell behind; recovery is required." : "Transcript could not be finalized."))
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

}
