import Foundation
import SuperflowKernel
import SuperflowPorts

extension MeetingEngine {
    func startSource(_ source: AudioSourceKind, audio: any AudioSource,
                     session: SessionID) async throws {
        // The system lane is journaled on the shared meeting clock, so its writer starts at the
        // source's offset rather than 0. Disk-full here is a hard start failure: a lane that
        // cannot be journaled must never begin, or audio would be silently dropped.
        let offset = source == .system ? systemOffsetSamples : 0
        let writer = try await journals.openWriter(session: session, source: source,
                                                   startingSample: offset)
        writers[source] = writer
        let streams = try await audio.start()
        let recognition = try await recognizer.makeStream(profile: settings.asrProfile, source: source)
        recognitionStreams[source] = recognition
        recognitionTasks[source] = Task { [weak self] in
            await self?.consumeRecognition(recognition, source: source, session: session)
        }
        sampleTasks[source] = Task { [weak self] in
            await self?.consumeAudio(streams.samples, source: source, offset: offset,
                                     writer: writer, stream: recognition)
        }
        eventTasks[source] = Task { [weak self] in
            await self?.consumeEvents(streams.events, source: source, session: session)
        }
    }

    func audio(for source: AudioSourceKind) -> (any AudioSource)? {
        source == .mic ? mic : system
    }

    /// Rewrites the system source's local sample clock onto the shared meeting clock before
    /// journaling and recognition. The recognizer still receives the local clock so its segment
    /// boundaries stay stable; `persist` applies the same offset to committed timestamps.
    func consumeAudio(_ samples: AsyncStream<AudioChunk>, source: AudioSourceKind, offset: Int64,
                      writer: (any AudioJournalWriter)?, stream: any RecognitionStream) async {
        var counter = 0
        for await chunk in samples {
            let journalChunk = Self.offset(chunk, by: offset)
            await writer?.append(journalChunk)
            await stream.feed(chunk)
            if source == .system { await diarizer?.feed(chunk) }
            counter += 1
            if counter % 4 == 0 { emit(.level(source, Self.rms(chunk.samples))) }
        }
    }

    func consumeEvents(_ events: AsyncStream<AudioEvent>, source: AudioSourceKind,
                       session: SessionID) async {
        for await event in events {
            switch event {
            case .routeChanged:
                emit(.notice("\(source.label) route changed; capture rebuilt."))
            case .failed(let message):
                await sourceFailed(source, message: message, session: session)
            case .permissionRevoked:
                await sourceFailed(source, message: "\(source.label) permission was revoked.",
                                   session: session)
            case .stopped:
                break
            }
        }
    }

    func sourceFailed(_ source: AudioSourceKind, message: String, session: SessionID) async {
        addNotice(message)
        if source == .system, systemAvailable {
            systemAvailable = false
            await addGap("System audio lost", atMs: lastEndMs, session: session)
        }
    }

    func systemUnavailable(_ reason: String, session: SessionID) async {
        let message = "System audio unavailable: \(reason) Continuing with the microphone."
        addNotice(message)
        await addGap("System audio unavailable", atMs: 0, session: session)
    }

    func consumeRecognition(_ stream: any RecognitionStream, source: AudioSourceKind,
                            session: SessionID) async {
        for await event in stream.events {
            switch event {
            case .partial(let text):
                emit(.partial(source, text))
            case .committed(let segment):
                await persist(segment, source: source, session: session)
            case .endpoint:
                break
            case .failure(let message):
                emit(.notice("\(source.label) recognition problem: \(message)"))
            }
        }
    }

    /// Stops capture, drains recognition, closes journals, and waits for pending cleanup. Order
    /// matters: sample producers must stop before recognition streams are finished.
    func finishCapture() async {
        for source in sampleTasks.keys { await audio(for: source)?.stop() }
        for task in sampleTasks.values { await task.value }
        sampleTasks.removeAll()
        for stream in recognitionStreams.values { await stream.finish() }
        for task in recognitionTasks.values { await task.value }
        recognitionTasks.removeAll()
        for writer in writers.values { _ = await writer.close() }
        writers.removeAll()
        for task in eventTasks.values { task.cancel() }
        eventTasks.removeAll()
        await diarizer?.finish()
        for task in pipelineTasks.values { await task.value }
        pipelineTasks.removeAll()
    }

    static func offset(_ chunk: AudioChunk, by samples: Int64) -> AudioChunk {
        guard samples != 0 else { return chunk }
        return AudioChunk(samples: chunk.samples,
                          startSample: max(0, chunk.startSample + samples),
                          source: chunk.source)
    }
}
