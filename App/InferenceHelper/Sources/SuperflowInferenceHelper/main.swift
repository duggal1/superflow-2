import Foundation
import SuperflowInferenceHelperCore
import SuperflowInferenceHelperProtocol

/// Owns the listener's delegate for the lifetime of the process. `NSXPCListener`
/// holds its delegate weakly, so this top-level binding is what keeps the
/// service alive while `resume()` runs the helper's run loop.
final class InferenceHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: InferenceHelperProtocol.self)
        connection.exportedObject = InferenceHelperService()
        connection.resume()
        return true
    }
}

let listener = NSXPCListener.service()
let delegate = InferenceHelperListenerDelegate()
listener.delegate = delegate
listener.resume()
