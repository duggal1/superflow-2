import Foundation
import CryptoKit
import SuperflowKernel
import SuperflowPorts
import XCTest
@testable import SuperflowLLMCore

private actor StubProvider: ModelProvider {
    var url: URL?
    init(url: URL?) { self.url = url }
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let url else { throw SuperflowError.modelUnavailable(profileID) }
        return url
    }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let url else { throw SuperflowError.modelUnavailable("llm") }
        progress(1)
        return url
    }
}

private actor FakeRuntime: LlamaRuntime {
    var response: String
    var loadedURL: URL?
    private(set) var prompts: [String] = []

    init(response: String) { self.response = response }

    func load(modelURL: URL) async throws { loadedURL = modelURL }
    func countTokens(_ text: String) async -> Int? { LlamaPrompt.estimateTokens(text) }
    func complete(prompt: String, maxTokens: Int) async throws -> String {
        prompts.append(prompt)
        return response
    }
}

final class LlamaCleanerTests: XCTestCase {
    func testPromptCarriesOptionsAndText() {
        let options = CleanOptions(styling: "casual", structure: "bullets", context: "email")
        let prompt = LlamaPrompt.render(text: "hello there", options: options)
        XCTAssertTrue(prompt.contains("casual"))
        XCTAssertTrue(prompt.contains("bullets"))
        XCTAssertTrue(prompt.contains("email"))
        XCTAssertTrue(prompt.contains("hello there"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant"))
        XCTAssertTrue(prompt.contains("[Styling: casual] [Structure: bullets] [Context: email]"))
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant\n<think>\n\n</think>\n\n"))
    }

    func testBundledPromptMatchesPinnedHash() throws {
        let data = try XCTUnwrap(LlamaPrompt.resourceData())
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "7d9d1b20117eb230cc5b91ed3470dea314f33562ca7731a88520aaf6fc3d2602")
    }

    func testPlainTemplateHasNoChatTokens() {
        let prompt = LlamaPrompt.render(text: "hello", options: CleanOptions(), template: .plain)
        XCTAssertFalse(prompt.contains("<|im_start|>"))
        XCTAssertTrue(prompt.contains("[Styling: semi-formal] [Structure: prose] [Context: general]"))
        XCTAssertTrue(prompt.hasSuffix("hello"))
    }

    func testSanitizeStripsLabelsTokensAndWrapping() {
        XCTAssertEqual(LlamaPrompt.sanitize("assistant: Hello world."), "Hello world.")
        XCTAssertEqual(LlamaPrompt.sanitize("<|im_end|>Hello world.<|im_end|>"), "Hello world.")
        XCTAssertEqual(LlamaPrompt.sanitize("```\nHello world.\n```"), "Hello world.")
        XCTAssertEqual(LlamaPrompt.sanitize("\"Hello world.\""), "Hello world.")
        XCTAssertEqual(LlamaPrompt.sanitize("Cleaned transcript:\nHello."), "Hello.")
    }

    func testTokenEstimateIsBounded() {
        XCTAssertEqual(LlamaPrompt.estimateTokens(""), 0)
        XCTAssertEqual(LlamaPrompt.estimateTokens("a"), 1)
        XCTAssertEqual(LlamaPrompt.estimateTokens(String(repeating: "a", count: 400)), 100)
    }

    func testUnavailableCleanerReportsNotReadyAndThrows() async {
        let cleaner = LlamaCleaner(modelProvider: StubProvider(url: URL(fileURLWithPath: "/tmp/none.gguf")),
                                   runtime: UnavailableLlamaRuntime())
        let ready = await cleaner.isReady
        XCTAssertFalse(ready)
        let tokens = await cleaner.countTokens("hello world")
        XCTAssertEqual(tokens, 0)
        do {
            _ = try await cleaner.clean("hello world", options: CleanOptions())
            XCTFail("expected modelUnavailable")
        } catch let error as SuperflowError {
            guard case .modelUnavailable(let message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(message.contains("llama.cpp"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testCleanLoadsOnceAndReturnsSanitizedResult() async throws {
        let url = URL(fileURLWithPath: "/tmp/s1-mini.gguf")
        let runtime = FakeRuntime(response: "assistant: Hello, world.")
        let cleaner = LlamaCleaner(modelProvider: StubProvider(url: url), runtime: runtime)
        let result = try await cleaner.clean("um hello world", options: CleanOptions())
        XCTAssertEqual(result.text, "Hello, world.")
        XCTAssertGreaterThan(result.tokensIn, 0)
        XCTAssertGreaterThan(result.tokensOut, 0)
        XCTAssertFalse(result.hitTokenCap)
        let ready = await cleaner.isReady
        XCTAssertTrue(ready)
        let loaded = await runtime.loadedURL
        XCTAssertEqual(loaded, url)

        _ = try await cleaner.clean("again", options: CleanOptions())
        let prompts = await runtime.prompts
        XCTAssertEqual(prompts.count, 2)
    }

    func testEmptyCompletionThrows() async {
        let url = URL(fileURLWithPath: "/tmp/s1-mini.gguf")
        let cleaner = LlamaCleaner(modelProvider: StubProvider(url: url),
                                   runtime: FakeRuntime(response: "  <|im_end|>  "))
        do {
            _ = try await cleaner.clean("hello", options: CleanOptions())
            XCTFail("expected empty completion failure")
        } catch let error as SuperflowError {
            guard case .modelUnavailable(let message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(message.contains("empty completion"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testHitTokenCapWhenOutputIsLong() async throws {
        let url = URL(fileURLWithPath: "/tmp/s1-mini.gguf")
        let long = String(repeating: "word ", count: 100)
        let cleaner = LlamaCleaner(modelProvider: StubProvider(url: url),
                                   runtime: FakeRuntime(response: long))
        let result = try await cleaner.clean("hello", options: CleanOptions(maxNewTokens: 10))
        XCTAssertTrue(result.hitTokenCap)
    }
}
