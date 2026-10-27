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
    @Published public private(set) var contributions: [ContributionGridDay] = []
    @Published public private(set) var insights: DashboardInsights = .empty
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?

    private let repository: any TranscriptRepository
    private let calendar: Calendar
    private let now: () -> Date
    public private(set) var settings: AppSettings

    public init(repository: any TranscriptRepository, settings: AppSettings = .default,
                calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.settings = settings
        self.calendar = calendar
        self.now = now
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
            contributions = StatsEngine.contributions(daily: daily, endingOn: now(),
                                                      calendar: calendar).map {
                ContributionGridDay(day: $0.day, words: $0.words, level: $0.level, isFuture: $0.isFuture)
            }
            insights = await DashboardInsightsLoader.load(repository: repository,
                                                          now: now(),
                                                          calendar: calendar)
        } catch {
            self.error = "Could not load your stats. \(error.localizedDescription)"
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
    public var levels: [ContributionGridDay] { contributions }

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
    public var sessionsLabel: String {
        summary.totalSessions == 1 ? "1 session" : "\(summary.totalSessions.formatted()) sessions"
    }
}
