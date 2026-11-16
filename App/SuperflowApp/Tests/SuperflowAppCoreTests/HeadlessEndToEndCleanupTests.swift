import XCTest
import SuperflowKernel
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import SuperflowPorts
import SuperflowTextCleanup
import SuperflowTextPipeline

/// Full production chain with the real pinned S1-mini (direct llama.cpp runtime
/// instead of the XPC transport): S1 -> CleanupService guard -> all stages.
/// Enable with SUPERFLOW_E2E_PROBE=1.
private struct LocalModelProvider: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { url }
    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {}
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

final class HeadlessEndToEndCleanupTests: XCTestCase {
    func testEndToEndGrammarAndLists() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_E2E_PROBE"] == "1" else { return }
        let output = ProcessInfo.processInfo.environment["SUPERFLOW_E2E_OUT"]
            ?? "/private/var/folders/ct/cwpf7vpn059fkp932tq9zm4m0000gn/T/opencode/e2e-cleanup.txt"
        let model = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("S1-mini not installed") }
        LlamaLogging.silence()
        let runtime = LlamaCppRuntime(sessions: 2)
        let cleaner = LlamaCleaner(modelProvider: LocalModelProvider(url: model), runtime: runtime)
        try await cleaner.prepare(compute: .gpu)
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        settings.cleanupStructure = "lists"
        settings.harperEnabled = false
        let pipeline = TextPipelineBuilder.make(
            settings: settings,
            dependencies: TextPipelineDependencies(cleaner: CleanupService(cleaner: cleaner)))
        let context = TextContext(settings: settings)
        let cases = [
            "for the trip we need to pack sunscreen a first aid kit and chargers for everything",
            "here are the steps first open the app second press record third copy the text",
            "um so like the report is due friday no wait make that thursday",
            "i think the answer is forty two no sorry forty three",
            "he dont have no money and we cant send the report",
            "hey sarah just wanted to follow up on the proposal can you send the numbers by end of week thanks john",
        ]
        var report = "harper=\(settings.harperEnabled) structure=\(settings.cleanupStructure)\n"
        for input in cases {
            let result = await pipeline.run(input, context: context)
            report += "IN:      \(input)\nOUT:     \(result.text)\nSTATE:   \(result.draft.cleanupState)\n\n"
        }
        let transcripts = [
            ("backend", "The next year's APOINT is experience intermediate illitency because the PostgreSQL connection pool is reaching the maximum capacity we need to inspect the redish cash configuration analyze open trace and identifys is restarting the affected pod. The P 95 response should remain below 200ms before deploying the fixed verifier gRPC communication varier validate UNTC and short JWT token refresh or hardcored security finally run the complete CI/CD pipeline confirm that all integration test pass and monitor the production environment for Unexpected errors after deployment."),
            ("ai", "We are optimizing a quantized language model for local inference on Apple Silicon. The current implementation use MLX with 4 bit quantization or token generation slows down when memory bandwidth becomes saturated. We should benchmark time to first token measure token per second and compare skeptical decoding against standard autoaggressive inference. The KV cash must remain within variable unified naming budget additionally we need to evaluate metal GPU. A utilization reduce unnecessary tensor allocation and profile the attention kernel. Our objective is to is consistent streaming performance withoutput quality numerical stability or model accuracy."),
        ]
        let preIDs: Set<String> = ["selfCorrection", "preCleanupRepair", "aiEraPreCleanup",
                                   "preCleanupModelNames", "techDictionaryPreCleanup"]
        let s1First = TextPipeline(stages: pipeline.stages.filter { !preIDs.contains($0.id) }
                                   + pipeline.stages.filter { preIDs.contains($0.id) },
                                   seedProtected: pipeline.seedProtected)
        for (label, input) in transcripts {
            let current = await pipeline.run(input, context: context)
            let reordered = await s1First.run(input, context: context)
            let rawModel = try await cleaner.clean(input, options: CleanOptions(deadlineMs: 10_000))
            report += "== \(label) ==\nRAW: \(input)\nS1: \(rawModel.text)\nCURRENT: \(current.text)\nSTATE: \(current.draft.cleanupState)\nWHY: \(current.draft.diagnostics.filter { $0.stage.hasPrefix("cleanup") }.map(\.message).joined(separator: ","))\nS1FIRST: \(reordered.text)\nSTATE2: \(reordered.draft.cleanupState)\n\n"
        }
        try report.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
    }

    /// Brutal general invariants. No expected exact strings: only facts that
    /// must survive any cleanup. Enable with SUPERFLOW_E2E_PROBE=1.
    func testBrutalInvariants() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_E2E_PROBE"] == "1" else { return }
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

        let long = (0..<55).map { index in
            "step \(index + 1) verify the build and report the status"
        }.joined(separator: ". ")
        let cases: [(String, String, [String], [String])] = [
            ("negation", "do not send the report", ["not"], []),
            ("status", "the server returned 503 not 403", ["503", "403", "not"], []),
            ("retry", "retry 500 and keep 200 as the target", ["500", "200"], []),
            ("paths", "open hero.tsx and package.json then run npm install", ["hero.tsx", "package.json"], []),
            ("url", "the url is https://example.com/a/b for the api", ["example.com/a/b"], []),
            ("revision", "move it to Thursday actually no Wednesday at three thirty", ["Wednesday"], ["Thursday"]),
            ("numeric-revision", "i think the answer is forty two no sorry forty three", ["43"], ["42"]),
            ("negation-apostrophe", "he dont have no money and we cant send it", ["don't", "can't", "no"], []),
            ("list", "first open the app second press record third copy the text", ["\n"], []),
            ("long", long, ["step 55", "status"], []),
        ]
        var failures: [String] = []
        for (label, input, required, forbidden) in cases {
            let result = await pipeline.run(input, context: context)
            let text = result.text
            for token in required where !text.localizedCaseInsensitiveContains(token) {
                failures.append("\(label): missing '\(token)' in '\(text)'")
            }
            for token in forbidden where text.localizedCaseInsensitiveContains(token) {
                failures.append("\(label): unexpected '\(token)' in '\(text)'")
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               result.draft.cleanupState == .fallback {
                let why = result.draft.diagnostics.filter { $0.stage.hasPrefix("cleanup") }
                    .map(\.message).joined(separator: ",")
                failures.append("\(label): unexpected fallback [\(why)] text=\(text)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
