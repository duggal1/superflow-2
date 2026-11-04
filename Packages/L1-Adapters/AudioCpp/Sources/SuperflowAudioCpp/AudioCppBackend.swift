import Foundation

/// GPU remains the product default. Hosted CI can run full inference on CPU
/// when its virtualized Metal device cannot execute the Nemotron graph.
enum AudioCppBackend {
    static func select(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        switch environment["SUPERFLOW_AUDIOCPP_BACKEND"]?.lowercased() {
        case "cpu": return "cpu"
        case "metal", nil: return "metal"
        default: return "metal"
        }
    }
}
