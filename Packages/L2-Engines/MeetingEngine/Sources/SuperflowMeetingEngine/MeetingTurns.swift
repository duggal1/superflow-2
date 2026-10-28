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
        try? await repository.appendSegment(row)
        try? await repository.upsertSpeaker(SpeakerRecord(sessionID: session, id: speakerID,
                                                         label: speakerName,
                                                         isSelf: speakerID == "self"))
        if duplicate {
            await drop(index, session: session)
            return
        }
        if source == .system {
            await dropOverlappingMicTurns(turn, session: session)
        }
        let context = TextContext(source: source, speakerID: speakerID, interactive: false,
                                  settings: settings, project: project)
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
        try? await repository.updateCleaned(session: session, index: index, cleaned: text,
                                            state: result.draft.cleanupState)
    }

    func addGap(_ message: String, atMs: Int, session: SessionID) async {
        let index = nextIndex
        nextIndex += 1
        lastEndMs = max(lastEndMs, atMs)
        let turn = MeetingTurn(index: index, speakerID: "system", speakerName: "System audio",
                               startMs: atMs, endMs: atMs, text: message, rawText: message,
                               source: .system, isGap: true)
        appendResident(turn)
        try? await repository.appendSegment(Segment(sessionID: session, index: index,
                                                    startMs: atMs, endMs: atMs,
                                                    speakerID: "system", source: .system,
                                                    rawText: message, cleanedText: "",
                                                    cleanupState: .skipped))
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

    func isDuplicate(_ candidate: MeetingTurn) -> Bool {
        residentTurns.contains { existing in
            guard !existing.isGap, existing.source != candidate.source else { return false }
            return overlapRatio(existing, candidate) > 0.5 &&
                MeetingTextSimilarity.ratio(existing.rawText, candidate.rawText) > 0.8
        }
    }

    func dropOverlappingMicTurns(_ systemTurn: MeetingTurn, session: SessionID) async {
        let matches = residentTurns.filter { turn in
            turn.source == .mic && !turn.isGap &&
                overlapRatio(turn, systemTurn) > 0.5 &&
                MeetingTextSimilarity.ratio(turn.rawText, systemTurn.rawText) > 0.8
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
        try? await repository.updateCleaned(session: session, index: index, cleaned: "",
                                            state: .skipped)
        trimDroppedIndexes()
    }

    func overlapRatio(_ a: MeetingTurn, _ b: MeetingTurn) -> Double {
        let overlap = max(0, min(a.endMs, b.endMs) - max(a.startMs, b.startMs))
        let shortest = max(1, min(a.endMs - a.startMs, b.endMs - b.startMs))
        return Double(overlap) / Double(shortest)
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
