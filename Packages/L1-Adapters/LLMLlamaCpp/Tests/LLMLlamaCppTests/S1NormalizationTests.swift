import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowLLMCore
import SuperflowLLMLlamaCpp

private struct NormalizationModel: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

final class S1NormalizationTests: XCTestCase {
    func testRealModelNormalizationAcrossRegisters() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_MODEL"] else {
            throw XCTSkip("Set SUPERFLOW_CLEANUP_MODEL to the local S1-mini GGUF.")
        }
        LlamaLogging.silence()
        let cleaner = LlamaCleaner(modelProvider: NormalizationModel(url: URL(fileURLWithPath: path)),
                                   runtime: LlamaCppRuntime(sessions: 1))
        try await cleaner.prepare()
        let cases: [(String, [String])] = [
            ("so um i need to like send the the report by uh friday no wait make that thursday", ["thursday"]),
            ("please send the report tomorrow um", ["tomorrow"]),
            ("i think the answer is forty two no sorry forty three", ["43"]),
            ("the invoice came to twenty three thousand four hundred and fifty dollars", ["23,450"]),
            ("um", []),
            ("hmm im gonna be late theres a cute dog outside i cant just walk past him", ["dog", "outside"]),
            ("um use S1-mini and Nemotron with GPT-6 Astra and Hugging Face", ["s1-mini", "nemotron", "astra", "hugging face"]),
            ("do not delete the file keep all five backups before the release", ["not", "all", "before"]),
        ]

        // Verbatim official S1-mini outputs recorded in
        // agents/codex/s1-quality/results/prompt-comparison.json (empty think
        // block, temperature 0, top_k 1). These are EXACT assertions: a
        // plausible paraphrase or a superseded value is a FAIL. The empty
        // string is a valid official result for filler-only input ("um").
        let exactOutputs: [String: [String: String]] = [
            "i think the answer is forty two no sorry forty three": [
                "casual": "i think the answer is 43",
                "semi-casual": "I think the answer is 43",
                "semi-formal": "I think the answer is 43.",
                "formal": "I think the answer is 43.",
            ],
            "um": [
                "casual": "", "semi-casual": "", "semi-formal": "", "formal": "",
            ],
            "the invoice came to twenty three thousand four hundred and fifty dollars": [
                "casual": "the invoice came to $23,450",
                "semi-casual": "the invoice came to $23,450",
                "semi-formal": "The invoice came to $23,450.",
                "formal": "The invoice came to $23,450.",
            ],
        ]

        for styling in ["casual", "semi-casual", "semi-formal", "formal"] {
            for (input, required) in cases {
                let result = try await cleaner.clean(input, options: CleanOptions(
                    styling: styling, structure: "prose", deadlineMs: 30_000))
                XCTAssertFalse(result.hitTokenCap, styling)
                if input == "um" { XCTAssertTrue(result.text.isEmpty, styling) }
                else { XCTAssertFalse(result.text.isEmpty, styling) }
                for term in required {
                    XCTAssertTrue(result.text.localizedCaseInsensitiveContains(term), "\(styling): missing \(term)")
                }
                if let expected = exactOutputs[input]?[styling] {
                    XCTAssertEqual(result.text, expected,
                                   "\(styling): exact official output mismatch for \"\(input)\"")
                }
                // The superseded self-correction value must never survive.
                if input.contains("forty two no sorry") {
                    XCTAssertFalse(result.text.localizedCaseInsensitiveContains("42"),
                                   "\(styling): superseded answer 42 survived in \(result.text)")
                }
                XCTAssertFalse(result.text.contains("<think>"))
            }
        }
    }
}
