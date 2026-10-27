import Darwin
import Foundation
import SuperflowASRFluidAudio
import SuperflowKernel
import SuperflowPorts

/// Small-clip, release-only ASR speed bench. No journal, no text pipeline: it measures the
/// recognizer itself so a slow number cannot hide behind another stage.
///
/// Usage: superflowctl bench <audio> <profile> <model-cache-root> [repeats] [chunk-ms]
struct RealModelSpeedBench {
    private let inputURL: URL
    private let profileID: String
    private let modelCacheRoot: URL
    private let repeats: Int
    private let chunkMS: Int

    init(arguments: ArraySlice<String>) throws {
        let values = Array(arguments)
        guard values.count >= 3 else { throw BenchError.usage }
        inputURL = URL(fileURLWithPath: values[0]).standardizedFileURL
        profileID = values[1]
        modelCacheRoot = URL(fileURLWithPath: values[2], isDirectory: true).standardizedFileURL
        repeats = values.count > 3 ? (Int(values[3]) ?? 5) : 5
        chunkMS = values.count > 4 ? (Int(values[4]) ?? 1_120) : 1_120
        guard repeats > 0, chunkMS > 0 else { throw BenchError.usage }
    }

    func run() async throws {
        #if DEBUG
        throw BenchError.debugBuild
        #endif

        let audio = try Self.loadSamples(from: inputURL)
        let audioSeconds = Double(audio.count) / Double(sampleRate)
        let chunkSamples = sampleRate * chunkMS / 1_000

        let recognizer = FluidAudioRecognizer(modelCacheRoot: modelCacheRoot)
        let loadClock = ContinuousClock()
        let loadStart = loadClock.now
        try await recognizer.warmUp(profile: profileID)
        let loadSeconds = Self.seconds(loadClock.now - loadStart)

        // Two discarded passes: page in weights and let Core ML finish lazy specialization.
        for _ in 0..<2 { _ = try await runOnce(recognizer: recognizer, audio: audio, chunkSamples: chunkSamples) }

        let baseline = Self.footprintBytes()
        var walls: [Double] = []
        var finishes: [Double] = []
        var chunkLatencies: [Double] = []
        var lastWords = 0

        for index in 1...repeats {
            let run = try await runOnce(recognizer: recognizer, audio: audio, chunkSamples: chunkSamples)
            walls.append(run.wall)
            finishes.append(run.finish)
            chunkLatencies.append(contentsOf: run.chunkLatencies)
            lastWords = run.words
            print(String(format: "run %d: wall %.3fs  RTFx %.1f  stop->text %.0fms  words %d",
                         index, run.wall, audioSeconds / run.wall, run.finish * 1000, run.words))
        }

        let peak = Self.footprintBytes()
        let median = Self.percentile(walls, 0.5)
        print(String(format: """

        audio %.1fs  profile %@  chunk %dms
        load+warm %.2fs
        RTFx median %.1fx  (min %.1fx, max %.1fx)
        chunk latency p50 %.1fms  p95 %.1fms
        stop->text p50 %.0fms  p95 %.0fms
        footprint after warm-up %.0fMB  growth %+.0fMB  peak %.0fMB
        words %d
        """,
        audioSeconds, profileID, chunkMS, loadSeconds,
        audioSeconds / median, audioSeconds / (walls.max() ?? median), audioSeconds / (walls.min() ?? median),
        Self.percentile(chunkLatencies, 0.5) * 1000, Self.percentile(chunkLatencies, 0.95) * 1000,
        Self.percentile(finishes, 0.5) * 1000, Self.percentile(finishes, 0.95) * 1000,
        // Signed: the footprint can legitimately shrink between the baseline and the peak
        // (mapped pages released, compressor reclaiming idle weights), and a UInt64
        // subtraction traps in that case.
        Double(baseline) / 1_048_576, (Double(peak) - Double(baseline)) / 1_048_576, Double(peak) / 1_048_576,
        lastWords))
    }

    private struct Run {
        let wall: Double
        let finish: Double
        let chunkLatencies: [Double]
        let words: Int
    }

    private func runOnce(recognizer: FluidAudioRecognizer, audio: [Float],
                         chunkSamples: Int) async throws -> Run {
        let stream = try await recognizer.makeStream(profile: profileID, source: .mic)
        let counter = WordCounter()
        let consumer = Task {
            for await event in stream.events {
                if case .committed(let segment) = event { await counter.add(segment.text) }
            }
        }
        let clock = ContinuousClock()
        let start = clock.now
        var latencies: [Double] = []
        var offset = 0
        while offset < audio.count {
            let end = min(offset + chunkSamples, audio.count)
            let chunk = AudioChunk(samples: Array(audio[offset..<end]),
                                   startSample: Int64(offset), source: .mic)
            let chunkStart = clock.now
            await stream.feed(chunk)
            latencies.append(Self.seconds(clock.now - chunkStart))
            offset = end
        }
        let wall = Self.seconds(clock.now - start)
        let finishStart = clock.now
        await stream.finish()
        await consumer.value
        let finish = Self.seconds(clock.now - finishStart)
        return Run(wall: wall, finish: finish, chunkLatencies: latencies,
                   words: await counter.words)
    }

    private static func loadSamples(from url: URL) throws -> [Float] {
        var reader = try AudioFileChunkReader(url: url)
        var samples: [Float] = []
        while let chunk = try reader.next() { samples.append(contentsOf: chunk.samples) }
        return samples
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
    }

    /// phys_footprint, not RSS: RSS undercounts until pages fault in, which is what produced the
    /// bogus "1 GB growth" when the baseline was taken before the weights were resident.
    private static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

private actor WordCounter {
    private(set) var words = 0
    func add(_ text: String) { words += text.split(whereSeparator: \.isWhitespace).count }
}

private enum BenchError: Error, LocalizedError {
    case usage
    case debugBuild
    var errorDescription: String? {
        switch self {
        case .usage: "usage: superflowctl bench <audio> <profile> <model-cache-root> [repeats] [chunk-ms]"
        case .debugBuild: "Refusing to benchmark a Debug build; use swift build -c release."
        }
    }
}
