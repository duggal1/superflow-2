import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowLLMCore
import SuperflowLLMLlamaCpp

/// Headless, real-model S1-mini benchmark. Gated by SUPERFLOW_PERF_PROBE=1 so the
/// ordinary unit suite never loads a 484 MB GGUF. Writes JSON under .proof/performance.
///
/// Env:
///  SUPERFLOW_PERF_PROBE=1         enable
///  SUPERFLOW_PERF_MODEL=<path>    GGUF (defaults to the installed Application Support model)
///  SUPERFLOW_PERF_PHASE=before|after  label written into the JSON
///  SUPERFLOW_PERF_MODE=quick|full quick = 1 pass / full = 3 passes
///  SUPERFLOW_PERF_SESSIONS=N      override runtime session count (default = runtime recommendation)
///  SUPERFLOW_PERF_COMPUTE=gpu|cpu default gpu
private struct InstalledModelProvider: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { url }
    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {}
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

private struct CaseResult: Encodable {
    let label: String
    let words: Int
    let deadlineMs: Int
    let pass: Int
    let success: Bool
    let error: String?
    let latencyMs: Int
    let prefillMs: Int?
    let generationMs: Int?
    let tokensIn: Int
    let tokensOut: Int
    let hitTokenCap: Bool
    let outputChars: Int
}

private struct BenchmarkReport: Encodable {
    let phase: String
    let model: String
    let machine: String
    let physicalGB: Int
    let cores: Int
    let sessions: Int
    let compute: String
    let mode: String
    let prepareMs: Int
    let cases: [CaseResult]
    let failureCount: Int
    let totalCount: Int
}

final class PerformanceBenchmarkTests: XCTestCase {
    func testRealS1LatencyAndFailureRate() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_PERF_PROBE"] == "1" else { return }
        let env = ProcessInfo.processInfo.environment
        let modelPath = env["SUPERFLOW_PERF_MODEL"]
            ?? "\(NSHomeDirectory())/Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf"
        let model = URL(fileURLWithPath: modelPath)
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw XCTSkip("S1-mini GGUF not found at \(model.path)")
        }
        let phase = env["SUPERFLOW_PERF_PHASE"] ?? "before"
        let mode = env["SUPERFLOW_PERF_MODE"] ?? "quick"
        let duration = env["SUPERFLOW_PERF_DURATION"] ?? "10s"
        guard ["10s", "30s", "1min"].contains(duration) else {
            throw XCTSkip("SUPERFLOW_PERF_DURATION must be 10s, 30s or 1min (10 min is NOT MEASURED)")
        }
        let passes = mode == "full" ? 2 : 1
        let sessionsOverride = env["SUPERFLOW_PERF_SESSIONS"].flatMap(Int.init)
        let compute: ModelCompute = env["SUPERFLOW_PERF_COMPUTE"] == "cpu" ? .cpu : .gpu

        LlamaLogging.silence()
        let sessions = sessionsOverride ?? LlamaCppRuntime.recommendedSessionCount
        let runtime = LlamaCppRuntime(sessions: sessions)
        let cleaner = LlamaCleaner(modelProvider: InstalledModelProvider(url: model), runtime: runtime)
        let prepareStart = DispatchTime.now().uptimeNanoseconds
        try await cleaner.prepare(compute: compute)
        let prepareMs = Int((DispatchTime.now().uptimeNanoseconds - prepareStart) / 1_000_000)

        // One duration per batch (coordinator safety cap). 10 min is deliberately
        // NOT MEASURED directly; a short synthetic workload below is labelled as
        // such. 10 s ~ 25 words, 30 s ~ 75, 1 min ~ 150 words of raw dictation.
        let durations: [(String, Int)] = [("10s", 25), ("30s", 75), ("1min", 150)]
            .filter { $0.0 == duration }
        var results: [CaseResult] = []
        // Real app default (1500 ms) plus a generous 30 s deadline that isolates model speed.
        let deadlines = [1_500, 30_000]
        for (label, words) in durations {
            let text = Self.asrText(words: words)
            for deadline in deadlines {
                for pass in 0..<passes {
                    let started = DispatchTime.now().uptimeNanoseconds
                    do {
                        let r = try await cleaner.clean(text, options: CleanOptions(deadlineMs: deadline))
                        let latency = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                        results.append(CaseResult(label: label, words: words, deadlineMs: deadline, pass: pass,
                                                  success: true, error: nil, latencyMs: latency,
                                                  prefillMs: r.prefillMs, generationMs: r.generationMs,
                                                  tokensIn: r.tokensIn, tokensOut: r.tokensOut,
                                                  hitTokenCap: r.hitTokenCap, outputChars: r.text.count))
                    } catch {
                        let latency = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                        results.append(CaseResult(label: label, words: words, deadlineMs: deadline, pass: pass,
                                                  success: false, error: "\(error)", latencyMs: latency,
                                                  prefillMs: nil, generationMs: nil,
                                                  tokensIn: 0, tokensOut: 0, hitTokenCap: false, outputChars: 0))
                    }
                }
            }
        }
        let report = BenchmarkReport(
            phase: phase, model: model.lastPathComponent,
            machine: "arm64 Apple Silicon", physicalGB: Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824),
            cores: ProcessInfo.processInfo.activeProcessorCount, sessions: sessions,
            compute: compute == .gpu ? "gpu" : "cpu", mode: "\(mode)-\(duration)", prepareMs: prepareMs,
            cases: results, failureCount: results.filter { !$0.success }.count, totalCount: results.count)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../..", isDirectory: true).standardizedFileURL
        let out = root.appendingPathComponent(".proof/performance/s1-\(phase)-\(duration).json")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: out)
        NSLog("S1_BENCH phase=\(phase) prepareMs=\(prepareMs) failures=\(report.failureCount)/\(report.totalCount) out=\(out.path)")
    }

    private static func asrText(words: Int) -> String {
        let bank = ["please", "send", "the", "report", "to", "the", "team", "tomorrow", "morning",
                    "and", "make", "sure", "the", "status", "code", "is", "four", "hundred", "twenty", "nine",
                    "we", "deploy", "to", "production", "every", "afternoon", "after", "the", "review",
                    "check", "the", "dashboard", "and", "the", "traces", "before", "the", "release"]
        var out = ""
        for i in 0..<max(1, words) { out += (i == 0 ? "" : " ") + bank[i % bank.count] }
        return out
    }
}
