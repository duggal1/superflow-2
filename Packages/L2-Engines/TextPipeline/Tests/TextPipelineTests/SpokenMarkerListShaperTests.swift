import XCTest
import SuperflowTextCleanup

/// Regression gates for the exact broken S1-mini renderings measured by
/// tools/brutal-s1. Every repair must be layout-only: no content word may be
/// added, removed or rewritten.
final class SpokenMarkerListShaperTests: XCTestCase {
    private func bullets(_ text: String) -> Int {
        text.split(separator: "\n").filter { $0.hasPrefix("- ") }.count
    }

    func testGluedHyphenMarkersBecomeDashBullets() {
        let out = SpokenMarkerListShaper.apply(
            "The plan is -ship, the API, -update the docs, -tell the team.")
        XCTAssertEqual(bullets(out), 3, out)
        XCTAssertTrue(out.contains("- ship the API"), out)
        XCTAssertTrue(out.contains("- update the docs"), out)
        XCTAssertTrue(out.contains("- tell the team"), out)
        XCTAssertFalse(out.contains(" -ship"), out)
    }

    func testHyphenSpokenChecklistBecomesDashBullets() {
        let out = SpokenMarkerListShaper.apply(
            "The checklist is -restart the server -clear the cache -verify the logs.")
        XCTAssertEqual(bullets(out), 3, out)
        XCTAssertTrue(out.contains("- restart the server"), out)
        XCTAssertTrue(out.contains("- clear the cache"), out)
        XCTAssertTrue(out.contains("- verify the logs"), out)
    }

    func testBulletMarkersWithCommasBecomeDashBullets() {
        let out = SpokenMarkerListShaper.apply(
            "The agenda is: Bullet, introductions, Bullet, demo, Bullet, questions.")
        XCTAssertEqual(bullets(out), 3, out)
        XCTAssertTrue(out.contains("- introductions"), out)
        XCTAssertTrue(out.contains("- demo"), out)
        XCTAssertTrue(out.contains("- questions"), out)
    }

    func testPseudoDecimalsBecomeDashBullets() {
        let out = SpokenMarkerListShaper.apply(
            "The results are: 0.1 latency is high, 0.2 memory is fine, 0.03 CPU is low.")
        XCTAssertEqual(bullets(out), 3, out)
        XCTAssertTrue(out.contains("- latency is high"), out)
        XCTAssertTrue(out.contains("- memory is fine"), out)
        XCTAssertTrue(out.contains("- CPU is low"), out)
    }

    func testSpokenPointMarkersBecomeDashBullets() {
        let out = SpokenMarkerListShaper.apply(
            "The results are point one latency is high point two memory is fine point three CPU is low")
        XCTAssertEqual(bullets(out), 3, out)
    }

    func testOrdinaryProseIsUntouched() {
        let inputs = [
            "The API returned 0.1 percent error on the first run.",
            "Cut the wire with a dash and move on.",
            "We should react to the news and see you next year.",
            "The temperature is 37.4 degrees, point three above average.",
            "First we tested locally, then we shipped.",
        ]
        for input in inputs {
            XCTAssertEqual(SpokenMarkerListShaper.apply(input), input, input)
        }
    }

    func testFencedCodeIsUntouched() {
        let input = "```\nthe plan is -ship, -update, -tell\n```"
        XCTAssertEqual(SpokenMarkerListShaper.apply(input), input)
    }

    func testDetectorSendsListsForSpokenSeparators() {
        for raw in [
            "the plan is dash ship the api dash update the docs dash tell the team",
            "the checklist is hyphen restart the server hyphen clear the cache hyphen verify the logs",
            "the agenda is bullet introductions bullet demo bullet questions",
        ] {
            guard case .list(let count) = EnumerationDetector.detect(raw) else {
                return XCTFail("not detected as list: \(raw)")
            }
            XCTAssertEqual(count, 3, raw)
        }
    }

    func testDetectorDoesNotInventListsInOrdinaryProse() {
        let raw = "we should react to the news and see you next year I need some cash tomorrow"
        if case .list = EnumerationDetector.detect(raw) {
            XCTFail("ordinary prose misdetected as a list")
        }
    }
}
