import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextCleanup

/// Verifies the production guard against the exact S1-mini mutation observed
/// in the headless model probe: a spoken 503 rewritten as 530.
final class HeadlessGuardProbeTests: XCTestCase {
    func testGuardRejectsChangedStatusCode() {
        let input = "Off two point zero returned a five hundred three error"
        let result = CleanResult(text: "Off 2.0 returned a 530 error.",
                                 tokensIn: 10, tokensOut: 13, hitTokenCap: false, latencyMs: 0)
        XCTAssertNotNil(CleanGuard.verify(input: input, protected: Protected(), result: result, cap: 850),
                        "a changed status code must be rejected")
    }

    func testGuardAlsoRejectsBenignNumberFormatting() {
        // Observed headlessly: the guard is conservative and falls back even
        // for "two point zero" -> "2.0". That preserves correctness but means
        // the deterministic Numbers stage, not S1-mini, owns numeric formatting.
        let input = "Off two point zero returned a five hundred three error"
        let result = CleanResult(text: "Off 2.0 returned a five hundred three error.",
                                 tokensIn: 10, tokensOut: 13, hitTokenCap: false, latencyMs: 0)
        XCTAssertNotNil(CleanGuard.verify(input: input, protected: Protected(), result: result, cap: 850))
    }
}
