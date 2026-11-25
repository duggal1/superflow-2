import Foundation
import OSLog
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowLLMCore
import SuperflowLLMLlamaCpp

private struct LongTranscriptModel: ModelProvider {
    let url: URL

    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

final class LiveSingleContextLongTranscriptTests: XCTestCase {
    func testThirtyMinuteTranscriptCleansWithOneContext() async throws {
        guard let modelPath = ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_MODEL"] else {
            throw XCTSkip("Set SUPERFLOW_CLEANUP_MODEL to the installed S1-mini GGUF.")
        }
        LlamaLogging.silence()

        let runtime = LlamaCppRuntime(sessions: 1)
        let cleaner = LlamaCleaner(modelProvider: LongTranscriptModel(url: URL(fileURLWithPath: modelPath)),
                                   runtime: runtime)
        try await cleaner.prepare(compute: .gpu)
        let sentences = (0..<450).map {
            "Review technical item number \($0) and approve before lunch today."
        }
        let input = sentences.joined(separator: " ")
        let inputWords = input.split(whereSeparator: \.isWhitespace).count
        XCTAssertEqual(inputWords, 4_500)
        let sessions = await runtime.activeSessionCount
        XCTAssertEqual(sessions, 1)

        let started = ContinuousClock.now
        let result = try await cleaner.clean(input, options: CleanOptions(deadlineMs: 300_000))
        let elapsed = started.duration(to: .now)
        let components = elapsed.components
        let elapsedMs = Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
        let outputWords = result.text.split(whereSeparator: \.isWhitespace).count
        let numberPattern = try NSRegularExpression(pattern: #"\b([0-9]{1,3})\b"#)
        let fullRange = NSRange(result.text.startIndex..<result.text.endIndex, in: result.text)
        let outputIDs: [Int] = numberPattern.matches(in: result.text, range: fullRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: result.text) else { return nil }
            return Int(result.text[range])
        }

        Logger(subsystem: "com.superflow.tests", category: "S1LongTranscript").notice("LIVE_S1_LONG input_words=\(inputWords) output_words=\(outputWords) elapsed_ms=\(elapsedMs) output_ids=\(outputIDs.count) token_cap=\(result.hitTokenCap)")
        XCTAssertFalse(result.hitTokenCap)
        XCTAssertGreaterThanOrEqual(outputWords, 4_000)
        XCTAssertEqual(outputIDs, Array(0..<450))
        XCTAssertLessThan(elapsedMs, 300_000)
    }
}
