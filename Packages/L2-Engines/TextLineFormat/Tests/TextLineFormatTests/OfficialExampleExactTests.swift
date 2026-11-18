import Foundation
import XCTest
@testable import SuperflowTextLineFormat

/// Exact-form guards for the official S1-mini v1 examples at the final-polish
/// boundary (`Normalizer` + `LineFormatter`). The deterministic polish must not
/// drop a final period, lose a thousands separator, or leave an email address
/// spoken after the number stage has done its work.
final class OfficialExampleExactTests: XCTestCase {
    private func polish(_ raw: String) -> String {
        LineFormatter.format(Normalizer.normalize(raw))
    }

    // MARK: Official example 3 — email address

    func testOfficialEmailExampleExact() {
        // "support at superwhisper dot com" is a corporate address, not a
        // gmail/yahoo local part. The provider gate used to leave it spoken.
        XCTAssertEqual(polish("send it to support at superwhisper dot com"),
                       "Send it to support@superwhisper.com.")
        XCTAssertEqual(Normalizer.normalize("john dot smith at john dot example dot com"),
                       "john.smith@john.example.com")
    }

    // MARK: Official example 1 — date punctuation and grouping survive polish

    func testOfficialDateAndCurrencyPunctuationExact() {
        XCTAssertEqual(polish("it's due on march third twenty twenty six"),
                       "It's due on March 3, 2026.")
        XCTAssertEqual(polish("the invoice came to $23,450 and it's due on march third twenty twenty six"),
                       "The invoice came to $23,450 and it's due on March 3, 2026.")
        let out = polish("the invoice came to $23,450 and it's due on march third twenty twenty six")
        XCTAssertTrue(out.contains("$23,450"))
        XCTAssertFalse(out.contains("$23450"))
        XCTAssertFalse(out.contains("March 3 2026"))
    }

    // MARK: Official example 2 — the clock renders once and keeps its period

    func testOfficialTimeIsRenderedOnceWithFinalPeriod() {
        let out = polish("let's meet at 3:15pm tomorrow")
        XCTAssertEqual(out.components(separatedBy: "3:15").count - 1, 1)
        XCTAssertFalse(out.contains("2:30"))
        XCTAssertTrue(out.hasSuffix("."))
        // The trailing-period case used to lose its "." when the clock regex
        // swallowed it; keep that punctuation byte exactly once.
        let spoken = Normalizer.normalize("meet at 3:15pm.")
        XCTAssertEqual(spoken.components(separatedBy: ".").count - 1, 1)
        XCTAssertTrue(spoken.hasSuffix("."))
    }
}
