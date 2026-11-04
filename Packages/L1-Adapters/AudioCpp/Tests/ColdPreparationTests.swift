import Foundation
import Testing
@testable import SuperflowAudioCpp

@Test func coldPreparationStages() async throws {
    let root = AudioCppTestModels.repositoryRoot
    try await AudioCppTestModels.shared.prepareSpeech()
    let runtime = AudioCppRuntime(asset: .speech, root: root.appendingPathComponent(".models/audio-cpp"))
    let clock = ContinuousClock()
    let start = clock.now
    try await runtime.load()
    let loaded = clock.now
    try await runtime.prime()
    let prepared = clock.now
    #expect(await runtime.isReady)
    TestMetricsLog.record("cold_model_load=\(start.duration(to: loaded)) native_session_prepare=\(loaded.duration(to: prepared)) runs=1")
    await runtime.unload()
}

@Test func backendSelectionIsExplicitAndSafe() {
    #expect(AudioCppBackend.select(environment: [:]) == "metal")
    #expect(AudioCppBackend.select(environment: ["SUPERFLOW_AUDIOCPP_BACKEND": "cpu"]) == "cpu")
    #expect(AudioCppBackend.select(environment: ["SUPERFLOW_AUDIOCPP_BACKEND": "metal"]) == "metal")
    #expect(AudioCppBackend.select(environment: ["SUPERFLOW_AUDIOCPP_BACKEND": "unknown"]) == "metal")
}
