import Foundation
import Testing
import SuperflowKernel
@testable import SuperflowAudioCpp

@Test func selectableSpeechModelsHaveNativeIncrementalOutputPaths() {
    let ids = ModelProfile.streamingProfiles.map(\.id)
    #expect(ids == [
        ModelProfile.nemotron35Streaming.id,
        ModelProfile.qwen3ASR06B.id,
        ModelProfile.qwen3ASR17B.id,
        ModelProfile.voxtralRealtime.id,
    ])
    for id in ids {
        #expect(AudioCppRecognizer.supports(id), "Missing native runtime for \(id)")
        #expect(ModelProfile.byID(id).streaming)
    }
    #expect(!ids.contains("moonshine-streaming-tiny"))
    #expect(!AudioCppRecognizer.supports("moonshine-streaming-tiny"))
    #expect(!AudioCppRecognizer.supports("unknown"))
}

@Test func pinnedStreamingArtifactsAreUniqueChecksummedAndVendorAccurate() {
    let pairs: [(String, AudioCppAsset)] = [
        (ModelProfile.nemotron35Streaming.id, .speech),
        (ModelProfile.qwen3ASR06B.id, .qwenASR06B),
        (ModelProfile.qwen3ASR17B.id, .qwenASR17B),
        (ModelProfile.voxtralRealtime.id, .voxtralRealtime),
    ]
    var filenames = Set<String>()
    for (id, asset) in pairs {
        #expect(AudioCppAsset(speechProfileID: id) == asset)
        #expect(asset.isSpeech)
        #expect(asset.task == "asr")
        #expect(asset.digest.count == 64)
        #expect(asset.digest.allSatisfy { $0.isHexDigit })
        #expect(asset.downloadPath.hasPrefix("audio-cpp/"))
        #expect(asset.downloadPath.contains("/resolve/"))
        #expect(filenames.insert(asset.fileName).inserted)
        #expect(ModelProfile.byID(id).licenseName != "Not verified")
        #expect(ModelProfile.byID(id).artifactBytes > 0)
    }
    #expect(AudioCppAsset.speakers.task == "diar")
    #expect(AudioCppAsset.speakers.family == "nemotron_3_diar")
    #expect(AudioCppAsset.speech.fileName == "nemotron-q8_0.gguf")
    // Values from the pinned audio-cpp/audio.cpp-gguf Git LFS pointers.
    let pinned: [(ModelProfile, AudioCppAsset, String, Int64)] = [
        (.qwen3ASR06B, .qwenASR06B,
         "6c44ec2fb4cee513892d7863c1fcc3ea6b699ffa4d899b0ef4ab19956d9544f7", 1_151_272_416),
        (.qwen3ASR17B, .qwenASR17B,
         "da4fc2ac7f24dee784d1684eb1f35836cdbf559519452ae11777670734c0a4f8", 2_473_010_048),
        (.voxtralRealtime, .voxtralRealtime,
         "8cafef18ea3e4cad81da8ffc4e72b69d2eab2c159c2e68428e2e088accbfc7f8", 3_097_662_432),
    ]
    for (profile, asset, sha, bytes) in pinned {
        #expect(asset.digest == sha)
        #expect(profile.artifactBytes == bytes)
    }

}

@Test func unknownSpeechProfilesAreNeverMistakenForNemotron() async {
    let recognizer = AudioCppRecognizer()
    #expect(await recognizer.isAvailable(profileID: "moonshine-streaming-tiny") == false)
    #expect(await recognizer.isAvailable(profileID: "not-a-real-model") == false)
    do {
        try await recognizer.warmUp(profile: "not-a-real-model")
        Issue.record("Unrecognized streaming profile was accepted")
    } catch {
        #expect(error.localizedDescription.contains("Unsupported streaming ASR profile"))
    }
}


@Test func deletingOneStreamingArtifactPreservesOtherModelsAndCaches() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("superflow-removal-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let qwen = directory.appendingPathComponent(AudioCppAsset.qwenASR06B.fileName)
    let nemotron = directory.appendingPathComponent(AudioCppAsset.speech.fileName)
    let receipt = qwen.appendingPathExtension("verified.json")
    try Data("mock qwen weights".utf8).write(to: qwen)
    try Data("mock nemotron weights".utf8).write(to: nemotron)
    try Data("stale verification".utf8).write(to: receipt)

    let runtime = AudioCppRuntime(asset: .qwenASR06B, root: directory)
    try await runtime.removeInstalledModel()
    #expect(!FileManager.default.fileExists(atPath: qwen.path))
    #expect(!FileManager.default.fileExists(atPath: receipt.path))
    #expect(FileManager.default.fileExists(atPath: nemotron.path))

    let speakerRuntime = AudioCppRuntime(asset: .speakers, root: directory)
    do {
        try await speakerRuntime.removeInstalledModel()
        Issue.record("Diarization model was incorrectly removable as speech")
    } catch {
        #expect(error.localizedDescription.isEmpty == false)
    }
}
