import Foundation
import SuperflowKernel
import SuperflowPorts

public actor AudioCppRecognizer: SpeechRecognizer, ASRModelRemoving {
    /// Each family owns its own immutable model, stream handles and verified
    /// artifact. Selecting another profile must never overwrite Nemotron's
    /// installed files or reuse a session from an incompatible family.
    private let runtimes: [String: AudioCppRuntime]
    private var currentProfile = ModelProfile.default.id
    private var streamStarts: [String: Int] = [:]
    private var warmStarts: [String: Int] = [:]

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
        try await runtime.install(progress: progress, warmAfterInstall: false)
    }
    public func warmUp(profile: String) async throws {
        let runtime = try Self.runtime(profile, from: runtimes)
        guard streamStarts.allSatisfy({ $0.key == profile }),
              warmStarts.allSatisfy({ $0.key == profile }) else {
            throw SuperflowError.invalidState("Another speech model is starting or preparing")
        }
        // On launch, the preload and session paths can both request the same
        // model. Coalesce their family reservation rather than rejecting one.
        warmStarts[profile, default: 0] += 1
        defer {
            let remaining = (warmStarts[profile] ?? 1) - 1
            if remaining == 0 { warmStarts.removeValue(forKey: profile) }
            else { warmStarts[profile] = remaining }
        }
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
        for (id, other) in runtimes where id != profile { await other.unloadResident() }
    }
    public func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        let runtime = try Self.runtime(profile, from: runtimes)
        guard streamStarts.allSatisfy({ $0.key == profile }),
              warmStarts.allSatisfy({ $0.key == profile }) else {
            throw SuperflowError.invalidState("Another ASR family is starting or preparing")
        }
        streamStarts[profile, default: 0] += 1
        defer {
            let remaining = (streamStarts[profile] ?? 1) - 1
            if remaining == 0 { streamStarts.removeValue(forKey: profile) }
            else { streamStarts[profile] = remaining }
        }
        for (id, other) in runtimes where id != profile {
            if await other.hasActiveStreams() {
                throw SuperflowError.invalidState("Cannot mix streaming ASR model families")
            }
        }
        currentProfile = profile
        return try await runtime.start(source: source)
    }
    public func remove(profileID: String) async throws {
        let runtime = try Self.runtime(profileID, from: runtimes)
        guard profileID != currentProfile,
              warmStarts[profileID] == nil,
              streamStarts[profileID] == nil else {
            throw SuperflowError.invalidState("Cannot remove an active or preparing speech model")
        }
        try await runtime.removeInstalledModel()
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
