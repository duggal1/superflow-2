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
    private(set) var outputCaps: [Int] = []

    init(response: String) { self.response = response }

    func load(modelURL: URL) async throws { loadedURL = modelURL }
    func countTokens(_ text: String) async -> Int? { LlamaPrompt.estimateTokens(text) }
    func complete(prompt: String, maxTokens: Int) async throws -> String {
        prompts.append(prompt)
        outputCaps.append(maxTokens)
        return response
    }
}

final class LlamaCleanerTests: XCTestCase {
    func testPromptCarriesOptionsAndText() {
        let options = CleanOptions(styling: "casual", structure: "lists", context: "email")
        let prompt = LlamaPrompt.render(text: "hello there", options: options)
        XCTAssertTrue(prompt.contains("casual"))
        XCTAssertTrue(prompt.contains("lists"))
        XCTAssertTrue(prompt.contains("email"))
        XCTAssertTrue(prompt.contains("hello there"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant"))
        XCTAssertTrue(prompt.contains("[Styling: casual] [Structure: lists] [Context: email]"))
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant\n<think>\n\n</think>\n\n"))
    }

    /// The app has context profiles whose values predate S1-mini's trained set.
    /// Only the four styling, two structure and two context values the model was
    /// trained on may reach the control line.
    func testControlLineNormalizesUntrainedValues() {
        let options = CleanOptions(styling: "direct", structure: "bullets", context: "coding")
        XCTAssertEqual(LlamaPrompt.controlLine(options: options),
                       "[Styling: semi-formal] [Structure: lists] [Context: general]")
    }

    func testControlLineMapsEveryLegacyAlias() {
        let cases: [(styling: String, structure: String, context: String,
                     expected: String)] = [
            ("direct", "list", "code", "[Styling: semi-formal] [Structure: lists] [Context: general]"),
            ("DIRECT", "LIST", "PROMPT",
             "[Styling: semi-formal] [Structure: lists] [Context: general]"),
            ("  formal  ", "bullets", "chat",
             "[Styling: formal] [Structure: lists] [Context: general]"),
            ("unknown", "unknown", "email",
             "[Styling: semi-formal] [Structure: prose] [Context: email]"),
        ]
        for item in cases {
            let options = CleanOptions(styling: item.styling, structure: item.structure,
                                       context: item.context)
            XCTAssertEqual(LlamaPrompt.controlLine(options: options), item.expected,
                           "\(item.styling)/\(item.structure)/\(item.context)")
        }
    }

    func testControlLineKeepsEveryTrainedCombination() {
        for styling in ["casual", "semi-casual", "semi-formal", "formal"] {
            for structure in ["prose", "lists"] {
                for context in ["general", "email"] {
                    let options = CleanOptions(styling: styling, structure: structure,
                                               context: context)
                    XCTAssertEqual(
                        LlamaPrompt.controlLine(options: options),
                        "[Styling: \(styling)] [Structure: \(structure)] [Context: \(context)]")
                }
            }
        }
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

    /// S1-mini returns an empty string for filler-only or noise-only input.
    /// That is a successful normalization, not a model failure.
    func testEmptyCompletionIsAValidEmptyResult() async throws {
        let url = URL(fileURLWithPath: "/tmp/s1-mini.gguf")
        let cleaner = LlamaCleaner(modelProvider: StubProvider(url: url),
                                   runtime: FakeRuntime(response: "  <|im_end|>  "))
        let result = try await cleaner.clean("um", options: CleanOptions())
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.tokensOut, 0)
        XCTAssertFalse(result.hitTokenCap)
    }

    /// The model card's sizing rule: 1.3 x input tokens + 32, never above the
    /// configured ceiling. A fixed 1024 is wasteful for dictation-length input.
    func testOutputCapIsSizedToTheInput() async throws {
        let url = URL(fileURLWithPath: "/tmp/s1-mini.gguf")
        let runtime = FakeRuntime(response: "Clean.")
        let cleaner = LlamaCleaner(modelProvider: StubProvider(url: url), runtime: runtime)
        let input = String(repeating: "word ", count: 100)
        _ = try await cleaner.clean(input, options: CleanOptions())
        let tokens = LlamaPrompt.estimateTokens(input)
        let expected = min(1_024, Int((Double(tokens) * 1.3).rounded(.up)) + 32)
        let caps = await runtime.outputCaps
        XCTAssertEqual(caps, [expected])
    }

    func testConfiguredCapRemainsTheCeiling() async throws {
        let url = URL(fileURLWithPath: "/tmp/s1-mini.gguf")
        let runtime = FakeRuntime(response: "Clean.")
        let cleaner = LlamaCleaner(modelProvider: StubProvider(url: url), runtime: runtime)
        _ = try await cleaner.clean(String(repeating: "word ", count: 100),
                                    options: CleanOptions(maxNewTokens: 40))
        let caps = await runtime.outputCaps
        XCTAssertEqual(caps, [40])
    }

    func testHitTokenCapUsesTheInputSizedCap() async throws {
        let url = URL(fileURLWithPath: "/tmp/s1-mini.gguf")
        let runtime = FakeRuntime(response: String(repeating: "word ", count: 80))
        let cleaner = LlamaCleaner(modelProvider: StubProvider(url: url), runtime: runtime)
        // 20 input words estimate to 25 tokens, so the effective cap is 65,
        // not the configured 1024. 80 output words is well past that cap.
        let result = try await cleaner.clean(String(repeating: "word ", count: 20),
                                             options: CleanOptions())
        XCTAssertTrue(result.hitTokenCap)
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
