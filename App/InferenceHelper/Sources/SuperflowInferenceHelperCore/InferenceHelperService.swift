import Foundation
import SuperflowInferenceHelperProtocol
import SuperflowLLMCore
import SuperflowLLMLlamaCpp

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

    public func prepareModel(atPath path: String, reply: @escaping (Bool, String?) -> Void) {
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
        Task {
            do {
                try await runtime.load(modelURL: URL(fileURLWithPath: path))
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

    public func complete(prompt: String, maxTokens: Int,
                         reply: @escaping (String?, String?) -> Void) {
        let callback = HelperCallback(reply)
        let runtime = self.runtime
        Task {
            do {
                callback.call((try await runtime.complete(prompt: prompt, maxTokens: maxTokens), nil))
            } catch {
                callback.call((nil, error.localizedDescription))
            }
        }
    }
}

private final class HelperCallback<Value: Sendable>: @unchecked Sendable {
    private let body: (Value) -> Void

    init(_ body: @escaping (Value) -> Void) { self.body = body }

    func call(_ value: Value) { body(value) }
}
