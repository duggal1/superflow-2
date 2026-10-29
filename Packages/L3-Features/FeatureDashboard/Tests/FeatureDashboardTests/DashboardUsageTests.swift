import Foundation
import SuperflowKernel
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureDashboard

final class DashboardUsageTests: XCTestCase {
    func testUsageAggregatesEveryPageWithoutMeetingsOrUnknownApps() async throws {
        let repository = InMemoryRepository()
        let now = Date()
        for _ in 0..<1_601 {
            try await repository.createSession(SessionRecord(kind: .dictation, startedAt: now,
                status: .complete, frontmostBundleID: "app.editor", modelProfile: "test", durationMs: 1_500, wordCount: 2))
        }
        try await repository.createSession(SessionRecord(kind: .meeting, startedAt: now,
            frontmostBundleID: "app.meeting", modelProfile: "test", wordCount: 9_999))
        try await repository.createSession(SessionRecord(kind: .dictation, startedAt: now,
            modelProfile: "test", wordCount: 9_999))
        let result = try await DashboardUsageLoader.load(repository: repository, range: .all, now: now)
        XCTAssertEqual(result, [AppUsage(bundleID: "app.editor", words: 3_202, sessions: 1_601, seconds: 2_401.5)])
    }

    func testRangeFiltersAndRetainsTrueSharesAcrossMoreThanSixApps() async throws {
        let repository = InMemoryRepository()
        let now = Date()
        for index in 0..<8 {
            try await repository.createSession(SessionRecord(kind: .dictation, startedAt: now,
                frontmostBundleID: "app.\(index)", modelProfile: "test", wordCount: 10))
        }
        try await repository.createSession(SessionRecord(kind: .dictation,
            startedAt: now.addingTimeInterval(-20 * 86_400), frontmostBundleID: "app.old",
            modelProfile: "test", wordCount: 100))
        let week = try await DashboardUsageLoader.load(repository: repository, range: .week, now: now)
        let month = try await DashboardUsageLoader.load(repository: repository, range: .month, now: now)
        XCTAssertEqual(week.count, 8)
        XCTAssertEqual(week.reduce(0) { $0 + $1.words }, 80)
        XCTAssertEqual(month.first?.bundleID, "app.old")
        XCTAssertEqual(month.reduce(0) { $0 + $1.words }, 180)
    }
}
