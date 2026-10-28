import Foundation

/// XPC surface between the menu-bar app and the inference helper.
///
/// The helper owns the ASR and LLM runtimes so that a crash or a wedged model
/// restarts the helper process instead of taking the app down with it. Keeping
/// the protocol in its own library lets the app and the helper agree on the
/// surface without either importing the other's implementation.
@objc public protocol InferenceHelperProtocol {
    /// Liveness probe used by the app's watchdog and by packaging smoke tests.
    func ping(reply: @escaping (String) -> Void)

    /// Load the cleanup model from a verified local path. `gpu` places the
    /// weights on Metal (`true`) or keeps them on the CPU (`false`); the
    /// helper reloads the model when it differs from the loaded one.
    func prepareModel(atPath path: String, gpu: Bool, reply: @escaping (Bool, String?) -> Void)

    /// Run tokenization and completion in the helper process.
    func countTokens(in text: String, reply: @escaping (Int, String?) -> Void)
    func complete(prompt: String, maxTokens: Int,
                  reply: @escaping (String?, String?) -> Void)
}

/// Version of the protocol surface, returned by `ping`. Bump when a method is
/// added or its semantics change; the app refuses to use a helper it does not
/// understand.
public enum InferenceHelperProtocolVersion {
    public static let current = "3"
}
