import Foundation
import XCTest
import SuperflowInferenceHelperCore
import SuperflowKernel
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import SuperflowPorts

final class LiveInferenceHelperTests: XCTestCase {
    func testHelperLoadsRealModelAndCleansSpeech() async throws {
        guard let path = ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_MODEL"] else {
            throw XCTSkip("Set SUPERFLOW_CLEANUP_MODEL to the installed S1-mini GGUF.")
        }
        LlamaLogging.silence()
        let service = InferenceHelperService()
        let prepared = expectation(description: "real model preparation")
        service.prepareModel(atPath: path, gpu: true) { success, error in
            XCTAssertTrue(success, error ?? "Model preparation failed")
            prepared.fulfill()
        }
        await fulfillment(of: [prepared], timeout: 90)
        let completed = expectation(description: "real model completion")
        let prompt = LlamaPrompt.render(text: "so um send the report by uh thursday", options: CleanOptions(structure: "prose"))
        service.complete(prompt: prompt, maxTokens: 64, deadlineMs: 30_000, interactive: true) {
            text, tokens, capped, _, _, error in
            XCTAssertNil(error)
            XCTAssertFalse(capped)
            XCTAssertGreaterThan(tokens, 0)
            XCTAssertTrue(text?.localizedCaseInsensitiveContains("thursday") == true)
            XCTAssertFalse(text?.localizedCaseInsensitiveContains(" um ") == true)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 35)
    }
}
