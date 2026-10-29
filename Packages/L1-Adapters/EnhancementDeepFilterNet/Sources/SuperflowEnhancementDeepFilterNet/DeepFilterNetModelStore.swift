import CryptoKit
import Foundation
import SuperflowKernel

/// A revision- and checksum-pinned snapshot, shared by download UI and runtime.
actor DeepFilterNetModelStore {
    static let revision = "dfc12319b3a62d09e9d51aace480c981067b9d7b"
    let directory: URL
    private var downloading: Task<Void, Error>?

    init(directory: URL) { self.directory = directory }

    static let artifacts: [(String, String)] = [
        ("DeepFilterNet3-Streaming.mlpackage/Data/com.apple.CoreML/model.mlmodel", "6796e71c000712f22c30a9b8359b139ad363ea425fcae302ab85b85d728a2742"),
        ("DeepFilterNet3-Streaming.mlpackage/Data/com.apple.CoreML/weights/weight.bin", "1114ff972e25679e7f9707da85eee62659e1bdf50199035ecacba12e4ec0425d"),
        ("DeepFilterNet3-Streaming.mlpackage/Manifest.json", "1a9e9a167e295175f2ff7704e11e7fdf573afdebee1b5a3ee0e5d72cc0ed89f0"),
        ("auxiliary.npz", "332f9e9c4ee639e9edd61b27a873e84270b1aab1355c728b97efe7bb1d1563a1"),
        ("config.json", "cc96fe1bf688e99ed9d31c26ad881d8e0799394862eb35e0be2513afcb3cf7ca"),
        ("model.safetensors", "fca0af2f25cad49d74fc9ac5f9155813416e4b350ec344bb433b4a48a9a76d38"),
        ("LICENSE-APACHE", "1eaee808c5fb6b4e895ba30425285a5cdc5dd25bba2cd230f264c2200c331aec"),
        ("LICENSE-MIT", "24e6bb09c928af8d8e56268082f87413247ce36b39dd5d33add2f9893968065e"),
    ]

    func isAvailable() -> Bool {
        Self.artifacts.allSatisfy { path, hash in Self.matches(directory.appendingPathComponent(path), hash: hash) }
    }

    func ensure(progress: @escaping @Sendable (Double) -> Void) async throws {
        if let downloading { try await downloading.value; progress(1); return }
        let directory = directory
        let task = Task {
            for (index, artifact) in Self.artifacts.enumerated() {
                try Task.checkCancellation()
                let (path, hash) = artifact
                let destination = directory.appendingPathComponent(path)
                if !Self.matches(destination, hash: hash) {
                    guard let url = URL(string: "https://huggingface.co/iky1e/DeepFilterNet3-Streaming-CoreML/resolve/\(Self.revision)/\(path)") else {
                        throw SuperflowError.modelUnavailable("Invalid DeepFilterNet 3 artifact URL.")
                    }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 120
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                          Self.hash(data) == hash else {
                        throw SuperflowError.modelUnavailable("DeepFilterNet 3 download or checksum failed: \(path)")
                    }
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: destination, options: .atomic)
                }
                progress(Double(index + 1) / Double(Self.artifacts.count))
            }
        }
        downloading = task
        defer { downloading = nil }
        try await task.value
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func matches(_ url: URL, hash: String) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return self.hash(data) == hash
    }
}
