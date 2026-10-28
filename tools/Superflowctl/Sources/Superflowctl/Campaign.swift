import AVFoundation
import Darwin
import Foundation
import SuperflowASRFluidAudio
import SuperflowGrammarHarper
import SuperflowKernel
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import SuperflowPorts
import SuperflowTextCleanup
import SuperflowTextPipeline

/// One streaming ASR run plus the cleanup comparison for the same transcript.
///
/// Usage:
///   superflowctl campaign <audio> <profile> <model-cache-root> <pace|inf> <output.json>
///
/// Environment:
///   SUPERFLOW_COMPUTE_UNITS=cpu|gpu|ane|all   (default: gpu, matching the product)
///   SUPERFLOW_MODEL_DIR=<tier directory>     (optional tier override)
///   SUPERFLOW_CLEANUP=off|deterministic|full (default: full)
///   SUPERFLOW_CLEANUP_MODEL=<gguf path>      (default: .models/s1-mini/s1-mini-q4_k_m.gguf)
struct Campaign {
    struct StageTimingRecord: Codable {
        let id: String
        let ms: Int
    }

    struct Result: Codable {
        let run_id: String
        let profile_id: String
        let model: String
        let backend: String
        let compute_units_env: String
        let tier_ms: Int?
        let streaming: Bool
        let pace: String
        let audio_file: String
        let audio_duration_s: Double
        let wall_clock_s: Double
        let rtf: Double
        let rtfx: Double
        let ttfp_ms: Int?
        let input_finished_ms: Int
        let load_ms: Int
        let peak_rss_mb: Double
        let peak_footprint_mb: Double
        let rss_growth_mb: Double
        let chunks_emitted: Int
        let segments_committed: Int
        let audio_chunks_fed: Int
        let raw_words: Int
        let failures: [String]
        let thermal_start: String
        let thermal_end: String
        let cleanup_mode: String
        let cleanup_model_load_ms: Int?
        let deterministic_wall_ms: Int?
        let full_wall_ms: Int?
        let full_cleanup_state: String?
        let deterministic_stages: [StageTimingRecord]
        let full_stages: [StageTimingRecord]
        let raw_transcript: String
        let deterministic_transcript: String
        let full_transcript: String
        let cleanup_error: String?
    }

    private let audioURL: URL
    private let profileID: String
    private let modelCacheRoot: URL
    private let outputURL: URL
    private let pace: Double
    private let cleanupMode: String
    private let cleanupModelURL: URL

    init(arguments: ArraySlice<String>) throws {
        let values = Array(arguments)
        guard values.count == 5, let pace = Double(values[3]), pace > 0 else {
            throw CampaignError.usage
        }
        audioURL = URL(fileURLWithPath: values[0]).standardizedFileURL
        profileID = values[1]
        modelCacheRoot = URL(fileURLWithPath: values[2], isDirectory: true).standardizedFileURL
        self.pace = pace
        outputURL = URL(fileURLWithPath: values[4]).standardizedFileURL
        let env = ProcessInfo.processInfo.environment
        cleanupMode = (env["SUPERFLOW_CLEANUP"] ?? "full").lowercased()
        let modelPath = env["SUPERFLOW_CLEANUP_MODEL"]
            ?? FileManager.default.currentDirectoryPath + "/.models/s1-mini/s1-mini-q4_k_m.gguf"
        cleanupModelURL = URL(fileURLWithPath: modelPath).standardizedFileURL
    }

    func run() async throws {
        let startedAt = Date()
        let runID = Self.timestamp(startedAt)
        let computeUnits = ProcessInfo.processInfo.environment["SUPERFLOW_COMPUTE_UNITS"]?
            .lowercased() ?? "gpu"
        let tier = Self.tierMilliseconds(profileID: profileID, cacheRoot: modelCacheRoot)

        let recognizer = FluidAudioRecognizer(modelCacheRoot: modelCacheRoot)
        let baselineRSS = Self.currentRSS()
        let loadClock = ContinuousClock()
        let loadStart = loadClock.now
        try await recognizer.warmUp(profile: profileID)
        let loadMs = Self.milliseconds(loadClock.now - loadStart)

        var reader = try AudioFileChunkReader(url: audioURL)
        let audioDuration = try Self.duration(of: audioURL)
        let stream = try await recognizer.makeStream(profile: profileID, source: .mic)

        let collector = CampaignEventCollector(start: .now)
        let eventTask = Task {
            for await event in stream.events {
                switch event {
                case .partial:
                    await collector.recordPartial()
                case .committed(let segment):
                    await collector.recordCommit(segment.text)
                case .failure(let message):
                    await collector.recordFailure(message)
                case .endpoint:
                    break
                }
            }
        }

        let monitor = PeakMonitor(initial: baselineRSS)
        let monitorTask = Task {
            while !Task.isCancelled {
                await monitor.sample(Self.currentRSS(), Self.currentFootprint())
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        let clock = ContinuousClock()
        let start = clock.now
        var chunksFed = 0
        var activeStage = "audio read"
        do {
            while true {
                activeStage = "audio read"
                guard let chunk = try reader.next() else { break }
                activeStage = "stream feed"
                await stream.feed(chunk)
                chunksFed += 1
                if pace != .infinity {
                    let nanos = UInt64(Double(chunk.samples.count) / Double(sampleRate) / pace * 1_000_000_000)
                    activeStage = "replay pacing"
                    try await Task.sleep(for: .nanoseconds(nanos))
                }
            }
            await collector.recordInputFinished()
            activeStage = "stream finish"
            await stream.finish()
            await eventTask.value
        } catch {
            await stream.finish()
            monitorTask.cancel()
            throw CampaignError.stageFailed(activeStage, error.localizedDescription)
        }

        let wall = Self.seconds(clock.now - start)
        let snapshot = await collector.snapshot()
        monitorTask.cancel()
        await monitorTask.value
        let peaks = await monitor.snapshot()
        let thermalEnd = Self.thermalState()

        let raw = snapshot.segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        var deterministicText = ""
        var deterministicWall: Int?
        var deterministicStages: [StageTimingRecord] = []
        var fullText = ""
        var fullWall: Int?
        var fullStages: [StageTimingRecord] = []
        var fullState: String?
        var cleanupLoadMs: Int?
        var cleanupError: String?

        if cleanupMode != "off" {
            var settings = AppSettings.default
            settings.commandsEnabled = true
            settings.codeAware.enabled = true
            settings.cleanupContext = "coding"
            settings.cleanupWorkers = 1
            settings.backgroundDeadlineMs = 30_000
            let deterministic = TextPipelineBuilder.make(settings: Self.deterministicSettings(settings))
            let detClock = ContinuousClock()
            let detStart = detClock.now
            let detResult = await deterministic.run(
                raw, context: TextContext(source: .mic, interactive: false, settings: settings))
            deterministicWall = Self.milliseconds(detClock.now - detStart)
            deterministicText = detResult.text
            deterministicStages = detResult.timings.map { .init(id: $0.id, ms: $0.ms) }

            if cleanupMode == "full" {
                do {
                    LlamaLogging.silence()
                    let cleaner = LlamaCleaner(
                        modelProvider: StaticModelProvider(url: cleanupModelURL),
                        runtime: LlamaCppRuntime())
                    let prepareClock = ContinuousClock()
                    let prepareStart = prepareClock.now
                    try await cleaner.prepare()
                    cleanupLoadMs = Self.milliseconds(prepareClock.now - prepareStart)

                    let service = CleanupService(
                        cleaner: cleaner,
                        config: CleanupConfig(backgroundDeadlineMs: 30_000, workers: 1,
                                              maxNewTokens: 1_024))
                    let linter: any HarperLinting = HarperAvailability.isCompiledIn
                        ? HarperFFILinter()
                        : UnavailableHarperLinter()
                    let grammar = HarperChecker(linter: linter)
                    settings.harperEnabled = HarperAvailability.isCompiledIn
                    let full = TextPipelineBuilder.make(
                        settings: settings,
                        dependencies: TextPipelineDependencies(
                            cleaner: service, grammarChecker: grammar,
                            grammarPolicy: .loadBundled(), project: nil))
                    let fullClock = ContinuousClock()
                    let fullStart = fullClock.now
                    let fullResult = await full.run(
                        raw, context: TextContext(source: .mic, interactive: false, settings: settings))
                    fullWall = Self.milliseconds(fullClock.now - fullStart)
                    fullText = fullResult.text
                    fullState = fullResult.draft.cleanupState.rawValue
                    fullStages = fullResult.timings.map { .init(id: $0.id, ms: $0.ms) }
                } catch {
                    cleanupError = error.localizedDescription
                }
            }
        }

        let result = Result(
            run_id: runID,
            profile_id: profileID,
            model: "nvidia/nemotron-3.5-asr-streaming-0.6b",
            backend: computeUnits,
            compute_units_env: computeUnits,
            tier_ms: tier,
            streaming: true,
            pace: pace == .infinity ? "unpaced" : String(format: "%.2f", pace),
            audio_file: audioURL.lastPathComponent,
            audio_duration_s: audioDuration,
            wall_clock_s: wall,
            rtf: audioDuration > 0 ? wall / audioDuration : 0,
            rtfx: wall > 0 ? audioDuration / wall : 0,
            ttfp_ms: snapshot.firstPartialMs,
            input_finished_ms: snapshot.inputFinishedMs,
            load_ms: loadMs,
            peak_rss_mb: Double(peaks.rss) / 1_048_576,
            peak_footprint_mb: Double(peaks.footprint) / 1_048_576,
            rss_growth_mb: (Double(peaks.rss) - Double(baselineRSS)) / 1_048_576,
            chunks_emitted: snapshot.partials,
            segments_committed: snapshot.segments.count,
            audio_chunks_fed: chunksFed,
            raw_words: raw.split(whereSeparator: \.isWhitespace).count,
            failures: snapshot.failures,
            thermal_start: Self.thermalState(),
            thermal_end: thermalEnd,
            cleanup_mode: cleanupMode,
            cleanup_model_load_ms: cleanupLoadMs,
            deterministic_wall_ms: deterministicWall,
            full_wall_ms: fullWall,
            full_cleanup_state: fullState,
            deterministic_stages: deterministicStages,
            full_stages: fullStages,
            raw_transcript: raw,
            deterministic_transcript: deterministicText,
            full_transcript: fullText,
            cleanup_error: cleanupError)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(result).write(to: outputURL, options: .atomic)

        let summary = String(format:
            "%@ %@ tier=%@ audio=%.1fs wall=%.1fs RTFx=%.2f RTF=%.3f ttfp=%@ peak=%.0fMB segments=%d partials=%d",
            result.backend, audioURL.lastPathComponent, tier.map(String.init) ?? "?",
            audioDuration, wall, result.rtfx, result.rtf,
            result.ttfp_ms.map { "\($0)ms" } ?? "none",
            result.peak_footprint_mb, result.segments_committed, result.chunks_emitted)
        FileHandle.standardOutput.write(Data((summary + "\n").utf8))
    }

    private static func deterministicSettings(_ base: AppSettings) -> AppSettings {
        var settings = base
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        return settings
    }

    private static func tierMilliseconds(profileID: String, cacheRoot: URL) -> Int? {
        guard let profile = FluidAudioCatalog.profile(for: profileID) else { return nil }
        let dir = ProcessInfo.processInfo.environment["SUPERFLOW_MODEL_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: cacheRoot)
        if let raw = dir.lastPathComponent.split(separator: "m").first, let value = Int(raw) {
            return value
        }
        let metadata = dir.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadata),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let frames = object["chunk_mel_frames"] as? Int else { return nil }
        return frames * 10
    }

    private static func duration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int((seconds(duration) * 1000).rounded())
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func currentRSS() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private static func currentFootprint() -> UInt64 {
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

private actor CampaignEventCollector {
    struct Snapshot {
        let partials: Int
        let firstPartialMs: Int?
        let inputFinishedMs: Int
        let segments: [String]
        let failures: [String]
    }

    private let start: ContinuousClock.Instant
    private var partials = 0
    private var firstPartialMs: Int?
    private var inputFinishedMs = 0
    private var segments: [String] = []
    private var failures: [String] = []

    init(start: ContinuousClock.Instant) { self.start = start }

    func recordPartial() {
        partials += 1
        if firstPartialMs == nil {
            firstPartialMs = elapsedMs()
        }
    }

    func recordCommit(_ text: String) { segments.append(text) }
    func recordFailure(_ message: String) { failures.append(message) }
    func recordInputFinished() { inputFinishedMs = elapsedMs() }

    func snapshot() -> Snapshot {
        Snapshot(partials: partials, firstPartialMs: firstPartialMs,
                 inputFinishedMs: inputFinishedMs, segments: segments, failures: failures)
    }

    private func elapsedMs() -> Int {
        let duration = start.duration(to: .now)
        return Int((Double(duration.components.seconds)
                    + Double(duration.components.attoseconds) * 1e-18) * 1000)
    }
}

private actor PeakMonitor {
    struct Peaks { let rss: UInt64; let footprint: UInt64 }
    private var peakRSS: UInt64
    private var peakFootprint: UInt64

    init(initial: UInt64) {
        peakRSS = initial
        peakFootprint = initial
    }

    func sample(_ rss: UInt64, _ footprint: UInt64) {
        peakRSS = max(peakRSS, rss)
        peakFootprint = max(peakFootprint, footprint)
    }

    func snapshot() -> Peaks { Peaks(rss: peakRSS, footprint: peakFootprint) }
}

/// Minimal `ModelProvider` that only serves the local S1-mini GGUF. It never
/// downloads; a missing file fails loudly.
private struct StaticModelProvider: ModelProvider {
    let url: URL

    func localURL(for profileID: String) async -> URL? { nil }
    func ensure(profileID: String,
                progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        throw SuperflowError.modelUnavailable("StaticModelProvider does not download ASR models")
    }
    func llmModelURL() async -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SuperflowError.modelUnavailable("Cleanup model not found at \(url.path)")
        }
        return url
    }
}

private enum CampaignError: Error, LocalizedError {
    case usage
    case stageFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "usage: superflowctl campaign <audio> <profile> <cache-root> <pace|inf> <output.json>"
        case .stageFailed(let stage, let detail):
            "campaign failed during \(stage): \(detail)"
        }
    }
}
