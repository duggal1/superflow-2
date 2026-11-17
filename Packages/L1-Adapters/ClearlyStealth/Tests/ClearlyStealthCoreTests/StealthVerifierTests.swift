import XCTest
@testable import ClearlyStealthCore

@MainActor
private struct FixedCapture: ProbeCapturing {
    let measurement: ProbeMeasurement?
    let error: Error?

    func capture() async throws -> ProbeMeasurement {
        if let error { throw error }
        return measurement!
    }
}

private enum CaptureFailure: Error { case denied }

final class StealthVerifierTests: XCTestCase {
    private let build = "26B123"

    func testVerifiedRunPersistsBuildMatchedRecord() async {
        let store = InMemoryStealthStatusStore()
        let verifier = StealthVerifier(
            capture: FixedCapture(measurement: ProbeMeasurement(controlMatchedRatio: 0.99,
                                                                islandMatchedRatio: 0.0), error: nil),
            store: store, osBuild: build, displayConfiguration: "1512x982@2x"
        )
        let outcome = await verifier.verify()
        XCTAssertEqual(outcome.status, .verified)

        let record = store.load(build: build)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.status, .verified)
        XCTAssertEqual(record?.osBuild, build)
        XCTAssertEqual(record?.displayConfiguration, "1512x982@2x")
        XCTAssertEqual(StealthStatusRecord.current(record, build: build)?.status, .verified)
    }

    func testForcedReadOnlyIslandProducesFailedRecord() async {
        // Gate 5b: force the Island capturable, confirm the verifier can fail.
        let store = InMemoryStealthStatusStore()
        let verifier = StealthVerifier(
            capture: FixedCapture(measurement: ProbeMeasurement(controlMatchedRatio: 0.97,
                                                                islandMatchedRatio: 0.93), error: nil),
            store: store, osBuild: build, displayConfiguration: "x"
        )
        let outcome = await verifier.verify()
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(store.load(build: build)?.status, .failed)
    }

    func testBlockedCaptureIsUnverifiedNotPass() async {
        // Gate 5c: no Screen Recording => Unverified, never Verified.
        let store = InMemoryStealthStatusStore()
        let verifier = StealthVerifier(
            capture: FixedCapture(measurement: nil, error: CaptureFailure.denied),
            store: store, osBuild: build, displayConfiguration: "x"
        )
        let outcome = await verifier.verify()
        XCTAssertEqual(outcome.status, .unverified)
        XCTAssertEqual(outcome.reason, .captureFailed)
        let record = store.load(build: build)
        XCTAssertEqual(record?.status, .unverified)
        // An unverified record is never treated as current proof.
        XCTAssertNil(StealthStatusRecord.current(record, build: build))
    }

    func testStaleBuildRecordIsNotCurrent() {
        let store = InMemoryStealthStatusStore()
        store.save(StealthStatusRecord(status: .verified, osBuild: "oldBuild",
                                       displayConfiguration: "x"))
        XCTAssertNil(store.load(build: build))
        XCTAssertNil(StealthStatusRecord.current(store.load(build: "oldBuild"), build: build))
    }

    func testReverifyOverwritesPreviousResult() async {
        let store = InMemoryStealthStatusStore()
        let pass = StealthVerifier(
            capture: FixedCapture(measurement: ProbeMeasurement(controlMatchedRatio: 0.99,
                                                                islandMatchedRatio: 0.0), error: nil),
            store: store, osBuild: build, displayConfiguration: "x"
        )
        await pass.verify()
        XCTAssertEqual(store.load(build: build)?.status, .verified)

        let fail = StealthVerifier(
            capture: FixedCapture(measurement: ProbeMeasurement(controlMatchedRatio: 0.99,
                                                                islandMatchedRatio: 0.5), error: nil),
            store: store, osBuild: build, displayConfiguration: "x"
        )
        await fail.verify()
        XCTAssertEqual(store.load(build: build)?.status, .failed)
    }
}
