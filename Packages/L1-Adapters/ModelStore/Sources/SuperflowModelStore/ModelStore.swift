import CryptoKit
import Foundation
import SuperflowKernel
import SuperflowPorts

public protocol ModelDownloading: Sendable {
    func download(from url: URL, to destination: URL, expectedBytes: Int64?,
                  progress: @escaping @Sendable (Double) -> Void) async throws
}

/// Downloads and verifies the model artifacts declared in a manifest. A verified
/// sidecar avoids re-hashing a multi-gigabyte file at every launch, while a
/// changed size invalidates the sidecar immediately.
public actor ModelStore: ModelProvider {
    private struct Marker: Codable {
        var sha256: String
        var bytes: Int64
    }

    private let root: URL
    private nonisolated let manifest: ModelManifest
    private let downloader: any ModelDownloading
    private let fileManager: FileManager
    private let overrideRoot: URL?

    public init(root: URL? = nil, manifest: ModelManifest? = nil,
                downloader: any ModelDownloading = URLSessionModelDownloader(),
                fileManager: FileManager = .default,
                environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let resolvedRoot = root ?? base.appendingPathComponent("Superflow/Models", isDirectory: true)
        self.root = resolvedRoot
        self.fileManager = fileManager
        self.downloader = downloader
        if let manifest {
            self.manifest = manifest
        } else {
            self.manifest = ModelManifest.load(root: resolvedRoot, environment: environment,
                                               fileManager: fileManager)
        }
        if let override = environment["SUPERFLOW_MODEL_DIR"], !override.isEmpty {
            overrideRoot = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            overrideRoot = nil
        }
        try fileManager.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
    }

    public func localURL(for profileID: String) async -> URL? {
        guard let artifact = manifest.asr[profileID] else { return nil }
        if let overrideURL = overrideFile(for: artifact), fileManager.fileExists(atPath: overrideURL.path) {
            return overrideURL
        }
        let file = fileURL(for: artifact)
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        if markerMatches(file: file, artifact: artifact) { return file }
        guard ModelVerification.matches(file: file, artifact: artifact) else { return nil }
        writeMarker(file: file, artifact: artifact)
        return file
    }

    public func ensure(profileID: String,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let artifact = manifest.asr[profileID] else {
            throw SuperflowError.modelUnavailable("No manifest entry for \(profileID)")
        }
        if let existing = await localURL(for: profileID) { return existing }
        return try await fetch(artifact, progress: progress)
    }

    public func llmModelURL() async -> URL? {
        guard let artifact = manifest.llm else { return nil }
        if let overrideURL = overrideFile(for: artifact), fileManager.fileExists(atPath: overrideURL.path) {
            return overrideURL
        }
        let file = fileURL(for: artifact)
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        if markerMatches(file: file, artifact: artifact) { return file }
        guard ModelVerification.matches(file: file, artifact: artifact) else { return nil }
        writeMarker(file: file, artifact: artifact)
        return file
    }

    public func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let artifact = manifest.llm else {
            throw SuperflowError.modelUnavailable("No LLM artifact in the model manifest")
        }
        if let existing = await llmModelURL() { return existing }
        return try await fetch(artifact, progress: progress)
    }

    /// Verifies the cached file from scratch and re-downloads when it fails.
    @discardableResult
    public func repair(profileID: String,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let artifact = manifest.asr[profileID] else {
            throw SuperflowError.modelUnavailable("No manifest entry for \(profileID)")
        }
        let file = fileURL(for: artifact)
        if fileManager.fileExists(atPath: file.path) {
            if ModelVerification.matches(file: file, artifact: artifact) {
                writeMarker(file: file, artifact: artifact)
                return file
            }
            try? fileManager.removeItem(at: file)
            try? fileManager.removeItem(at: markerURL(for: file))
            SegmentedTransfer.removeParts(for: temporaryURL(for: artifact))
        }
        return try await fetch(artifact, progress: progress)
    }

    private func fetch(_ artifact: ModelArtifact,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let directory = directory(for: artifact)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let required = artifact.bytes {
            let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
            if available > 0, available < required + 64 * 1_024 * 1_024 {
                throw ModelStoreError.diskSpace(required: required + 64 * 1_024 * 1_024,
                                                available: available)
            }
        }
        let destination = fileURL(for: artifact)
        // Stable per artifact, not a UUID: a retry or a relaunch must find the
        // same partial chunks and resume them instead of starting over.
        let temporary = temporaryURL(for: artifact)
        progress(0)
        defer { try? fileManager.removeItem(at: temporary) }
        try await downloader.download(from: artifact.url, to: temporary,
                                      expectedBytes: artifact.bytes, progress: progress)
        guard ModelVerification.matches(file: temporary, artifact: artifact) else {
            try? fileManager.removeItem(at: temporary)
            SegmentedTransfer.removeParts(for: temporary)
            throw SuperflowError.modelUnavailable("Checksum mismatch for \(artifact.id)")
        }
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)
        writeMarker(file: destination, artifact: artifact)
        progress(1)
        return destination
    }

    private func directory(for artifact: ModelArtifact) -> URL {
        root.appendingPathComponent(safe(artifact.id), isDirectory: true)
    }

    private func fileURL(for artifact: ModelArtifact) -> URL {
        directory(for: artifact).appendingPathComponent(safe(artifact.fileName))
    }

    private func overrideFile(for artifact: ModelArtifact) -> URL? {
        overrideRoot?.appendingPathComponent(safe(artifact.id), isDirectory: true)
            .appendingPathComponent(safe(artifact.fileName))
    }

    private func temporaryURL(for artifact: ModelArtifact) -> URL {
        directory(for: artifact).appendingPathComponent(".download-\(safe(artifact.fileName)).tmp")
    }

    private func markerURL(for file: URL) -> URL {
        file.deletingLastPathComponent().appendingPathComponent(".verified")
    }

    private func markerMatches(file: URL, artifact: ModelArtifact) -> Bool {
        guard let data = try? Data(contentsOf: markerURL(for: file)),
              let marker = try? JSONDecoder().decode(Marker.self, from: data),
              marker.sha256 == artifact.sha256 else { return false }
        if let expected = artifact.bytes, expected > 0, marker.bytes != expected { return false }
        let actual = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        return Int64(actual) == marker.bytes
    }

    private func writeMarker(file: URL, artifact: ModelArtifact) {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let marker = Marker(sha256: artifact.sha256, bytes: Int64(size))
        guard let data = try? JSONEncoder().encode(marker) else { return }
        try? data.write(to: markerURL(for: file), options: .atomic)
    }

    private func safe(_ component: String) -> String {
        URL(fileURLWithPath: component).lastPathComponent
            .replacingOccurrences(of: "..", with: "_")
    }
}
