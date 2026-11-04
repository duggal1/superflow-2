import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowLLMCore
import SuperflowLLMLlamaCpp

private struct BudgetModel: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

final class LiveInputBudgetTests: XCTestCase {
    func testRealModelAcceptsNear850TokenTranscript() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_MODEL"] else {
            throw XCTSkip("Set SUPERFLOW_CLEANUP_MODEL to the installed S1-mini GGUF.")
        }
        LlamaLogging.silence()
        let cleaner = LlamaCleaner(modelProvider: BudgetModel(url: URL(fileURLWithPath: path)),
                                   runtime: LlamaCppRuntime(sessions: 2))
        try await cleaner.prepare()
        var sentences: [String] = []
        for number in 1...100 {
            let next = "The team reviewed item \(number) and confirmed that the release includes the updated documentation."
            let proposed = (sentences + [next]).joined(separator: " ")
            if await cleaner.countTokens(proposed) > 850 { break }
            sentences.append(next)
        }
        let input = sentences.joined(separator: " ")
        let tokens = await cleaner.countTokens(input)
        XCTAssertGreaterThanOrEqual(tokens, 800)
        XCTAssertLessThanOrEqual(tokens, 850)
        let result = try await cleaner.clean(input, options: CleanOptions(
            styling: "semi-formal", structure: "prose", deadlineMs: 90_000, maxNewTokens: 1_137))
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertFalse(result.hitTokenCap)
        XCTAssertTrue(result.text.contains("item \(sentences.count)"), "Last item missing")
        TestMetricsLog.record("s1_live_input_tokens=\(tokens) output_tokens=\(result.tokensOut) capped=\(result.hitTokenCap)")
    }
}
