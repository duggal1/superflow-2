import CryptoKit
import Foundation
import SuperflowKernel

enum AudioCppAsset: Sendable {
    private struct Verification: Codable, Equatable {
        let digest: String
        let size: Int
        let modified: Date
    }

    case speech, qwenASR06B, qwenASR17B, voxtralRealtime, speakers

    init?(speechProfileID id: String) {
        switch id {
        case ModelProfile.nemotron35Streaming.id: self = .speech
        case ModelProfile.voxtralRealtime.id: self = .voxtralRealtime
        case ModelProfile.qwen3ASR06B.id: self = .qwenASR06B
        case ModelProfile.qwen3ASR17B.id: self = .qwenASR17B
        default: return nil
        }
    }

    var isSpeech: Bool { self != .speakers }
    var isNemotron: Bool { self == .speech }

    var family: String {
        switch self {
        case .speech: "nemotron_asr"
        case .voxtralRealtime: "voxtral_realtime"
        case .qwenASR06B, .qwenASR17B: "qwen3_asr"
        case .speakers: "nemotron_3_diar"
        }
    }
    var task: String { isSpeech ? "asr" : "diar" }
    var fileName: String {
        switch self {
        case .speech: "nemotron-q8_0.gguf" // Preserve existing installed artifact paths.
        case .voxtralRealtime: "voxtral-mini-4b-realtime-2602-q4_k.gguf"
        case .qwenASR06B: "qwen3-asr-0.6b-q8_0.gguf"
        case .qwenASR17B: "qwen3-asr-1.7b-q8_0.gguf"
        case .speakers: "diarization-q8_0.gguf"
        }
    }
    var digest: String {
        switch self {
        case .speech: "c58b62c1bdd6c5d7b14b08126c5bd16c1289fee6e0d6ac0761dbd3aa6d714935"
        case .voxtralRealtime: "8cafef18ea3e4cad81da8ffc4e72b69d2eab2c159c2e68428e2e088accbfc7f8"
        case .qwenASR06B: "6c44ec2fb4cee513892d7863c1fcc3ea6b699ffa4d899b0ef4ab19956d9544f7"
        case .qwenASR17B: "da4fc2ac7f24dee784d1684eb1f35836cdbf559519452ae11777670734c0a4f8"
        case .speakers: "9a737455bd10123bcf1e036d9a0b07b6e8c42e7d0dd1a5ee4141dc386db46d0b"
        }
    }

    var downloadPath: String {
        switch self {
        case .speech:
            "audio-cpp/audio.cpp-gguf/resolve/874fcb41ececda20bcbc0782d6b4ea7f7d069ea8/Nemotron-3.5-ASR-Streaming-0.6B-GGUF/nemotron-3.5-asr-streaming-0.6b-q8_0.gguf"
        case .voxtralRealtime:
            "audio-cpp/audio.cpp-gguf/resolve/4afa5086d2411a3b9e8ec96f1a1c4dd5312b50cd/Voxtral-Mini-4B-Realtime-2602-GGUF/voxtral-mini-4b-realtime-2602-q4_k.gguf"
        case .qwenASR06B:
            "audio-cpp/audio.cpp-gguf/resolve/4c9a3098d552a0f3d9b2adc11638a11022c07d7e/Qwen3-ASR-0.6B-GGUF/qwen3-asr-0.6b-q8_0.gguf"
        case .qwenASR17B:
            "audio-cpp/audio.cpp-gguf/resolve/4c9a3098d552a0f3d9b2adc11638a11022c07d7e/Qwen3-ASR-1.7B-GGUF/qwen3-asr-1.7b-q8_0.gguf"
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

    private func writeVerifiedReceipt(for url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values.fileSize, let modified = values.contentModificationDate else {
            return // Rehash on the next check rather than accept missing metadata.
        }
        let receipt = Verification(digest: digest, size: size, modified: modified)
        let data = try JSONEncoder().encode(receipt)
        try data.write(to: url.appendingPathExtension("verified.json"), options: .atomic)
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
        // The temporary download was SHA-256 checked above. Its receipt is
        // adjacent to the temporary file, not the installed destination.
        // Persist destination metadata to avoid hashing a 1-3 GB model again.
        try? writeVerifiedReceipt(for: destination)
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
