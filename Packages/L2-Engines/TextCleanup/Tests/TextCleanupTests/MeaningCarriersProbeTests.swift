import XCTest
@testable import SuperflowTextCleanup

/// Regression: the safety guard must ACCEPT a model that resolves an explicit
/// self-correction or a false-start double negator, while still REJECTING a
/// model that drops a real clause negation. This was the root cause of valid
/// S1-mini output falling back to raw text on garbled transcripts.
final class MeaningCarriersProbeTests: XCTestCase {
    func testSelfCorrectionNegatorsAreNotCountedAsClauseNegations() {
        let cases: [(String, String)] = [
            ("Okay so the JWT token it's expired you know and the API is returning a 403 not a 500 wait no 429 because the rate limiter is kicking in",
             "Okay so the JWT token is expired, and the API is returning a 429 because the rate limiter is kicking in."),
            ("So like I don't not want to deploy the config on Friday actually no wait Thursday because the staging cluster is still red",
             "So I don't want to deploy the config on Thursday, because the staging cluster is still red."),
        ]
        for (input, output) in cases {
            XCTAssertTrue(MeaningCarriers.hasRevisionCue(input), input)
            XCTAssertTrue(MeaningCarriers.accepts(input, output, allowsRevision: true), input)
        }
    }

    func testRealNegationDropIsStillRejected() {
        XCTAssertFalse(MeaningCarriers.accepts("I did not save the file.",
                                               "I did save the file.",
                                               allowsRevision: false))
        XCTAssertTrue(MeaningCarriers.accepts("The server is down and we do not have a backup and we cannot rollback so do not deploy",
                                              "The server is down, and we do not have a backup, and we cannot rollback, so do not deploy.",
                                              allowsRevision: false))
    }
}
