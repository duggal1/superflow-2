import CryptoKit
import Foundation
import SuperflowKernel
import SuperflowModelStore

public actor SherpaOnnxModelStore {
    public static let profileID = ModelProfile.nemotron35Streaming.id
    public static let modelName = "sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-80ms-int8-2026-06-11"
    public static let archiveSize: Int64 = 475_274_007
    public static let archiveSHA256 = "fb170128c496db33a1fb9f5f9f823257f42f911224ee218bb429f3c2eaf90a8d"
    public static let archiveURLString =
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(modelName).tar.bz2"
    public static let requiredFiles = ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]

    private struct Marker: Codable, Equatable {
        var archiveSHA256: String
        var fileSizes: [String: Int64]
    }

    private let root: URL
    private let fileManager: FileManager
    private let downloader: any ModelDownloading

    public init(root: URL? = nil, fileManager: FileManager = .default,
                downloader: any ModelDownloading = URLSessionModelDownloader()) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.root = root ?? support.appendingPathComponent("Superflow/Models/SherpaOnnx", isDirectory: true)
        self.fileManager = fileManager
        self.downloader = downloader
    }

    public func modelDirectory() -> URL {
        root.appendingPathComponent(Self.modelName, isDirectory: true)
    }

    public func isAvailable() -> Bool {
        let directory = modelDirectory()
        guard let data = try? Data(contentsOf: markerURL(in: directory)),
              let marker = try? JSONDecoder().decode(Marker.self, from: data),
              marker.archiveSHA256 == Self.archiveSHA256 else { return false }
        return Self.requiredFiles.allSatisfy { name in
            let url = directory.appendingPathComponent(name)
            guard let expected = marker.fileSizes[name], expected > 0,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
                return false
            }
            return values.isRegularFile == true && Int64(values.fileSize ?? 0) == expected
        }
    }

    public func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if isAvailable() {
            progress(1)
            return
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let transaction = UUID().uuidString
        let archive = root.appendingPathComponent(".\(Self.modelName).tar.bz2")
        let extraction = root.appendingPathComponent(".\(transaction)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: extraction)
        }

        guard let archiveURL = URL(string: Self.archiveURLString) else {
            throw SuperflowError.modelUnavailable("The sherpa-onnx model URL is invalid.")
        }
        progress(0)
        let archiveIsVerified = fileManager.fileExists(atPath: archive.path)
            && (try? Self.sha256(of: archive)) == Self.archiveSHA256
        if archiveIsVerified {
            progress(0.75)
        } else {
            try? fileManager.removeItem(at: archive)
            try adoptResumableParts(for: archive)
            if try assembleCompleteParts(for: archive) {
                progress(0.75)
            } else {
                try await downloader.download(from: archiveURL, to: archive,
                                              expectedBytes: Self.archiveSize) { fraction in
                    progress(min(0.75, fraction * 0.75))
                }
            }
            guard try Self.sha256(of: archive) == Self.archiveSHA256 else {
                try? fileManager.removeItem(at: archive)
                throw SuperflowError.modelUnavailable(
                    "The sherpa-onnx model archive failed SHA-256 verification.")
            }
        }

        try fileManager.createDirectory(at: extraction, withIntermediateDirectories: true)
        try Self.extract(archive, into: extraction)
        let staged = extraction.appendingPathComponent(Self.modelName, isDirectory: true)
        let fileSizes = try Self.fileSizes(in: staged)
        progress(0.9)

        let marker = Marker(archiveSHA256: Self.archiveSHA256, fileSizes: fileSizes)
        try JSONEncoder().encode(marker).write(to: markerURL(in: staged), options: .atomic)
        try install(staged)
        guard isAvailable() else {
            throw SuperflowError.modelUnavailable("The installed sherpa-onnx model is incomplete.")
        }
        try? fileManager.removeItem(at: archive)
        progress(1)
    }

    private func adoptResumableParts(for archive: URL) throws {
        let target = Self.partsDirectory(for: archive)
        guard !fileManager.fileExists(atPath: target.path) else { return }
        let candidates = try fileManager.contentsOfDirectory(at: root,
                                                              includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.lastPathComponent.hasPrefix(".segments-.")
                && $0.lastPathComponent.hasSuffix(".tar.bz2") }
            .compactMap { candidate -> (URL, Int64)? in
                guard (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      let marker = try? String(contentsOf: candidate.appendingPathComponent("total"),
                                               encoding: .utf8),
                      marker.trimmingCharacters(in: .whitespacesAndNewlines)
                        == "\(Self.archiveSize) 8" else { return nil }
                var bytes: Int64 = 0
                for index in 0..<8 {
                    let part = candidate.appendingPathComponent("part-\(index)")
                    guard fileManager.fileExists(atPath: part.path) else { continue }
                    guard let values = try? part.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true,
                          let size = values.fileSize else { return nil }
                    let expected = index == 7
                        ? Self.archiveSize - (Self.archiveSize / 8) * 7
                        : Self.archiveSize / 8
                    guard Int64(size) <= expected else { return nil }
                    bytes += Int64(size)
                }
                return bytes > 0 ? (candidate, bytes) : nil
            }
        guard let candidate = candidates.max(by: { $0.1 < $1.1 })?.0 else { return }
        try fileManager.moveItem(at: candidate, to: target)
    }

    private func assembleCompleteParts(for archive: URL) throws -> Bool {
        let directory = Self.partsDirectory(for: archive)
        guard let marker = try? String(contentsOf: directory.appendingPathComponent("total"),
                                       encoding: .utf8),
              marker.trimmingCharacters(in: .whitespacesAndNewlines) == "\(Self.archiveSize) 8" else {
            return false
        }

        var parts: [URL] = []
        for index in 0..<8 {
            let part = directory.appendingPathComponent("part-\(index)")
            guard let values = try? part.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { return false }
            let expected = index == 7
                ? Self.archiveSize - (Self.archiveSize / 8) * 7
                : Self.archiveSize / 8
            guard Int64(size) == expected else { return false }
            parts.append(part)
        }

        guard fileManager.createFile(atPath: archive.path, contents: nil),
              let output = try? FileHandle(forWritingTo: archive) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? output.close() }
        var written: Int64 = 0
        for part in parts {
            let input = try FileHandle(forReadingFrom: part)
            defer { try? input.close() }
            while let data = try input.read(upToCount: 1 << 20), !data.isEmpty {
                try output.write(contentsOf: data)
                written += Int64(data.count)
            }
        }
        guard written == Self.archiveSize else {
            try? fileManager.removeItem(at: archive)
            throw SuperflowError.modelUnavailable(
                "The sherpa-onnx model archive ended at \(written) of \(Self.archiveSize) bytes.")
        }
        try output.synchronize()
        try fileManager.removeItem(at: directory)
        return true
    }

    private static func partsDirectory(for archive: URL) -> URL {
        archive.deletingLastPathComponent()
            .appendingPathComponent(".segments-\(archive.lastPathComponent)", isDirectory: true)
    }

    private func install(_ staged: URL) throws {
        let destination = modelDirectory()
        let backup = root.appendingPathComponent(".\(Self.modelName).\(UUID().uuidString).backup",
                                                 isDirectory: true)
        let hadExisting = fileManager.fileExists(atPath: destination.path)
        if hadExisting { try fileManager.moveItem(at: destination, to: backup) }
        do {
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            if hadExisting { try? fileManager.moveItem(at: backup, to: destination) }
            throw error
        }
        if hadExisting { try? fileManager.removeItem(at: backup) }
    }

    private func markerURL(in directory: URL) -> URL {
        directory.appendingPathComponent(".superflow-verified.json")
    }

    private static func fileSizes(in directory: URL) throws -> [String: Int64] {
        var result: [String: Int64] = [:]
        for name in requiredFiles {
            let url = directory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize, size > 0 else {
                throw SuperflowError.modelUnavailable("Missing sherpa-onnx model file \(name).")
            }
            result[name] = Int64(size)
        }
        return result
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func extract(_ archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archive.path, "-C", directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SuperflowError.modelUnavailable("The sherpa-onnx model archive could not be extracted.")
        }
    }
}
