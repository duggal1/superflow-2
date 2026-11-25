import XCTest
@testable import SuperflowRecoveryEngine

final class RecoveryEpochCompletionTests: XCTestCase {
    func testStaleCompletionDoesNotFinishNewRun() async throws {
        let gate = RecoverySessionGate()
        let first = await gate.begin()
        let old = try XCTUnwrap(first)
        await gate.cancel()
        _ = await gate.rearm()
        let second = await gate.begin()
        let fresh = try XCTUnwrap(second)
        await gate.finish(epoch: old)
        let active = await gate.isActive(fresh)
        XCTAssertTrue(active)
        await gate.finish(epoch: fresh)
        let phase = await gate.currentPhase
        XCTAssertEqual(phase, .idle)
    }
}
