import Foundation

extension ModelProfile {
    /// Upstream streaming families with pinned audio.cpp native GGUF packages.
    /// Unverified means the implementation still requires a real-device
    /// capture-time partial/final transcript test before claiming a benchmark.
    public static let moonshineTiny = ModelProfile(
        id: "moonshine-streaming-tiny",
        displayName: "Moonshine Streaming Tiny",
        vendor: "Useful Sensors",
        upstreamRepo: "UsefulSensors/moonshine-streaming-tiny",
        runtimeRepo: "audio-cpp/audio.cpp-gguf/Moonshine-Streaming-GGUF",
        language: "English", chunkMs: 320, streaming: true, status: .unverified,
        note: "Lightweight native streaming ASR, Q8_0, MIT license.")

    public static let moonshineSmall = ModelProfile(
        id: "moonshine-streaming-small",
        displayName: "Moonshine Streaming Small",
        vendor: "Useful Sensors",
        upstreamRepo: "UsefulSensors/moonshine-streaming-small",
        runtimeRepo: "audio-cpp/audio.cpp-gguf/Moonshine-Streaming-GGUF",
        language: "English", chunkMs: 320, streaming: true, status: .unverified,
        note: "Native English streaming ASR, Q8_0, MIT license.")

    public static let qwen3ASR06B = ModelProfile(
        id: "qwen3-asr-0.6b",
        displayName: "Qwen3-ASR 0.6B",
        vendor: "Qwen",
        upstreamRepo: "Qwen/Qwen3-ASR-0.6B",
        runtimeRepo: "audio-cpp/audio.cpp-gguf/Qwen3-ASR-0.6B-GGUF",
        language: "30 languages", chunkMs: 320, streaming: true, status: .unverified,
        note: "Multilingual audio.cpp streaming ASR, Q8_0, Apache-2.0 license.")

    public var licenseName: String {
        switch id {
        case Self.moonshineTiny.id, Self.moonshineSmall.id: "MIT"
        case Self.qwen3ASR06B.id: "Apache-2.0"
        case Self.nemotron35Streaming.id: "OpenMDW-1.1"
        default: "Not verified"
        }
    }

    public var artifactBytes: Int64 {
        switch id {
        case Self.moonshineTiny.id: 60_408_448
        case Self.moonshineSmall.id: 300_621_792
        case Self.qwen3ASR06B.id: 1_150_000_000 // Display estimate only; download hashes validate actual bytes.
        case Self.nemotron35Streaming.id: 930_625_888
        default: 0
        }
    }
}
