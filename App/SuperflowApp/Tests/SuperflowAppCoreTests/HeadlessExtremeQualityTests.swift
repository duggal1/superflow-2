import XCTest
import SuperflowKernel
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import SuperflowPorts
import SuperflowTextCleanup
import SuperflowTextPipeline

private struct ExtremeModelProvider: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { url }
    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {}
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

/// EXTREME full-pipeline quality gate with the real S1-mini in the loop.
/// Deliberately garbled ASR text (fillers, stutters, false starts, garbled tech
/// terms, spoken numbers, self-corrections) across technical and professional
/// use. Runs through the exact production pipeline (all safeguard + format
/// stages), headless, no audio/UI. Enable with SUPERFLOW_EXTREME_PROBE=1.
final class HeadlessExtremeQualityTests: XCTestCase {
    func testExtremeFullPipelineQuality() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_EXTREME_PROBE"] == "1" else { return }
        let output = ProcessInfo.processInfo.environment["SUPERFLOW_EXTREME_OUT"]
            ?? "/private/var/folders/ct/cwpf7vpn059fkp932tq9zm4m0000gn/T/opencode/extreme-full.txt"
        let model = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("S1-mini not installed") }
        LlamaLogging.silence()
        let runtime = LlamaCppRuntime(sessions: 2)
        let cleaner = LlamaCleaner(modelProvider: ExtremeModelProvider(url: model), runtime: runtime)
        try await cleaner.prepare(compute: .gpu)
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        settings.cleanupStructure = "prose"
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
            Case(name: "broken-tech",
                 raw: "okay so um the the the JWT token it's it's expired you know and the api is is returning a four zero three not a five hundred wait no four two nine because uh the rate limiter is kicking in",
                 required: ["JWT", "429", "API", "rate limiter"],
                 forbidden: ["500", "you know", "um "]),
            Case(name: "broken-negation",
                 raw: "um so like I I I don't not want to uh deploy the the config on Friday actually no wait Thursday because the the staging cluster is is still red",
                 required: ["Thursday", "staging", "red"],
                 forbidden: ["Friday"]),
            Case(name: "garbled-path",
                 raw: "open lib slash backend slash main slash engine slash router slash prospect dash main dash engine dot t s then fix the get user by id function no wait getUserById and change the timeout from three thousand to five thousand milliseconds",
                 required: ["lib/backend/main/engine/router/prospect-main-engine.ts", "getUserById", "3,000", "5,000"],
                 forbidden: ["backend/backend", "get user by id"]),
            Case(name: "status-chaos",
                 raw: "the the response was a four oh four then a five oh three then a four two nine and uh finally a two hundred but but not a five hundred",
                 required: ["404", "503", "429", "200", "500", "not"],
                 forbidden: []),
            Case(name: "professional-meeting",
                 raw: "thanks everyone um so let's start with the the Q three numbers revenue was uh two point four million dollars which is is up from one point eight million last quarter and the the churn rate dropped to two point one percent from three point four percent the main driver was uh the enterprise tier you know which we shipped in in July",
                 required: ["Q3", "2.4", "2.1", "July", "enterprise"],
                 forbidden: ["you know", "the the"]),
            Case(name: "professional-standup",
                 raw: "so um yesterday I I worked on the the auth flow and and today I'm going to to review the pull request for the billing service unless uh unless the API contract changes you know then I'll pair with Sarah on that instead",
                 required: ["auth flow", "billing service", "API", "Sarah"],
                 forbidden: ["you know"]),
            Case(name: "professional-budget",
                 raw: "the the budget is uh four hundred fifty thousand dollars and we need two point five full time engineers by Q one next year okay",
                 required: ["450,000", "2.5", "Q1"],
                 forbidden: ["two.5"]),
            Case(name: "filler-only",
                 raw: "um uh um you know like I mean um uh basically um",
                 required: [],
                 // A content-free utterance need not normalize to empty, but it
                 // must not echo the raw vocal fillers ("um", "uh") and must
                 // stay short. Discourse markers are the model's styling call.
                 forbidden: ["um ", "uh ", "um,", "uh,"]),
        ]

        var report = ""
        var passed = 0
        for item in cases {
            let result = await pipeline.run(item.raw, context: context)
            let text = result.text
            var misses: [String] = []
            for token in item.required where !text.localizedCaseInsensitiveContains(token) { misses.append("missing:\(token)") }
            for token in item.forbidden where text.localizedCaseInsensitiveContains(token) { misses.append("bad:\(token)") }
            if misses.isEmpty { passed += 1 }
            report += "== \(item.name) ==\nIN:  \(item.raw)\nOUT: \(text)\nSTATE: \(result.draft.cleanupState)\nSCORE: \(misses.isEmpty ? "PASS" : misses.joined(separator: ", "))\n\n"
        }
        report = "extreme full-pipeline quality score: \(passed)/\(cases.count)\n\n" + report
        try report.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
        XCTAssertEqual(passed, cases.count, report)
    }
}
