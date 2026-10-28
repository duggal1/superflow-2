import XCTest
import SuperflowPorts
@testable import SuperflowLLMCore

final class WorkerPoolTests: XCTestCase {
    private func waitForQueue(_ pool: WorkerPool<Int>, count: Int) async -> Bool {
        for _ in 0..<10_000 {
            if await pool.waitingCount == count { return true }
            await Task.yield()
        }
        return false
    }

    func testInteractivePassesQueuedBackgroundWork() async throws {
        let pool = WorkerPool([1])
        let held = try await pool.acquire(.background)
        let background = Task { try await pool.acquire(.background) }
        let backgroundQueued = await waitForQueue(pool, count: 1)
        XCTAssertTrue(backgroundQueued)
        let interactive = Task { try await pool.acquire(.interactive) }
        let bothQueued = await waitForQueue(pool, count: 2)
        XCTAssertTrue(bothQueued)
        await pool.release(held)
        let first = try await interactive.value
        XCTAssertEqual(first, held)
        let remaining = await pool.waitingCount
        XCTAssertEqual(remaining, 1)
        await pool.release(first)
        let second = try await background.value
        await pool.release(second)
    }

    func testCancelledWaiterIsRemovedWithoutLosingResource() async throws {
        let pool = WorkerPool([1])
        let held = try await pool.acquire(.background)
        let waiter = Task { try await pool.acquire(.interactive) }
        let queued = await waitForQueue(pool, count: 1)
        XCTAssertTrue(queued)
        waiter.cancel()
        do {
            _ = try await waiter.value
            XCTFail("cancelled waiter acquired a resource")
        } catch is CancellationError {} catch { XCTFail("unexpected error: \(error)") }
        await pool.release(held)
        let recovered = try await pool.acquire(.background)
        XCTAssertEqual(recovered, held)
        await pool.release(recovered)
    }

    func testQueueIsBoundedAndEmptyPoolFails() async throws {
        let empty = WorkerPool<Int>([])
        do {
            _ = try await empty.acquire(.background)
            XCTFail("empty pool should reject work")
        } catch WorkerPool<Int>.Failure.empty {} catch { XCTFail("unexpected error: \(error)") }
        let pool = WorkerPool([1], capacity: 0)
        let held = try await pool.acquire(.background)
        do {
            _ = try await pool.acquire(.interactive)
            XCTFail("full queue should reject work")
        } catch WorkerPool<Int>.Failure.exhausted {} catch { XCTFail("unexpected error: \(error)") }
        await pool.release(held)
    }

    func testThrowingOperationReleasesItsLease() async throws {
        enum Failure: Error { case expected }
        let pool = WorkerPool([1])
        do {
            let _: Int = try await pool.use(.interactive) { _ in throw Failure.expected }
            XCTFail("expected operation failure")
        } catch Failure.expected {} catch { XCTFail("unexpected error: \(error)") }
        let recovered = try await pool.acquire(.background)
        XCTAssertEqual(recovered, 1)
        await pool.release(recovered)
    }
}
