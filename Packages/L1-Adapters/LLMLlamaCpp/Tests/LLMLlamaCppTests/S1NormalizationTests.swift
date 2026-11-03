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
                XCTAssertFalse(result.text.contains("<think>"))
            }
        }
    }
}
