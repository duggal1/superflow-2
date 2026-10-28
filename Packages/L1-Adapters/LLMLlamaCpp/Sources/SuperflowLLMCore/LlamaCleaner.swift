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

    /// S1-mini was trained with exactly four styling values, two structure
    /// values and two context values. App-level profiles predate that set, so
    /// untrained values are clamped here, at the model-prompt boundary, rather
    /// than changing the user's saved settings.
    public static func controlLine(options: CleanOptions) -> String {
        definition.controlLine
            .replacingOccurrences(of: "{{styling}}", with: normalizedStyling(options.styling))
            .replacingOccurrences(of: "{{structure}}", with: normalizedStructure(options.structure))
            .replacingOccurrences(of: "{{context}}", with: normalizedContext(options.context))
    }

    private static func normalizedValue(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedStyling(_ raw: String) -> String {
        let value = normalizedValue(raw)
        switch value {
        case "casual", "semi-casual", "semi-formal", "formal":
            return value
        default:
            return "semi-formal"
        }
    }

    private static func normalizedStructure(_ raw: String) -> String {
        switch normalizedValue(raw) {
        case "prose":
            return "prose"
        case "lists", "list", "bullets":
            return "lists"
        default:
            return "prose"
        }
    }

    private static func normalizedContext(_ raw: String) -> String {
        normalizedValue(raw) == "email" ? "email" : "general"
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

public struct LlamaCompletion: Sendable {
    public var text: String
    public var generatedTokens: Int?
    public var hitTokenCap: Bool

    public init(text: String, generatedTokens: Int? = nil, hitTokenCap: Bool = false) {
        self.text = text
        self.generatedTokens = generatedTokens
        self.hitTokenCap = hitTokenCap
    }
}

public protocol LlamaRuntime: Sendable {
    /// Loads the model and is the only place compute is chosen. Re-loading the
    /// same URL with a different `compute` must re-place the weights, because
    /// the setting may be changed at runtime from Settings.
    func load(modelURL: URL, compute: ModelCompute) async throws
    func countTokens(_ text: String) async -> Int?
    func complete(prompt: String, maxTokens: Int) async throws -> String
    func completion(prompt: String, maxTokens: Int, deadlineMs: Int) async throws -> LlamaCompletion
}

public extension LlamaRuntime {
    func countTokens(_ text: String) async -> Int? { nil }
    func completion(prompt: String, maxTokens: Int, deadlineMs: Int) async throws -> LlamaCompletion {
        try await withThrowingTaskGroup(of: LlamaCompletion.self) { group in
            group.addTask {
                LlamaCompletion(text: try await complete(prompt: prompt, maxTokens: maxTokens))
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(max(1, deadlineMs)))
                throw SuperflowError.timeout("cleanup")
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }
}

public struct UnavailableLlamaRuntime: LlamaRuntime {
    public init() {}
    public func load(modelURL: URL, compute: ModelCompute) async throws {
        throw SuperflowError.modelUnavailable("llama.cpp is not available in this build.")
    }
    public func complete(prompt: String, maxTokens: Int) async throws -> String {
        throw SuperflowError.modelUnavailable("llama.cpp is not available in this build.")
    }
}

/// Tier 1 cleaner. Model load is lazy so app launch never blocks on a
/// multi-gigabyte file; the composition root calls `prepare()` during warm-up.
public actor LlamaCleaner: DeadlineManagedTextCleaner {
    private let modelProvider: any ModelProvider
    private let runtime: any LlamaRuntime
    private var ready = false
    /// Compute the model is currently loaded with, so a settings change reloads
    /// it instead of silently keeping the old placement.
    private var loadedCompute: ModelCompute?
    private var preparation: (id: UUID, task: Task<Void, any Error>)?

    public init(modelProvider: any ModelProvider, runtime: any LlamaRuntime) {
        self.modelProvider = modelProvider
        self.runtime = runtime
    }

    public var isReady: Bool { ready }

    public func prepare(compute: ModelCompute = .gpu) async throws {
        if let preparation { try await preparation.task.value }
        if ready, loadedCompute == compute { return }
        let id = UUID()
        let task = Task {
            let url = try await modelProvider.ensureLLM { _ in }
            try await runtime.load(modelURL: url, compute: compute)
            loadedCompute = compute
            ready = true
        }
        preparation = (id, task)
        do {
            try await task.value
            if preparation?.id == id { preparation = nil }
        } catch {
            if preparation?.id == id { preparation = nil }
            throw error
        }
    }

    public func countTokens(_ text: String) async -> Int {
        await runtime.countTokens(text) ?? 0
    }

    public func prewarm() async {
        _ = try? await clean("hello there", options: CleanOptions())
    }

    public func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        if !ready { try await prepare() }
        let started = DispatchTime.now().uptimeNanoseconds
        let prompt = LlamaPrompt.render(text: text, options: options)
        // The model card's sizing rule: output length tracks input length, so a
        // fixed ceiling wastes generation budget. `countTokens` is the model's
        // own tokenizer; the estimate is only a fallback for test runtimes.
        let inputTokens = await runtime.countTokens(text) ?? LlamaPrompt.estimateTokens(text)
        let outputCap = Self.outputTokenCap(inputTokens: inputTokens, configured: options.maxNewTokens)
        let output = try await runtime.completion(prompt: prompt, maxTokens: outputCap,
                                                  deadlineMs: options.deadlineMs)
        let cleaned = LlamaPrompt.sanitize(output.text)
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        let retokenized = await runtime.countTokens(cleaned) ?? 0
        let tokensOut = output.generatedTokens ?? retokenized
        let tokensIn = await runtime.countTokens(prompt) ?? 0
        // Filler-only input legitimately normalizes to an empty string.
        return CleanResult(text: cleaned,
                           tokensIn: tokensIn,
                           tokensOut: tokensOut,
                           hitTokenCap: output.hitTokenCap || (!cleaned.isEmpty && tokensOut >= outputCap),
                           latencyMs: elapsed)
    }

    static func outputTokenCap(inputTokens: Int, configured: Int) -> Int {
        let ceiling = max(1, configured)
        let sized = Int((Double(max(0, inputTokens)) * 1.3).rounded(.up)) + 32
        return min(ceiling, sized)
    }
}
