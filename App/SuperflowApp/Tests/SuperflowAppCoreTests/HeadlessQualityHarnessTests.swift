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
/// scored on required facts, forbidden artifacts and formatting. No audio,
/// no UI. Enable with SUPERFLOW_QUALITY_PROBE=1.
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
            let required: [String]
            let forbidden: [String]
        }
        let cases = [
            Case(name: "backend",
                 raw: "the next year's APOINT is experience intermediate illitency because the postgresql connection pool is reaching the maximum capacity we need to inspect the redish cash configuration analyze open trace and identifys is restarting the affected pod. the p 95 response should remain below 200ms",
                 required: ["Next.js", "API endpoint", "intermittent latency", "PostgreSQL", "Redis cache", "OpenTelemetry", "Kubernetes", "p95", "200"],
                 forbidden: ["APOINT", "illitency", "redish cash", "open trace", "identifys", "next year's"]),
            Case(name: "engineering",
                 raw: "we are optimizing a quantized language model for local inference on apple silicon the current implementation use mlx with 4 bit quantization or token generation slows down when memory bandwidth becomes saturated we should benchmark time to first token measure token per second and compare skeptical decoding against standard autoaggressive inference the kv cash must remain within variable unified naming budget additionally we need to evaluate metal gpu utilization",
                 required: ["uses MLX", "4-bit", "time to first token", "tokens per second", "speculative decoding", "autoregressive", "KV cache", "Metal GPU", "utilization"],
                 forbidden: ["skeptical", "autoaggressive", "kv cash", "withoutput"]),
            Case(name: "meeting",
                 raw: "hey can you move the meeting to thursday actually no wednesday at three thirty and tell sarah the budget spreadsheet needs to be updated before friday",
                 required: ["Wednesday", "3:30", "Sarah", "budget spreadsheet", "Friday"],
                 forbidden: ["Thursday", "thursday"]),
            Case(name: "stutter",
                 raw: "um so like i i i think we we should maybe uh just ship it um tomorrow",
                 required: ["I think", "ship it", "tomorrow"],
                 forbidden: [" um ", " uh ", "i i", "we we"]),
            Case(name: "negation",
                 raw: "no dont delete the file and make sure we do not send it to the client",
                 required: ["do not delete", "do not send", "client"],
                 forbidden: []),
            Case(name: "numbers",
                 raw: "the invoice came to twenty three thousand four hundred and fifty dollars and its due on march third twenty twenty six",
                 required: ["23,450", "March 3, 2026"],
                 forbidden: []),
            Case(name: "email",
                 raw: "hey sarah just wanted to follow up on the proposal can you send the numbers by end of week thanks john",
                 required: ["Sarah", "proposal", "end of week", "John"],
                 forbidden: []),
            Case(name: "list",
                 raw: "for the trip we need to pack sunscreen and then also a first aid kit and um chargers for everything",
                 required: ["\n-"],
                 forbidden: []),
            Case(name: "selfcorrection",
                 raw: "i think the answer is forty two no sorry forty three",
                 required: ["43"],
                 forbidden: ["42"]),
            Case(name: "garble-mixed",
                 raw: "the next year's APOINT is down again and the redish cash is full so check the open trace in kubernetes",
                 required: ["Next.js API endpoint", "Redis cache", "OpenTelemetry", "Kubernetes"],
                 forbidden: ["APOINT", "redish cash", "open trace", "next year's"]),
            Case(name: "ai-mixed",
                 raw: "benchmark time to first token and token per second and compare skeptical decoding with autoaggressive inference while the kv cash grows",
                 required: ["time to first token", "tokens per second", "speculative decoding", "autoregressive", "KV cache"],
                 forbidden: ["skeptical", "autoaggressive", "kv cash"]),
            Case(name: "time-revision",
                 raw: "the meeting is at four p m on thursday actually no friday at five thirty",
                 required: ["Friday", "5:30"],
                 forbidden: ["Thursday"]),
            Case(name: "negation-stack",
                 raw: "the server is down and we do not have a backup and we cannot rollback so do not deploy",
                 required: ["do not have", "cannot rollback", "do not deploy"],
                 forbidden: []),
            Case(name: "email-address",
                 raw: "send the report to john at john dot example dot com by friday",
                 required: ["john@john.example.com", "Friday"],
                 forbidden: [" dot "] ),
            Case(name: "list-alt",
                 raw: "we need to buy milk and eggs and bread for the office",
                 required: ["\n-"],
                 forbidden: []),
        ]

        var report = ""
        var passed = 0
        for item in cases {
            let result = await pipeline.run(item.raw, context: context)
            let text = result.text
            var misses: [String] = []
            for token in item.required where !text.localizedCaseInsensitiveContains(token) {
                misses.append("missing:\(token)")
            }
            for token in item.forbidden where text.localizedCaseInsensitiveContains(token) {
                misses.append("bad:\(token)")
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || !"?!.".contains(trimmed.last!) { misses.append("no-final-punctuation") }
            if trimmed.first?.isUppercase != true { misses.append("no-capital") }
            if text.contains("  ") { misses.append("double-space") }
            if misses.isEmpty { passed += 1 }
            report += "== \(item.name) ==\nIN:  \(item.raw)\nOUT: \(text)\nSTATE: \(result.draft.cleanupState)\nSCORE: \(misses.isEmpty ? "PASS" : misses.joined(separator: ", "))\n\n"
        }
        report = "quality score: \(passed)/\(cases.count)\n\n" + report
        try report.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
        XCTAssertEqual(passed, cases.count, report)
    }
}
