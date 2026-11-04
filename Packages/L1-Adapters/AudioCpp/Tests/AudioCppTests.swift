import Foundation
import Testing
import SuperflowAudioCpp
import SuperflowKernel

@Test func metalStreamingProducesAndFinalizesSpeech() async throws {
    let root = AudioCppTestModels.repositoryRoot
    let models = root.appendingPathComponent(".models/audio-cpp")
    try await AudioCppTestModels.shared.prepareSpeech()
    try await AudioCppTestModels.shared.prepareSpeakers()
    let fixture = root.appendingPathComponent("ThirdParty/audio.cpp/tests/parakeet_tdt/assets/2086-149220-0033.wav")
    let data = try Data(contentsOf: fixture)
    var offset = 12
    var samples: [Float] = []
    while offset + 8 <= data.count {
        let length = data.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))) }
        let end = offset + 8 + length
        #expect(end <= data.count)
        guard end <= data.count else { return }
        if String(decoding: data[offset..<offset + 4], as: UTF8.self) == "data" {
            samples = stride(from: offset + 8, to: end - 1, by: 2).map { index in
                data.withUnsafeBytes { Float(Int16(littleEndian: $0.loadUnaligned(fromByteOffset: index, as: Int16.self))) / 32_768 }
            }
            break
        }
        offset = end + length % 2
    }
    #expect(!samples.isEmpty)
    let recognizer = AudioCppRecognizer(modelCacheRoot: models)
    try await recognizer.warmUp(profile: ModelProfile.default.id)
    let stream = try await recognizer.makeStream(profile: ModelProfile.default.id, source: .mic)
    let collected = Task { () -> [RecognitionEvent] in
        var values: [RecognitionEvent] = []
        for await event in stream.events { values.append(event) }
        return values
    }
    for start in stride(from: 0, to: samples.count, by: 5_120) {
        let end = min(samples.count, start + 5_120)
        await stream.feed(AudioChunk(samples: Array(samples[start..<end]), startSample: Int64(start), source: .mic))
    }
    await stream.finish()
    await stream.finish()
    let events = await collected.value
    #expect(events.contains { if case .partial = $0 { true } else { false } })
    let committed = events.compactMap { event -> RawSegment? in
        if case let .committed(segment) = event { segment } else { nil }
    }
    #expect(!committed.isEmpty)
    let expected = "well i don t wish to see it any more observed phoebe turning away her eyes it is certainly very like the old portrait"
    let actual = committed.map(\.text).joined(separator: " ").lowercased()
        .split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    #expect(actual == expected)
    #expect(committed.last?.endSample == Int64(samples.count))
    #expect(!events.contains { if case .failure = $0 { true } else { false } })
    let clock = ContinuousClock()
    let started = clock.now
    let warm = try await recognizer.makeStream(profile: ModelProfile.default.id, source: .mic)
    let warmEvents = Task { () -> [RecognitionEvent] in
        var values: [RecognitionEvent] = []
        for await event in warm.events { values.append(event) }
        return values
    }
    for start in stride(from: 0, to: samples.count, by: 5_120) {
        let end = min(samples.count, start + 5_120)
        await warm.feed(AudioChunk(samples: Array(samples[start..<end]), startSample: Int64(start), source: .mic))
    }
    await warm.finish()
    let elapsed = started.duration(to: clock.now).components
    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    let repeated = await warmEvents.value
    let text = repeated.compactMap { event -> String? in
        if case let .committed(segment) = event { segment.text } else { nil }
    }.joined(separator: " ")
    let normalized = text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    #expect(normalized == expected)
    #expect(!repeated.contains { if case .failure = $0 { true } else { false } })
    TestMetricsLog.record("audio_cpp_warm_stream_seconds=\(seconds) audio_seconds=\(Double(samples.count) / 16_000) runs=1")
    let shifted = try await recognizer.makeStream(profile: ModelProfile.default.id, source: .mic)
    let shiftedEvents = Task { () -> [RecognitionEvent] in
        var values: [RecognitionEvent] = []
        for await event in shifted.events { values.append(event) }
        return values
    }
    var cursor: Int64 = 32_000
    for repetition in 0..<2 {
        for start in stride(from: 0, to: samples.count, by: 5_120) {
            let end = min(samples.count, start + 5_120)
            let chunk = Array(samples[start..<end])
            await shifted.feed(AudioChunk(samples: chunk, startSample: cursor, source: .mic))
            cursor += Int64(chunk.count)
        }
        if repetition == 0 {
            for _ in 0..<3 {
                await shifted.feed(AudioChunk(samples: Array(repeating: 0, count: 5_120),
                                               startSample: cursor, source: .mic))
                cursor += 5_120
            }
        }
    }
    await shifted.finish()
    let resumed = await shiftedEvents.value
    let resumedSegments = resumed.compactMap { event -> RawSegment? in
        if case let .committed(segment) = event { segment } else { nil }
    }
    let resumedText = resumedSegments.map(\.text).joined(separator: " ").lowercased()
        .split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    #expect(resumedText == expected + " " + expected)
    #expect(resumedSegments.first?.startSample == 32_000)
    #expect(resumedSegments.last?.endSample == cursor)
    #expect(!resumed.contains { if case .failure = $0 { true } else { false } })
    await recognizer.unload()
    let diarizer = AudioCppDiarizer(cacheDirectory: models)
    try await diarizer.prepare { _ in }
    await diarizer.beginSession()
    for start in stride(from: 0, to: samples.count, by: 5_120) {
        let end = min(samples.count, start + 5_120)
        await diarizer.feed(AudioChunk(samples: Array(samples[start..<end]), startSample: Int64(start), source: .system))
    }
    await diarizer.finish()
    var identified = false
    for time in stride(from: 1_000, through: 6_000, by: 500) {
        if await diarizer.speaker(atMs: time) == "remote-1" { identified = true }
    }
    #expect(identified)
}
