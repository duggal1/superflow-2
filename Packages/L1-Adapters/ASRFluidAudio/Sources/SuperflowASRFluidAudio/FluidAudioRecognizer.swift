import FluidAudio
import Foundation
import SuperflowKernel
import SuperflowPorts

/// FluidAudio-backed streaming recognizer. The adapter is intentionally
/// offline at record time: `prepare` checks that every artifact is already on
/// disk, then asks FluidAudio to load from that directory without downloading.
public actor FluidAudioRecognizer: SpeechRecognizer {
    private let modelCacheRoot: URL
    private let fileManager: FileManager
    private let engineFactory: FluidAudioEngineFactory
    private let voiceActivityFactory: VoiceActivityFactory?
    private let downloader: any FluidAudioModelDownloading
    private let pool: FluidAudioManagerPool

    private var preparedProfiles: Set<String> = []
    private var preparing: [String: Task<any StreamingAsrManager, Error>] = [:]
    private var vadManager: VadManager?

    public init(modelCacheRoot: URL? = nil, fileManager: FileManager = .default,
                engineFactory: FluidAudioEngineFactory? = nil,
                voiceActivityFactory: VoiceActivityFactory? = nil,
                downloader: any FluidAudioModelDownloading = FluidAudioModelHubDownloader()) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let root = modelCacheRoot
            ?? appSupport.appendingPathComponent("Superflow/Models/FluidAudio", isDirectory: true)
        let factory: FluidAudioEngineFactory = engineFactory ?? { profileID, directory in
            try await FluidAudioEngineLoader.load(profileID: profileID, modelDirectory: directory)
        }
        self.modelCacheRoot = root
        self.fileManager = fileManager
        self.engineFactory = factory
        self.voiceActivityFactory = voiceActivityFactory
        self.downloader = downloader
        self.pool = FluidAudioManagerPool(cacheRoot: root, factory: factory)
    }

    public var isReady: Bool { !preparedProfiles.isEmpty }

    public func isAvailable(profileID: String) async -> Bool {
        FluidAudioCatalog.isInstalled(profileID, cacheRoot: modelCacheRoot, fileManager: fileManager)
    }

    /// Download when needed, verify integrity, then load. This is the onboarding/Settings
    /// download entry point and the only ASR path allowed to touch the network. A cache that is
    /// present but fails verification is dropped and refetched rather than loaded.
    public func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let profile = FluidAudioCatalog.profile(for: profileID) else {
            throw SuperflowError.modelUnavailable("Unsupported ASR profile \(profileID)")
        }
        if preparedProfiles.contains(profileID) {
            progress(1)
            return
        }

        var installed = FluidAudioCatalog.isInstalled(profileID, cacheRoot: modelCacheRoot,
                                                      fileManager: fileManager)
        if installed {
            installed = (try? FluidAudioArtifactIntegrity.verify(profile: profile,
                                                                 cacheRoot: modelCacheRoot,
                                                                 fileManager: fileManager)) ?? false
        }
        if !installed {
            if FluidAudioCatalog.isInstalled(profileID, cacheRoot: modelCacheRoot,
                                             fileManager: fileManager) {
                FluidAudioArtifactIntegrity.invalidate(profile: profile, cacheRoot: modelCacheRoot,
                                                       fileManager: fileManager)
            }
            progress(0)
            try await downloader.download(profileID: profileID, cacheRoot: modelCacheRoot) { value in
                progress(min(0.9, value * 0.9))
            }
            let complete = (try? FluidAudioArtifactIntegrity.verify(profile: profile,
                                                                    cacheRoot: modelCacheRoot,
                                                                    fileManager: fileManager)) ?? false
            guard complete else {
                throw SuperflowError.modelUnavailable(
                    "Downloaded \(profile.id) failed integrity verification.")
            }
        }

        progress(0.92)
        let task: Task<any StreamingAsrManager, Error>
        if let existing = preparing[profileID] {
            task = existing
        } else {
            let factory = engineFactory
            let directory = FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: modelCacheRoot)
            task = Task { try await factory(profileID, directory) }
            preparing[profileID] = task
        }

        do {
            let manager = try await task.value
            preparing[profileID] = nil
            preparedProfiles.insert(profileID)
            await Self.warmPredictions(manager)
            await pool.release(manager, profileID: profileID)
            progress(1)
        } catch {
            preparing[profileID] = nil
            throw error
        }
    }

    /// Load-only warm-up for launch and record time. It never downloads: if the verified
    /// artifacts are absent the caller surfaces "download in Settings" instead of blocking on
    /// the network mid-session.
    public func warmUp(profile: String) async throws {
        guard let profile = FluidAudioCatalog.profile(for: profile) else {
            throw SuperflowError.modelUnavailable("Unsupported ASR profile \(profile)")
        }
        if preparedProfiles.contains(profile.id) { return }
        guard FluidAudioCatalog.isInstalled(profile.id, cacheRoot: modelCacheRoot,
                                            fileManager: fileManager) else {
            let missing = FluidAudioCatalog.missingArtifacts(profile.id, cacheRoot: modelCacheRoot,
                                                             fileManager: fileManager)
            throw SuperflowError.modelUnavailable(
                "\(profile.id) is not downloaded (missing \(missing.joined(separator: ", "))).")
        }
        let task: Task<any StreamingAsrManager, Error>
        if let existing = preparing[profile.id] {
            task = existing
        } else {
            let factory = engineFactory
            let directory = FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: modelCacheRoot)
            task = Task { try await factory(profile.id, directory) }
            preparing[profile.id] = task
        }
        do {
            let manager = try await task.value
            preparing[profile.id] = nil
            preparedProfiles.insert(profile.id)
            await Self.warmPredictions(manager)
            await pool.release(manager, profileID: profile.id)
        } catch {
            preparing[profile.id] = nil
            throw error
        }
    }

    public func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        guard let descriptor = FluidAudioCatalog.profile(for: profile) else {
            throw SuperflowError.modelUnavailable("Unsupported ASR profile \(profile)")
        }
        guard preparedProfiles.contains(profile) else {
            throw SuperflowError.invalidState("prepare(profileID:) must succeed before makeStream")
        }
        guard await isAvailable(profileID: profile) else {
            throw SuperflowError.modelUnavailable("\(descriptor.id) is no longer on disk.")
        }

        let manager = try await pool.acquire(profileID: profile)
        let activity = await makeVoiceActivity()
        let directory = FluidAudioCatalog.modelDirectory(for: descriptor, cacheRoot: modelCacheRoot)
        let stream = FluidAudioRecognitionStream(
            profileID: profile, source: source, manager: manager,
            modelDirectory: directory, engineFactory: engineFactory,
            voiceActivity: activity) { [weak self] returned in
                guard let self else {
                    await returned.cleanup()
                    return
                }
                await self.returnEngine(returned, profileID: profile)
            }
        await stream.configure()
        return stream
    }

    public func describeAvailability() -> String { FluidAudioAvailability.explanation }

    /// Releases every idle engine. Safe to call from any state; the next
    /// `makeStream` recreates what it needs.
    public func unload() async {
        preparedProfiles.removeAll()
        vadManager = nil
        await pool.removeAll()
    }

    private func returnEngine(_ manager: any StreamingAsrManager, profileID: String) async {
        await pool.release(manager, profileID: profileID)
    }

    /// Load plus one dummy prediction. The first prediction triggers Core ML's
    /// ANE specialization and warms the decode buffers; paying it at launch keeps
    /// it off the record path. Best effort: a failed warm-up must not fail prepare.
    private static func warmPredictions(_ manager: any StreamingAsrManager) async {
        // 4 s of silence covers the largest streaming chunk in the catalog
        // (2,240 ms) with margin; FluidAudio re-chunks internally.
        let silence = [Float](repeating: 0, count: sampleRate * 4)
        guard let buffer = try? FluidAudioBuffer.make(silence) else { return }
        try? await manager.appendAudio(buffer)
        try? await manager.processBufferedAudio()
        _ = try? await manager.finish()
        try? await manager.reset()
    }

    private func makeVoiceActivity() async -> any VoiceActivityClassifying {
        if let voiceActivityFactory { return await voiceActivityFactory() }
        if let vadManager { return SileroVoiceActivity(manager: vadManager) }
        let url = FluidAudioCatalog.vadModelURL(cacheRoot: modelCacheRoot)
        guard fileManager.fileExists(atPath: url.path) else { return EnergyVoiceActivity() }
        do {
            let manager = try SileroVoiceActivityLoader.makeManager(modelURL: url)
            vadManager = manager
            return SileroVoiceActivity(manager: manager)
        } catch {
            return EnergyVoiceActivity()
        }
    }
}

public struct UnavailableSpeechRecognizer: SpeechRecognizer {
    public init() {}
    public var isReady: Bool { false }
    public func isAvailable(profileID: String) async -> Bool { false }

    public func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        throw SuperflowError.modelUnavailable(FluidAudioAvailability.explanation)
    }

    public func warmUp(profile: String) async throws {
        throw SuperflowError.modelUnavailable(FluidAudioAvailability.explanation)
    }

    public func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        throw SuperflowError.modelUnavailable(FluidAudioAvailability.explanation)
    }
}
