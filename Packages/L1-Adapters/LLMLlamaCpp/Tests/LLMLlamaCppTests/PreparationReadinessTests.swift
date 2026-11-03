import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowLLMCore

private struct PreparedModel: ModelProvider {
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { URL(fileURLWithPath: "/tmp/model") }
    func llmModelURL() async -> URL? { URL(fileURLWithPath: "/tmp/model") }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { URL(fileURLWithPath: "/tmp/model") }
}

private actor SlowLoadRuntime: LlamaRuntime {
    private(set) var started = false
    func load(modelURL: URL, compute: ModelCompute) async throws {
        started = true
        try await Task.sleep(for: .milliseconds(300))
    }
    func complete(prompt: String, maxTokens: Int) async throws -> String { "hello" }
}

final class PreparationReadinessTests: XCTestCase {
    func testReadinessWaitsForAlreadyRunningModelPreparation() async throws {
        let runtime = SlowLoadRuntime()
        let cleaner = LlamaCleaner(modelProvider: PreparedModel(), runtime: runtime)
        let task = Task { try await cleaner.prepare() }
        while await !runtime.started { try await Task.sleep(for: .milliseconds(5)) }
        let ready = await cleaner.isReady
        try await task.value
        XCTAssertTrue(ready)
    }
}
