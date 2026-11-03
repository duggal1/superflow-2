import CryptoKit
import Foundation
import SuperflowKernel

enum AudioCppAsset: Sendable {
    private struct Verification: Codable, Equatable {
        let digest: String
        let size: Int
        let modified: Date
    }

    case speech, speakers

    var family: String { self == .speech ? "nemotron_asr" : "nemotron_3_diar" }
    var task: String { self == .speech ? "asr" : "diar" }
    var fileName: String { self == .speech ? "nemotron-q8_0.gguf" : "diarization-q8_0.gguf" }
    var digest: String {
        self == .speech
            ? "c58b62c1bdd6c5d7b14b08126c5bd16c1289fee6e0d6ac0761dbd3aa6d714935"
            : "9a737455bd10123bcf1e036d9a0b07b6e8c42e7d0dd1a5ee4141dc386db46d0b"
    }
    var downloadPath: String {
        switch self {
        case .speech:
            "audio-cpp/audio.cpp-gguf/resolve/874fcb41ececda20bcbc0782d6b4ea7f7d069ea8/Nemotron-3.5-ASR-Streaming-0.6B-GGUF/nemotron-3.5-asr-streaming-0.6b-q8_0.gguf"
        case .speakers:
            "audio-cpp/Nemotron-3-Diarization-GGUF/resolve/647d39feaa0e91dca5ce355a95403837b76dff56/nemotron-3-diarization-q8_0.gguf"
        }
    }

    func verified(_ url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values.fileSize, let modified = values.contentModificationDate else { return false }
        let verification = Verification(digest: digest, size: size, modified: modified)
        let receipt = url.appendingPathExtension("verified.json")
        if let data = try? Data(contentsOf: receipt),
           let cached = try? JSONDecoder().decode(Verification.self, from: data), cached == verification {
            return true
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == digest else { return false }
        if let data = try? JSONEncoder().encode(verification) {
            try? data.write(to: receipt, options: .atomic)
        }
        return true
    }

    func install(at destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let url = URL(string: "https://huggingface.co/" + downloadPath) else {
            throw SuperflowError.modelUnavailable("Invalid audio.cpp model URL")
        }
        let (temporary, response) = try await URLSession.shared.download(from: url, delegate: ModelDownloadProgress(progress: progress))
        defer {
            try? FileManager.default.removeItem(at: temporary)
            try? FileManager.default.removeItem(at: temporary.appendingPathExtension("verified.json"))
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              try verified(temporary) else {
            throw SuperflowError.modelUnavailable("audio.cpp model download failed verification")
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}

private final class ModelDownloadProgress: NSObject, URLSessionDownloadDelegate {
    private let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(0.9, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 0.9))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
