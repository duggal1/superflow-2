@preconcurrency import CoreML
import FluidAudio
import Foundation
import SuperflowKernel

/// Builds and loads one FluidAudio streaming manager from a directory that is
/// already on disk. The injected form is the test seam for watchdog recreation.
public typealias FluidAudioEngineFactory =
    @Sendable (_ profileID: String, _ modelDirectory: URL) async throws -> any StreamingAsrManager

public enum FluidAudioEngineLoader {
    /// Loads only from `modelDirectory`; it never asks FluidAudio to download.
    public static func load(profileID: String, modelDirectory: URL) async throws -> any StreamingAsrManager {
        guard let profile = FluidAudioCatalog.profile(for: profileID) else {
            throw SuperflowError.modelUnavailable("Unsupported ASR profile \(profileID)")
        }
        // Test seam: lets the speed bench point at another tier (for example latin/2240ms)
        // without changing the product profile.
        let directory = ProcessInfo.processInfo.environment["SUPERFLOW_MODEL_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? modelDirectory
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits()
        switch profile.engine {
        case .streaming(let variant):
            let manager = variant.createManager(configuration: configuration)
            try await loadModels(manager, from: directory)
            return manager
        case .nemotronMultilingual:
            let manager = NemotronMultilingualStreamingEngine(configuration: configuration)
            try await manager.loadModels(from: directory)
            return manager
        }
    }

    private static func computeUnits() -> MLComputeUnits {
        switch ProcessInfo.processInfo.environment["SUPERFLOW_COMPUTE_UNITS"]?.lowercased() {
        case "cpu": return .cpuOnly
        case "gpu": return .cpuAndGPU
        case "all": return .all
        case "ane": return .cpuAndNeuralEngine
        // Owner decision: GPU is the default for long runs. Measured on this M1 at the
        // 1120 ms tier: CPU 12.7x vs GPU 10.9x (CPU slightly ahead at short chunks);
        // the 2240 ms GPU comparison is still outstanding. Override with
        // SUPERFLOW_COMPUTE_UNITS=cpu|ane|all.
        default: return .cpuAndGPU
        }
    }

    private static func loadModels(_ manager: any StreamingAsrManager, from directory: URL) async throws {
        switch manager {
        case let eou as StreamingEouAsrManager:
            try await eou.loadModels(from: directory)
        case let nemotron as StreamingNemotronAsrManager:
            try await nemotron.loadModels(from: directory)
        case let unified as StreamingUnifiedAsrManager:
            try await unified.loadModels(from: directory)
        default:
            throw SuperflowError.modelUnavailable("FluidAudio manager cannot load from a local directory")
        }
    }
}

/// Allocates and releases streaming managers. The pool is deliberately tiny:
/// meeting mode needs two engines (mic + system) and nothing else runs at the
/// same time. Returning a third engine cleans it up instead of retaining it.
actor FluidAudioManagerPool {
    private let factory: FluidAudioEngineFactory
    private let cacheRoot: URL
    private let maximumIdlePerProfile: Int
    private var idle: [String: [any StreamingAsrManager]] = [:]

    init(cacheRoot: URL, maximumIdlePerProfile: Int = 2,
         factory: @escaping FluidAudioEngineFactory = { profileID, directory in
             try await FluidAudioEngineLoader.load(profileID: profileID, modelDirectory: directory)
         }) {
        self.cacheRoot = cacheRoot
        self.maximumIdlePerProfile = maximumIdlePerProfile
        self.factory = factory
    }

    func acquire(profileID: String) async throws -> any StreamingAsrManager {
        if var managers = idle[profileID], let manager = managers.popLast() {
            idle[profileID] = managers
            return manager
        }
        guard let profile = FluidAudioCatalog.profile(for: profileID) else {
            throw SuperflowError.modelUnavailable("Unsupported ASR profile \(profileID)")
        }
        let directory = FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: cacheRoot)
        return try await factory(profileID, directory)
    }

    func release(_ manager: any StreamingAsrManager, profileID: String) async {
        if idle[profileID, default: []].count < maximumIdlePerProfile {
            idle[profileID, default: []].append(manager)
            return
        }
        await manager.cleanup()
    }

    func removeAll() async {
        let managers = idle.values.flatMap { $0 }
        idle.removeAll()
        for manager in managers { await manager.cleanup() }
    }

    var idleCount: Int {
        idle.values.reduce(0) { $0 + $1.count }
    }
}
