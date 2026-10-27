import CryptoKit
import Foundation

public struct ModelArtifact: Sendable, Codable, Hashable {
    public var id: String
    public var fileName: String
    public var url: URL
    public var sha256: String
    public var bytes: Int64?

    public init(id: String, fileName: String, url: URL, sha256: String, bytes: Int64? = nil) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.sha256 = sha256.lowercased()
        self.bytes = bytes
    }
}

public struct ModelManifest: Sendable, Codable, Equatable {
    public var asr: [String: ModelArtifact]
    public var llm: ModelArtifact?

    public init(asr: [String: ModelArtifact] = [:], llm: ModelArtifact? = nil) {
        self.asr = asr
        self.llm = llm
    }

    public static let empty = ModelManifest()

    public static func load(root: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                            fileManager: FileManager = .default) -> ModelManifest {
        var candidates: [URL] = []
        if let override = environment["SUPERFLOW_MODEL_MANIFEST"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        candidates.append(root.appendingPathComponent("manifest.json"))
        if let bundled = Bundle.module.url(forResource: "model-manifest", withExtension: "json") {
            candidates.append(bundled)
        }
        if let bundled = Bundle.main.url(forResource: "model-manifest", withExtension: "json") {
            candidates.append(bundled)
        }
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(ModelManifest.self, from: data) else { continue }
            return manifest
        }
        return .empty
    }
}

public enum ModelVerification {
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let data = try handle.read(upToCount: 1 << 20), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func matches(file: URL, artifact: ModelArtifact) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let number = attributes[.size] as? NSNumber else { return false }
        let size = number.int64Value
        if let expected = artifact.bytes, expected > 0, size != expected { return false }
        return (try? sha256(of: file)) == artifact.sha256
    }
}

public enum ModelStoreError: Error, LocalizedError, Sendable {
    case diskSpace(required: Int64, available: Int64)

    public var errorDescription: String? {
        switch self {
        case .diskSpace(let required, let available):
            "Need \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) free; " +
            "only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available."
        }
    }
}
