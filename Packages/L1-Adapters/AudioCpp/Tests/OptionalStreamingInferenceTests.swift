import AVFoundation
import Foundation
import SuperflowAudioCpp
import SuperflowKernel
import Testing

private actor StreamingObservations {
    private(set) var partials = 0
    private(set) var commits = 0
    private(set) var failures: [String] = []

    func observe(_ event: RecognitionEvent) {
        switch event {
        case .partial(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                partials += 1
            }
        case .committed(let segment):
            if !segment.text.isEmpty { commits += 1 }
        case .failure(let message):
            failures.append(message)
        case .endpoint:
            break
        }
    }
}

/// Run explicitly on a real Apple-silicon Mac AFTER downloading the selected
/// GGUFs through Models. This is a real hardware acceptance test, not a mock:
/// SUPERFLOW_TEST_OPTIONAL_STREAMING=1 swift test --package-path
/// Packages/L1-Adapters/AudioCpp --filter optionalASREmitsTextDuringCapture
@Test(.enabled(if: ProcessInfo.processInfo.environment["SUPERFLOW_TEST_OPTIONAL_STREAMING"] == "1"),
      arguments: [ModelProfile.qwen3ASR06B, .qwen3ASR17B, .voxtralRealtime])
func optionalASREmitsTextDuringCapture(profile: ModelProfile) async throws {
    let root = AudioCppTestModels.repositoryRoot
    let cache = root.appendingPathComponent(".models/audio-cpp", isDirectory: true)
    let recognizer = AudioCppRecognizer(modelCacheRoot: cache)
    #expect(await recognizer.isAvailable(profileID: profile.id),
            "Install \(profile.displayName) in the test cache before running")
    try await recognizer.warmUp(profile: profile.id)

    let fixture = root.appendingPathComponent(
        "ThirdParty/audio.cpp/tests/parakeet_tdt/assets/2086-149220-0033.wav")
    let audio = try AVAudioFile(forReading: fixture)
    let format = audio.processingFormat
    #expect(format.sampleRate == 16_000 && format.channelCount == 1)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                        frameCapacity: AVAudioFrameCount(audio.length)) else {
        Issue.record("Cannot read the speech fixture as 16-kHz mono PCM")
        return
    }
    try audio.read(into: buffer)
    guard let channel = buffer.floatChannelData?.pointee else {
        Issue.record("Speech fixture has no decoded float samples")
        return
    }

    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    let stream = try await recognizer.makeStream(profile: profile.id, source: .mic)
    let observed = StreamingObservations()
    let receiver = Task {
        for await event in stream.events { await observed.observe(event) }
    }

    for offset in stride(from: 0, to: samples.count, by: 5_120) {
        let end = min(samples.count, offset + 5_120)
        await stream.feed(AudioChunk(samples: Array(samples[offset..<end]),
                                     startSample: Int64(offset), source: .mic))
    }
    // The model must emit useful text while the microphone is still active,
    // not only after finish() has buffered and decoded the whole recording.
    try await Task.sleep(for: .milliseconds(100))
    let duringCapture = await observed.partials
    await stream.finish()
    await receiver.value
    let commits = await observed.commits
    let failures = await observed.failures
    #expect(duringCapture > 0, "\(profile.displayName) did not emit an incremental transcript")
    #expect(commits > 0, "\(profile.displayName) did not commit a final transcript")
    #expect(failures.isEmpty)
    await recognizer.unload()
}
