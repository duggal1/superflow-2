import Foundation
import SuperflowKernel
import SuperflowPorts

/// AudioSource contract: ordered, non-overlapping chunks on a sample clock,
/// an observable stop event, and idempotent stop with a clean restart.
public struct AudioSourceContract: Sendable {
    public let expectedKind: AudioSourceKind
    public let maximumChunks: Int

    public init(expectedKind: AudioSourceKind = .mic, maximumChunks: Int = 1_000) {
        self.expectedKind = expectedKind
        self.maximumChunks = maximumChunks
    }

    public func verify(_ source: any AudioSource) async throws {
        try contractRequire(source.kind == expectedKind,
                            "AudioSource kind \(source.kind) does not match \(expectedKind)")

        let first = try await source.start()
        let chunks = await ContractStream.collect(first.samples, limit: maximumChunks)
        try contractRequire(!chunks.isEmpty, "AudioSource produced no samples")
        try contractRequire(chunks[0].startSample == 0,
                            "first chunk starts at \(chunks[0].startSample), expected 0")

        var previousEnd: Int64 = 0
        for chunk in chunks {
            try contractRequire(!chunk.samples.isEmpty, "AudioSource produced an empty chunk")
            try contractRequire(chunk.source == expectedKind,
                                "chunk source \(chunk.source) does not match \(expectedKind)")
            try contractRequire(chunk.startSample >= previousEnd,
                                "chunks overlap: \(chunk.startSample) < \(previousEnd)")
            try contractRequire(chunk.endSample == chunk.startSample + Int64(chunk.samples.count),
                                "chunk endSample is not startSample + sample count")
            previousEnd = chunk.endSample
        }

        await source.stop()
        await source.stop()

        let events = await ContractStream.collect(first.events, limit: 16, timeout: .seconds(1))
        try contractRequire(events.contains(.stopped),
                            "AudioSource did not emit .stopped after stop()")

        let second = try await source.start()
        let restarted = await ContractStream.collect(second.samples, limit: 1, timeout: .seconds(1))
        try contractRequire(restarted.first?.startSample == 0,
                            "restart did not reset the sample clock")
        await source.stop()
    }
}

/// SpeechRecognizer contract: prepare warms the requested profile, progress is
/// bounded and monotonic, and a stream commits at least one segment after finish.
public struct SpeechRecognizerContract: Sendable {
    public let profile: String
    public let feedChunks: Int
    public let samplesPerChunk: Int

    public init(profile: String = "contract-profile", feedChunks: Int = 120,
                samplesPerChunk: Int = 1_600) {
        self.profile = profile
        self.feedChunks = feedChunks
        self.samplesPerChunk = samplesPerChunk
    }

    public func verify(_ recognizer: any SpeechRecognizer) async throws {
        let progress = ProgressRecorder()
        try await recognizer.prepare(profileID: profile, progress: { progress.record($0) })
        let ready = await recognizer.isReady
        try contractRequire(ready, "recognizer is not ready after prepare")
        let available = await recognizer.isAvailable(profileID: profile)
        try contractRequire(available, "recognizer is not available after prepare")

        let values = progress.values
        try contractRequire(values.first == 0 && values.last == 1,
                            "prepare progress did not run from 0 to 1: \(values)")
        try contractRequire(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 },
                            "prepare progress is not monotonic: \(values)")

        let stream = try await recognizer.makeStream(profile: profile, source: .mic)
        for index in 0..<feedChunks {
            let start = Int64(index * samplesPerChunk)
            let chunk = AudioChunk(samples: Array(repeating: 0, count: samplesPerChunk),
                                   startSample: start, source: .mic)
            await stream.feed(chunk)
        }
        await stream.finish()

        let events = await ContractStream.collect(stream.events, limit: 512, timeout: .seconds(5))
        let committed = events.contains { event in
            if case .committed = event { return true }
            return false
        }
        try contractRequire(committed, "recognizer stream emitted no committed segment")
    }
}

/// SpeakerDiarizer contract: readiness, session lifecycle, stable labels and
/// idempotent finish.
public struct SpeakerDiarizerContract: Sendable {
    public init() {}

    public func verify(_ diarizer: any SpeakerDiarizer) async throws {
        let ready = await diarizer.isReady()
        try contractRequire(ready, "diarizer is not ready")

        let progress = ProgressRecorder()
        try await diarizer.prepare(progress: { progress.record($0) })
        let values = progress.values
        try contractRequire(values.allSatisfy { (0...1).contains($0) },
                            "prepare progress left 0...1: \(values)")

        await diarizer.beginSession()
        for index in 0..<5 {
            let chunk = AudioChunk(samples: Array(repeating: 0, count: 1_600),
                                   startSample: Int64(index * 1_600), source: .system)
            await diarizer.feed(chunk)
        }
        let speaker = await diarizer.speaker(atMs: 0)
        try contractRequire(speaker != nil && !speaker!.isEmpty,
                            "diarizer returned no speaker label for fed audio")

        await diarizer.finish()
        await diarizer.finish()
    }
}
