import CryptoKit
import FluidAudio
import Foundation
import SuperflowKernel

/// Downloads the FluidAudio-managed artifacts a streaming profile needs into the app's model
/// cache. This is the only place that touches the network for ASR; record time never does. The
/// concrete implementation delegates to FluidAudio's own download stack so its resumable
/// byte-range transfers, revision pinning and completeness checks stay authoritative, then
/// verifies the on-disk result before the caller loads it.
public protocol FluidAudioModelDownloading: Sendable {
    func download(profileID: String, cacheRoot: URL,
                  progress: @escaping @Sendable (Double) -> Void) async throws
}

/// FluidAudio-backed downloader. Maps each profile to the exact repo/subdirectory FluidAudio
/// expects and forwards progress as a plain fraction.
public struct FluidAudioModelHubDownloader: FluidAudioModelDownloading {
    public init() {}

    public func download(profileID: String, cacheRoot: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let profile = FluidAudioCatalog.profile(for: profileID) else {
            throw SuperflowError.modelUnavailable("Unsupported ASR profile \(profileID)")
        }
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let handler: ProgressHandler = { update in progress(update.fractionCompleted) }
        progress(0)

        switch profile.engine {
        case .streaming(let variant):
            // `additionalModelNames` carries the catalog's exact artifact list so the download
            // covers context-specific encoders (for example Parakeet Unified's latency tier).
            try await ModelHub.download(variant.repo, to: cacheRoot,
                                        additionalModelNames: Set(profile.requiredArtifacts),
                                        progressHandler: handler)
        case .nemotronMultilingual(let languageDirectory, let chunkMs):
            try await ModelHub.download(.nemotronMultilingual,
                                        subdirectory: "\(languageDirectory)/\(chunkMs)ms",
                                        to: cacheRoot,
                                        progressHandler: handler,
                                        shouldSkip: { $0.contains(".mlpackage") })
        }
        progress(1)
    }
}

/// Verifies a downloaded ASR profile: every required artifact must be present and the compiled
/// CoreML bundles must be non-empty, and a SHA-256 over the artifact tree must match the sidecar
/// recorded on the first successful verification. A mismatch means a partial or corrupt cache and
/// the caller re-downloads instead of loading garbage.
public enum FluidAudioArtifactIntegrity {
    private struct Marker: Codable {
        var sha256: String
        var fileCount: Int
    }

    /// One combined hash over every artifact, independent of directory enumeration order.
    public static func digest(profile: FluidAudioProfile, cacheRoot: URL,
                              fileManager: FileManager = .default) throws -> String {
        let directory = FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: cacheRoot)
        var hasher = SHA256()
        for artifact in profile.requiredArtifacts.sorted() {
            let url = directory.appendingPathComponent(artifact)
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                try hashDirectory(url, into: &hasher, root: directory, fileManager: fileManager)
            } else {
                guard fileManager.fileExists(atPath: url.path) else {
                    throw SuperflowError.modelUnavailable("Missing artifact \(artifact)")
                }
                hasher.update(data: Data(("F:" + artifact).utf8))
                hashFile(url, into: &hasher)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Returns true when the cache is complete and matches its recorded sidecar. Writes the
    /// sidecar the first time a freshly downloaded cache verifies clean.
    @discardableResult
    public static func verify(profile: FluidAudioProfile, cacheRoot: URL,
                              fileManager: FileManager = .default) throws -> Bool {
        let missing = FluidAudioCatalog.missingArtifacts(profile.id, cacheRoot: cacheRoot,
                                                         fileManager: fileManager)
        guard missing.isEmpty else { return false }
        let digest = try digest(profile: profile, cacheRoot: cacheRoot, fileManager: fileManager)
        let markerURL = markerURL(for: profile, cacheRoot: cacheRoot)
        if let data = try? Data(contentsOf: markerURL),
           let marker = try? JSONDecoder().decode(Marker.self, from: data) {
            return marker.sha256 == digest
        }
        let count = fileCount(profile: profile, cacheRoot: cacheRoot, fileManager: fileManager)
        if let data = try? JSONEncoder().encode(Marker(sha256: digest, fileCount: count)) {
            try? data.write(to: markerURL, options: .atomic)
        }
        return true
    }

    public static func invalidate(profile: FluidAudioProfile, cacheRoot: URL,
                                  fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: markerURL(for: profile, cacheRoot: cacheRoot))
        let directory = FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: cacheRoot)
        try? fileManager.removeItem(at: directory)
    }

    private static func markerURL(for profile: FluidAudioProfile, cacheRoot: URL) -> URL {
        cacheRoot.appendingPathComponent("\(profile.id).integrity.json")
    }

    private static func fileCount(profile: FluidAudioProfile, cacheRoot: URL,
                                  fileManager: FileManager) -> Int {
        let directory = FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: cacheRoot)
        guard let enumerator = fileManager.enumerator(at: directory,
                                                      includingPropertiesForKeys: [.isRegularFileKey]) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { count += 1 }
        }
        return count
    }

    private static func hashDirectory(_ url: URL, into hasher: inout SHA256, root: URL,
                                      fileManager: FileManager) throws {
        guard let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        var files: [URL] = []
        for case let item as URL in enumerator {
            if (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(item)
            }
        }
        for file in files.sorted(by: { $0.path < $1.path }) {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            hasher.update(data: Data(("D:" + relative).utf8))
            hashFile(file, into: &hasher)
        }
    }

    private static func hashFile(_ url: URL, into hasher: inout SHA256) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        while let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
    }
}
