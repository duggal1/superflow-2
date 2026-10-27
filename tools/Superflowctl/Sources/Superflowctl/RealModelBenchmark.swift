import Darwin
import Foundation
import SuperflowASRFluidAudio
import SuperflowAudioJournal
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

struct RealModelBenchmark {
    struct Result: Codable {
        let profileID: String
        let input: String
        let inputSamples: Int64
        let journalSamples: Int64
        let journalDegraded: Bool
        let committedRows: Int
        let partialEvents: Int
        let firstPartialMs: Int?
        let inputFinishedMs: Int
        let elapsedMs: Int
        let realTimeFactor: Double
        let baselineRSSBytes: UInt64
        let peakRSSBytes: UInt64
        let rssGrowthBytes: Int64
        let userCPUSeconds: Double
        let systemCPUSeconds: Double
        let outputWords: Int
        let failureEvents: [String]
        let chunksResolved: Bool
    }

    private let profileID: String
    private let inputURL: URL
    private let modelCacheRoot: URL
    private let journalRoot: URL
    private let reportURL: URL?
    private let pace: Double

    init(arguments: ArraySlice<String>) throws {
        let values = Array(arguments)
        guard values.count == 4 || values.count == 5,
              let pace = Double(values[3]), pace > 0 else {
            throw BenchmarkError.invalidArguments
        }
        inputURL = URL(fileURLWithPath: values[0]).standardizedFileURL
        profileID = values[1]
        modelCacheRoot = URL(fileURLWithPath: values[2], isDirectory: true).standardizedFileURL
        self.pace = pace
        journalRoot = URL(fileURLWithPath: values.count == 5 ? values[4] : ".models/benchmark-journals",
                          isDirectory: true).standardizedFileURL
        reportURL = ProcessInfo.processInfo.environment["SUPERFLOW_BENCHMARK_REPORT"]
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    func run() async throws {
        let recognizer = FluidAudioRecognizer(modelCacheRoot: modelCacheRoot)
        try await recognizer.warmUp(profile: profileID)
        let baselineRSS = Self.currentRSS()
        let rssMonitor = RSSPeak(initial: baselineRSS)
        let rssTask = Task {
            while !Task.isCancelled {
                await rssMonitor.sample(Self.currentRSS())
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let cpuStart = Self.cpuUsage()
        let clock = ContinuousClock()
        let start = clock.now
        var reader = try AudioFileChunkReader(url: inputURL)
        let journal = FileJournalStore(root: journalRoot)
        let session = SessionID()
        let writer = try await journal.openWriter(session: session, source: .mic)
        let stream = try await recognizer.makeStream(profile: profileID, source: .mic)
        let measurements = BenchmarkEventCollector(start: start)
        let pipeline = makePipeline()
        let eventTask = Task {
            for await event in stream.events {
                switch event {
                case .partial:
                    await measurements.recordPartial()
                case .committed(let segment):
                    let result = await pipeline.run(segment.text,
                                                    context: TextContext(source: segment.source,
                                                                         interactive: false))
                    await measurements.recordCommit(result.text)
                case .failure(let message):
                    await measurements.recordFailure(message)
                case .endpoint:
                    break
                }
            }
        }

        var inputSamples: Int64 = 0
        var activeStage = "audio file read"
        do {
            while true {
                activeStage = "audio file read"
                guard let chunk = try reader.next() else { break }
                activeStage = "journal append"
                await writer.append(chunk)
                activeStage = "streaming recognizer feed"
                await stream.feed(chunk)
                inputSamples += Int64(chunk.samples.count)
                if pace != .infinity {
                    let nanos = UInt64(Double(chunk.samples.count) / Double(sampleRate) / pace * 1_000_000_000)
                    activeStage = "replay pacing"
                    try await Task.sleep(for: .nanoseconds(nanos))
                }
            }
            await measurements.recordInputFinished()
            await stream.finish()
            await eventTask.value
        } catch {
            await stream.finish()
            _ = await writer.close()
            await journal.delete(session: session)
            let underlying = error as NSError
            throw BenchmarkError.stageFailed(activeStage, "\(underlying.domain) \(underlying.code): \(error.localizedDescription)")
        }

        let elapsed = start.duration(to: clock.now)
        let elapsedMs = Int(elapsed.components.seconds * 1000
                            + elapsed.components.attoseconds / 1_000_000_000_000_000)
        let journalSummary = await writer.close()
        let journalSamples = await journal.sampleCount(session: session, source: .mic)
        let snapshot = await measurements.snapshot()
        rssTask.cancel()
        await rssTask.value
        let peakRSS = await rssMonitor.peak
        let cpuEnd = Self.cpuUsage()
        let result = Result(
            profileID: profileID,
            input: inputURL.lastPathComponent,
            inputSamples: inputSamples,
            journalSamples: journalSamples,
            journalDegraded: journalSummary.degraded,
            committedRows: snapshot.commits,
            partialEvents: snapshot.partials,
            firstPartialMs: snapshot.firstPartialMs,
            inputFinishedMs: snapshot.inputFinishedMs,
            elapsedMs: elapsedMs,
            realTimeFactor: elapsedMs == 0 ? 0 : Double(inputSamples) / Double(sampleRate) / (Double(elapsedMs) / 1000),
            baselineRSSBytes: baselineRSS,
            peakRSSBytes: peakRSS,
            rssGrowthBytes: Int64(peakRSS) - Int64(baselineRSS),
            userCPUSeconds: cpuEnd.user - cpuStart.user,
            systemCPUSeconds: cpuEnd.system - cpuStart.system,
            outputWords: snapshot.outputWords,
            failureEvents: snapshot.failures,
            chunksResolved: snapshot.commits > 0 && snapshot.failures.isEmpty)
        let data = try JSONEncoder.output.encode(result)
        if let reportURL {
            try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: reportURL, options: .atomic)
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        await journal.delete(session: session)
        guard result.inputSamples == result.journalSamples,
              !result.journalDegraded,
              result.chunksResolved else {
            throw BenchmarkError.assertionFailed("journal or transcript assertion failed")
        }
        if pace == 1 {
            guard let firstPartialMs = result.firstPartialMs,
                  firstPartialMs < result.inputFinishedMs else {
                throw BenchmarkError.assertionFailed("no streaming partial arrived while audio was still playing")
            }
        }
    }

    private func makePipeline() -> TextPipeline {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        return TextPipelineBuilder.make(settings: settings)
    }

    private static func currentRSS() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private static func cpuUsage() -> (user: Double, system: Double) {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return (seconds(usage.ru_utime), seconds(usage.ru_stime))
    }

    private static func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }
}

private actor BenchmarkEventCollector {
    struct Snapshot {
        let commits: Int
        let partials: Int
        let firstPartialMs: Int?
        let inputFinishedMs: Int
        let outputWords: Int
        let failures: [String]
    }

    private let start: ContinuousClock.Instant
    private var commits = 0
    private var partials = 0
    private var firstPartialMs: Int?
    private var inputFinishedMs = 0
    private var outputWords = 0
    private var failures: [String] = []

    init(start: ContinuousClock.Instant) { self.start = start }

    func recordPartial() {
        partials += 1
        if firstPartialMs == nil {
            let duration = start.duration(to: .now)
            firstPartialMs = Int(duration.components.seconds * 1000
                                 + duration.components.attoseconds / 1_000_000_000_000_000)
        }
    }

    func recordCommit(_ text: String) {
        commits += 1
        outputWords += text.split(whereSeparator: \.isWhitespace).count
    }

    func recordFailure(_ message: String) { failures.append(message) }

    func recordInputFinished() {
        let duration = start.duration(to: .now)
        inputFinishedMs = Int(duration.components.seconds * 1000
                              + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    func snapshot() -> Snapshot {
        Snapshot(commits: commits, partials: partials, firstPartialMs: firstPartialMs,
                 inputFinishedMs: inputFinishedMs,
                 outputWords: outputWords, failures: failures)
    }
}

private actor RSSPeak {
    private(set) var peak: UInt64

    init(initial: UInt64) { peak = initial }

    func sample(_ value: UInt64) { peak = max(peak, value) }
}

private enum BenchmarkError: Error, LocalizedError {
    case invalidArguments
    case stageFailed(String, String)
    case assertionFailed(String)
    var errorDescription: String? {
        switch self {
        case .invalidArguments: "Invalid benchmark arguments."
        case .stageFailed(let stage, let detail): "Benchmark failed during \(stage): \(detail)"
        case .assertionFailed(let message): message
        }
    }
}

private extension JSONEncoder {
    static var output: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
