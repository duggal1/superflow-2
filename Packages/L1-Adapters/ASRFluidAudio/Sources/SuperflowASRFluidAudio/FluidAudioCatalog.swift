import FluidAudio
import Foundation
import SuperflowKernel

/// The FluidAudio engine family behind one catalog profile. Most models use a
/// cache-aware `StreamingModelVariant`; Nemotron 3.5 ships as a separate
/// multilingual manager with its own vocabulary and prompt handling.
public enum FluidAudioEngine: Sendable, Equatable {
    case streaming(StreamingModelVariant)
    case nemotronMultilingual(languageDirectory: String, chunkMs: Int)

    var cachePath: String {
        switch self {
        case .streaming(let variant):
            variant.repo.folderName
        case .nemotronMultilingual(let languageDirectory, let chunkMs):
            "\(Repo.nemotronMultilingual.folderName)/\(languageDirectory)/\(chunkMs)ms"
        }
    }
}

/// One profile the adapter can run. The registry in `SuperflowKernel` owns the
/// product-facing metadata; this type only maps an id to the concrete
/// FluidAudio engine and the artifacts that must already be on disk.
public struct FluidAudioProfile: Sendable, Equatable {
    public let id: String
    public let engine: FluidAudioEngine
    public let requiredArtifacts: [String]
    public let hasNativeEndpointing: Bool

    public init(id: String, engine: FluidAudioEngine,
                requiredArtifacts: [String], hasNativeEndpointing: Bool) {
        self.id = id
        self.engine = engine
        self.requiredArtifacts = requiredArtifacts
        self.hasNativeEndpointing = hasNativeEndpointing
    }

    public var variant: StreamingModelVariant? {
        guard case .streaming(let variant) = engine else { return nil }
        return variant
    }
}

/// Maps product profile ids to FluidAudio variants and local model layout.
/// Nothing here downloads: `isInstalled` is the gate that keeps record-time
/// work offline, and `modelDirectory` is what the loader hands to FluidAudio.
public enum FluidAudioCatalog {
    public static let profiles: [FluidAudioProfile] = [
        FluidAudioProfile(
            id: ModelProfile.parakeetEOU120M.id,
            engine: .streaming(.parakeetEou320ms),
            requiredArtifacts: Array(ModelNames.ParakeetEOU.requiredModels),
            hasNativeEndpointing: true),
        FluidAudioProfile(
            id: ModelProfile.nemotronStreaming.id,
            engine: .streaming(.nemotron560ms),
            requiredArtifacts: [
                ModelNames.NemotronStreaming.preprocessorFile,
                "encoder/encoder_int8.mlmodelc",
                ModelNames.NemotronStreaming.decoderFile,
                ModelNames.NemotronStreaming.jointFile,
                ModelNames.NemotronStreaming.tokenizer,
            ],
            hasNativeEndpointing: false),
        FluidAudioProfile(
            id: ModelProfile.parakeetUnified.id,
            engine: .streaming(.parakeetUnified640ms),
            requiredArtifacts: [
                ModelNames.ParakeetUnified.streamingEncoderFile(
                    precision: .int8, contextSuffix: "70_7_1"),
                ModelNames.ParakeetUnified.decoderFile,
                ModelNames.ParakeetUnified.jointDecisionFile,
                ModelNames.ParakeetUnified.vocab,
            ],
            hasNativeEndpointing: false),
        FluidAudioProfile(
            id: ModelProfile.nemotron35Streaming.id,
            engine: .nemotronMultilingual(languageDirectory: "latin", chunkMs: 2_240),
            requiredArtifacts: [
                ModelNames.NemotronMultilingualStreaming.metadata,
                ModelNames.NemotronMultilingualStreaming.tokenizer,
                ModelNames.NemotronMultilingualStreaming.encoderFile,
                ModelNames.NemotronMultilingualStreaming.decoderFile,
                ModelNames.NemotronMultilingualStreaming.jointFile,
            ],
            hasNativeEndpointing: false),
    ]

    public static func profile(for profileID: String) -> FluidAudioProfile? {
        profiles.first { $0.id == profileID }
    }

    public static func supports(_ profileID: String) -> Bool {
        profile(for: profileID) != nil
    }

    public static func variant(for profileID: String) -> StreamingModelVariant? {
        profile(for: profileID)?.variant
    }

    public static func modelDirectory(for profile: FluidAudioProfile, cacheRoot: URL) -> URL {
        cacheRoot.appendingPathComponent(profile.engine.cachePath, isDirectory: true)
    }

    public static func isInstalled(_ profileID: String, cacheRoot: URL,
                                   fileManager: FileManager = .default) -> Bool {
        guard let profile = profile(for: profileID) else { return false }
        let directory = modelDirectory(for: profile, cacheRoot: cacheRoot)
        return profile.requiredArtifacts.allSatisfy {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    public static func vadModelURL(cacheRoot: URL) -> URL {
        cacheRoot
            .appendingPathComponent(Repo.vad.folderName, isDirectory: true)
            .appendingPathComponent(ModelNames.VAD.sileroVadFile, isDirectory: true)
    }

    public static func vadIsInstalled(cacheRoot: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: vadModelURL(cacheRoot: cacheRoot).path)
    }

    /// Human-readable explanation used when a profile's artifacts are absent.
    public static func missingArtifacts(_ profileID: String, cacheRoot: URL,
                                        fileManager: FileManager = .default) -> [String] {
        guard let profile = profile(for: profileID) else { return ["unsupported profile"] }
        let directory = modelDirectory(for: profile, cacheRoot: cacheRoot)
        return profile.requiredArtifacts.filter {
            !fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}

public enum FluidAudioAvailability {
    public static let isLinked = true
    public static let explanation =
        "FluidAudio 0.17.7 is linked. NVIDIA ASR models must be downloaded in Settings before recording."
}
