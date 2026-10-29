import Foundation
import SuperflowKernel
import SuperflowPorts

public struct AppUsage: Identifiable, Equatable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public var words: Int
    public var sessions: Int
    public var seconds: TimeInterval

    public init(bundleID: String, words: Int, sessions: Int, seconds: TimeInterval) {
        self.bundleID = bundleID
        self.words = words
        self.sessions = sessions
        self.seconds = seconds
    }

    public static let examples = [
        AppUsage(bundleID: "com.google.Chrome", words: 1_840, sessions: 41, seconds: 1_020),
        AppUsage(bundleID: "com.microsoft.VSCode", words: 1_210, sessions: 29, seconds: 760),
        AppUsage(bundleID: "com.apple.Terminal", words: 640, sessions: 17, seconds: 380),
        AppUsage(bundleID: "com.apple.mail", words: 310, sessions: 9, seconds: 190),
    ]
}

public enum UsageRange: Hashable, Sendable, CaseIterable {
    case week, month, all

    public func since(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .week: calendar.date(byAdding: .day, value: -7, to: now)
        case .month: calendar.date(byAdding: .day, value: -30, to: now)
        case .all: nil
        }
    }
}

public enum DashboardUsageLoader {
    public static func load(repository: any TranscriptRepository, range: UsageRange,
                            now: Date = Date(), calendar: Calendar = .current) async throws -> [AppUsage] {
        let since = range.since(now: now, calendar: calendar)
        var aggregates: [String: AppUsage] = [:]
        var offset = 0
        let pageSize = 200
        while true {
            try Task.checkCancellation()
            let batch = try await repository.sessions(kind: .dictation, query: nil, limit: pageSize, offset: offset)
            guard !batch.isEmpty else { break }
            var pastWindow = false
            for session in batch {
                if let since, session.startedAt < since { pastWindow = true; continue }
                guard session.kind == .dictation, session.wordCount > 0,
                      let bundleID = session.frontmostBundleID, !bundleID.isEmpty else { continue }
                var app = aggregates[bundleID] ?? AppUsage(bundleID: bundleID, words: 0, sessions: 0, seconds: 0)
                app.words += session.wordCount
                app.sessions += 1
                app.seconds += Double(max(0, session.durationMs)) / 1_000
                aggregates[bundleID] = app
            }
            if pastWindow || batch.count < pageSize { break }
            offset += batch.count
        }
        return aggregates.values.sorted {
            $0.words == $1.words ? $0.bundleID < $1.bundleID : $0.words > $1.words
        }
    }
}
