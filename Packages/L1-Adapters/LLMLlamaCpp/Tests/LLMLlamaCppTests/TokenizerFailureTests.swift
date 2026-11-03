import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowLLMCore

private struct TokenizerFailureModel: ModelProvider {
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { URL(fileURLWithPath: "/tmp/model") }
    func llmModelURL() async -> URL? { URL(fileURLWithPath: "/tmp/model") }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { URL(fileURLWithPath: "/tmp/model") }
}

private struct TokenizerFailureRuntime: LlamaRuntime {
    let count: Int?
    func load(modelURL: URL, compute: ModelCompute) async throws {}
    func countTokens(_ text: String) async -> Int? { count }
    func complete(prompt: String, maxTokens: Int) async throws -> String { "hello" }
}

final class TokenizerFailureTests: XCTestCase {
    func testUnavailableTokenizerDoesNotMakeLongInputAppearEmpty() async throws {
        for response: Int? in [nil, 0] {
            let cleaner = LlamaCleaner(modelProvider: TokenizerFailureModel(),
                                       runtime: TokenizerFailureRuntime(count: response))
            try await cleaner.prepare()
            let input = String(repeating: "hello ", count: 500)
            let count = await cleaner.countTokens(input)
            XCTAssertGreaterThan(count, 850)
        }
    }
}
