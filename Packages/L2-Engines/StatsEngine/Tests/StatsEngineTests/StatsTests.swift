import XCTest
import SuperflowKernel
@testable import SuperflowStatsEngine

final class StatsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> String {
        LocalDay.string(for: date(y, m, d), calendar: calendar)
    }

    func testEmptySummary() {
        let s = StatsEngine.summary(daily: [], today: date(2026, 10, 25), calendar: calendar)
        XCTAssertEqual(s, StatsSummary())
    }

    func testTotalsTimeSavedAndSpeed() {
        let daily = [
            DailyStat(day: day(2026, 10, 24), words: 200, audioMs: 120_000, sessions: 2),
            DailyStat(day: day(2026, 10, 25), words: 200, audioMs: 180_000, sessions: 1),
        ]
        let s = StatsEngine.summary(daily: daily, typingWPM: 40,
                                    today: date(2026, 10, 25), calendar: calendar)
        XCTAssertEqual(s.totalWords, 400)
        XCTAssertEqual(s.totalAudioMs, 300_000)
        XCTAssertEqual(s.totalSessions, 3)
        XCTAssertEqual(s.timeSavedMs, 300_000)
        XCTAssertEqual(s.averageWPM, 80, accuracy: 0.001)
        XCTAssertEqual(s.todayWords, 200)
        XCTAssertEqual(s.timeSavedLabel, "5m")
    }

    func testTimeSavedNeverNegative() {
        let daily = [DailyStat(day: day(2026, 10, 25), words: 10, audioMs: 600_000, sessions: 1)]
        let s = StatsEngine.summary(daily: daily, typingWPM: 40,
                                    today: date(2026, 10, 25), calendar: calendar)
        XCTAssertEqual(s.timeSavedMs, 0)
    }

    func testCurrentStreakIncludesToday() {
        let active: Set<String> = [day(2026, 10, 23), day(2026, 10, 24), day(2026, 10, 25)]
        XCTAssertEqual(StatsEngine.currentStreak(active: active, today: date(2026, 10, 25),
                                                 calendar: calendar), 3)
    }

    func testCurrentStreakFallsBackToYesterday() {
        let active: Set<String> = [day(2026, 10, 23), day(2026, 10, 24)]
        XCTAssertEqual(StatsEngine.currentStreak(active: active, today: date(2026, 10, 25),
                                                 calendar: calendar), 2)
    }

    func testCurrentStreakBreaksOnGap() {
        let active: Set<String> = [day(2026, 10, 22), day(2026, 10, 24), day(2026, 10, 25)]
        XCTAssertEqual(StatsEngine.currentStreak(active: active, today: date(2026, 10, 25),
                                                 calendar: calendar), 2)
    }

    func testLongestStreak() {
        let active: Set<String> = [
            day(2026, 9, 1), day(2026, 9, 2), day(2026, 9, 3), day(2026, 9, 4),
            day(2026, 10, 1), day(2026, 10, 2),
        ]
        XCTAssertEqual(StatsEngine.longestStreak(active: active, calendar: calendar), 4)
        XCTAssertEqual(StatsEngine.longestStreak(active: [], calendar: calendar), 0)
    }

    func testContributionGridShapeAndFuture() {
        let cells = StatsEngine.contributions(daily: [], endingOn: date(2026, 10, 25),
                                              calendar: calendar, weeks: 53)
        XCTAssertEqual(cells.count, 371)
        XCTAssertEqual(cells.first?.day, "2025-10-26")
        XCTAssertEqual(cells.last?.day, "2026-10-31")
        XCTAssertEqual(cells.filter(\.isFuture).count, 6)
        XCTAssertTrue(cells.allSatisfy { $0.level == 0 })
        let firstWeekday = calendar.component(.weekday, from: LocalDay.date(from: cells[0].day, calendar: calendar)!)
        XCTAssertEqual(firstWeekday, 1)
    }

    func testContributionLevels() {
        let daily = [
            DailyStat(day: day(2026, 10, 19), words: 10, audioMs: 0, sessions: 1),
            DailyStat(day: day(2026, 10, 20), words: 20, audioMs: 0, sessions: 1),
            DailyStat(day: day(2026, 10, 21), words: 30, audioMs: 0, sessions: 1),
            DailyStat(day: day(2026, 10, 22), words: 40, audioMs: 0, sessions: 1),
        ]
        let cells = StatsEngine.contributions(daily: daily, endingOn: date(2026, 10, 25),
                                              calendar: calendar, weeks: 2)
        let byDay = Dictionary(uniqueKeysWithValues: cells.map { ($0.day, $0) })
        XCTAssertEqual(byDay[day(2026, 10, 19)]?.level, 1)
        XCTAssertEqual(byDay[day(2026, 10, 20)]?.level, 2)
        XCTAssertEqual(byDay[day(2026, 10, 21)]?.level, 3)
        XCTAssertEqual(byDay[day(2026, 10, 22)]?.level, 4)
        XCTAssertEqual(byDay[day(2026, 10, 23)]?.level, 0)
    }

    func testContributionEqualValuesGetLowestPositiveLevel() {
        let daily = [
            DailyStat(day: day(2026, 10, 19), words: 7, audioMs: 0, sessions: 1),
            DailyStat(day: day(2026, 10, 20), words: 7, audioMs: 0, sessions: 1),
        ]
        let cells = StatsEngine.contributions(daily: daily, endingOn: date(2026, 10, 25),
                                              calendar: calendar, weeks: 2)
        let levels = Set(cells.filter { $0.words > 0 }.map(\.level))
        XCTAssertEqual(levels, [1])
    }

    func testGridIsO365AndDeterministic() {
        let daily = (0..<800).map { i in
            DailyStat(day: day(2024, 1, 1), words: i, audioMs: 0, sessions: 1)
        }
        let a = StatsEngine.contributions(daily: daily, endingOn: date(2026, 10, 25),
                                          calendar: calendar)
        let b = StatsEngine.contributions(daily: daily, endingOn: date(2026, 10, 25),
                                          calendar: calendar)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 371)
    }
}
