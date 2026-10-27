import Foundation
import SuperflowKernel
import SuperflowPorts

public enum ChatTemplate: String, Sendable {
    case chatML, plain
}

public struct LlamaPrompt: Sendable {
    private struct Definition: Decodable, Sendable {
        let systemPrompt: String
        let controlLine: String
        let assistantPrefix: String
    }

    private static let definition: Definition = {
        guard let url = Bundle.module.url(forResource: "s1-prompt", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let definition = try? JSONDecoder().decode(Definition.self, from: data) else {
            preconditionFailure("The bundled S1-mini prompt resource is missing or invalid.")
        }
        return definition
    }()

    public static func resourceData() -> Data? {
        guard let url = Bundle.module.url(forResource: "s1-prompt", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func system(options: CleanOptions) -> String { definition.systemPrompt }

    public static func controlLine(options: CleanOptions) -> String {
        definition.controlLine
            .replacingOccurrences(of: "{{styling}}", with: options.styling)
            .replacingOccurrences(of: "{{structure}}", with: options.structure)
            .replacingOccurrences(of: "{{context}}", with: options.context)
    }

    public static func render(text: String, options: CleanOptions,
                              template: ChatTemplate = .chatML) -> String {
        switch template {
        case .plain:
            return system(options: options) + "\n" + controlLine(options: options) + "\n" + text
        case .chatML:
            return "<|im_start|>system\n" + system(options: options) + "<|im_end|>\n" +
                "<|im_start|>user\n" + controlLine(options: options) + "\n" + text + "<|im_end|>\n" +
                definition.assistantPrefix
        }
    }

    public static func sanitize(_ output: String) -> String {
        var text = output
        for token in ["<|im_start|>assistant", "<|im_start|>system", "<|im_end|>", "<|endoftext|>", "<|fim_suffix|>"] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["assistant:", "cleaned transcript:", "cleaned text:", "output:", "transcript:"]
        var changed = true
        while changed {
            changed = false
            let lower = text.lowercased()
            for prefix in prefixes where lower.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                break
            }
        }
        if text.hasPrefix("```"), text.hasSuffix("```"), text.count >= 6 {
            text = String(text.dropFirst(3).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// Kept for diagnostics and test fixtures. Production chunk planning uses the model tokenizer.
    public static func estimateTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, (text.count + 3) / 4)
    }
}

public protocol LlamaRuntime: Sendable {
    func load(modelURL: URL) async throws
    func countTokens(_ text: String) async -> Int?
    func complete(prompt: String, maxTokens: Int) async throws -> String
}

public extension LlamaRuntime {
    func countTokens(_ text: String) async -> Int? { nil }
}

public struct UnavailableLlamaRuntime: LlamaRuntime {
    public init() {}
    public func load(modelURL: URL) async throws {
        throw SuperflowError.modelUnavailable("llama.cpp is not available in this build.")
    }
    public func complete(prompt: String, maxTokens: Int) async throws -> String {
        throw SuperflowError.modelUnavailable("llama.cpp is not available in this build.")
    }
}

/// Tier 1 cleaner. Model load is lazy so app launch never blocks on a
/// multi-gigabyte file; the composition root calls `prepare()` during warm-up.
public actor LlamaCleaner: TextCleaner {
    private let modelProvider: any ModelProvider
    private let runtime: any LlamaRuntime
    private var ready = false

    public init(modelProvider: any ModelProvider, runtime: any LlamaRuntime) {
        self.modelProvider = modelProvider
        self.runtime = runtime
    }

    public var isReady: Bool { ready }

    public func prepare() async throws {
        guard !ready else { return }
        let url = try await modelProvider.ensureLLM { _ in }
        try await runtime.load(modelURL: url)
        ready = true
    }

    public func countTokens(_ text: String) async -> Int {
        await runtime.countTokens(text) ?? 0
    }

    public func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        if !ready { try await prepare() }
        let started = DispatchTime.now().uptimeNanoseconds
        let prompt = LlamaPrompt.render(text: text, options: options)
        let output = try await runtime.complete(prompt: prompt, maxTokens: options.maxNewTokens)
        let cleaned = LlamaPrompt.sanitize(output)
        guard !cleaned.isEmpty else {
            throw SuperflowError.modelUnavailable("The cleanup model returned an empty completion")
        }
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        let tokensOut = await runtime.countTokens(cleaned) ?? 0
        let tokensIn = await runtime.countTokens(prompt) ?? 0
        return CleanResult(text: cleaned,
                           tokensIn: tokensIn,
                           tokensOut: tokensOut,
                           hitTokenCap: tokensOut >= options.maxNewTokens,
                           latencyMs: elapsed)
    }
}
