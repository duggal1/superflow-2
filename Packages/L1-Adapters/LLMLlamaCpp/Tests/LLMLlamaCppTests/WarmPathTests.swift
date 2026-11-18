import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowLLMCore

/// Counts real `load` calls on a fake runtime: warm-up must be idempotent and
/// serialized without ever touching llama.cpp or a GGUF file.
private actor CountingLoadRuntime: LlamaRuntime {
    private(set) var loadComputes: [ModelCompute] = []

    func load(modelURL: URL, compute: ModelCompute) async throws {
        loadComputes.append(compute)
        try await Task.sleep(for: .milliseconds(20))
    }

    func countTokens(_ text: String) async -> Int? { LlamaPrompt.estimateTokens(text) }
    func complete(prompt: String, maxTokens: Int) async throws -> String { "cleaned" }
}

private actor TimeoutRuntime: LlamaRuntime {
    func load(modelURL: URL, compute: ModelCompute) async throws {}
    func countTokens(_ text: String) async -> Int? { LlamaPrompt.estimateTokens(text) }
    func complete(prompt: String, maxTokens: Int) async throws -> String { "never" }
    func completion(prompt: String, maxTokens: Int, deadlineMs: Int) async throws -> LlamaCompletion {
        throw SuperflowError.timeout("cleanup")
    }
}

private struct WarmModelProvider: ModelProvider {
    let url = URL(fileURLWithPath: "/tmp/s1-warm.gguf")
    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

final class WarmPathTests: XCTestCase {
    /// Concurrent first calls (launch + settings refresh + first hotkey) must
    /// join one serialized load, never double-load the model.
    func testPrewarmLoadsExactlyOnceUnderConcurrentCalls() async throws {
        let runtime = CountingLoadRuntime()
        let cleaner = LlamaCleaner(modelProvider: WarmModelProvider(), runtime: runtime)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 { group.addTask { await cleaner.prewarm() } }
            try await group.waitForAll()
        }
        let loads = await runtime.loadComputes
        XCTAssertEqual(loads, [.gpu])
    }

    /// A warmed model stays resident: the first cleanup must not reload it.
    func testPrewarmThenCleanDoesNotReload() async throws {
        let runtime = CountingLoadRuntime()
        let cleaner = LlamaCleaner(modelProvider: WarmModelProvider(), runtime: runtime)
        await cleaner.prewarm()
        _ = try await cleaner.clean("um hello world", options: CleanOptions())
        let loads = await runtime.loadComputes
        XCTAssertEqual(loads, [.gpu])
    }

    /// The cacheable prefix is the constant system turn: identical for every
    /// transcript and every styling/structure/context combination.
    func testPrefixSplitIsConstantAcrossTextAndOptions() {
        let samples = [
            ("um", "casual"),
            ("please send the report", "formal"),
            (String(repeating: "long ", count: 200), "semi-casual"),
        ]
        let prefixes = samples.map { text, styling -> String in
            let prompt = LlamaPrompt.render(text: text, options: CleanOptions(styling: styling))
            return LlamaPrompt.prefixSplit(prompt)!.prefix
        }
        XCTAssertEqual(Set(prefixes).count, 1, "system prefix must not vary with text or options")
        XCTAssertTrue(prefixes[0].hasSuffix("<|im_end|>\n"))
    }

    /// Splitting at the special-token boundary must lose no bytes: the two
    /// halves reconstruct the exact rendered prompt.
    func testPrefixSplitReconstructsExactPrompt() throws {
        let options = CleanOptions(styling: "formal", structure: "lists", context: "email")
        let text = "um use S1-mini and Nemotron with GPT-6"
        let full = LlamaPrompt.render(text: text, options: options)
        let split = try XCTUnwrap(LlamaPrompt.prefixSplit(full))
        XCTAssertEqual(split.prefix + split.variable, full)
        XCTAssertTrue(split.variable.hasPrefix("<|im_start|>user\n"))
        XCTAssertTrue(split.variable.contains(LlamaPrompt.controlLine(options: options)))
    }

    /// Even when the transcript literally contains a user-turn marker, the cut
    /// stays at the first (real) marker so tokenization remains byte-exact.
    func testPrefixSplitUsesFirstMarkerWhenTextContainsMarker() throws {
        let marker = "<|im_start|>user\n"
        let text = "literal " + marker + "inside transcript"
        let full = LlamaPrompt.render(text: text, options: CleanOptions())
        let split = try XCTUnwrap(LlamaPrompt.prefixSplit(full))
        XCTAssertEqual(split.prefix + split.variable, full)
        XCTAssertFalse(split.prefix.contains("literal"))
        XCTAssertTrue(split.variable.contains(text))
        XCTAssertTrue(split.variable.hasPrefix(marker))
        // The literal copy appears only after the real cut, inside the variable.
        XCTAssertEqual(split.variable.components(separatedBy: marker).count - 1, 2)
    }

    /// The plain template has no special-token boundary; the runtime must fall
    /// back to whole-prompt tokenization instead of guessing a cut.
    func testPrefixSplitReturnsNilForPlainTemplate() {
        let full = LlamaPrompt.render(text: "hello", options: CleanOptions(), template: .plain)
        XCTAssertNil(LlamaPrompt.prefixSplit(full, template: .plain))
    }

    /// A deadline miss must surface as a timeout (which the coordinator turns
    /// into a visible raw-ASR fallback), never as a plausible-looking success.
    func testDeadlineMissPropagatesInsteadOfFakeSuccess() async throws {
        let cleaner = LlamaCleaner(modelProvider: WarmModelProvider(), runtime: TimeoutRuntime())
        do {
            _ = try await cleaner.clean("um hello", options: CleanOptions())
            XCTFail("a deadline miss must fail, not return a fake success")
        } catch SuperflowError.timeout(let stage) {
            XCTAssertEqual(stage, "cleanup")
        }
    }

    /// The cache key includes the whole prefix, so any prompt-template edit
    /// produces a different key rather than reusing stale tokens.
    func testPrefixSplitKeyChangesWithTemplateEdit() {
        let original = LlamaPrompt.render(text: "hello", options: CleanOptions())
        var altered = original
        altered.replaceSubrange(altered.range(of: "You are a text normalizer")!,
                                with: "You are a strict text normalizer")
        let originalPrefix = LlamaPrompt.prefixSplit(original)!.prefix
        let alteredPrefix = LlamaPrompt.prefixSplit(altered)!.prefix
        XCTAssertNotEqual(originalPrefix, alteredPrefix)
    }
}
