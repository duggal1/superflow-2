import Foundation
import SuperflowInferenceHelperProtocol
import SuperflowLLMCore

/// Runs llama.cpp in the embedded helper process so inference failures do not
/// terminate the menu-bar app or its active recording session.
public actor XPCInferenceHelperRuntime: LlamaRuntime {
    private let serviceName: String
    private var connection: NSXPCConnection?
    private var modelURL: URL?
    private var ready = false

    public init(serviceName: String = "com.superflow.app.InferenceHelper") {
        self.serviceName = serviceName
    }

    public func load(modelURL: URL) async throws {
        self.modelURL = modelURL
        try await connectAndLoad(modelURL)
    }

    public func countTokens(_ text: String) async -> Int? {
        guard ready else { return nil }
        do {
            return try await withRecovery {
                let reply: Int = try await self.request { proxy, finish in
                    proxy.countTokens(in: text) { count, error in
                        if let error {
                            finish(.failure(.helper(error)))
                        } else {
                            finish(.success(count))
                        }
                    }
                }
                return reply
            }
        } catch {
            return nil
        }
    }

    public func complete(prompt: String, maxTokens: Int) async throws -> String {
        guard ready else {
            throw XPCInferenceError.helper("The inference helper is not ready.")
        }
        return try await withRecovery {
            try await self.request { proxy, finish in
                proxy.complete(prompt: prompt, maxTokens: maxTokens) { text, error in
                    if let error {
                        finish(.failure(.helper(error)))
                    } else if let text {
                        finish(.success(text))
                    } else {
                        finish(.failure(.helper("The inference helper returned no text.")))
                    }
                }
            }
        }
    }

    private func connectAndLoad(_ modelURL: URL) async throws {
        ready = false
        invalidateConnection()

        let version: String = try await request { proxy, finish in
            proxy.ping { finish(.success($0)) }
        }
        guard version == InferenceHelperProtocolVersion.current else {
            invalidateConnection()
            throw XPCInferenceError.incompatibleVersion(version)
        }

        let loaded: ModelLoadReply = try await request { proxy, finish in
            proxy.prepareModel(atPath: modelURL.path) { success, message in
                finish(.success(ModelLoadReply(success: success, message: message)))
            }
        }
        guard loaded.success else {
            invalidateConnection()
            throw XPCInferenceError.helper(loaded.message ?? "The inference helper could not load the model.")
        }
        ready = true
    }

    private func withRecovery<Value: Sendable>(
        operation: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation()
        } catch let error as XPCInferenceError {
            guard case .connection = error, let modelURL else { throw error }
            invalidateConnection()
            try await connectAndLoad(modelURL)
            return try await operation()
        }
    }

    private func request<Value: Sendable>(
        _ operation: (InferenceHelperProtocol, @escaping (Result<Value, XPCInferenceError>) -> Void) -> Void
    ) async throws -> Value {
        let connection = getConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let reply = XPCReply<Value>(continuation)
            let remote = connection.remoteObjectProxyWithErrorHandler { error in
                reply.fail(String(describing: error))
            }
            guard let proxy = remote as? InferenceHelperProtocol else {
                reply.fail("The inference helper does not implement its XPC protocol.")
                return
            }
            operation(proxy) { result in reply.resolve(result) }
        }
    }

    private func getConnection() -> NSXPCConnection {
        if let connection { return connection }
        let newConnection = NSXPCConnection(serviceName: serviceName)
        newConnection.remoteObjectInterface = NSXPCInterface(with: InferenceHelperProtocol.self)
        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func invalidateConnection() {
        connection?.invalidate()
        connection = nil
        ready = false
    }
}

private struct ModelLoadReply: Sendable {
    let success: Bool
    let message: String?
}

private enum XPCInferenceError: Error, LocalizedError, Sendable {
    case connection(String)
    case helper(String)
    case incompatibleVersion(String)

    var errorDescription: String? {
        switch self {
        case .connection(let message): "Inference helper connection failed: \(message)"
        case .helper(let message): message
        case .incompatibleVersion(let version):
            "Inference helper protocol \(version) is incompatible; expected \(InferenceHelperProtocolVersion.current)."
        }
    }
}

private final class XPCReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, XPCInferenceError>?

    init(_ continuation: CheckedContinuation<Value, XPCInferenceError>) {
        self.continuation = continuation
    }

    func resolve(_ result: Result<Value, XPCInferenceError>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func fail(_ message: String) {
        resolve(.failure(.connection(message)))
    }
}
