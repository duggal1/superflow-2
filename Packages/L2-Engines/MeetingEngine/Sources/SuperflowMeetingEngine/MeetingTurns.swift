import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

extension MeetingEngine {
    func persist(_ raw: RawSegment, source: AudioSourceKind, session: SessionID) async {
        guard state == .warming || state == .recording || state == .finalizing else { return }
        let index = nextIndex
        nextIndex += 1
        let sharedStart = source == .system ? raw.startMs + systemOffsetMs : raw.startMs
        let sharedEnd = source == .system ? raw.endMs + systemOffsetMs : raw.endMs
        lastEndMs = max(lastEndMs, sharedEnd)
        let speakerID = source == .mic ? "self" : await speakerID(atLocalMs: raw.startMs)
        let speakerName = label(for: speakerID)
        let turn = MeetingTurn(index: index, speakerID: speakerID, speakerName: speakerName,
                               startMs: sharedStart, endMs: sharedEnd, text: raw.text,
                               rawText: raw.text, source: source)
        let duplicate = source == .mic && isDuplicate(turn)
        if !duplicate { appendResident(turn) }
        let row = Segment(sessionID: session, index: index, startMs: sharedStart, endMs: sharedEnd,
                          speakerID: speakerID, source: source, rawText: raw.text,
                          cleanupState: .pending)
        do {
            try await repository.appendSegment(row)
            try await repository.upsertSpeaker(SpeakerRecord(sessionID: session, id: speakerID,
                                                              label: speakerName, isSelf: speakerID == "self"))
        } catch { persistenceFailed = true }
        if duplicate {
            await drop(index, session: session)
            return
        }
        if source == .system {
            await dropOverlappingMicTurns(turn, session: session)
        }
        let context = TextContext(source: source, speakerID: speakerID, interactive: false,
                                  settings: settings, project: project, wordTimings: raw.words)
        pipelineTasks[index] = Task { [weak self, pipeline] in
            let result = await pipeline.run(raw.text, context: context)
            guard !Task.isCancelled else { return }
            await self?.resolve(index: index, result: result, session: session)
        }
    }

    func resolve(index: Int, result: PipelineResult, session: SessionID) async {
        pipelineTasks.removeValue(forKey: index)
        guard !droppedIndexes.contains(index) else { return }
        let text = result.draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // The pipeline never invents empty text for non-empty input, but a defensive guard
        // avoids turning a real segment into the dropped sentinel.
        guard !text.isEmpty else { return }
        if let position = residentTurns.firstIndex(where: { $0.index == index }) {
            residentTurns[position].text = text
        }
        do {
            try await repository.updateCleaned(session: session, index: index, cleaned: text,
                                               state: result.draft.cleanupState)
        } catch { persistenceFailed = true }
    }

    /// Inserts one explicit marker per lost source. The bracketed raw text is the durable marker:
    /// `MeetingDocumentProjection` recognizes it in both the live window and a repository rebuild.
    /// A second failure on the same source adds another notice but not a duplicate marker.
    func addGap(_ message: String, atMs: Int, session: SessionID,
                source: AudioSourceKind = .system) async {
        guard !lostStreams.contains(source) else { return }
        lostStreams.insert(source)
        let index = nextIndex
        nextIndex += 1
        lastEndMs = max(lastEndMs, atMs)
        let marker = MeetingStreamLoss.marker(message)
        let speakerID = source == .system ? MeetingDocumentProjection.gapSpeakerID : "mic"
        let speakerName = source == .system ? MeetingDocumentProjection.gapSpeakerName : AudioSourceKind.mic.label
        let turn = MeetingTurn(index: index, speakerID: speakerID, speakerName: speakerName,
                               startMs: atMs, endMs: atMs, text: message, rawText: marker,
                               source: source, isGap: true)
        appendResident(turn)
        do {
            try await repository.appendSegment(Segment(sessionID: session, index: index,
                                                    startMs: atMs, endMs: atMs,
                                                    speakerID: speakerID, source: source,
                                                    rawText: marker, cleanedText: "",
                                                    cleanupState: .skipped))
        } catch { persistenceFailed = true }
    }

    /// A recogniser dying is a one-channel failure: keep that channel's journaled audio and the
    /// other channel's raw transcript, mark the loss, and still publish a complete document.
    func recognitionFailed(_ source: AudioSourceKind, reason: String, session: SessionID) async {
        let notice = "\(source.label) recognition problem: \(reason)"
        addNotice(notice)
        let message = source == .system
            ? MeetingStreamLoss.systemTranscriptLost
            : MeetingStreamLoss.micTranscriptLost
        await addGap(message, atMs: lastEndMs, session: session, source: source)
    }

    func speakerID(atLocalMs ms: Int) async -> String {
        guard let diarizer else { return "remote-1" }
        return await diarizer.speaker(atMs: ms) ?? "remote-1"
    }

    func label(for id: String) -> String {
        if id == "self" {
            return settings.displayName.isEmpty ? "You" : settings.displayName
        }
        if let name = speakerNames[id] { return name }
        if let suffix = id.split(separator: "-").last, let number = Int(suffix) {
            return "Speaker \(number)"
        }
        return id
    }

    var systemOffsetMs: Int {
        Int(systemOffsetSamples * 1000 / Int64(sampleRate))
    }

    /// Both arrival orders use the same gate. A microphone turn is removed only when a system
    /// turn on the shared clock is time-aligned and its words match in order; simultaneous but
    /// different speech is always kept.
    func isDuplicate(_ candidate: MeetingTurn) -> Bool {
        guard candidate.source == .mic, !candidate.isGap else { return false }
        return residentTurns.contains { existing in
            MeetingEcho.isEcho(mic: candidate, system: existing)
        }
    }

    func dropOverlappingMicTurns(_ systemTurn: MeetingTurn, session: SessionID) async {
        let matches = residentTurns.filter {
            MeetingEcho.isEcho(mic: $0, system: systemTurn)
        }.map(\.index)
        for index in matches { await drop(index, session: session) }
    }

    /// Persists the drop so the repository-backed document can exclude the turn after the
    /// resident window has moved on. Cancelling the cleanup task prevents it from resurrecting
    /// the segment with cleaned text.
    func drop(_ index: Int, session: SessionID) async {
        droppedIndexes.insert(index)
        residentTurns.removeAll { $0.index == index }
        pipelineTasks.removeValue(forKey: index)?.cancel()
        do {
            try await repository.updateCleaned(session: session, index: index, cleaned: "", state: .skipped)
        } catch { persistenceFailed = true }
        trimDroppedIndexes()
    }

    func appendResident(_ turn: MeetingTurn) {
        residentTurns.append(turn)
        guard residentTurns.count > Self.residentTurnLimit else { return }
        let overflow = residentTurns.count - Self.residentTurnLimit
        let removed = Set(residentTurns.prefix(overflow).map(\.index))
        residentTurns.removeFirst(overflow)
        droppedIndexes.subtract(removed)
    }

    func trimDroppedIndexes() {
        guard droppedIndexes.count > Self.droppedIndexLimit else { return }
        droppedIndexes = Set(droppedIndexes.sorted().suffix(Self.droppedIndexLimit))
    }
}
