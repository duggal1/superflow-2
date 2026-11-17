import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowLLMCore
import SuperflowLLMLlamaCpp

/// Headless probe: runs the REAL S1-mini cleanup model over deliberately broken
/// transcripts and writes every output to a report for quality inspection.
/// Gated on SUPERFLOW_CLEANUP_MODEL so normal `swift test` stays fast.
private struct ProbeModelProvider: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

final class ExtremeLiveCleanupProbe: XCTestCase {
    func testExtremeFixturesThroughRealModel() async throws {
        guard let modelPath = ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_MODEL"] else {
            throw XCTSkip("Set SUPERFLOW_CLEANUP_MODEL to the local S1-mini GGUF.")
        }
        LlamaLogging.silence()
        let runtime = LlamaCppRuntime(sessions: 2)
        let cleaner = LlamaCleaner(modelProvider: ProbeModelProvider(url: URL(fileURLWithPath: modelPath)),
                                   runtime: runtime)
        try await cleaner.prepare(compute: .gpu)

        let fixtures: [(String, String)] = [
            ("broken-tech", "okay so um the the the JWT token it's it's expired you know and the api is is returning a four zero three not a five hundred wait no four two nine because uh the rate limiter is kicking in"),
            ("broken-negation", "um so like I I I don't not want to uh deploy the the config on Friday actually no wait Thursday because the the staging cluster is is still red"),
            ("garbled-path", "open lib slash backend slash main slash engine slash router slash prospect dash main dash engine dot t s then fix the get user by id function no wait getUserById and change the timeout from three thousand to five thousand milliseconds"),
            ("status-chaos", "the the response was a four oh four then a five oh three then a four two nine and uh finally a two hundred but but not a five hundred"),
            ("professional-meeting", "thanks everyone um so let's start with the the Q three numbers revenue was uh two point four million dollars which is is up from one point eight million last quarter and the the churn rate dropped to two point one percent from three point four percent the main driver was uh the enterprise tier you know which we shipped in in July"),
            ("professional-standup", "so um yesterday I I worked on the the auth flow and and today I'm going to to review the pull request for the billing service unless uh unless the API contract changes you know then I'll pair with Sarah on that instead"),
            ("professional-budget", "the the budget is uh four hundred fifty thousand dollars and we need two point five full time engineers by Q one next year okay"),
            ("filler-only", "um uh um you know like I mean um uh basically um"),
        ]

        var report = "# Extreme live cleanup probe\n\nModel: \(modelPath)\n\n"
        var failures: [String] = []
        for (name, input) in fixtures {
            let options = CleanOptions(styling: "semi-formal", structure: "prose",
                                       context: "general", deadlineMs: 30_000)
            let result = try await CleanPriority.$current.withValue(.background) {
                try await cleaner.clean(input, options: options)
            }
            report += "## \(name)\n\nIN : \(input)\n\nOUT: \(result.text)\n\n"
            report += "tokens \(result.tokensIn)->\(result.tokensOut), \(result.latencyMs)ms, capped=\(result.hitTokenCap)\n\n"
            if result.hitTokenCap || result.text.isEmpty {
                failures.append("\(name): capped=\(result.hitTokenCap) empty=\(result.text.isEmpty)")
            }
        }
        if let reportPath = ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_REPORT"] {
            let url = URL(fileURLWithPath: reportPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.write(to: url, atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
    }
}
