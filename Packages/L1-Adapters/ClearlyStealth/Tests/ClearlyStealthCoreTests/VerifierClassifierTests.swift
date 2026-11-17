import XCTest
@testable import ClearlyStealthCore

final class VerifierClassifierTests: XCTestCase {
    func testControlPresentAndIslandAbsentIsVerified() {
        let outcome = VerifierClassifier.classify(
            ProbeMeasurement(controlMatchedRatio: 0.98, islandMatchedRatio: 0.0)
        )
        XCTAssertEqual(outcome.status, .verified)
        XCTAssertNil(outcome.reason)
    }

    func testIslandCapturedIsFailed() {
        let outcome = VerifierClassifier.classify(
            ProbeMeasurement(controlMatchedRatio: 0.96, islandMatchedRatio: 0.04)
        )
        XCTAssertEqual(outcome.status, .failed)
    }

    func testIslandAtThresholdIsFailedNotVerified() {
        // The boundary belongs to the failure side: >= islandMaximumRatio is a leak.
        let outcome = VerifierClassifier.classify(
            ProbeMeasurement(controlMatchedRatio: 0.99,
                             islandMatchedRatio: VerifierClassifier.islandMaximumRatio)
        )
        XCTAssertEqual(outcome.status, .failed)
    }

    func testMissingPositiveControlIsUnverifiedNeverPass() {
        // This is the anti-false-positive guard: a capture that misses the
        // visible control cannot be used to claim the Island is hidden.
        let outcome = VerifierClassifier.classify(
            ProbeMeasurement(controlMatchedRatio: 0.42, islandMatchedRatio: 0.0)
        )
        XCTAssertEqual(outcome.status, .unverified)
        XCTAssertEqual(outcome.reason, .invalidPositiveControl)
    }

    func testBothCapturedIsFailedNotUnverified() {
        let outcome = VerifierClassifier.classify(
            ProbeMeasurement(controlMatchedRatio: 0.95, islandMatchedRatio: 0.95)
        )
        XCTAssertEqual(outcome.status, .failed)
    }

    func testOutOfRangeMeasurementIsUnverified() {
        for measurement in [
            ProbeMeasurement(controlMatchedRatio: 1.4, islandMatchedRatio: 0.0),
            ProbeMeasurement(controlMatchedRatio: 0.95, islandMatchedRatio: -0.1),
        ] {
            XCTAssertEqual(VerifierClassifier.classify(measurement).status, .unverified)
        }
    }

    func testJustBelowControlThresholdIsUnverified() {
        let outcome = VerifierClassifier.classify(
            ProbeMeasurement(controlMatchedRatio: VerifierClassifier.positiveControlMinimumRatio - 0.01,
                             islandMatchedRatio: 0.0)
        )
        XCTAssertEqual(outcome.status, .unverified)
    }
}
