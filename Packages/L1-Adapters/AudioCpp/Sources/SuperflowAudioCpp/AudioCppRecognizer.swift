import Foundation
import SuperflowKernel
import SuperflowPorts

public actor AudioCppRecognizer: SpeechRecognizer {
    /// Each family owns its own immutable model, stream handles and verified
    /// artifact. Selecting another profile must never overwrite Nemotron's
    /// installed files or reuse a session from an incompatible family.
    private let runtimes: [String: AudioCppRuntime]
    private var currentProfile = ModelProfile.default.id

    public init(modelCacheRoot: URL? = nil, fileManager: FileManager = .default) {
        let root = modelCacheRoot ?? Self.defaultRoot(fileManager)
        runtimes = Dictionary(uniqueKeysWithValues: ModelProfile.streamingProfiles.compactMap { profile in
            guard let asset = AudioCppAsset(speechProfileID: profile.id) else { return nil }
            return (profile.id, AudioCppRuntime(asset: asset, root: root))
        })
    }

    public var isReady: Bool {
        get async { await runtimes[currentProfile]?.isReady ?? false }
    }
    public func isPrepared(profile: String) async -> Bool {
        guard let runtime = runtimes[profile] else { return false }
        return await runtime.isReady
    }
    public func isAvailable(profileID: String) async -> Bool {
        guard let runtime = runtimes[profileID] else { return false }
        return await runtime.isInstalled()
    }
    public func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let runtime = try Self.runtime(profileID, from: runtimes)
        try await runtime.install(progress: progress)
    }
    public func warmUp(profile: String) async throws {
        let runtime = try Self.runtime(profile, from: runtimes)
        // Model preparation can be triggered while another recording is live.
        // Refuse the switch instead of evicting that session's native handles.
        for (id, other) in runtimes where id != profile {
            if await other.hasActiveStreams() {
                throw SuperflowError.invalidState("Cannot switch ASR during active recording")
            }
        }
        try await runtime.prime()
        // Prime may load a large model. Another capture could begin during the
        // await, so repeat the guard before reclaiming old native handles.
        for (id, other) in runtimes where id != profile {
            if await other.hasActiveStreams() {
                throw SuperflowError.invalidState("Active recording started during model preparation")
            }
        }
        currentProfile = profile
        for (id, other) in runtimes where id != profile { await other.unload() }
    }
    public func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        let runtime = try Self.runtime(profile, from: runtimes)
        for (id, other) in runtimes where id != profile {
            if await other.hasActiveStreams() {
                throw SuperflowError.invalidState("Cannot mix streaming ASR model families")
            }
        }
        currentProfile = profile
        return try await runtime.start(source: source)
    }
    public func unload() async {
        for runtime in runtimes.values { await runtime.unload() }
    }
    public static func supports(_ profile: String) -> Bool {
        AudioCppAsset(speechProfileID: profile) != nil
    }
    private static func runtime(_ profile: String, from runtimes: [String: AudioCppRuntime]) throws
        -> AudioCppRuntime {
        guard let runtime = runtimes[profile] else {
            throw SuperflowError.modelUnavailable("Unsupported streaming ASR profile: \(profile)")
        }
        return runtime
    }
    static func defaultRoot(_ fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Superflow/Models/AudioCpp", isDirectory: true)
    }
}

public actor AudioCppDiarizer: SpeakerDiarizer {
    private let runtime: AudioCppRuntime
    private var stream: AudioCppStream?
    public init(cacheDirectory: URL? = nil) {
        runtime = AudioCppRuntime(asset: .speakers,
                                 root: cacheDirectory ?? AudioCppRecognizer.defaultRoot(.default))
    }
    public func isReady() async -> Bool { await runtime.isReady }
    public func isInstalled() async -> Bool { await runtime.isInstalled() }
    public func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await runtime.install(progress: progress)
    }
    public func beginSession() async {
        await stream?.finish()
        await runtime.resetSpeakers()
        stream = try? await runtime.start(source: .system)
    }
    public func feed(_ chunk: AudioChunk) async {
        guard chunk.source == .system else { return }
        await stream?.feed(chunk)
    }
    public func unload() async {
        await stream?.finish()
        stream = nil
        await runtime.unload()
    }
    public func speaker(atMs: Int) async -> String? { await runtime.speaker(atMs: atMs) }
    public func finish() async {
        await stream?.finish()
        stream = nil
    }
}
