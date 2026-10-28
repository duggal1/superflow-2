import Foundation
import llama
import SuperflowKernel
import SuperflowLLMCore

private final class LlamaResources: @unchecked Sendable {
    let model: OpaquePointer
    let context: OpaquePointer
    let vocabulary: OpaquePointer

    init(model: OpaquePointer, context: OpaquePointer, vocabulary: OpaquePointer) {
        self.model = model
        self.context = context
        self.vocabulary = vocabulary
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }
}

/// Process-wide llama.cpp log control. Benchmark tools call `silence()` so the
/// model's graph/kernel chatter does not drown the measurement output.
public enum LlamaLogging {
    public static func silence() {
        llama_log_set({ _, _, _ in }, nil)
    }
}

/// Owns the process's llama.cpp model and one reusable context. Actor isolation
/// serializes Metal access and keeps one model mapping resident.
public actor LlamaCppRuntime: LlamaRuntime {
    private var resources: LlamaResources?
    private var loadedCompute: ModelCompute?

    public init() {}

    public func load(modelURL: URL, compute: ModelCompute) async throws {
        if resources != nil, loadedCompute == compute { return }
        // The same file requested with a different placement: drop the old
        // weights first so the setting actually takes effect without a restart.
        resources = nil
        loadedCompute = nil
        llama_backend_init()

        var modelParams = llama_model_default_params()
        // llama.cpp's split knob: -1 offloads every layer to Metal, 0 keeps the
        // whole model on the CPU.
        modelParams.n_gpu_layers = compute == .gpu ? -1 : 0
        guard let loadedModel = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw SuperflowError.modelUnavailable("llama.cpp could not load \(modelURL.lastPathComponent)")
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 4_096
        contextParams.n_batch = 512
        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            throw SuperflowError.modelUnavailable("llama.cpp could not create a context")
        }

        guard let vocabulary = llama_model_get_vocab(loadedModel) else {
            llama_free(loadedContext)
            llama_model_free(loadedModel)
            llama_backend_free()
            throw SuperflowError.modelUnavailable("llama.cpp could not access the model vocabulary")
        }
        resources = LlamaResources(model: loadedModel, context: loadedContext, vocabulary: vocabulary)
        loadedCompute = compute
    }

    public func countTokens(_ text: String) async -> Int? {
        guard let resources else { return nil }
        return try? tokenize(text, vocabulary: resources.vocabulary).count
    }

    public func complete(prompt: String, maxTokens: Int) async throws -> String {
        guard let resources else {
            throw SuperflowError.invalidState("llama.cpp model is not loaded")
        }
        let context = resources.context
        let vocabulary = resources.vocabulary
        let tokens = try tokenize(prompt, vocabulary: vocabulary)
        guard !tokens.isEmpty else { return "" }
        guard tokens.count < Int(llama_n_ctx(context)) else {
            throw SuperflowError.invalidState("The S1-mini prompt exceeds the loaded context window")
        }

        llama_memory_clear(llama_get_memory(context), true)
        let promptStatus = tokens.withUnsafeBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            var batch = llama_batch_get_one(UnsafeMutablePointer(mutating: baseAddress), Int32(buffer.count))
            return llama_decode(context, batch)
        }
        guard promptStatus == 0 else {
            throw SuperflowError.modelUnavailable("llama.cpp could not evaluate the prompt")
        }

        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()),
              let greedySampler = llama_sampler_init_greedy() else {
            throw SuperflowError.modelUnavailable("llama.cpp could not create a sampler")
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, greedySampler)

        var output: [UInt8] = []
        let outputLimit = min(max(1, maxTokens), max(1, Int(llama_n_ctx(context)) - tokens.count))
        for _ in 0..<outputLimit {
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) { break }
            output.append(contentsOf: try tokenBytes(token, vocabulary: vocabulary))

            var nextToken = token
            let status = withUnsafeMutablePointer(to: &nextToken) { tokenPointer -> Int32 in
                var batch = llama_batch_get_one(tokenPointer, 1)
                return llama_decode(context, batch)
            }
            guard status == 0 else {
                throw SuperflowError.modelUnavailable("llama.cpp failed while generating cleanup text")
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    private func tokenize(_ text: String, vocabulary: OpaquePointer) throws -> [llama_token] {
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

    private func tokenBytes(_ token: llama_token, vocabulary: OpaquePointer) throws -> [UInt8] {
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
