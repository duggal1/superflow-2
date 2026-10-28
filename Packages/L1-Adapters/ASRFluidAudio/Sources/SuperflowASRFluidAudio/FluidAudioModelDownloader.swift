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

        // FluidAudio reports a fraction only, so speed is measured where the
        // bytes actually land: the size of the profile's cache directory. The
        // total is not published up front, so the meter carries bytes and MB/s
        // without inventing a percentage of its own.
        let directory = FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: cacheRoot)
        DownloadTelemetry.shared.begin(label: profile.id, totalBytes: nil)
        let meter = ModelDirectoryMeter(directory: directory)
        meter.start()
        defer {
            meter.stop()
            DownloadTelemetry.shared.end()
        }

        // Files, connections and stall detection are already resumable and
        // parallel inside FluidAudio; raise the fan-out so a fast link is not
        // limited to four files at a time, and keep the stall watchdog at a
        // minute instead of two so a frozen CDN connection retries sooner.
        let config = DownloadConfig(timeout: 60 * 60,
                                    minStallBytes: 1 << 20,
                                    stallWindow: 60,
                                    maxConcurrentFiles: 8)

        switch profile.engine {
        case .streaming(let variant):
            // `additionalModelNames` carries the catalog's exact artifact list so the download
            // covers context-specific encoders (for example Parakeet Unified's latency tier).
            try await ModelHub.download(variant.repo, to: cacheRoot,
                                        additionalModelNames: Set(profile.requiredArtifacts),
                                        config: config,
                                        progressHandler: handler)
        case .nemotronMultilingual(let languageDirectory, let chunkMs):
            // A subdirectory download is saved at `to/<remote path>`, so `to` has to be the
            // repo folder the catalog reads from. Passing the cache root put the tree at
            // `<cache>/latin/2240ms`, one level above `modelDirectory`, and every completed
            // download then failed integrity verification against an empty directory.
            let subdirectory = "\(languageDirectory)/\(chunkMs)ms"
            let repoDirectory = cacheRoot.appendingPathComponent(
                Repo.nemotronMultilingual.folderName, isDirectory: true)
            Self.adoptFlatCacheIfNeeded(cacheRoot: cacheRoot, subdirectory: subdirectory,
                                        repoDirectory: repoDirectory)
            try await ModelHub.download(.nemotronMultilingual,
                                        subdirectory: subdirectory,
                                        to: repoDirectory,
                                        config: config,
                                        progressHandler: handler,
                                        shouldSkip: { $0.contains(".mlpackage") })
        }
        progress(1)
    }

    /// Builds before this fix downloaded the multilingual tier straight into the cache
    /// root. Move that tree under the repo folder so an existing 584 MB install verifies
    /// instead of being fetched a second time.
    static func adoptFlatCacheIfNeeded(cacheRoot: URL, subdirectory: String,
                                       repoDirectory: URL,
                                       fileManager: FileManager = .default) {
        let legacy = cacheRoot.appendingPathComponent(subdirectory, isDirectory: true)
        let destination = repoDirectory.appendingPathComponent(subdirectory, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path),
              fileManager.fileExists(atPath: legacy.path) else {
            return
        }
        try? fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        try? fileManager.moveItem(at: legacy, to: destination)
    }
}

/// Samples the on-disk size of one model directory while it downloads. This is
/// the only byte source FluidAudio exposes, and it is a real one: the bytes on
/// disk are the bytes that arrived.
final class ModelDirectoryMeter: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "com.superflow.model-download-meter")
    private var timer: DispatchSourceTimer?

    init(directory: URL) {
        self.directory = directory
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(300), repeating: .milliseconds(400))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func sample() {
        DownloadTelemetry.shared.record(receivedBytes: Self.size(of: directory))
    }

    static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory,
                                                              includingPropertiesForKeys: keys) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
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
