import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowLLMCore
import SuperflowLLMLlamaCpp

private struct LiveModelProvider: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

final class LiveCleanupTests: XCTestCase {
    func testLiveExamplesAndCancellation() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["SUPERFLOW_CLEANUP_MODEL"] else {
            throw XCTSkip("Set SUPERFLOW_CLEANUP_MODEL to a local S1-mini GGUF to run live inference.")
        }
        LlamaLogging.silence()
        let runtime = LlamaCppRuntime(sessions: 2)
        let modelURL = URL(fileURLWithPath: modelPath)
        let cleaner = LlamaCleaner(modelProvider: LiveModelProvider(url: modelURL),
                                   runtime: runtime)
        let loadStart = ContinuousClock.now
        try await cleaner.prepare(compute: .gpu)
        var report = "# Live cleanup verification\n\n"
        let modelBytes = try modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        report += "Model: \(modelURL.lastPathComponent), \(modelBytes) bytes. GPU placement, two shared-model contexts.\n\n"
        report += "Command: set SUPERFLOW_CLEANUP_MODEL to the local GGUF and SUPERFLOW_CLEANUP_REPORT to this file, "
        report += "then run `swift test --package-path Packages/L1-Adapters/LLMLlamaCpp --jobs 2 --filter LiveCleanupTests`.\n\n"
        report += "Load and prewarm: \(loadStart.duration(to: .now)). This is one functional run, not a benchmark.\n\n"
        let examples: [(name: String, text: String, protected: [String])] = [
            ("Use case 1", "okay so I need you to open the file hero.tsx in the components folder then go to lib backend folder and fix the prospect main engine the path should be lib/backend/main/engine/router/prospect-main-engine.ts and change the status code from 500 to 429 when the rate limit is hit also update the constant MAX_RETRY_COUNT from 3 to 5",
             ["hero.tsx", "lib/backend/main/engine/router/prospect-main-engine.ts", "500", "429", "MAX_RETRY_COUNT", "3", "5"]),
            ("Use case 3 with discourse fillers", "I was thinking about the performance and you know like it keeps saying warming the GPU or warming the CPU and that is really bad", []),
        ]
        var results: [(CleanResult, [String])] = []
        for example in examples {
            let result = try await CleanPriority.$current.withValue(.background) {
                try await cleaner.clean(example.text, options: CleanOptions(deadlineMs: 30_000))
            }
            report += "## \(example.name)\n\nInput:\n\n\(example.text)\n\nOutput:\n\n\(result.text)\n\n"
            report += "Prompt tokens: \(result.tokensIn). Generated tokens: \(result.tokensOut). "
            report += "Latency: \(result.latencyMs) ms. Hit token cap: \(result.hitTokenCap).\n\n"
            if example.name == "Use case 1" {
                report += "Protected tokens are checked as complete tokens, with exact case and original order. "
                report += "This test does not assert zero content damage for unprotected prose. "
                report += "In particular, compare `lib backend folder` in the input with the output before accepting it in the full pipeline.\n\n"
            }
            results.append((result, example.protected))
        }
        let longInput = Array(repeating: examples[1].text, count: 20).joined(separator: " ")
        let generation = Task {
            try await cleaner.clean(longInput, options: CleanOptions(deadlineMs: 30_000))
        }
        try await Task.sleep(for: .milliseconds(20))
        let cancelStart = ContinuousClock.now
        generation.cancel()
        var cancelled = false
        do {
            _ = try await generation.value
        } catch is CancellationError {
            cancelled = true
        }
        report += "## Cancellation\n\nCancellation requested 20 ms after starting a long example. "
        report += "CancellationError returned: \(cancelled). Time from cancel to return: \(cancelStart.duration(to: .now)).\n\n"
        report += "Checks occur between generated tokens and prefill batches. One observation does not establish a worst-case bound.\n\n"
        report += "Not measured: Spike B safe-length sweep, Spike C tokenizer error, Spike D session throughput/RSS/p95, "
        report += "Spike E equivalence, the owner's 100-dictation golden set, or real-model 30/60/120-minute soaks.\n"
        if let reportPath = environment["SUPERFLOW_CLEANUP_REPORT"] {
            let url = URL(fileURLWithPath: reportPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.write(to: url, atomically: true, encoding: .utf8)
        }
        for (result, protected) in results {
            XCTAssertFalse(result.hitTokenCap)
            XCTAssertFalse(result.text.isEmpty)
            let cores = Tokenizer.tokens(in: result.text).map(\.core)
            var cursor = cores.startIndex
            for token in protected {
                guard let index = cores[cursor...].firstIndex(of: token) else {
                    XCTFail("Lost or reordered protected token: \(token)")
                    continue
                }
                cursor = index + 1
            }
        }
        XCTAssertTrue(cancelled)
    }
}
