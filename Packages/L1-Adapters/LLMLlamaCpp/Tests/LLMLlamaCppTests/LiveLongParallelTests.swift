import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowLLMCore
import SuperflowLLMLlamaCpp

private struct ParallelModel: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

final class LiveLongParallelTests: XCTestCase {
    func testLongTranscriptEquivalentRunsTwoModelWorkers() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_MODEL"] else {
            throw XCTSkip("Set SUPERFLOW_CLEANUP_MODEL to the installed S1-mini GGUF.")
        }
        LlamaLogging.silence()
        let cleaner = LlamaCleaner(modelProvider: ParallelModel(url: URL(fileURLWithPath: path)),
                                   runtime: LlamaCppRuntime(sessions: 2))
        try await cleaner.prepare()
        let input = "Please send the report to the team tomorrow. The project manager will review the budget before the meeting. Our customer needs a copy of the latest documentation. The engineers will check the service and confirm the release schedule. We should keep the current settings until the review is complete. After the meeting we can update the notes and share them with everyone."
        let words = input.split(whereSeparator: \.isWhitespace).count
        let expected = input.lowercased().filter { $0.isLetter || $0.isWhitespace }.split(whereSeparator: \.isWhitespace)
        let minutes = Int(ProcessInfo.processInfo.environment["SUPERFLOW_LONG_MINUTES"] ?? "10") ?? 10
        guard (1...60).contains(minutes) else { throw XCTSkip("SUPERFLOW_LONG_MINUTES must be between 1 and 60.") }
        let batches = (minutes * 150 + words * 2 - 1) / (words * 2)
        var failures = 0
        for _ in 0..<batches {
            await withTaskGroup(of: CleanResult?.self) { group in
                for _ in 0..<2 {
                    group.addTask { try? await cleaner.clean(input, options: CleanOptions(
                        styling: "semi-formal", structure: "prose", deadlineMs: 30_000)) }
                }
                for await result in group {
                    guard let result, !result.hitTokenCap,
                          result.text.lowercased().filter({ $0.isLetter || $0.isWhitespace })
                            .split(whereSeparator: \.isWhitespace) == expected else {
                        failures += 1
                        continue
                    }
                }
            }
        }
        TestMetricsLog.record("s1_long_parallel_input_words=\(batches * 2 * words) requests=\(batches * 2) failures=\(failures)")
        XCTAssertEqual(failures, 0)
    }
}
