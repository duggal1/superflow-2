import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import SuperflowTextCleanup

private struct LocalModel: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

private actor MeasuredCleaner: DeadlineManagedTextCleaner {
    struct Counts: Sendable {
        var requests = 0
        var successes = 0
        var errors = 0
        var tokensIn = 0
        var tokensOut = 0
        var capped = 0
    }
    let inner: LlamaCleaner
    private var counts = Counts()
    init(_ inner: LlamaCleaner) { self.inner = inner }
    var isReady: Bool { get async { await inner.isReady } }
    func countTokens(_ text: String) async -> Int { await inner.countTokens(text) }
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        counts.requests += 1
        do {
            let result = try await inner.clean(text, options: options)
            counts.successes += 1
            counts.tokensIn += result.tokensIn
            counts.tokensOut += result.tokensOut
            if result.hitTokenCap { counts.capped += 1 }
            return result
        } catch { counts.errors += 1; throw error }
    }
    func snapshot() -> Counts { counts }
}

final class LiveServiceTests: XCTestCase {
    private func model() async throws -> LlamaCleaner {
        guard let path = ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_MODEL"] else {
            throw XCTSkip("Set SUPERFLOW_CLEANUP_MODEL to a local S1-mini GGUF.")
        }
        LlamaLogging.silence()
        let cleaner = LlamaCleaner(modelProvider: LocalModel(url: URL(fileURLWithPath: path)),
                                   runtime: LlamaCppRuntime(sessions: 2))
        try await cleaner.prepare(compute: .gpu)
        return cleaner
    }

    private func normalized(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map {
            String($0.lowercased().filter { $0.isLetter || $0.isNumber || "/_".contains($0) })
        }.filter { !$0.isEmpty }
    }

    private func write(_ text: String, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_RESULTS"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testLiveServicePreservesExamples() async throws {
        let cleaner = try await model()
        let input = "okay so I need you to open the file hero.tsx in the components folder then go to lib backend folder and fix the prospect main engine the path should be lib/backend/main/engine/router/prospect-main-engine.ts and change the status code from 500 to 429 when the rate limit is hit also update the constant MAX_RETRY_COUNT from 3 to 5"
        let protected = Protected(literals: ["hero.tsx", "lib/backend/main/engine/router/prospect-main-engine.ts", "500", "429", "MAX_RETRY_COUNT", "3", "5"])
        let raw = try await cleaner.clean(input, options: CleanOptions(deadlineMs: 30_000))
        XCTAssertEqual(CleanGuard.verify(input: input, protected: protected, result: raw, cap: 1_024), .contentChanged)
        let service = CleanupService(cleaner: cleaner)
        let outcome = await service.clean(input, protected: protected, context: TextContext(interactive: false))
        XCTAssertEqual(normalized(outcome.text), normalized(input))
        XCTAssertFalse(outcome.text.contains("lib/backend folder"))
        let safe = CleanResult(text: outcome.text, tokensIn: 0, tokensOut: 0, hitTokenCap: false, latencyMs: 0)
        XCTAssertNil(CleanGuard.verify(input: input, protected: protected, result: safe, cap: 1_024))
        let third = "I was thinking about the performance and you know like it keeps saying warming the GPU or warming the CPU and that is really bad"
        let cleaned = await service.clean(third, context: TextContext(interactive: false))
        let expected = third.replacingOccurrences(of: "you know like ", with: "")
        XCTAssertEqual(normalized(cleaned.text), normalized(expected))
        var report = "# Live cleanup service verification\n\nRelease SwiftPM build. Real S1-mini Q4_K_M on GPU, two shared-model contexts.\n\n"
        report += "The direct model completion changes `lib backend folder` to `lib/backend folder`. CleanGuard rejects it as contentChanged.\n\n"
        report += "## Use case 1 through CleanupService\n\nState: \(outcome.state). Chunks: \(outcome.chunks.count). Reasons: \(outcome.chunks.compactMap(\.reason)).\n\n\(outcome.text)\n\n"
        report += "Normalized output words exactly match Tier-0 input words. No invented path separator survives.\n\n"
        report += "## Use case 3 through CleanupService\n\nState: \(cleaned.state).\n\n\(cleaned.text)\n\n"
        report += "Normalized output exactly matches the input with the permitted phrase `you know like` removed.\n"
        try write(report, name: "live-service.md")
    }

    func testLiveSyntheticSoaks() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_SOAK"] == "1" else {
            throw XCTSkip("Set SUPERFLOW_CLEANUP_SOAK=1 to run the 30/60/120 minute synthetic soaks.")
        }
        let cleaner = try await model()
        var report = "# Live synthetic cleanup soaks\n\nOne release-build run per length on real S1-mini Q4_K_M, GPU, two contexts, default CleanupConfig. "
        report += "Inputs represent speech at 150 words/minute and contain six-word sentences with sequential change numbers. "
        report += "The timer includes planning, model calls, retries, stitching, and final validation. It excludes model loading, prewarm, input generation, ASR, and recording. "
        report += "These are cleanup completion times for already-transcribed text, not streaming stop-to-final measurements.\n\n"
        report += "| Simulated minutes | Input words | Seconds to final | Cleanup RTF | Requests | Successful calls | Errors | Capped calls | Prompt tokens | Generated tokens | Final fallback chunks | Exact content |\n"
        report += "|---|---|---|---|---|---|---|---|---|---|---|---|\n"
        for minutes in [30, 60, 120] {
            let wordCount = minutes * 150
            let input = (1...(wordCount / 6)).map { "We reviewed change \($0) before release." }.joined(separator: " ")
            XCTAssertEqual(input.split(whereSeparator: \.isWhitespace).count, wordCount)
            let measured = MeasuredCleaner(cleaner)
            let service = CleanupService(cleaner: measured)
            let start = ContinuousClock.now
            let outcome = await service.clean(input, context: TextContext(interactive: false))
            let duration = start.duration(to: .now)
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            let counts = await measured.snapshot()
            let exact = normalized(outcome.text) == normalized(input)
            XCTAssertTrue(exact, "content damage in \(minutes)-minute soak")
            XCTAssertGreaterThan(counts.requests, 0)
            XCTAssertGreaterThan(counts.successes, 0)
            XCTAssertGreaterThan(counts.tokensOut, 0)
            let fallback = outcome.chunks.filter { $0.state == .fallback }.count
            report += "| \(minutes) | \(wordCount) | \(String(format: "%.3f", seconds)) | \(String(format: "%.6f", seconds / Double(minutes * 60))) | \(counts.requests) | \(counts.successes) | \(counts.errors) | \(counts.capped) | \(counts.tokensIn) | \(counts.tokensOut) | \(fallback) | \(exact) |\n"
            try write(report, name: "live-soak.md")
        }
        report += "\nNo throughput comparison, safe-length calibration, session-count choice, or p95 claim follows from one run per length. "
        report += "The real-model calls and consumed output token counts above confirm inference happened inside each timed region. "
        report += "Fallbacks and capped calls remain visible because rejecting output can be faster than successful cleanup.\n"
        try write(report, name: "live-soak.md")
    }
}
