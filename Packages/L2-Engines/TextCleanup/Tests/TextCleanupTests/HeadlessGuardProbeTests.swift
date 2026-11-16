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

    func testGuardAcceptsS1MiniListAndGrammarOutputs() {
        let cases = [
            ("for the trip we need to pack sunscreen a first aid kit and chargers for everything",
             "For the trip, we need to pack:\n- Sunscreen\n- A first aid kit\n- Chargers for everything"),
            ("here are the steps first open the app second press record third copy the text",
             "Here are the steps:\n1. Open the app.\n2. Press record.\n3. Copy the text."),
            ("um so like the report is due friday no wait make that thursday",
             "So the report is due Thursday."),
            ("i think the answer is forty two no sorry forty three", "I think the answer is 43."),
        ]
        for (input, cleaned) in cases {
            let result = CleanResult(text: cleaned, tokensIn: 12, tokensOut: 16,
                                     hitTokenCap: false, latencyMs: 0)
            let failure = CleanGuard.verify(input: input, protected: Protected(), result: result, cap: 850)
            XCTAssertNil(failure, "guard rejected '\(cleaned)': \(String(describing: failure))")
        }
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
