import Foundation
import SuperflowKernel

/// The two nullable audio columns, kept out of `TranscriptRepository` so a test
/// double can save transcripts without pretending to archive audio.
public protocol AudioMetadataStore: Sendable {
    func setAudio(session: SessionID, duration: TimeInterval, peaks: Data) async throws
    func clearAudio(session: SessionID) async throws
    func sessionsWithAudio() async throws -> [SessionID]
}

public protocol TranscriptRepository: Sendable {
    func createSession(_ s: SessionRecord) async throws
    func appendSegment(_ s: Segment) async throws
    func updateCleaned(session: SessionID, index: Int, cleaned: String?, state: CleanupState) async throws
    func finalizeSession(_ id: SessionID, endedAt: Date, status: SessionStatus, durationMs: Int,
                         wordCount: Int, cleanupState: CleanupState) async throws
    func sessions(kind: SessionKind?, query: String?, limit: Int, offset: Int) async throws -> [SessionRecord]
    func renameSession(_ id: SessionID, title: String) async throws
    func session(_ id: SessionID) async throws -> SessionRecord?
    func segment(session: SessionID, index: Int) async throws -> Segment?
    func segments(session: SessionID) async throws -> [Segment]
    func segmentForProcessing(session: SessionID, index: Int) async throws -> Segment?
    func segmentsForProcessing(session: SessionID) async throws -> [Segment]
    func transcriptTextForProcessing(session: SessionID) async throws -> String
    func deleteSession(_ id: SessionID) async throws
    func upsertSpeaker(_ s: SpeakerRecord) async throws
    func speakers(session: SessionID) async throws -> [SpeakerRecord]
    func renameSpeaker(session: SessionID, id: String, label: String) async throws
    func dailyStats(fromDay: String, toDay: String) async throws -> [DailyStat]
    func addDailyStat(_ s: DailyStat) async throws
    func unfinishedSessions() async throws -> [SessionRecord]
    func purge(olderThan: Date) async throws -> Int
    func sessionCount(kind: SessionKind?) async throws -> Int
}

public extension TranscriptRepository {
    func segmentForProcessing(session: SessionID, index: Int) async throws -> Segment? {
        try await segment(session: session, index: index)
    }

    func segmentsForProcessing(session: SessionID) async throws -> [Segment] {
        try await segments(session: session)
    }

    func transcriptTextForProcessing(session: SessionID) async throws -> String {
        let segments = try await segmentsForProcessing(session: session)
        var text = ""
        for segment in segments.sorted(by: { $0.index < $1.index }) {
            let value = segment.bestText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if !text.isEmpty { text.append(contentsOf: "\n\n") }
            text.append(contentsOf: value)
        }
        return text
    }
}

public protocol LibraryRepository: Sendable {
    func lexicon() async throws -> [LexiconEntry]
    func saveLexicon(_ e: LexiconEntry) async throws
    func deleteLexicon(id: String) async throws
    func shortcuts() async throws -> [ShortcutEntry]
    func saveShortcut(_ e: ShortcutEntry) async throws
    func deleteShortcut(id: String) async throws
}

public protocol SettingsStore: Sendable {
    func load() async -> AppSettings
    func save(_ s: AppSettings) async
}

public protocol ModelProvider: ASRModelProvider, Sendable {
    func localURL(for profileID: String) async -> URL?
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
    func llmModelURL() async -> URL?
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

public extension ModelProvider {
    func isAvailable(profileID: String) async -> Bool {
        await localURL(for: profileID) != nil
    }

    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await ensure(profileID: profileID, progress: progress)
    }
}

public protocol DiagnosticsExporting: Sendable {
    func exportDiagnostics(to url: URL) async throws
}
