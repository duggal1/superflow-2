import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowLLMCore
import SuperflowLLMLlamaCpp

private struct ProbeModel: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

final class ParallelCapacityProbeTests: XCTestCase {
    func testCompareConcurrentS1Requests() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_MODEL"] else {
            throw XCTSkip("Set SUPERFLOW_CLEANUP_MODEL to the installed S1-mini GGUF.")
        }
        LlamaLogging.silence()
        let cleaner = LlamaCleaner(modelProvider: ProbeModel(url: URL(fileURLWithPath: path)),
                                   runtime: LlamaCppRuntime(sessions: 4))
        try await cleaner.prepare(compute: .gpu)
        let input = "please send the report to the team tomorrow morning and make sure the status code is 429 when the rate limit is reached"
        let options = CleanOptions(styling: "semi-formal", structure: "prose", deadlineMs: 30_000)
        let baseline = try await cleaner.clean(input, options: options)
        XCTAssertFalse(baseline.text.isEmpty)
        XCTAssertFalse(baseline.hitTokenCap)
        var samples: [Int: [Double]] = [:]
        for round in 0..<5 {
            let order = round.isMultiple(of: 2) ? [1, 2, 4] : [4, 2, 1]
            for workers in order {
                let start = ContinuousClock.now
                var errors = 0
                for _ in 0..<(4 / workers) {
                    await withTaskGroup(of: CleanResult?.self) { group in
                        for _ in 0..<workers {
                            group.addTask { try? await cleaner.clean(input, options: options) }
                        }
                        for await result in group {
                            guard let result, !result.hitTokenCap, result.text == baseline.text else {
                                errors += 1
                                continue
                            }
                        }
                    }
                }
                let elapsed = start.duration(to: .now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                samples[workers, default: []].append(seconds)
                print("PROBE workers=\(workers) round=\(round) requests=4 errors=\(errors) seconds=\(seconds)")
                XCTAssertEqual(errors, 0)
            }
        }
        for workers in [1, 2, 4] {
            let values = samples[workers, default: []].sorted()
            print("PROBE_SUMMARY workers=\(workers) median=\(values[2]) min=\(values[0]) max=\(values[4])")
        }
    }
}
