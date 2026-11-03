import AVFoundation
import Foundation
import Testing
import SuperflowAudioCpp
import SuperflowKernel

private actor FirstPartial {
    private(set) var elapsed: Duration?
    func record(_ duration: Duration) { if elapsed == nil { elapsed = duration } }
}

@Test func firstPartialArrivesDuringPacedShortAudio() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../..", isDirectory: true).standardizedFileURL
    let audio = try AVAudioFile(forReading: root.appendingPathComponent(
        "ThirdParty/audio.cpp/tests/parakeet_tdt/assets/2086-149220-0033.wav"))
    let format = audio.processingFormat
    #expect(format.sampleRate == 16_000 && format.channelCount == 1)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000) else {
        Issue.record("Could not allocate the audio fixture buffer")
        return
    }
    try audio.read(into: buffer, frameCount: 32_000)
    guard let channel = buffer.floatChannelData?.pointee else {
        Issue.record("Audio fixture is not float PCM")
        return
    }
    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    let recognizer = AudioCppRecognizer(modelCacheRoot: root.appendingPathComponent(".models/audio-cpp"))
    try await recognizer.warmUp(profile: ModelProfile.default.id)
    let stream = try await recognizer.makeStream(profile: ModelProfile.default.id, source: .mic)
    let clock = ContinuousClock()
    let start = clock.now
    let observed = FirstPartial()
    let collector = Task { () -> Int in
        var failures = 0
        for await event in stream.events {
            if case let .partial(text) = event, !text.isEmpty {
                await observed.record(start.duration(to: clock.now))
            }
            if case .failure = event { failures += 1 }
        }
        return failures
    }
    for offset in stride(from: 0, to: samples.count, by: 5_120) {
        let end = min(samples.count, offset + 5_120)
        await stream.feed(AudioChunk(samples: Array(samples[offset..<end]), startSample: Int64(offset), source: .mic))
        let deadline = start.advanced(by: .milliseconds(Int64(end * 1_000 / 16_000)))
        if clock.now < deadline { try await clock.sleep(until: deadline) }
    }
    await stream.finish()
    let failures = await collector.value
    let elapsed = await observed.elapsed
    #expect(failures == 0)
    #expect(elapsed != nil)
    print("asr_first_partial=\(String(describing: elapsed)) input_audio_seconds=\(Double(samples.count) / 16_000) failures=\(failures) runs=1")
    await recognizer.unload()
}
