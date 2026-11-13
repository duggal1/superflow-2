import Foundation

extension ModelProfile {
    /// Upstream streaming families with pinned audio.cpp native GGUF packages.
    /// Unverified means the implementation still requires a real-device
    /// capture-time partial/final transcript test before claiming a benchmark.
    /// Over the 600M-param budget: no longer offered for dictation or download.
    /// Kept defined so saved profiles and installed artifacts still resolve.
    public static let voxtralRealtime = ModelProfile(
        id: "voxtral-mini-4b-realtime-2602",
        displayName: "Voxtral Mini 4B Realtime",
        vendor: "Mistral",
        upstreamRepo: "mistralai/Voxtral-Mini-4B-Realtime-2602",
        runtimeRepo: "audio-cpp/audio.cpp-gguf/Voxtral-Mini-4B-Realtime-2602-GGUF",
        language: "13 languages", chunkMs: nil, streaming: true, status: .unavailable,
        note: "Deprecated: 4B params exceed the 600M budget. Use a 0.6B model.")

    public static let qwen3ASR06B = ModelProfile(
        id: "qwen3-asr-0.6b",
        displayName: "Qwen3-ASR 0.6B",
        vendor: "Qwen",
        upstreamRepo: "Qwen/Qwen3-ASR-0.6B",
        runtimeRepo: "audio-cpp/audio.cpp-gguf/Qwen3-ASR-0.6B-GGUF",
        language: "30 languages", chunkMs: nil, streaming: true, status: .unverified,
        note: "Multilingual audio.cpp streaming ASR, Q8_0, Apache-2.0 license.")

    /// Over the 600M-param budget: no longer offered for dictation or download.
    /// Kept defined so saved profiles and installed artifacts still resolve.
    public static let qwen3ASR17B = ModelProfile(
        id: "qwen3-asr-1.7b",
        displayName: "Qwen3-ASR 1.7B",
        vendor: "Qwen",
        upstreamRepo: "Qwen/Qwen3-ASR-1.7B",
        runtimeRepo: "audio-cpp/audio.cpp-gguf/Qwen3-ASR-1.7B-GGUF",
        language: "30 languages", chunkMs: nil, streaming: true, status: .unavailable,
        note: "Deprecated: 1.7B params exceed the 600M budget. Use a 0.6B model.")

    public var licenseName: String {
        switch id {
        case Self.voxtralRealtime.id: "Apache-2.0"
        case Self.qwen3ASR06B.id, Self.qwen3ASR17B.id: "Apache-2.0"
        case Self.nemotron35Streaming.id: "OpenMDW-1.1"
        default: "Not verified"
        }
    }

    public var artifactBytes: Int64 {
        switch id {
        case Self.qwen3ASR06B.id: 1_151_272_416
        case Self.qwen3ASR17B.id: 2_473_010_048
        case Self.voxtralRealtime.id: 3_097_662_432
        case Self.nemotron35Streaming.id: 930_625_888
        default: 0
        }
    }
}
