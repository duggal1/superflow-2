import Foundation
import SuperflowKernel
import SuperflowPorts

enum DashboardDictationStats {
    static func load(repository: any TranscriptRepository, calendar: Calendar, now: Date) async throws -> [DailyStat] {
        let pageSize = 500
        var offset = 0
        var days: [String: DailyStat] = [:]
        while true {
            let sessions = try await repository.sessions(kind: .dictation, query: nil,
                                                         limit: pageSize, offset: offset)
            for session in sessions where session.startedAt <= now &&
                session.status != .recording && session.status != .finalizing {
                let day = LocalDay.string(for: session.startedAt, calendar: calendar)
                var stat = days[day] ?? DailyStat(day: day, words: 0, audioMs: 0, sessions: 0)
                stat.words += session.wordCount
                stat.audioMs += session.durationMs
                stat.sessions += 1
                days[day] = stat
            }
            guard sessions.count == pageSize else { break }
            offset += sessions.count
        }
        return days.values.sorted { $0.day < $1.day }
    }
}
