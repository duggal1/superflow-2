import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowLLMCore

private actor RecordingProvider: ModelProvider {
    let url = URL(fileURLWithPath: "/tmp/s1-chunk.gguf")
    func localURL(for profileID: String) async -> URL? { url }
    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {}
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

/// Records every completion and the peak number of simultaneous calls so we can
/// prove long transcripts fan out across the worker pool in deadline-bounded requests.
private actor ParallelRuntime: LlamaRuntime {
    private(set) var prompts: [String] = []
    private(set) var deadlines: [Int] = []
    private(set) var peakConcurrency = 0
    private var active = 0
    let failOnPromptContaining: String?

    init(failOnPromptContaining: String? = nil) { self.failOnPromptContaining = failOnPromptContaining }

    func load(modelURL: URL, compute: ModelCompute) async throws {}
    func countTokens(_ text: String) async -> Int? { LlamaPrompt.estimateTokens(text) }
    func complete(prompt: String, maxTokens: Int) async throws -> String { "unused" }
    func completion(prompt: String, maxTokens: Int, deadlineMs: Int) async throws -> LlamaCompletion {
        active += 1
        peakConcurrency = max(peakConcurrency, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(8))
        if let needle = failOnPromptContaining, prompt.contains(needle) {
            throw SuperflowError.modelUnavailable("injected chunk failure")
        }
        prompts.append(prompt)
        deadlines.append(deadlineMs)
        // Echo the last words of the user turn so ordering is observable.
        let cleaned = String(prompt.suffix(7))
        return LlamaCompletion(text: cleaned, generatedTokens: 2, hitTokenCap: false)
    }
}

final class ChunkedCleanupTests: XCTestCase {
    func testWordBoundarySplitPreservesEveryWord() {
        let input = (1...131).map { "w\($0)" }.joined(separator: " ")
        let chunks = LlamaCleaner.split(input, wordsPerChunk: 50)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks.map { $0.split(separator: " ").count }, [50, 50, 31])
        XCTAssertEqual(chunks.joined(separator: " ").split(separator: " ").count, 131)
    }

    func testSplitPrefersSentenceBoundaryWithoutFlatteningMarkdown() {
        let input = "First, keep these four words.\n\nNext preserve this sentence in order."
        let chunks = LlamaCleaner.split(input, wordsPerChunk: 8)
        XCTAssertEqual(chunks, ["First, keep these four words.", "Next preserve this sentence in order."])
        XCTAssertEqual(LlamaCleaner.split(input, wordsPerChunk: 20), [input])
    }

    func testShortInputStaysSingleCall() async throws {
        let runtime = ParallelRuntime()
        let cleaner = LlamaCleaner(modelProvider: RecordingProvider(), runtime: runtime)
        _ = try await cleaner.clean((1...100).map { "w\($0)" }.joined(separator: " "),
                                    options: CleanOptions())
        let count = await runtime.prompts.count
        XCTAssertEqual(count, 1, "short dictation must not pay chunk overhead")
    }

    func testLongInputFansOutAndKeepsOrder() async throws {
        let runtime = ParallelRuntime()
        let cleaner = LlamaCleaner(modelProvider: RecordingProvider(), runtime: runtime,
                                   maxConcurrentChunks: 4)
        let input = (1...131).map { "w\($0)" }.joined(separator: " ")
        let result = try await cleaner.clean(input, options: CleanOptions(deadlineMs: 5_000))
        let prompts = await runtime.prompts
        let peak = await runtime.peakConcurrency
        XCTAssertEqual(prompts.count, 3)
        XCTAssertEqual(peak, 3, "chunks must run concurrently on the worker pool")
        XCTAssertFalse(result.text.isEmpty)
        let expected = LlamaCleaner.split(input, wordsPerChunk: 50)
            .reduce(0) { $0 + LlamaPrompt.estimateTokens($1) }
        XCTAssertEqual(result.tokensIn, expected)
        XCTAssertFalse(result.hitTokenCap)
        let waveDeadlines = await runtime.deadlines
        XCTAssertTrue(waveDeadlines.allSatisfy { $0 > 0 && $0 <= 5_000 })
    }

    func testChunkFailureFailsWholeCallWithoutPartialText() async throws {
        let runtime = ParallelRuntime(failOnPromptContaining: "w51")
        let cleaner = LlamaCleaner(modelProvider: RecordingProvider(), runtime: runtime,
                                   maxConcurrentChunks: 3)
        do {
            _ = try await cleaner.clean((1...131).map { "w\($0)" }.joined(separator: " "),
                                        options: CleanOptions(deadlineMs: 5_000))
            XCTFail("a failed chunk must fail the call")
        } catch SuperflowError.modelUnavailable(let message) {
            XCTAssertTrue(message.contains("injected chunk failure"))
        }
    }

    func testTinyDeadlineFailsLoudly() async throws {
        let runtime = ParallelRuntime()
        let cleaner = LlamaCleaner(modelProvider: RecordingProvider(), runtime: runtime)
        do {
            _ = try await cleaner.clean((1...131).map { "w\($0)" }.joined(separator: " "),
                                        options: CleanOptions(deadlineMs: 1))
            XCTFail("expired deadline must throw")
        } catch SuperflowError.timeout(let stage) {
            XCTAssertEqual(stage, "cleanup")
        }
    }
}
