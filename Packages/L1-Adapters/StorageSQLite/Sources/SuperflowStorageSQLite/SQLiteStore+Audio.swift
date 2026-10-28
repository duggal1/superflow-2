import Foundation
import SuperflowKernel
import SuperflowPorts

extension SQLiteStore {
    // MARK: audio

    public func setAudio(session: SessionID, duration: TimeInterval, peaks: Data) async throws {
        let statement = try db.prepare(
            "UPDATE sessions SET audio_duration = ?, audio_peaks = ? WHERE id = ?")
        try statement.bind([.real(duration), .blob(peaks), .text(session.value)])
        try statement.step()
    }

    public func clearAudio(session: SessionID) async throws {
        let statement = try db.prepare(
            "UPDATE sessions SET audio_duration = NULL, audio_peaks = NULL WHERE id = ?")
        try statement.bind([.text(session.value)])
        try statement.step()
    }

    public func sessionsWithAudio() async throws -> [SessionID] {
        let statement = try db.prepare(
            "SELECT id FROM sessions WHERE audio_duration IS NOT NULL ORDER BY started_at ASC")
        var ids: [SessionID] = []
        while try statement.step() {
            if let id = statement.text(0) { ids.append(SessionID(id)) }
        }
        return ids
    }

    static func segment(from statement: SQLiteStatement) -> Segment {
        Segment(
            sessionID: SessionID(statement.text(0) ?? ""),
            index: Int(statement.int(1)),
            startMs: Int(statement.int(2)),
            endMs: Int(statement.int(3)),
            speakerID: statement.text(4),
            source: AudioSourceKind(rawValue: statement.text(5) ?? "") ?? .mic,
            rawText: statement.text(6) ?? "",
            cleanedText: statement.text(7),
            cleanupState: CleanupState(rawValue: statement.text(8) ?? "") ?? .pending,
            createdAt: Date(timeIntervalSince1970: statement.double(9)))
    }
}
