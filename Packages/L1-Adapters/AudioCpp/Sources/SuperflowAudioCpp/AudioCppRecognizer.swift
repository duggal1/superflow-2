import Foundation
import SuperflowKernel
import SuperflowPorts

public actor AudioCppRecognizer: SpeechRecognizer {
    private let runtime: AudioCppRuntime

    public init(modelCacheRoot: URL? = nil, fileManager: FileManager = .default) {
        runtime = AudioCppRuntime(asset: .speech, root: modelCacheRoot ?? Self.defaultRoot(fileManager))
    }
    public var isReady: Bool { get async { await runtime.isReady } }
    public func isPrepared(profile: String) async -> Bool {
        guard Self.supports(profile) else { return false }
        return await runtime.isReady
    }
    public func isAvailable(profileID: String) async -> Bool {
        guard Self.supports(profileID) else { return false }
        return await runtime.isInstalled()
    }
    public func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        try Self.validate(profileID)
        try await runtime.install(progress: progress)
    }
    public func warmUp(profile: String) async throws {
        try Self.validate(profile)
        try await runtime.prime()
    }
    public func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        try Self.validate(profile)
        return try await runtime.start(source: source)
    }
    public func unload() async { await runtime.unload() }
    public static func supports(_ profile: String) -> Bool { profile == ModelProfile.default.id }
    private static func validate(_ profile: String) throws {
        guard supports(profile) else {
            throw SuperflowError.modelUnavailable("audio.cpp supports Nemotron 3.5 streaming")
        }
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
