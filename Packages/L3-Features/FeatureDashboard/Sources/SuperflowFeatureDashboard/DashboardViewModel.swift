import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowStatsEngine
import SuperflowUIComponents
import SwiftUI

public enum DashboardCopy {
    /// The greeting uses a name only when the user actually set one. The default
    /// display name is "You", which reads as not set.
    public static func greeting(name: String, hour: Int) -> String {
        let salutation: String
        switch hour {
        case 5..<12: salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        case 17..<22: salutation = "Good evening"
        default: salutation = "Still up"
        }
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty, who.caseInsensitiveCompare("You") != .orderedSame else {
            return "\(salutation)."
        }
        return "\(salutation), \(who)."
    }
}

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var summary = StatsSummary()
    @Published public private(set) var activity: [ActivityDay] = []
    @Published public private(set) var insights: DashboardInsights = .empty
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    /// The physical fn key. The cleanup keycap goes down with it.
    @Published public private(set) var isFnHeld = false

    public let recent: RecentDictationViewModel
    @Published public var usageRange: UsageRange = .week
    @Published public private(set) var usage: [AppUsage] = []

    private let repository: any TranscriptRepository
    private let calendar: Calendar
    private let now: () -> Date
    public private(set) var settings: AppSettings

    public init(repository: any TranscriptRepository, settings: AppSettings = .default,
                calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.recent = RecentDictationViewModel(repository: repository)
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    public func setFnHeld(_ held: Bool) {
        guard isFnHeld != held else { return }
        isFnHeld = held
    }

    public func update(settings: AppSettings) {
        self.settings = settings
        summary = StatsEngine.summary(daily: dailyCache, typingWPM: settings.typingWPM,
                                      today: now(), calendar: calendar)
    }

    private var dailyCache: [DailyStat] = []

    public func load() async {
        isLoading = true
        error = nil
        await recent.load(settings: settings)
        await loadUsage()
        defer { isLoading = false }
        let today = calendar.startOfDay(for: now())
        guard let start = calendar.date(byAdding: .day, value: -364, to: today) else { return }
        let from = LocalDay.string(for: start, calendar: calendar)
        let to = LocalDay.string(for: today, calendar: calendar)
        do {
            let daily = try await repository.dailyStats(fromDay: from, toDay: to)
            dailyCache = daily
            summary = StatsEngine.summary(daily: daily, typingWPM: settings.typingWPM,
                                          today: now(), calendar: calendar)
            let end = calendar.startOfDay(for: now())
            guard let start = calendar.date(byAdding: .day, value: -364, to: end) else { return }
            let wordsByDay = Dictionary(daily.map { ($0.day, $0.words) }, uniquingKeysWith: +)
            var words: [Int] = []
            var dates: [Date] = []
            for offset in 0..<365 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                dates.append(date)
                let key = LocalDay.string(for: date, calendar: calendar)
                words.append(wordsByDay[key] ?? 0)
            }
            let levels = ActivityLevel.assign(words)
            activity = zip(dates, zip(words, levels)).map { d, wl in
                ActivityDay(date: d, words: wl.0, level: wl.1)
            }
            insights = await DashboardInsightsLoader.load(repository: repository,
                                                          now: now(),
                                                          calendar: calendar)
        } catch {
            self.error = "Could not load your stats. \(error.localizedDescription)"
        }
    }

    public func loadUsage() async {
        guard !settings.noTranscriptStorage else { usage = []; return }
        do {
            usage = try await DashboardUsageLoader.load(repository: repository, range: usageRange, now: now(), calendar: calendar)
        } catch {
            usage = []
            self.error = "Could not load app usage."
        }
    }

    public var greeting: String {
        let hour = calendar.component(.hour, from: now())
        return DashboardCopy.greeting(name: settings.displayName, hour: hour)
    }

    public var subtitle: String {
        let n = summary.todayWords
        let word = n == 1 ? "word" : "words"
        return "\(n) \(word) today. Meetings stay out of these numbers."
    }

    public var hasActivity: Bool { summary.totalSessions > 0 }

    /// The archived clip for the newest dictation, when the archive kept one.
    /// The file is the source of truth: a row can outlive a swept clip.
    public var latestAudioURL: URL? {
        guard let id = insights.latest?.sessionID else { return nil }
        let url = AudioArchiveLocation.url(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The entrance stagger runs once after launch, not on every route change.
    public private(set) var hasAppeared = false

    public func markAppeared() {
        hasAppeared = true
    }

    // Names the dashboard reads. The labels above stay for other callers.
    public var words: String { wordsLabel }
    public var timeSaved: String { timeSavedLabel }
    public var speed: String { speedLabel }
    public var streak: String { streakLabel }
    public var sessionsNote: String { sessionsLabel }
    public var todayNote: String { todayLabel }

    public var wordsLabel: String { summary.totalWords.formatted() }
    public var timeSavedLabel: String { summary.timeSavedLabel }
    public var speedLabel: String {
        summary.averageWPM > 0 ? "\(Int(summary.averageWPM.rounded())) wpm" : "—"
    }
    public var streakLabel: String {
        summary.currentStreak == 1 ? "1 day" : "\(summary.currentStreak) days"
    }
    public var todayLabel: String {
        summary.todayWords == 1 ? "1 word today" : "\(summary.todayWords.formatted()) words today"
    }
    /// `daily_stats.sessions` is a running counter, and deleting a session writes
    /// `sessions: -1` into the row for that day (HistoryViewModel.deleteSelected).
    /// Deleting a session that predates the 365-day window — or deleting without a
    /// matching increment — drives the column below zero, and StatsEngine sums it.
    /// The count is clamped here, so the ledger can never read "-1 sessions".
    public var sessionsLabel: String {
        let n = max(summary.totalSessions, 0)
        return "\(n) \(n == 1 ? "session" : "sessions")"
    }
}
