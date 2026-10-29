import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureDashboard

@MainActor
final class DashboardViewModelTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private var now = Date()

    override func setUp() async throws {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 12
        now = calendar.date(from: components)!
    }

    private func seed(_ repository: InMemoryRepository, day: String, words: Int,
                      audioMs: Int, sessions: Int) async throws {
        let date = try XCTUnwrap(LocalDay.date(from: day, calendar: calendar))
        for index in 0..<sessions {
            try await repository.createSession(SessionRecord(kind: .dictation, startedAt: date,
                status: .complete, modelProfile: "test", durationMs: index == 0 ? audioMs : 0,
                wordCount: index == 0 ? words : 0))
        }
    }

    func testGreetingBoundaries() {
        XCTAssertEqual(DashboardCopy.greeting(name: "Harshit", hour: 5), "Good morning, Harshit.")
        XCTAssertEqual(DashboardCopy.greeting(name: "Harshit", hour: 11), "Good morning, Harshit.")
        XCTAssertEqual(DashboardCopy.greeting(name: "Harshit", hour: 12), "Good afternoon, Harshit.")
        XCTAssertEqual(DashboardCopy.greeting(name: "Harshit", hour: 17), "Good evening, Harshit.")
        XCTAssertEqual(DashboardCopy.greeting(name: "Harshit", hour: 23), "Still up, Harshit.")
    }

    func testStatsUseAllDictationsAndCurrentLocalDays() async throws {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let repository = InMemoryRepository()
        let midnightBoundary = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 15, hour: 2)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 15, hour: 10)))
        let old = try XCTUnwrap(calendar.date(byAdding: .day, value: -400, to: today))
        for (id, kind, date, words) in [("yesterday", SessionKind.dictation, midnightBoundary, 10),
                                        ("today", .dictation, today, 20),
                                        ("old", .dictation, old, 25),
                                        ("meeting", .meeting, today, 900)] {
            try await repository.createSession(SessionRecord(id: SessionID(id), kind: kind,
                startedAt: date, status: .complete, modelProfile: "test",
                durationMs: 60_000, wordCount: words, localDay: "wrong-day"))
        }
        let model = DashboardViewModel(repository: repository, calendar: localCalendar, now: { self.now })
        await model.load()
        XCTAssertEqual(model.summary.totalWords, 55)
        XCTAssertEqual(model.summary.totalSessions, 3)
        XCTAssertEqual(model.summary.todayWords, 20)
        XCTAssertEqual(model.summary.currentStreak, 2)
        XCTAssertEqual(model.activity.suffix(2).map(\.words), [10, 20])
        XCTAssertEqual(model.summary.averageWPM, 55.0 / 3.0, accuracy: 0.001)
    }

    /// A name appears only when the user set one; the default is "You".
    func testGreetingWithoutASetNameHasNoName() {
        XCTAssertEqual(DashboardCopy.greeting(name: "  ", hour: 9), "Good morning.")
        XCTAssertEqual(DashboardCopy.greeting(name: "You", hour: 9), "Good morning.")
        XCTAssertEqual(DashboardCopy.greeting(name: "you", hour: 21), "Good evening.")
    }

    func testLoadAggregatesStatsAndActivity() async throws {
        let repository = InMemoryRepository()
        try await seed(repository, day: "2026-03-14", words: 100, audioMs: 30_000, sessions: 1)
        try await seed(repository, day: "2026-03-15", words: 300, audioMs: 30_000, sessions: 2)
        var settings = AppSettings.default
        settings.displayName = "Harshit"
        settings.typingWPM = 40
        let model = DashboardViewModel(repository: repository, settings: settings,
                                       calendar: calendar, now: { self.now })
        await model.load()

        XCTAssertNil(model.error)
        XCTAssertEqual(model.summary.totalWords, 400)
        XCTAssertEqual(model.summary.totalSessions, 3)
        XCTAssertEqual(model.summary.currentStreak, 2)
        XCTAssertEqual(model.timeSavedLabel, "9m")
        XCTAssertEqual(model.speedLabel, "400 wpm")
        XCTAssertEqual(model.streakLabel, "2 days")
        XCTAssertEqual(model.todayLabel, "300 words today")
        XCTAssertEqual(model.sessionsLabel, "3 sessions")
        // The year is 365 days, oldest first, ending on today.
        XCTAssertEqual(model.activity.count, 365)
        XCTAssertEqual(model.activity.last?.date, calendar.startOfDay(for: now))
        XCTAssertTrue(model.hasActivity)
    }

    func testLegacyLedgerDoesNotCreatePhantomSessions() async throws {
        let repository = InMemoryRepository()
        try await repository.addDailyStat(DailyStat(day: "2026-03-15", words: 10,
                                                    audioMs: 1_000, sessions: -4))
        let model = DashboardViewModel(repository: repository, calendar: calendar,
                                       now: { self.now })
        await model.load()
        XCTAssertEqual(model.summary.totalSessions, 0)
        XCTAssertEqual(model.sessionsLabel, "0 sessions")
    }

    func testOneSessionReadsInTheSingular() async throws {
        let repository = InMemoryRepository()
        try await seed(repository, day: "2026-03-15", words: 10, audioMs: 1_000, sessions: 1)
        let model = DashboardViewModel(repository: repository, calendar: calendar,
                                       now: { self.now })
        await model.load()
        XCTAssertEqual(model.sessionsLabel, "1 session")
    }

    func testEmptyRepositoryHasNoActivity() async throws {
        let model = DashboardViewModel(repository: InMemoryRepository(), calendar: calendar,
                                       now: { self.now })
        await model.load()
        XCTAssertFalse(model.hasActivity)
        XCTAssertEqual(model.wordsLabel, "0")
        XCTAssertEqual(model.speedLabel, "—")
        XCTAssertEqual(model.streakLabel, "0 days")
        XCTAssertEqual(model.activity.count, 365)
        XCTAssertTrue(model.activity.allSatisfy { $0.words == 0 && $0.level == 0 })
    }

    /// The dashboard is open while a dictation finishes; it must follow the
    /// repository's change signal instead of waiting for the next visit.
    func testLedgerChangeRefreshesAnOpenDashboard() async throws {
        let repository = InMemoryRepository()
        let model = DashboardViewModel(repository: repository, calendar: calendar,
                                       now: { self.now })
        await model.load()
        XCTAssertEqual(model.summary.totalWords, 0)

        try await seed(repository, day: "2026-03-15", words: 42, audioMs: 1_000, sessions: 1)
        // The store posts this after every write; the double stays passive.
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
        var waited = 0
        while model.summary.totalWords == 0 && waited < 100 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        XCTAssertEqual(model.summary.totalWords, 42)
        XCTAssertEqual(model.summary.totalSessions, 1)
    }

    func testUpdateSettingsRecomputesSummaryWithoutReloading() async throws {
        let repository = InMemoryRepository()
        try await seed(repository, day: "2026-03-15", words: 200, audioMs: 60_000, sessions: 1)
        var settings = AppSettings.default
        settings.typingWPM = 40
        let model = DashboardViewModel(repository: repository, settings: settings,
                                       calendar: calendar, now: { self.now })
        await model.load()
        XCTAssertEqual(model.timeSavedLabel, "4m")

        settings.typingWPM = 20
        model.update(settings: settings)
        XCTAssertEqual(model.timeSavedLabel, "9m")
    }

    func testGreetingUsesConfiguredName() async throws {
        let repository = InMemoryRepository()
        var settings = AppSettings.default
        settings.displayName = "Priya"
        let model = DashboardViewModel(repository: repository, settings: settings,
                                       calendar: calendar, now: { self.now })
        XCTAssertEqual(model.greeting, "Good afternoon, Priya.")
    }
}
