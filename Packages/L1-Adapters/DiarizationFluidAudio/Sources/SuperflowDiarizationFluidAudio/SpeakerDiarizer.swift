import Foundation
import SuperflowKernel
import SuperflowPorts

public enum DiarizationAvailability {
    public static var isLinked: Bool {
        #if canImport(FluidAudio)
        return true
        #else
        return false
        #endif
    }

    public static var explanation: String {
        if isLinked { return "FluidAudio diarization is linked." }
        return "FluidAudio diarization is not linked. Meetings label all remote audio as Speaker 1."
    }
}

public struct DiarizationSegment: Sendable, Equatable {
    public var startMs: Int
    public var endMs: Int
    public var speakerID: String

    public init(startMs: Int, endMs: Int, speakerID: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.speakerID = speakerID
    }
}

/// Ordered, non-overlapping speaker spans. Lookup returns the span containing
/// the timestamp, otherwise the most recent span, so a turn that starts in a
/// silence gap still gets a stable label. The timeline is capped so meeting
/// length cannot grow memory without bound.
public struct DiarizationTimeline: Sendable, Equatable {
    public static let maximumSegments = 4_096
    public private(set) var segments: [DiarizationSegment]

    public init(segments: [DiarizationSegment] = []) {
        self.segments = DiarizationTimeline.merged(segments)
    }

    public mutating func append(_ segment: DiarizationSegment) {
        guard segment.endMs >= segment.startMs else { return }
        segments.append(segment)
        segments = DiarizationTimeline.merged(segments)
    }

    public func speaker(atMs ms: Int) -> String? {
        guard !segments.isEmpty else { return nil }
        var low = 0
        var high = segments.count - 1
        var candidate: DiarizationSegment?
        while low <= high {
            let middle = (low + high) / 2
            let segment = segments[middle]
            if segment.startMs <= ms {
                candidate = segment
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return candidate?.speakerID
    }

    public func ranges(for speakerID: String) -> [DiarizationSegment] {
        segments.filter { $0.speakerID == speakerID }
    }

    static func merged(_ input: [DiarizationSegment]) -> [DiarizationSegment] {
        let sorted = input.filter { $0.endMs >= $0.startMs }
            .sorted { $0.startMs == $1.startMs ? $0.endMs < $1.endMs : $0.startMs < $1.startMs }
        var output: [DiarizationSegment] = []
        for segment in sorted {
            if var last = output.last, last.speakerID == segment.speakerID,
               segment.startMs <= last.endMs + 50 {
                last.endMs = max(last.endMs, segment.endMs)
                output[output.count - 1] = last
            } else {
                output.append(segment)
            }
        }
        return Array(output.suffix(maximumSegments))
    }
}

/// Sortformer exposes four fixed speaker slots. Keeping the mapping in one
/// place makes the "four remote speakers plus You" product limit explicit and
/// guarantees ids are stable for the lifetime of a session.
public enum SortformerSpeakerLabel {
    public static let maximumSpeakers = 4

    public static func label(forSpeakerIndex index: Int) -> String {
        let clamped = min(max(index, 0), maximumSpeakers - 1)
        return "remote-\(clamped + 1)"
    }
}

/// Deterministic fallback used when diarization is unavailable. One remote
/// label is truthful; inventing speaker turns would be worse than admitting we
/// cannot separate them.
public actor SingleSpeakerDiarizer: SpeakerDiarizer {
    private let label: String
    private var firstSample: Int?

    public init(label: String = "remote-1") {
        self.label = label
    }

    public func isReady() async -> Bool { true }

    public func feed(_ chunk: AudioChunk) async {
        if firstSample == nil { firstSample = chunk.startMs }
    }

    public func speaker(atMs: Int) async -> String? {
        firstSample == nil ? nil : label
    }

    public func finish() async {}
}

#if canImport(FluidAudio)
import FluidAudio

/// Streaming Sortformer adapter. Model installation is explicit and can be
/// started from Settings; meeting capture never downloads a model.
public actor FluidAudioDiarizer: SpeakerDiarizer {
    /// `SortformerConfig.default` has no `modelVariant`, which makes FluidAudio
    /// unable to resolve a bundle. `fastV2_1` is the 4-speaker streaming model
    /// the product targets (~1 s latency).
    public static let configuration = SortformerConfig.fastV2_1
    public static let timelineConfiguration: DiarizerTimelineConfig = {
        var config = DiarizerTimelineConfig.sortformerDefault
        config.maxStoredFrames = 0
        config.storeSegments = false
        return config
    }()

    private var timeline = DiarizationTimeline()
    private var manager: SortformerDiarizer?
    private let cacheDirectory: URL?

    public init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory
    }

    public func isReady() async -> Bool { manager?.isAvailable == true }

    public func isInstalled() async -> Bool {
        if manager?.isAvailable == true { return true }
        guard let bundle = ModelNames.Sortformer.bundle(for: Self.configuration) else { return false }
        let root = cacheDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                                in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
        let repo = root.appendingPathComponent(Repo.sortformer.folderName, isDirectory: true)
        let marker = repo.appendingPathComponent(".fluidaudio-revision")
        if FileManager.default.fileExists(atPath: marker.path) {
            guard let revision = try? String(contentsOf: marker, encoding: .utf8),
                  revision.trimmingCharacters(in: .whitespacesAndNewlines) == Repo.sortformer.revision else {
                return false
            }
        } else if Repo.sortformer.revision != "main" {
            return false
        }
        let model = repo.appendingPathComponent(bundle, isDirectory: true)
        // These files belong to the pinned fastV2_1 compiled bundle. A directory
        // alone also exists during a partial download and cannot prove installation.
        return ["coremldata.bin", "model0/coremldata.bin", "model0/model.mil", "model0/weights/0-weight.bin",
                "model1/coremldata.bin", "model1/model.mil", "model1/weights/1-weight.bin"].allSatisfy {
            let path = model.appendingPathComponent($0).path
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else { return false }
            return size.int64Value > 0
        }
    }

    public func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if manager?.isAvailable == true { progress(1); return }
        progress(0)
        let config = Self.configuration
        let models = try await SortformerModels.loadFromHuggingFace(
            config: config,
            cacheDirectory: cacheDirectory,
            progressHandler: { update in progress(update.fractionCompleted) }
        )
        let diarizer = SortformerDiarizer(config: config, timelineConfig: Self.timelineConfiguration)
        diarizer.initialize(models: models)
        manager = diarizer
        progress(1)
    }

    public func beginSession() async {
        timeline = DiarizationTimeline()
        manager?.reset()
    }

    public func feed(_ chunk: AudioChunk) async {
        guard let manager, chunk.source == .system else { return }
        do {
            guard let update = try manager.process(samples: chunk.samples,
                                                   sourceSampleRate: Double(sampleRate)) else { return }
            append(update.finalizedSegments)
        } catch {
            // Meetings continue with the stable single-speaker fallback.
        }
    }

    public func speaker(atMs: Int) async -> String? {
        timeline.speaker(atMs: atMs)
    }

    public func finish() async {
        guard let manager else { return }
        if let update = try? manager.finalizeSession() { append(update.finalizedSegments) }
    }

    private func append(_ segments: [DiarizerSegment]) {
        for segment in segments {
            timeline.append(DiarizationSegment(
                startMs: Int((segment.startTime * 1_000).rounded()),
                endMs: Int((segment.endTime * 1_000).rounded()),
                speakerID: SortformerSpeakerLabel.label(forSpeakerIndex: segment.speakerIndex)
            ))
        }
    }
}
#endif
