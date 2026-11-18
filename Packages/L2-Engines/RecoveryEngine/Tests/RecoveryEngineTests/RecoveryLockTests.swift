import Darwin
import XCTest
import SuperflowKernel
@testable import SuperflowRecoveryEngine

final class RecoveryLockTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws { root = RecoveryTestSupport.tempRoot("lock") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testConcurrentAcquireHasExactlyOneWinner() async throws {
        actor Outcomes {
            var winners = 0
            var busy = 0
            func won() { winners += 1 }
            func blocked() { busy += 1 }
        }
        let outcomes = Outcomes()
        let session = SessionID("contended")
        let lockRoot = root!
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    let lock = RecoveryLock(root: lockRoot, session: session)
                    do {
                        try lock.acquire()
                        await outcomes.won()
                        lock.release()
                    } catch RecoveryLockError.busy {
                        await outcomes.blocked()
                    } catch {
                        XCTFail("unexpected lock error: \(error)")
                    }
                }
            }
        }
        let winners = await outcomes.winners
        let blocked = await outcomes.busy
        XCTAssertEqual(winners, 1)
        XCTAssertEqual(blocked, 11)
    }

    func testDeadOwnersLockIsBrokenAndPreservedAsEvidence() throws {
        let session = SessionID("dead-owner")
        let dead = RecoveryLockOwner(pid: 999_999, acquiredAt: Date(), heartbeatAt: Date())
        let abandoned = RecoveryLock(root: root, session: session, owner: dead)
        try abandoned.acquire()

        let restarted = RecoveryLock(root: root, session: session)
        XCTAssertNoThrow(try restarted.acquire(), "a kill -9 owner must not block relaunch")
        XCTAssertEqual(RecoveryLock.staleEvidence(root: root).count, 1)
        restarted.release()
    }

    func testStaleHeartbeatIsBrokenEvenWhenPIDIsAlive() throws {
        let session = SessionID("stale-heartbeat")
        let stale = RecoveryLockOwner(pid: getpid(), acquiredAt: Date().addingTimeInterval(-7_200),
                                      heartbeatAt: Date().addingTimeInterval(-7_200))
        let first = RecoveryLock(root: root, session: session, owner: stale, staleAfter: 60)
        try first.acquire()
        let restarted = RecoveryLock(root: root, session: session, staleAfter: 60)
        XCTAssertNoThrow(try restarted.acquire())
        XCTAssertFalse(try XCTUnwrap(try Data(contentsOf: restarted.directory.appendingPathComponent("owner.json"))).isEmpty)
        restarted.release()
    }

    func testLiveLockIsNotBroken() throws {
        let session = SessionID("live-owner")
        let live = RecoveryLock(root: root, session: session, owner: RecoveryLockOwner(pid: getpid()))
        try live.acquire()
        let second = RecoveryLock(root: root, session: session)
        XCTAssertThrowsError(try second.acquire()) { error in
            guard case RecoveryLockError.busy = error else { return XCTFail("expected busy, got \(error)") }
        }
        XCTAssertTrue(RecoveryLock.staleEvidence(root: root).isEmpty)
        live.release()
    }

    func testReleaseAllowsReacquireAndDifferentSessionsAreIndependent() throws {
        let first = RecoveryLock(root: root, session: SessionID("a"))
        let other = RecoveryLock(root: root, session: SessionID("b"))
        try first.acquire()
        try other.acquire()
        XCTAssertNoThrow(try RecoveryLock(root: root, session: SessionID("c")).acquire())
        first.release()
        let again = RecoveryLock(root: root, session: SessionID("a"))
        XCTAssertNoThrow(try again.acquire())
        again.release()
        other.release()
    }
}
