import Foundation
import XCTest
@testable import SuperflowKernel

final class DeadlineTests: XCTestCase {
    func testReturnsOperationResultWhenItFinishesFirst() async throws {
        let value = try await withDeadline(.seconds(5), label: "fast") { 41 + 1 }
        XCTAssertEqual(value, 42)
    }

    func testThrowsTimeoutWhenOperationOutlivesLimit() async {
        do {
            _ = try await withDeadline(.milliseconds(50), label: "slow") {
                try await Task.sleep(for: .seconds(5))
                return 0
            }
            XCTFail("Expected the deadline to fire")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .timeout("slow"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOperationErrorPropagates() async {
        do {
            _ = try await withDeadline(.seconds(5), label: "boom") {
                throw SuperflowError.cancelled
            }
            XCTFail("Expected the operation's error")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// The reason this exists instead of a `TaskGroup`: the caller must return as soon as the
    /// deadline fires, not wait for the abandoned call to finish.
    func testAbandonsTheOperationInsteadOfWaitingForIt() async {
        let clock = ContinuousClock()
        let start = clock.now
        _ = try? await withDeadline(.milliseconds(50), label: "hang") {
            try await Task.sleep(for: .seconds(3))
            return 0
        }
        let elapsed = clock.now - start
        XCTAssertLessThan(elapsed, .seconds(1), "Caller blocked on the abandoned operation")
    }
}
