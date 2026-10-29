import Foundation
import SuperflowKernel
import SuperflowPorts

public actor PrivacyRepository: TranscriptRepository {
    private let base: any TranscriptRepository
    private var suppressTranscripts: Bool
    private var ephemeralSegments: [SessionID: [Int: Segment]] = [:]

    public init(base: any TranscriptRepository, noTranscriptStorage: Bool = false) {
        self.base = base
        suppressTranscripts = noTranscriptStorage
    }

    public func setNoTranscriptStorage(_ enabled: Bool) {
        suppressTranscripts = enabled
    }

    public func createSession(_ session: SessionRecord) async throws {
        try await base.createSession(session)
    }

    public func renameSession(_ id: SessionID, title: String) async throws {
        try await base.renameSession(id, title: title)
    }

    public func appendSegment(_ segment: Segment) async throws {
        if suppressTranscripts {
            ephemeralSegments[segment.sessionID, default: [:]][segment.index] = segment
            return
        }
        try await base.appendSegment(segment)
    }

    public func updateCleaned(session: SessionID, index: Int, cleaned: String?,
                              state: CleanupState) async throws {
        if var segment = ephemeralSegments[session]?[index] {
            segment.cleanedText = cleaned
            segment.cleanupState = state
            ephemeralSegments[session]?[index] = segment
            return
        }
        try await base.updateCleaned(session: session, index: index, cleaned: cleaned, state: state)
    }

    public func finalizeSession(_ id: SessionID, endedAt: Date, status: SessionStatus,
                                durationMs: Int, wordCount: Int,
                                cleanupState: CleanupState) async throws {
        try await base.finalizeSession(id, endedAt: endedAt, status: status,
                                       durationMs: durationMs, wordCount: wordCount,
                                       cleanupState: cleanupState)
        ephemeralSegments[id] = nil
    }

    public func sessions(kind: SessionKind?, query: String?, limit: Int,
                         offset: Int) async throws -> [SessionRecord] {
        try await base.sessions(kind: kind, query: query, limit: limit, offset: offset)
    }

    public func session(_ id: SessionID) async throws -> SessionRecord? {
        try await base.session(id)
    }

    public func segment(session id: SessionID, index: Int) async throws -> Segment? {
        guard !suppressTranscripts else { return nil }
        return try await base.segment(session: id, index: index)
    }

    public func segmentForProcessing(session id: SessionID, index: Int) async throws -> Segment? {
        if let segment = ephemeralSegments[id]?[index] { return segment }
        return try await base.segment(session: id, index: index)
    }

    public func segments(session id: SessionID) async throws -> [Segment] {
        guard !suppressTranscripts else { return [] }
        return try await base.segments(session: id)
    }

    public func segmentsForProcessing(session id: SessionID) async throws -> [Segment] {
        let stored = try await base.segments(session: id)
        var byIndex = Dictionary(uniqueKeysWithValues: stored.map { ($0.index, $0) })
        for (index, segment) in ephemeralSegments[id] ?? [:] { byIndex[index] = segment }
        return byIndex.values.sorted { $0.index < $1.index }
    }

    public func transcriptTextForProcessing(session id: SessionID) async throws -> String {
        let segments = try await segmentsForProcessing(session: id)
        var text = ""
        for segment in segments {
            let value = segment.bestText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if !text.isEmpty { text.append(contentsOf: "\n\n") }
            text.append(contentsOf: value)
        }
        return text
    }

    public func deleteSession(_ id: SessionID) async throws {
        ephemeralSegments[id] = nil
        try await base.deleteSession(id)
    }

    public func upsertSpeaker(_ speaker: SpeakerRecord) async throws {
        guard !suppressTranscripts else { return }
        try await base.upsertSpeaker(speaker)
    }

    public func speakers(session id: SessionID) async throws -> [SpeakerRecord] {
        guard !suppressTranscripts else { return [] }
        return try await base.speakers(session: id)
    }

    public func renameSpeaker(session id: SessionID, id speakerID: String,
                              label: String) async throws {
        guard !suppressTranscripts else { return }
        try await base.renameSpeaker(session: id, id: speakerID, label: label)
    }

    public func dailyStats(fromDay: String, toDay: String) async throws -> [DailyStat] {
        try await base.dailyStats(fromDay: fromDay, toDay: toDay)
    }

    public func addDailyStat(_ stat: DailyStat) async throws {
        try await base.addDailyStat(stat)
    }

    public func unfinishedSessions() async throws -> [SessionRecord] {
        try await base.unfinishedSessions()
    }

    public func purge(olderThan date: Date) async throws -> Int {
        try await base.purge(olderThan: date)
    }

    public func sessionCount(kind: SessionKind?) async throws -> Int {
        try await base.sessionCount(kind: kind)
    }
}
