import Foundation
import SuperflowKernel
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

    func testGreetingBoundaries() {
        XCTAssertEqual(DashboardCopy.greeting(name: "Harshit", hour: 5), "Good morning, Harshit.")
        XCTAssertEqual(DashboardCopy.greeting(name: "Harshit", hour: 11), "Good morning, Harshit.")
        XCTAssertEqual(DashboardCopy.greeting(name: "Harshit", hour: 12), "Good afternoon, Harshit.")
        XCTAssertEqual(DashboardCopy.greeting(name: "Harshit", hour: 17), "Good evening, Harshit.")
        XCTAssertEqual(DashboardCopy.greeting(name: "Harshit", hour: 23), "Still up, Harshit.")
    }

    /// A name appears only when the user set one; the default is "You".
    func testGreetingWithoutASetNameHasNoName() {
        XCTAssertEqual(DashboardCopy.greeting(name: "  ", hour: 9), "Good morning.")
        XCTAssertEqual(DashboardCopy.greeting(name: "You", hour: 9), "Good morning.")
        XCTAssertEqual(DashboardCopy.greeting(name: "you", hour: 21), "Good evening.")
    }

    func testLoadAggregatesStatsAndContributions() async throws {
        let repository = InMemoryRepository()
        try await repository.addDailyStat(DailyStat(day: "2026-03-14", words: 100,
                                                    audioMs: 30_000, sessions: 1))
        try await repository.addDailyStat(DailyStat(day: "2026-03-15", words: 300,
                                                    audioMs: 30_000, sessions: 2))
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
        XCTAssertEqual(model.contributions.count, 371)
        XCTAssertTrue(model.hasActivity)
    }

    func testEmptyRepositoryHasNoActivity() async throws {
        let model = DashboardViewModel(repository: InMemoryRepository(), calendar: calendar,
                                       now: { self.now })
        await model.load()
        XCTAssertFalse(model.hasActivity)
        XCTAssertEqual(model.wordsLabel, "0")
        XCTAssertEqual(model.speedLabel, "—")
        XCTAssertEqual(model.streakLabel, "0 days")
        XCTAssertEqual(model.contributions.count, 371)
    }

    func testUpdateSettingsRecomputesSummaryWithoutReloading() async throws {
        let repository = InMemoryRepository()
        try await repository.addDailyStat(DailyStat(day: "2026-03-15", words: 200,
                                                    audioMs: 60_000, sessions: 1))
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
