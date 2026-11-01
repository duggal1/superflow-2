import Foundation
import SuperflowInferenceHelperProtocol
import SuperflowKernel
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import SuperflowPorts

/// Model runtime owner for the XPC process.
@objc public final class InferenceHelperService: NSObject, InferenceHelperProtocol {
    public static let version = InferenceHelperProtocolVersion.current
    private let runtime: any LlamaRuntime

    public init(runtime: any LlamaRuntime = LlamaCppRuntime()) {
        self.runtime = runtime
        super.init()
    }

    public func ping(reply: @escaping (String) -> Void) {
        reply(Self.version)
    }

    public func prepareModel(atPath path: String, gpu: Bool,
                             reply: @escaping (Bool, String?) -> Void) {
        guard !path.isEmpty else {
            reply(false, "Model path is empty.")
            return
        }
        guard FileManager.default.fileExists(atPath: path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
            reply(false, "Model path does not exist: \(path)")
            return
        }

        let callback = HelperCallback(reply)
        let runtime = self.runtime
        let compute: ModelCompute = gpu ? .gpu : .cpu
        Task {
            do {
                try await runtime.load(modelURL: URL(fileURLWithPath: path), compute: compute)
                callback.call((true, nil))
            } catch {
                callback.call((false, error.localizedDescription))
            }
        }
    }

    public func countTokens(in text: String, reply: @escaping (Int, String?) -> Void) {
        let callback = HelperCallback(reply)
        let runtime = self.runtime
        Task {
            guard let count = await runtime.countTokens(text) else {
                callback.call((0, "The cleanup model is not ready."))
                return
            }
            callback.call((count, nil))
        }
    }

    public func complete(prompt: String, maxTokens: Int, deadlineMs: Int, interactive: Bool,
                         reply: @escaping (String?, Int, Bool, String?) -> Void) {
        guard maxTokens > 0, deadlineMs > 0 else {
            reply(nil, -1, false, "Completion requires a positive token limit and deadline.")
            return
        }
        let callback = HelperCallback(reply)
        let runtime = self.runtime
        Task {
            do {
                let output = try await CleanPriority.$current.withValue(interactive ? .interactive : .background) {
                    try await runtime.completion(prompt: prompt, maxTokens: maxTokens, deadlineMs: deadlineMs)
                }
                callback.call((output.text, output.generatedTokens ?? -1, output.hitTokenCap, nil))
            } catch {
                callback.call((nil, -1, false, error.localizedDescription))
            }
        }
    }
}

private final class HelperCallback<Value: Sendable>: @unchecked Sendable {
    private let body: (Value) -> Void

    init(_ body: @escaping (Value) -> Void) { self.body = body }

    func call(_ value: Value) { body(value) }
}
