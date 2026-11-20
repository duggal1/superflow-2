import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTextCleanup
@testable import SuperflowTextPipeline

/// Offline gate: feeds the exact raw S1-mini completions measured by
/// tools/brutal-s1 through the REAL post-model pipeline stages and asserts the
/// text the app would actually deliver. No model load, no audio, no UI.
final class BrutalFormattingProbeTests: XCTestCase {
    private func polished(_ modelOutput: String, structure: String = "lists") async -> String {
        var settings = AppSettings.default
        settings.cleanupStructure = structure
        let built = TextPipelineBuilder.make(settings: settings)
        let preModel: Set<String> = [
            "selfCorrection", "preCleanupRepair", "aiEraPreCleanup", "preCleanupModelNames",
            "techDictionaryPreCleanup", "disfluency", "numbers", "cleanup",
        ]
        let pipeline = TextPipeline(stages: built.stages.filter { !preModel.contains($0.id) },
                                    seedProtected: built.seedProtected)
        return await pipeline.run(modelOutput, context: TextContext(settings: settings)).text
    }

    func testRawS1OutputsAreRepairedDownstream() async {
        let cases: [(name: String, raw: String, required: [String], forbidden: [String])] = [
            ("final-period",
             "Okay, so the JWT token is expired, and the API is returning a 429 because the rate limiter is kicking in",
             ["429", "JWT", "kicking in."], []),
            ("ordinal-date",
             "The invoice came to $23,450 and it's due on March 3rd, 2026.",
             ["$23,450", "March 3, 2026"], ["3rd"]),
            ("model-names",
             "Use S1 Mini and Nemotron with the new deployment next week and check the next.js app still builds.",
             ["S1-mini", "Nemotron"], ["S1 Mini"]),
            ("card-list",
             "So for the trip we need to pack sunscreen and then also a first aid kit and chargers for everything.",
             ["- sunscreen", "- a first aid kit", "- chargers for everything"], []),
            ("dash-spoken",
             "The plan is -ship, the API, -update the docs, -tell the team.",
             ["- ship the API", "- update the docs", "- tell the team"], [" -ship"]),
            ("point-spoken",
             "The results are: 0.1 latency is high, 0.2 memory is fine, 0.03 CPU is low.",
             ["- latency is high", "- memory is fine", "- CPU is low"], []),
            ("hyphen-spoken",
             "The checklist is -restart the server -clear the cache -verify the logs.",
             ["- restart the server", "- clear the cache", "- verify the logs"], []),
            ("bullet-spoken",
             "The agenda is: Bullet, introductions, Bullet, demo, Bullet, questions.",
             ["- introductions", "- demo", "- questions"], []),
        ]
        var failures: [String] = []
        for item in cases {
            let out = await polished(item.raw)
            for token in item.required where !out.localizedCaseInsensitiveContains(token) {
                failures.append("\(item.name): missing \(token) in \(out)")
            }
            for token in item.forbidden where out.localizedCaseInsensitiveContains(token) {
                failures.append("\(item.name): bad \(token) in \(out)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testTechnicalTermCasingInFullPipeline() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let out = await pipeline.run("i use next.js daily", context: TextContext(settings: settings)).text
        XCTAssertEqual(out, "I use Next.js daily.", out)
    }

    /// S1 outputs that the production CleanGuard accepts must not cause a
    /// retry or the raw-text fallback. This exercises the real guard code with
    /// real measured completions, without loading a model.
    func testCleanGuardAcceptsRealS1Completions() {
        let pairs: [(String, String)] = [
            ("um okay so like the the JWT token it's expired and the api is returning a four zero three no wait four two nine",
             "Okay, so the JWT token is expired, and the API is returning a 429."),
            ("the the response was a four oh four then a five oh three then a four two nine and uh finally a two hundred but not a five hundred",
             "The response was a 404, then a 503, then a 429, and finally a 200, but not a 500."),
            ("i think the answer is forty two no sorry forty three", "I think the answer is 43."),
            ("first um we need to fix the paywall second add the pricing page third update the docs",
             "1. Fix the paywall.\n2. Add the pricing page.\n3. Update the docs."),
        ]
        for (input, output) in pairs {
            let result = CleanResult(text: output, tokensIn: 10, tokensOut: 8,
                                     hitTokenCap: false, latencyMs: 0)
            let failure = CleanGuard.verify(input: input, protected: Protected(),
                                            result: result, cap: 512)
            XCTAssertNil(failure, "S1 output rejected -> fallback. \(String(describing: failure)) for \(output)")
        }
    }
}
