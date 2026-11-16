import Foundation
import SuperflowKernel
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import SuperflowPorts
import XCTest

/// Runs the real pinned S1-mini cleanup over raw ASR text with no XPC helper
/// and no UI. Enable with SUPERFLOW_S1_PROBE=1.
private struct LocalModelProvider: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { url }
    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {}
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

final class HeadlessS1ProbeTests: XCTestCase {
    func testRealS1CleanupAttribution() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_S1_PROBE"] == "1" else { return }
        let output = ProcessInfo.processInfo.environment["SUPERFLOW_S1_OUT"]
            ?? "/private/var/folders/ct/cwpf7vpn059fkp932tq9zm4m0000gn/T/opencode/s1-probe.txt"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../..", isDirectory: true).standardizedFileURL
        let model = root.appendingPathComponent(".models/s1-mini/s1-mini-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw XCTSkip("S1-mini model is not installed at \(model.path)")
        }
        LlamaLogging.silence()
        let runtime = LlamaCppRuntime(sessions: 2)
        let cleaner = LlamaCleaner(modelProvider: LocalModelProvider(url: model), runtime: runtime)
        try await cleaner.prepare(compute: .gpu)

        let rawASR = [
            "The rediscache and validation is broken",
            "Check the Open Telemetry Traces before the release",
            "We deploy to Kubernetes every afternoon",
            "Off two point zero returned a five hundred three error",
            "The CICD pipeline failed on the last commit",
            "Time to first token matters more than tokens per second",
            "The intermittent failures are in the metal GPU path",
            "Evaluate metal GPU utilization and model accuracy",
            "Why did the queue stall during token generation",
            "Please ensure the dashboard shows the right number",
            "Time to first two. Can matters more than tokens per second",
        ]
        var report = "model=\(model.lastPathComponent)\n"
        for raw in rawASR {
            let result = try await cleaner.clean(raw, options: CleanOptions())
            report += "RAW:     \(raw)\nCLEANED: \(result.text)\ntokens=\(result.tokensIn)/\(result.tokensOut) cap=\(result.hitTokenCap)\n\n"
        }
        report += "== grammar and list control-line cases ==\n"
        let directed: [(String, CleanOptions)] = [
            ("so for the trip we need to pack sunscreen and then also a first aid kit and um chargers for everything",
             CleanOptions(structure: "lists")),
            ("so for the trip we need to pack sunscreen and then also a first aid kit and um chargers for everything",
             CleanOptions(structure: "prose")),
            ("first we need to pack sunscreen second a first aid kit and third chargers for everything",
             CleanOptions(structure: "lists")),
            ("here are the steps first open the app second press record third copy the text",
             CleanOptions(structure: "lists")),
            ("for the trip we need to pack sunscreen a first aid kit and chargers for everything",
             CleanOptions(structure: "lists")),
            ("i think the answer is forty two no sorry forty three", CleanOptions()),
            ("he dont have no money and we cant send the report", CleanOptions()),
            ("um so like the report is due friday no wait make that thursday", CleanOptions()),
            ("hey sarah just wanted to follow up on the proposal can you send the numbers by end of week thanks john",
             CleanOptions(context: "email")),
        ]
        for (raw, options) in directed {
            let result = try await cleaner.clean(raw, options: options)
            report += "STRUCT=\(options.structure) CTX=\(options.context)\nRAW:     \(raw)\nCLEANED: \(result.text)\n\n"
        }
        try report.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
    }
}
