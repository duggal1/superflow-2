import XCTest
import SuperflowKernel
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import SuperflowPorts
import SuperflowTextCleanup
import SuperflowTextPipeline

private struct LocalModelProvider: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { url }
    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {}
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

/// Brutal output-quality harness. Deliberately broken ASR-style transcripts,
/// scored against the VERBATIM official S1-mini outputs recorded in
/// `.proof/quality/baseline-15-cases.txt` (temperature 0, top_k 1). No audio,
/// no UI. Enable with SUPERFLOW_QUALITY_PROBE=1.
///
/// Strictness contract:
///  - `expected` is compared byte-for-byte; a plausible paraphrase is a FAIL.
///  - `forbidden` lists explicit dropped/corrupted facts; their presence is a FAIL.
///  - `expected == ""` is valid (filler-only input): the empty string is the
///    correct official result for "um" and must not be scored as missing
///    punctuation or a missing capital.
final class HeadlessQualityHarnessTests: XCTestCase {
    func testMessyTranscriptQuality() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_QUALITY_PROBE"] == "1" else { return }
        let output = ProcessInfo.processInfo.environment["SUPERFLOW_QUALITY_OUT"]
            ?? "/private/var/folders/ct/cwpf7vpn059fkp932tq9zm4m0000gn/T/opencode/quality.txt"
        let model = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("S1-mini not installed") }
        LlamaLogging.silence()
        let runtime = LlamaCppRuntime(sessions: 2)
        let cleaner = LlamaCleaner(modelProvider: LocalModelProvider(url: model), runtime: runtime)
        try await cleaner.prepare(compute: .gpu)
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        let pipeline = TextPipelineBuilder.make(
            settings: settings,
            dependencies: TextPipelineDependencies(cleaner: CleanupService(cleaner: cleaner)))
        let context = TextContext(settings: settings)

        struct Case {
            let name: String
            let raw: String
            /// Verbatim official output. Empty string is a valid expected result.
            let expected: String
            let forbidden: [String]
        }
        let cases = [
            Case(name: "backend",
                 raw: "the next year's APOINT is experience intermediate illitency because the postgresql connection pool is reaching the maximum capacity we need to inspect the redish cash configuration analyze open trace and identifys is restarting the affected pod. the p 95 response should remain below 200ms",
                 expected: """
                 The Next.js API endpoint is experiencing intermittent latency because the PostgreSQL connection pool is reaching the maximum capacity. We need to inspect the Redis cache configuration.

                 Analyze OpenTelemetry and Kubernetes is restarting the affected pod.

                 The P95 response should remain below 200ms.
                 """,
                 forbidden: ["APOINT", "illitency", "redish cash", "open trace", "identifys", "next year's"]),
            Case(name: "engineering",
                 raw: "we are optimizing a quantized language model for local inference on apple silicon the current implementation use mlx with 4 bit quantization or token generation slows down when memory bandwidth becomes saturated we should benchmark time to first token measure token per second and compare skeptical decoding against standard autoaggressive inference the kv cash must remain within variable unified naming budget additionally we need to evaluate metal gpu utilization",
                 expected: """
                 We are optimizing a quantized language model for local inference on Apple Silicon. The current implementation uses MLX with 4-bit quantization, or token generation slows down when memory bandwidth becomes saturated.

                 We should benchmark time to first token measure tokens per second and compare speculative decoding against standard autoregressive inference. The KV cache must remain within variable unified naming budget.

                 Additionally, we need to evaluate metal GPU utilization.
                 """,
                 forbidden: ["skeptical", "autoaggressive", "kv cash", "withoutput", "4 bit"]),
            Case(name: "meeting",
                 raw: "hey can you move the meeting to thursday actually no wednesday at three thirty and tell sarah the budget spreadsheet needs to be updated before friday",
                 expected: "Hey, can you move the meeting to Wednesday at 3:30 and tell Sarah the budget spreadsheet needs to be updated before Friday?",
                 forbidden: ["Thursday", "thursday", "three thirty", "three p m"]),
            Case(name: "stutter",
                 raw: "um so like i i i think we we should maybe uh just ship it um tomorrow",
                 expected: "So I think we should maybe just ship it tomorrow.",
                 forbidden: [" um ", " uh ", "i i", "we we"]),
            Case(name: "negation",
                 raw: "no dont delete the file and make sure we do not send it to the client",
                 expected: "Do not delete the file and make sure we do not send it to the client.",
                 forbidden: ["dont"]),
            Case(name: "numbers",
                 raw: "the invoice came to twenty three thousand four hundred and fifty dollars and its due on march third twenty twenty six",
                 expected: "The invoice came to $23,450 and it's due on March 3, 2026.",
                 forbidden: ["twenty three thousand", "23450", "23.450"]),
            Case(name: "email",
                 raw: "hey sarah just wanted to follow up on the proposal can you send the numbers by end of week thanks john",
                 expected: """
                 Hey Sarah, just wanted to follow up on the proposal. Can you send the numbers by end of week?

                 Thanks, John.
                 """,
                 forbidden: ["end of week thanks", "proposal can you"]),
            Case(name: "list",
                 raw: "for the trip we need to pack sunscreen and then also a first aid kit and um chargers for everything",
                 expected: """
                 For the trip, we need to pack

                 - sunscreen
                 - a first aid kit
                 - chargers for everything.
                 """,
                 forbidden: ["sunscreen and then", "aid kit and"]),
            Case(name: "selfcorrection",
                 raw: "i think the answer is forty two no sorry forty three",
                 expected: "I think the answer is 43.",
                 forbidden: ["42", "forty two"]),
            Case(name: "garble-mixed",
                 raw: "the next year's APOINT is down again and the redish cash is full so check the open trace in kubernetes",
                 expected: "The Next.js API endpoint is down again, and the Redis cache is full, so check the OpenTelemetry in Kubernetes.",
                 forbidden: ["APOINT", "redish cash", "open trace", "next year's"]),
            Case(name: "ai-mixed",
                 raw: "benchmark time to first token and token per second and compare skeptical decoding with autoaggressive inference while the kv cash grows",
                 expected: "Benchmark time to first token and tokens per second, and compare speculative decoding with autoregressive inference while the KV cache grows.",
                 forbidden: ["skeptical", "autoaggressive", "kv cash"]),
            Case(name: "time-revision",
                 raw: "the meeting is at four p m on thursday actually no friday at five thirty",
                 // Self-correction now keeps only the final value: the stale
                 // 4 PM and the superseded Thursday must not survive.
                 expected: "The meeting is at 5:30 on Friday.",
                 forbidden: ["4 PM", "four p m", "Thursday", "thursday"]),
            Case(name: "negation-stack",
                 raw: "the server is down and we do not have a backup and we cannot rollback so do not deploy",
                 expected: "The server is down, and we do not have a backup, and we cannot rollback, so do not deploy.",
                 forbidden: ["dont", "can rollback"]),
            Case(name: "email-address",
                 raw: "send the report to john at john dot example dot com by friday",
                 expected: "Send the report to john@john.example.com by Friday.",
                 forbidden: [" dot "]),
            Case(name: "list-alt",
                 raw: "we need to buy milk and eggs and bread for the office",
                 expected: """
                 We need to buy:
                 - Milk
                 - Eggs
                 - Bread

                 For the office.
                 """,
                 forbidden: ["milk and eggs and bread"]),
            // Empty-string-is-valid contract: filler-only input must yield "".
            Case(name: "filler-only",
                 raw: "um",
                 expected: "",
                 forbidden: ["um", "Uh"]),
        ]

        var report = ""
        var passed = 0
        for item in cases {
            let result = await pipeline.run(item.raw, context: context)
            let text = result.text
            var misses: [String] = []
            if text != item.expected {
                misses.append("exact-output-mismatch: got \(text.debugDescription) expected \(item.expected.debugDescription)")
            }
            for token in item.forbidden where text.localizedCaseInsensitiveContains(token) {
                misses.append("bad:\(token)")
            }
            // A self-correction must keep the single final value: both the
            // corrected time and the corrected day are explicitly required.
            if item.name == "time-revision" {
                for token in ["5:30", "Friday"] where !text.localizedCaseInsensitiveContains(token) {
                    misses.append("missing:\(token)")
                }
            }
            // Structural assertions only apply to a non-empty official result.
            // For expected == "" the empty output IS the passing result.
            if !item.expected.isEmpty {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || !"?!.".contains(trimmed.last!) { misses.append("no-final-punctuation") }
                if trimmed.first?.isUppercase != true { misses.append("no-capital") }
                if (item.name == "list" || item.name == "list-alt") {
                    let bullets = text.split(separator: "\n").filter { $0.hasPrefix("- ") }
                    if bullets.count != 3 { misses.append("bullet-count-\(bullets.count)-expected-3") }
                }
                if item.name == "email" && !text.contains("\n\nThanks, John.") {
                    misses.append("missing-blank-line-layout")
                }
            }
            if text.contains("  ") { misses.append("double-space") }
            if misses.isEmpty { passed += 1 }
            report += "== \(item.name) ==\nIN:  \(item.raw)\nOUT: \(text)\nEXPECTED: \(item.expected)\nSTATE: \(result.draft.cleanupState)\nSCORE: \(misses.isEmpty ? "PASS" : misses.joined(separator: ", "))\n\n"
        }
        report = "quality score: \(passed)/\(cases.count)\n\n" + report
        try report.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
        XCTAssertEqual(passed, cases.count, report)
    }

    /// A self-correction must leave ONE final time value. The stale 4 PM and
    /// the superseded Thursday must not survive alongside the final 5:30 on
    /// Friday. SelfCorrectionStage now resolves this case to
    /// "The meeting is at 5:30 on Friday." — kept as a strict independent guard.
    func testConflictingTimesMustCollapseToSingleFinalValue() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_QUALITY_PROBE"] == "1" else { return }
        let model = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("S1-mini not installed") }
        LlamaLogging.silence()
        let cleaner = LlamaCleaner(modelProvider: LocalModelProvider(url: model),
                                   runtime: LlamaCppRuntime(sessions: 1))
        try await cleaner.prepare(compute: .gpu)
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        let pipeline = TextPipelineBuilder.make(
            settings: settings,
            dependencies: TextPipelineDependencies(cleaner: CleanupService(cleaner: cleaner)))
        let context = TextContext(settings: settings)
        let text = await pipeline.run(
            "the meeting is at four p m on thursday actually no friday at five thirty",
            context: context).text

        XCTAssertEqual(text, "The meeting is at 5:30 on Friday.", text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("5:30"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Friday"), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("4 PM"), "stale time survived: \(text)")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("four p m"), "stale time survived: \(text)")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Thursday"), "superseded day survived: \(text)")
    }
}
