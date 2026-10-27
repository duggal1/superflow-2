import Foundation
import SuperflowKernel

public struct StatsSummary: Sendable, Equatable {
    public var totalWords: Int
    public var totalAudioMs: Int
    public var totalSessions: Int
    public var timeSavedMs: Int
    public var averageWPM: Double
    public var currentStreak: Int
    public var longestStreak: Int
    public var todayWords: Int

    public init(totalWords: Int = 0, totalAudioMs: Int = 0, totalSessions: Int = 0,
                timeSavedMs: Int = 0, averageWPM: Double = 0, currentStreak: Int = 0,
                longestStreak: Int = 0, todayWords: Int = 0) {
        self.totalWords = totalWords
        self.totalAudioMs = totalAudioMs
        self.totalSessions = totalSessions
        self.timeSavedMs = timeSavedMs
        self.averageWPM = averageWPM
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.todayWords = todayWords
    }

    public var timeSavedLabel: String {
        let minutes = timeSavedMs / 60_000
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

public struct ContributionDay: Sendable, Equatable, Identifiable {
    public var day: String
    public var words: Int
    public var level: Int
    public var isFuture: Bool
    public var id: String { day }
    public init(day: String, words: Int, level: Int, isFuture: Bool) {
        self.day = day
        self.words = words
        self.level = level
        self.isFuture = isFuture
    }
}

/// Pure aggregates over daily_stats. O(365) for the grid regardless of history size.
public enum StatsEngine {
    public static func summary(daily: [DailyStat], typingWPM: Int = 40,
                               today: Date = Date(), calendar: Calendar = .current) -> StatsSummary {
        let words = daily.reduce(0) { $0 + $1.words }
        let audioMs = daily.reduce(0) { $0 + $1.audioMs }
        let sessions = daily.reduce(0) { $0 + $1.sessions }
        let wpm = max(1, typingWPM)
        let typingMs = Int((Double(words) / Double(wpm)) * 60_000)
        let saved = max(0, typingMs - audioMs)
        let speakingMinutes = Double(audioMs) / 60_000
        let average = speakingMinutes > 0 ? Double(words) / speakingMinutes : 0
        let active = Set(daily.filter { $0.sessions > 0 }.map(\.day))
        let todayKey = LocalDay.string(for: today, calendar: calendar)
        let todayWords = daily.first { $0.day == todayKey }?.words ?? 0
        return StatsSummary(totalWords: words, totalAudioMs: audioMs, totalSessions: sessions,
                            timeSavedMs: saved, averageWPM: average,
                            currentStreak: currentStreak(active: active, today: today, calendar: calendar),
                            longestStreak: longestStreak(active: active, calendar: calendar),
                            todayWords: todayWords)
    }

    public static func currentStreak(active: Set<String>, today: Date,
                                     calendar: Calendar = .current) -> Int {
        var cursor = calendar.startOfDay(for: today)
        if !active.contains(LocalDay.string(for: cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while active.contains(LocalDay.string(for: cursor, calendar: calendar)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    public static func longestStreak(active: Set<String>, calendar: Calendar = .current) -> Int {
        let dates = active.compactMap { LocalDay.date(from: $0, calendar: calendar) }
            .sorted()
        guard !dates.isEmpty else { return 0 }
        var best = 1
        var run = 1
        for i in 1..<dates.count {
            let gap = calendar.dateComponents([.day], from: dates[i - 1], to: dates[i]).day ?? 0
            if gap == 1 {
                run += 1
                best = max(best, run)
            } else if gap > 1 {
                run = 1
            }
        }
        return best
    }

    /// GitHub-style 53 x 7 grid. Days are Sunday-first; future cells in the current week are flagged.
    public static func contributions(daily: [DailyStat], endingOn: Date = Date(),
                                     calendar: Calendar = .current, weeks: Int = 53) -> [ContributionDay] {
        let safeWeeks = max(1, weeks)
        let end = calendar.startOfDay(for: endingOn)
        let weekday = calendar.component(.weekday, from: end)
        guard let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: end),
              let start = calendar.date(byAdding: .day, value: -7 * (safeWeeks - 1), to: startOfWeek)
        else { return [] }

        let wordsByDay = Dictionary(daily.map { ($0.day, $0.words) }, uniquingKeysWith: +)
        let positives = daily.map(\.words).filter { $0 > 0 }.sorted()
        let thresholds = quartiles(positives)
        var cells: [ContributionDay] = []
        cells.reserveCapacity(safeWeeks * 7)
        for offset in 0..<(safeWeeks * 7) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let key = LocalDay.string(for: date, calendar: calendar)
            let words = wordsByDay[key] ?? 0
            cells.append(ContributionDay(day: key, words: words, level: level(words, thresholds: thresholds),
                                         isFuture: date > end))
        }
        return cells
    }

    private static func quartiles(_ sorted: [Int]) -> (Int, Int, Int)? {
        guard let smallest = sorted.first, let largest = sorted.last, smallest != largest else { return nil }
        func pick(_ q: Double) -> Int {
            let index = Int(Double(sorted.count - 1) * q)
            return sorted[Swift.min(sorted.count - 1, Swift.max(0, index))]
        }
        return (pick(0.25), pick(0.5), pick(0.75))
    }

    private static func level(_ words: Int, thresholds: (Int, Int, Int)?) -> Int {
        guard words > 0 else { return 0 }
        guard let t = thresholds else { return 1 }
        return 1 + (words > t.0 ? 1 : 0) + (words > t.1 ? 1 : 0) + (words > t.2 ? 1 : 0)
    }
}
