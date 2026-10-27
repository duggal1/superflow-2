import Foundation
import SuperflowKernel
import XCTest
@testable import SuperflowFeatureDashboard

final class WordDiffTests: XCTestCase {
    func testExampleRoundTripsInBothPhases() {
        let sample = CleanupSample.example
        let tokens = sample.tokens

        let said = tokens.compactMap { $0.text(in: .said) }.joined(separator: " ")
        let typed = tokens.compactMap { $0.text(in: .typed) }.joined(separator: " ")

        XCTAssertEqual(said, sample.raw)
        XCTAssertEqual(typed, sample.cleaned)
    }

    func testRawOrderIsPreserved() {
        let sample = CleanupSample.example
        let rawWords = sample.raw.split(separator: " ").map(String.init)
        let tokenWords = sample.tokens.compactMap(\.raw)
        XCTAssertEqual(rawWords, tokenWords)
    }

    func testOnlyRemovalsAndReplacementsAreMarked() {
        for token in CleanupSample.example.tokens {
            XCTAssertEqual(token.isMarked, token.kind == .remove || token.kind == .replace)
        }
    }

    func testNumberPairingProducesOneReplacementAndTwoRemovals() {
        let tokens = WordDiff.tokens(raw: "twelve thousand dollars", clean: "$12,000,")
        XCTAssertEqual(tokens.map(\.kind), [.replace, .remove, .remove])
        XCTAssertEqual(tokens.first?.raw, "twelve")
        XCTAssertEqual(tokens.first?.clean, "$12,000,")
    }

    func testIdenticalTextKeepsEveryToken() {
        let tokens = WordDiff.tokens(raw: "the same words", clean: "the same words")
        XCTAssertEqual(tokens.map(\.kind), [.keep, .keep, .keep])
        XCTAssertFalse(tokens.contains(where: \.isMarked))
    }
}

final class DashboardInsightsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func session(_ kind: SessionKind, hour: Int, bundle: String?, words: Int) -> SessionRecord {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 1
        components.hour = hour
        let start = calendar.date(from: components)!
        return SessionRecord(kind: kind, startedAt: start, status: .complete,
                             frontmostBundleID: bundle, modelProfile: "test",
                             wordCount: words)
    }

    func testHourlyAlwaysHasTwentyFourEntriesAndExcludesMeetings() {
        let insights = DashboardInsightsBuilder.build(
            sessions: [session(.dictation, hour: 14, bundle: "com.apple.TextEdit", words: 10),
                       session(.meeting, hour: 14, bundle: "com.apple.TextEdit", words: 90)],
            latest: nil,
            calendar: calendar,
            appName: { _ in "TextEdit" })

        XCTAssertEqual(insights.hourly.count, 24)
        XCTAssertEqual(insights.hourly[14], 10)
        XCTAssertEqual(insights.hourly.reduce(0, +), 10)
    }

    func testTopAppsAreDescendingAndCappedAtFive() {
        var sessions: [SessionRecord] = []
        for index in 0..<7 {
            sessions.append(session(.dictation, hour: 9, bundle: "app.\(index)",
                                    words: (index + 1) * 10))
        }
        let insights = DashboardInsightsBuilder.build(sessions: sessions, latest: nil,
                                                      calendar: calendar, appName: { $0 })
        XCTAssertEqual(insights.topApps.count, 5)
        XCTAssertEqual(insights.topApps.map(\.bundleID),
                       ["app.6", "app.5", "app.4", "app.3", "app.2"])
        XCTAssertEqual(insights.topApps.first?.words, 70)
        XCTAssertTrue(insights.hasData)
    }

    func testNoDataIsEmpty() {
        let insights = DashboardInsightsBuilder.build(sessions: [], latest: nil,
                                                      calendar: calendar, appName: { $0 })
        XCTAssertEqual(insights, .empty)
        XCTAssertFalse(insights.hasData)
        XCTAssertNil(insights.latest)
    }
}
