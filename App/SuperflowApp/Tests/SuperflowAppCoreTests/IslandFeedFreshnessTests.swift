import XCTest
@testable import SuperflowAppCore

final class IslandFeedFreshnessTests: XCTestCase {
    func testSlowConsumerReceivesNewestLevel() async {
        let feed = IslandFeedBox()
        feed.level(0.1)
        feed.level(0.4)
        feed.level(0.9)
        var iterator = feed.levels.makeAsyncIterator()
        let level = await iterator.next()
        XCTAssertEqual(level, 0.9)
    }
}
