import Foundation
import llama
import SuperflowKernel
import SuperflowPorts
import SuperflowLLMCore

private enum LlamaBackend {
    static let initialized: Void = llama_backend_init()
}

private final class LlamaModel: @unchecked Sendable {
    let pointer: OpaquePointer
    let vocabulary: OpaquePointer

    init(pointer: OpaquePointer, vocabulary: OpaquePointer) {
        self.pointer = pointer
        self.vocabulary = vocabulary
    }

    deinit { llama_model_free(pointer) }
}

private final class LlamaSession: @unchecked Sendable {
    let model: LlamaModel
    let context: OpaquePointer

    init(model: LlamaModel, context: OpaquePointer) {
        self.model = model
        self.context = context
    }

    deinit { llama_free(context) }
}

public enum LlamaLogging {
    public static func silence() {
        llama_log_set({ _, _, _ in }, nil)
    }
}

public actor LlamaCppRuntime: LlamaRuntime {
    private var model: LlamaModel?
    private var pool: WorkerPool<LlamaSession>?
    private var loadedCompute: ModelCompute?
    private var loadedURL: URL?
    private let sessionCount: Int

    public init(sessions: Int = 2) {
        sessionCount = min(4, max(1, sessions))
    }

    public func load(modelURL: URL, compute: ModelCompute) async throws {
        if model != nil, loadedCompute == compute, loadedURL == modelURL { return }
        _ = LlamaBackend.initialized
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = compute == .gpu ? -1 : 0
        guard let pointer = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw SuperflowError.modelUnavailable("llama.cpp could not load \(modelURL.lastPathComponent)")
        }
        guard let vocabulary = llama_model_get_vocab(pointer) else {
            llama_model_free(pointer)
            throw SuperflowError.modelUnavailable("llama.cpp could not access the model vocabulary")
        }
        let loadedModel = LlamaModel(pointer: pointer, vocabulary: vocabulary)
        var sessions: [LlamaSession] = []
        for _ in 0..<sessionCount {
            var params = llama_context_default_params()
            params.n_ctx = 4_096
            params.n_batch = 512
            guard let context = llama_init_from_model(pointer, params) else {
                throw SuperflowError.modelUnavailable("llama.cpp could not create a context")
            }
            sessions.append(LlamaSession(model: loadedModel, context: context))
        }
        let warmupPrompt = LlamaPrompt.render(text: "hello there", options: CleanOptions())
        for session in sessions {
            _ = try Self.decode(prompt: warmupPrompt, maxTokens: 32, session: session,
                                deadline: .now.advanced(by: .seconds(30)))
        }
        model = loadedModel
        pool = WorkerPool(sessions)
        loadedCompute = compute
        loadedURL = modelURL
    }

    public func countTokens(_ text: String) async -> Int? {
        guard let model else { return nil }
        return try? Self.tokenize(text, vocabulary: model.vocabulary).count
    }

    public func complete(prompt: String, maxTokens: Int) async throws -> String {
        try await completion(prompt: prompt, maxTokens: maxTokens, deadlineMs: 30_000).text
    }

    public func completion(prompt: String, maxTokens: Int, deadlineMs: Int) async throws -> LlamaCompletion {
        guard let pool else {
            throw SuperflowError.invalidState("llama.cpp model is not loaded")
        }
        return try await pool.use(CleanPriority.current) { session in
            let deadline = ContinuousClock.now.advanced(by: .milliseconds(max(1, deadlineMs)))
            let task = Task.detached {
                try Self.decode(prompt: prompt, maxTokens: maxTokens, session: session, deadline: deadline)
            }
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        }
    }

    private static func decode(prompt: String, maxTokens: Int, session: LlamaSession,
                               deadline: ContinuousClock.Instant) throws -> LlamaCompletion {
        func check() throws {
            try Task.checkCancellation()
            if ContinuousClock.now >= deadline { throw SuperflowError.timeout("cleanup") }
        }
        try check()
        let context = session.context
        let vocabulary = session.model.vocabulary
        let tokens = try tokenize(prompt, vocabulary: vocabulary)
        guard !tokens.isEmpty else { return LlamaCompletion(text: "", generatedTokens: 0) }
        guard tokens.count < Int(llama_n_ctx(context)) else {
            throw SuperflowError.invalidState("The S1-mini prompt exceeds the loaded context window")
        }
        llama_memory_clear(llama_get_memory(context), true)
        // Prefill uses bounded batches so cancellation is checked between graph evaluations.
        for start in stride(from: 0, to: tokens.count, by: 512) {
            try check()
            let batchTokens = Array(tokens[start..<min(tokens.count, start + 512)])
            let status = batchTokens.withUnsafeBufferPointer { buffer -> Int32 in
                guard let base = buffer.baseAddress else { return -1 }
                let batch = llama_batch_get_one(UnsafeMutablePointer(mutating: base), Int32(buffer.count))
                return llama_decode(context, batch)
            }
            guard status == 0 else {
                throw SuperflowError.modelUnavailable("llama.cpp could not evaluate the prompt")
            }
        }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw SuperflowError.modelUnavailable("llama.cpp could not create a sampler")
        }
        defer { llama_sampler_free(sampler) }
        guard let greedy = llama_sampler_init_greedy() else {
            throw SuperflowError.modelUnavailable("llama.cpp could not create a greedy sampler")
        }
        llama_sampler_chain_add(sampler, greedy)
        var output: [UInt8] = []
        var generated = 0
        let limit = min(max(1, maxTokens), Int(llama_n_ctx(context)) - tokens.count)
        for index in 0..<limit {
            try check()
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) {
                return LlamaCompletion(text: String(decoding: output, as: UTF8.self),
                                       generatedTokens: generated)
            }
            output.append(contentsOf: try tokenBytes(token, vocabulary: vocabulary))
            generated += 1
            if index + 1 == limit { break }
            var next = token
            let status = withUnsafeMutablePointer(to: &next) { pointer -> Int32 in
                let batch = llama_batch_get_one(pointer, 1)
                return llama_decode(context, batch)
            }
            guard status == 0 else {
                throw SuperflowError.modelUnavailable("llama.cpp failed while generating cleanup text")
            }
        }
        try check()
        return LlamaCompletion(text: String(decoding: output, as: UTF8.self),
                               generatedTokens: generated, hitTokenCap: true)
    }

    private static func tokenize(_ text: String, vocabulary: OpaquePointer) throws -> [llama_token] {
        let bytes = Array(text.utf8)
        guard bytes.count < Int(Int32.max) else {
            throw SuperflowError.invalidState("The S1-mini prompt is too large to tokenize")
        }
        var tokens = [llama_token](repeating: 0, count: max(1, bytes.count + 1))
        let count = text.withCString { textPointer in
            llama_tokenize(vocabulary, textPointer, Int32(bytes.count), &tokens, Int32(tokens.count), true, true)
        }
        guard count >= 0, Int(count) <= tokens.count else {
            throw SuperflowError.modelUnavailable("llama.cpp tokenization failed")
        }
        return Array(tokens.prefix(Int(count)))
    }

    private static func tokenBytes(_ token: llama_token, vocabulary: OpaquePointer) throws -> [UInt8] {
        var bytes = [CChar](repeating: 0, count: 256)
        let count = llama_token_to_piece(vocabulary, token, &bytes, Int32(bytes.count), 0, true)
        if count >= 0 {
            return bytes.prefix(Int(count)).map { UInt8(bitPattern: $0) }
        }

        let required = Int(-count)
        guard required > 0, required < Int(Int32.max) else {
            throw SuperflowError.modelUnavailable("llama.cpp returned an invalid token piece size")
        }
        bytes = [CChar](repeating: 0, count: required)
        let retriedCount = llama_token_to_piece(vocabulary, token, &bytes, Int32(bytes.count), 0, true)
        guard retriedCount >= 0, Int(retriedCount) <= bytes.count else {
            throw SuperflowError.modelUnavailable("llama.cpp could not decode a generated token")
        }
        return bytes.prefix(Int(retriedCount)).map { UInt8(bitPattern: $0) }
    }
}
