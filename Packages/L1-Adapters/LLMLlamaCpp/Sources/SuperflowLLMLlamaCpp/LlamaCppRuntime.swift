import Foundation
import os
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
    /// Scratch token buffer reused across decodes on this session. WorkerPool
    /// leases a session to exactly one decode at a time, so this is never shared
    /// concurrently, and keeping its capacity avoids reallocating the full
    /// prompt token array on every warm cleanup.
    var promptBuffer: [llama_token] = []

    init(model: LlamaModel, context: OpaquePointer) {
        self.model = model
        self.context = context
    }

    deinit { llama_free(context) }
}

/// Tokenizes the constant system prefix once and reuses it. `decode` runs in
/// detached tasks, so this is a small locked reference type rather than actor
/// state — routing it through the actor would serialize every concurrent decode.
/// Keys are the literal prefix text, so a future prompt edit adds a fresh entry
/// instead of silently reusing stale tokens.
private final class PrefixTokenCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: [llama_token]] = [:]
    private var enabled = true

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    func tokens(for prefix: String, vocabulary: OpaquePointer) throws -> [llama_token] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[prefix] { return cached }
        // The prefix is the start of the whole prompt, so it alone receives BOS.
        let fresh = try LlamaCppRuntime.tokenize(prefix, vocabulary: vocabulary, addSpecial: true)
        storage[prefix] = fresh
        return fresh
    }

    /// Proves once, at load time, that splitting on the special-token boundary
    /// reproduces whole-prompt tokens byte for byte. If a model's tokenizer ever
    /// violates that, the cache disables itself and every decode falls back to
    /// whole-prompt tokenization — no silent quality loss is possible.
    func verify(full: String, prefix: String, variable: String, vocabulary: OpaquePointer) {
        let whole = try? LlamaCppRuntime.tokenize(full, vocabulary: vocabulary, addSpecial: true)
        let head = try? LlamaCppRuntime.tokenize(prefix, vocabulary: vocabulary, addSpecial: true)
        let tail = try? LlamaCppRuntime.tokenize(variable, vocabulary: vocabulary, addSpecial: false)
        lock.lock()
        defer { lock.unlock() }
        if let whole, let head, let tail, head + tail == whole {
            storage[prefix] = head
            enabled = true
        } else {
            enabled = false
            storage.removeAll()
        }
    }
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
    private let prefixCache = PrefixTokenCache()

    /// A pool this large is only useful on a machine with enough memory *and*
    /// cores. HEX's reconnaissance found that more native threads than usable
    /// CPUs made tail latency worse without improving medians. On this app the
    /// same applies to contexts: six concurrent Metal contexts on an 8 GB M1
    /// made `llama_decode` fail during warm-up, so S1 never became ready.
    public static let maximumSessions = 10
    public static var recommendedSessionCount: Int {
        let gigabytes = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let cores = ProcessInfo.processInfo.activeProcessorCount
        // One decode lane needs ~2 compute threads; never oversubscribe. A
        // floor of 3 forced 3 sessions (6+ threads) on a 2-core machine, the
        // exact oversubscription this calculation is meant to prevent.
        let byMemory = Int(gigabytes / 2)
        let byCores = cores / 2
        return min(maximumSessions, max(1, min(byMemory, byCores)))
    }

    private static let runtimeLog = Logger(subsystem: "com.superflow.llm", category: "runtime")

    /// Contexts that survived warm-up. A context that fails its first decode is
    /// discarded rather than poisoning later requests; if none survive, load
    /// fails loudly instead of pretending S1 is ready.
    public private(set) var activeSessionCount: Int = 0

    public init(sessions: Int = LlamaCppRuntime.recommendedSessionCount) {
        sessionCount = min(LlamaCppRuntime.maximumSessions, max(1, sessions))
    }

    /// Idempotent, serialized load. Actor isolation plus the identity guard make
    /// concurrent launch/settings/first-call requests join one load: the model
    /// and its warmed contexts stay resident for the helper's lifetime and are
    /// only re-placed when the URL or compute actually changes.
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
        let cores = max(2, ProcessInfo.processInfo.activeProcessorCount)
        // Split the CPU budget across contexts instead of giving every context
        // all cores. 2 sessions x 4 threads is 8 threads on this M1; the old
        // 6 sessions x 8 threads was 48 threads fighting for 8 cores.
        let generationThreads = Int32(max(1, min(4, cores / max(1, sessionCount))))
        let batchThreads = Int32(min(cores, Int(generationThreads) + 2))
        var sessions: [LlamaSession] = []
        for _ in 0..<sessionCount {
            var params = llama_context_default_params()
            // Leave room for the S1 prompt, up to 850 input tokens, and the
            // output budget without clipping generation.
            params.n_ctx = 3_072
            params.n_batch = 1_024
            params.n_ubatch = 512
            params.n_threads = generationThreads
            params.n_threads_batch = batchThreads
            guard let context = llama_init_from_model(pointer, params) else {
                throw SuperflowError.modelUnavailable("llama.cpp could not create a context")
            }
            sessions.append(LlamaSession(model: loadedModel, context: context))
        }
        // Warm-up is sequential and short. Six simultaneous Metal graph builds
        // exhausted the 8 GB M1 and made llama_decode fail before any session
        // became useful. A small greedy pass still installs the Metal pipeline.
        let warmupPrompt = LlamaPrompt.render(text: "hello", options: CleanOptions())
        // Validate prefix reuse against this model's tokenizer; on any mismatch
        // the cache switches itself off and decode uses whole-prompt tokens.
        if let (prefix, variable) = LlamaPrompt.prefixSplit(warmupPrompt) {
            prefixCache.verify(full: warmupPrompt, prefix: prefix, variable: variable, vocabulary: vocabulary)
        }
        var warmed: [LlamaSession] = []
        warmed.reserveCapacity(sessions.count)
        for session in sessions {
            do {
                _ = try Self.decode(prompt: warmupPrompt, maxTokens: 8, session: session,
                                    deadline: .now.advanced(by: .seconds(15)), prefixCache: prefixCache)
                warmed.append(session)
            } catch {
                Self.runtimeLog.warning("Dropping S1 context after warm-up failure: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard !warmed.isEmpty else {
            throw SuperflowError.modelUnavailable("llama.cpp could not warm any S1 context")
        }
        Self.runtimeLog.info("S1 ready: \(warmed.count, privacy: .public)/\(sessions.count, privacy: .public) contexts, \(generationThreads, privacy: .public) threads each")
        model = loadedModel
        pool = WorkerPool(warmed)
        activeSessionCount = warmed.count
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
        // Queue time counts against the original request deadline. Previously,
        // each waiting caller received a fresh budget only after a worker was free.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(max(1, deadlineMs)))
        // Capture the immutable cache reference before the @Sendable closure so
        // decodes never hop back through actor isolation to read it.
        let cache = prefixCache
        do {
            return try await pool.use(CleanPriority.current, deadline: deadline) { session in
                let task = Task.detached {
                    try Self.decode(prompt: prompt, maxTokens: maxTokens, session: session,
                                    deadline: deadline, prefixCache: cache)
                }
                return try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                }
            }
        } catch WorkerPool<LlamaSession>.Failure.timedOut {
            throw SuperflowError.timeout("cleanup")
        }
    }

    private static func decode(prompt: String, maxTokens: Int, session: LlamaSession,
                               deadline: ContinuousClock.Instant,
                               prefixCache: PrefixTokenCache) throws -> LlamaCompletion {
        func check() throws {
            try Task.checkCancellation()
            if ContinuousClock.now >= deadline { throw SuperflowError.timeout("cleanup") }
        }
        try check()
        let context = session.context
        let vocabulary = session.model.vocabulary
        // The system turn is byte-identical on every cleanup. Tokenize it once
        // and reuse it; tokenize only the user turn/transcript per call. The cut
        // is at a special-token boundary, so the concatenated tokens are exactly
        // what whole-prompt tokenization would have produced — no quality drift.
        let tokens: [llama_token]
        if prefixCache.isEnabled, let (prefix, variable) = LlamaPrompt.prefixSplit(prompt) {
            let prefixTokens = try prefixCache.tokens(for: prefix, vocabulary: vocabulary)
            let variableTokens = try tokenize(variable, vocabulary: vocabulary, addSpecial: false)
            session.promptBuffer.removeAll(keepingCapacity: true)
            session.promptBuffer.append(contentsOf: prefixTokens)
            session.promptBuffer.append(contentsOf: variableTokens)
            tokens = session.promptBuffer
        } else {
            tokens = try tokenize(prompt, vocabulary: vocabulary)
        }
        guard !tokens.isEmpty else { return LlamaCompletion(text: "", generatedTokens: 0) }
        guard tokens.count < Int(llama_n_ctx(context)) else {
            throw SuperflowError.invalidState("The S1-mini prompt exceeds the loaded context window")
        }
        llama_memory_clear(llama_get_memory(context), true)
        // Prefill uses bounded batches so cancellation is checked between graph evaluations.
        let prefillStarted = DispatchTime.now().uptimeNanoseconds
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
        let prefillMs = Int((DispatchTime.now().uptimeNanoseconds - prefillStarted) / 1_000_000)
        let generationStarted = DispatchTime.now().uptimeNanoseconds
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
                                       generatedTokens: generated, prefillMs: prefillMs,
                                       generationMs: Int((DispatchTime.now().uptimeNanoseconds - generationStarted) / 1_000_000))
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
                               generatedTokens: generated, hitTokenCap: true, prefillMs: prefillMs,
                               generationMs: Int((DispatchTime.now().uptimeNanoseconds - generationStarted) / 1_000_000))
    }

    /// `addSpecial` prepends BOS; it is true only for the leading prefix so a
    /// cached prefix plus a freshly tokenized remainder matches whole-prompt
    /// tokenization exactly (never two BOS tokens). `parseSpecial` stays true so
    /// `<|im_start|>`/`<|im_end|>` remain atomic at the split boundary.
    fileprivate static func tokenize(_ text: String, vocabulary: OpaquePointer,
                                     addSpecial: Bool = true) throws -> [llama_token] {
        let bytes = Array(text.utf8)
        guard bytes.count < Int(Int32.max) else {
            throw SuperflowError.invalidState("The S1-mini prompt is too large to tokenize")
        }
        var tokens = [llama_token](repeating: 0, count: max(1, bytes.count + 1))
        let count = text.withCString { textPointer in
            llama_tokenize(vocabulary, textPointer, Int32(bytes.count), &tokens, Int32(tokens.count), addSpecial, true)
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
