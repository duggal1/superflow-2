import Foundation
import SuperflowKernel
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureDashboard

/// The lower half must aggregate the whole 90-day window. A single `sessions(...)`
/// call took only the newest page, so a heavy user's "Words by app" and "Your hours"
/// were silently short.
@MainActor
final class DashboardInsightsLoaderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 12
        return calendar.date(from: components)!
    }

    private func dictation(daysAgo: Int, hour: Int, bundle: String,
                           words: Int) -> SessionRecord {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return SessionRecord(kind: .dictation, startedAt: start, status: .complete,
                             frontmostBundleID: bundle, modelProfile: "test",
                             wordCount: words)
    }

    func testAggregateCoversTheWholeWindowNotOnePage() async throws {
        let repository = InMemoryRepository()
        let count = DashboardInsightsLoader.pageSize * 4 + 100
        for index in 0..<count {
            try await repository.createSession(dictation(daysAgo: index % 80,
                                                         hour: index % 24,
                                                         bundle: "app.\(index % 4)",
                                                         words: 10))
        }

        let insights = await DashboardInsightsLoader.load(repository: repository,
                                                          now: now, calendar: calendar)

        XCTAssertEqual(insights.hourly.count, 24)
        XCTAssertEqual(insights.hourly.reduce(0, +), count * 10,
                       "every session in the window must reach the aggregate")
        XCTAssertEqual(insights.topApps.map(\.bundleID).sorted(),
                       ["app.0", "app.1", "app.2", "app.3"])
    }

    func testSessionsOlderThanTheWindowAreExcluded() async throws {
        let repository = InMemoryRepository()
        try await repository.createSession(dictation(daysAgo: 5, hour: 9,
                                                     bundle: "app.recent", words: 10))
        try await repository.createSession(dictation(daysAgo: 400, hour: 9,
                                                     bundle: "app.old", words: 999))

        let insights = await DashboardInsightsLoader.load(repository: repository,
                                                          now: now, calendar: calendar)

        XCTAssertEqual(insights.hourly[9], 10)
        XCTAssertEqual(insights.topApps.map(\.bundleID), ["app.recent"])
    }

    func testWindowEndsMidPageAndTheWalkStops() async throws {
        let repository = InMemoryRepository()
        try await repository.createSession(dictation(daysAgo: 1, hour: 3,
                                                     bundle: "app.recent", words: 12))
        for index in 0..<40 {
            try await repository.createSession(dictation(daysAgo: 120 + index, hour: 3,
                                                         bundle: "app.old", words: 50))
        }

        let insights = await DashboardInsightsLoader.load(repository: repository,
                                                          now: now, calendar: calendar)

        XCTAssertEqual(insights.hourly[3], 12)
        XCTAssertEqual(insights.topApps.map(\.bundleID), ["app.recent"])
    }

    func testEmptyLibraryStaysEmpty() async throws {
        let insights = await DashboardInsightsLoader.load(repository: InMemoryRepository(),
                                                          now: now, calendar: calendar)
        XCTAssertEqual(insights, .empty)
        XCTAssertFalse(insights.hasData)
    }
}
