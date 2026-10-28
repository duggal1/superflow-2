import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowLLMCore

private struct SleepingRuntime: LlamaRuntime {
    func load(modelURL: URL, compute: ModelCompute) async throws {}
    func complete(prompt: String, maxTokens: Int) async throws -> String {
        try await Task.sleep(for: .seconds(30))
        return "unexpected completion"
    }
}

final class RuntimeCompletionTests: XCTestCase {
    func testLegacyRuntimeDeadlineCancelsGeneration() async {
        do {
            _ = try await SleepingRuntime().completion(prompt: "hello", maxTokens: 64, deadlineMs: 1)
            XCTFail("expected deadline failure")
        } catch SuperflowError.timeout(let stage) {
            XCTAssertEqual(stage, "cleanup")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCancelledLegacyRuntimePropagatesCancellation() async {
        let task = Task {
            try await SleepingRuntime().completion(prompt: "hello", maxTokens: 64, deadlineMs: 30_000)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {} catch { XCTFail("unexpected error: \(error)") }
    }
}
