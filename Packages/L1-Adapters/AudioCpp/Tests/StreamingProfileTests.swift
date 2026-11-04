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
