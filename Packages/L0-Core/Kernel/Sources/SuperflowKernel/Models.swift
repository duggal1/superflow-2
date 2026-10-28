import Foundation

public let sampleRate = 16_000

public struct SessionID: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let value: String
    public init(_ value: String = UUID().uuidString) { self.value = value }
    public init(stringLiteral value: String) { self.init(value) }
    public var description: String { value }
    public var short: String { String(value.prefix(8)) }
}

public enum SessionKind: String, Sendable, Codable, CaseIterable {
    case dictation, meeting
    public var label: String { self == .dictation ? "Dictation" : "Meeting" }
}

public enum SessionStatus: String, Sendable, Codable, CaseIterable {
    case recording, finalizing, complete, cancelled, failed, recovered
}

public enum AudioSourceKind: String, Sendable, Codable, CaseIterable {
    case mic, system
    public var label: String { self == .mic ? "Microphone" : "System audio" }
}

public enum CleanupState: String, Sendable, Codable, CaseIterable {
    case pending, cleaned, fallback, skipped
    public var label: String {
        switch self {
        case .pending: "Pending"
        case .cleaned: "Cleaned"
        case .fallback: "Basic cleanup"
        case .skipped: "Raw"
        }
    }
}

public struct AudioChunk: Sendable, Equatable {
    public var samples: [Float]
    public var startSample: Int64
    public var source: AudioSourceKind
    public init(samples: [Float], startSample: Int64, source: AudioSourceKind) {
        self.samples = samples
        self.startSample = startSample
        self.source = source
    }
    public var endSample: Int64 { startSample + Int64(samples.count) }
    public var startMs: Int { Int(startSample * 1000 / Int64(sampleRate)) }
    public var endMs: Int { Int(endSample * 1000 / Int64(sampleRate)) }
}

public struct WordTiming: Sendable, Codable, Hashable {
    public var word: String
    public var startMs: Int
    public var endMs: Int
    public init(word: String, startMs: Int, endMs: Int) {
        self.word = word
        self.startMs = startMs
        self.endMs = endMs
    }
}

public struct RawSegment: Sendable, Equatable {
    public var text: String
    public var startSample: Int64
    public var endSample: Int64
    public var words: [WordTiming]
    public var source: AudioSourceKind
    public var speakerHint: String?
    public init(text: String, startSample: Int64, endSample: Int64, words: [WordTiming] = [],
                source: AudioSourceKind, speakerHint: String? = nil) {
        self.text = text
        self.startSample = startSample
        self.endSample = endSample
        self.words = words
        self.source = source
        self.speakerHint = speakerHint
    }
    public var startMs: Int { Int(startSample * 1000 / Int64(sampleRate)) }
    public var endMs: Int { Int(endSample * 1000 / Int64(sampleRate)) }
}

public enum RecognitionEvent: Sendable, Equatable {
    case partial(String)
    case committed(RawSegment)
    case endpoint(Int64)
    case failure(String)
}

public struct Segment: Sendable, Codable, Hashable, Identifiable {
    public var sessionID: SessionID
    public var index: Int
    public var startMs: Int
    public var endMs: Int
    public var speakerID: String?
    public var source: AudioSourceKind
    public var rawText: String
    public var cleanedText: String?
    public var cleanupState: CleanupState
    public var createdAt: Date

    public var id: String { "\(sessionID.value)#\(index)" }
    public init(sessionID: SessionID, index: Int, startMs: Int, endMs: Int, speakerID: String? = nil,
                source: AudioSourceKind = .mic, rawText: String, cleanedText: String? = nil,
                cleanupState: CleanupState = .pending, createdAt: Date = Date()) {
        self.sessionID = sessionID
        self.index = index
        self.startMs = startMs
        self.endMs = endMs
        self.speakerID = speakerID
        self.source = source
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.cleanupState = cleanupState
        self.createdAt = createdAt
    }
    public var bestText: String { cleanedText ?? rawText }
    public var timestampLabel: String { Segment.timeLabel(startMs) }

    public static func timeLabel(_ ms: Int) -> String {
        let s = max(0, ms) / 1000
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

public struct SessionRecord: Sendable, Codable, Hashable, Identifiable {
    public var id: SessionID
    public var kind: SessionKind
    public var startedAt: Date
    public var endedAt: Date?
    public var status: SessionStatus
    public var frontmostBundleID: String?
    public var modelProfile: String
    public var durationMs: Int
    public var wordCount: Int
    public var cleanupState: CleanupState
    public var title: String?
    public var localDay: String
    /// The archived clip's length. Nil when no audio was kept.
    public var audioDuration: TimeInterval?
    /// One byte per 50 ms of precomputed waveform, so the player never decodes audio to draw.
    public var audioPeaks: Data?
    /// The first line of the transcript, read with the row. Not a stored column.
    public var preview: String?

    public init(id: SessionID = SessionID(), kind: SessionKind, startedAt: Date = Date(), endedAt: Date? = nil,
                status: SessionStatus = .recording, frontmostBundleID: String? = nil, modelProfile: String,
                durationMs: Int = 0, wordCount: Int = 0, cleanupState: CleanupState = .pending,
                title: String? = nil, localDay: String? = nil,
                audioDuration: TimeInterval? = nil, audioPeaks: Data? = nil,
                preview: String? = nil) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.frontmostBundleID = frontmostBundleID
        self.modelProfile = modelProfile
        self.durationMs = durationMs
        self.wordCount = wordCount
        self.cleanupState = cleanupState
        self.title = title
        self.localDay = localDay ?? LocalDay.string(for: startedAt)
        self.audioDuration = audioDuration
        self.audioPeaks = audioPeaks
        self.preview = preview
    }

    public var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: startedAt)
    }
    public var durationLabel: String {
        let s = durationMs / 1000
        if s >= 3600 { return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60) }
        if s >= 60 { return String(format: "%dm %02ds", s / 60, s % 60) }
        return "\(s)s"
    }
}

/// Where archived dictation audio lives. Path math only: the file itself is
/// written and read by an adapter, never by a feature.
public enum AudioArchiveLocation {
    public static func directory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Superflow/Audio", isDirectory: true)
    }

    public static func url(for session: SessionID, fileManager: FileManager = .default) -> URL {
        directory(fileManager: fileManager).appendingPathComponent("\(session.value).m4a")
    }
}

public struct SpeakerRecord: Sendable, Codable, Hashable, Identifiable {
    public var sessionID: SessionID
    public var id: String
    public var label: String
    public var isSelf: Bool
    public init(sessionID: SessionID, id: String, label: String, isSelf: Bool) {
        self.sessionID = sessionID
        self.id = id
        self.label = label
        self.isSelf = isSelf
    }
}

public struct DailyStat: Sendable, Codable, Hashable {
    public var day: String
    public var words: Int
    public var audioMs: Int
    public var sessions: Int
    public init(day: String, words: Int, audioMs: Int, sessions: Int) {
        self.day = day
        self.words = words
        self.audioMs = audioMs
        self.sessions = sessions
    }
}

public enum LexiconKind: String, Sendable, Codable, CaseIterable {
    case term, correction
    public var label: String { self == .term ? "Term" : "Correction" }
}

public enum EntrySource: String, Sendable, Codable {
    case user, bundled
}

public struct LexiconEntry: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var kind: LexiconKind
    public var triggers: [String]
    public var canonical: String
    public var enabled: Bool
    public var source: EntrySource
    public init(id: String = UUID().uuidString, kind: LexiconKind, triggers: [String], canonical: String,
                enabled: Bool = true, source: EntrySource = .user) {
        self.id = id
        self.kind = kind
        self.triggers = triggers
        self.canonical = canonical
        self.enabled = enabled
        self.source = source
    }
}

public enum ShortcutMatch: String, Sendable, Codable, CaseIterable {
    case wholeUtterance, inline
    public var label: String { self == .wholeUtterance ? "Whole utterance" : "Inline" }
}

public struct ShortcutEntry: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var trigger: String
    public var content: String
    public var match: ShortcutMatch
    public var enabled: Bool
    public init(id: String = UUID().uuidString, trigger: String, content: String,
                match: ShortcutMatch = .wholeUtterance, enabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.content = content
        self.match = match
        self.enabled = enabled
    }
}

public struct ModelProfile: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable {
        case verified, unverified, unavailable
    }

    public var id: String
    public var displayName: String
    public var vendor: String
    public var upstreamRepo: String
    public var runtimeRepo: String
    public var language: String
    public var chunkMs: Int?
    public var streaming: Bool
    public var status: Status
    public var note: String

    public init(id: String, displayName: String, vendor: String, upstreamRepo: String,
                runtimeRepo: String, language: String, chunkMs: Int?, streaming: Bool,
                status: Status, note: String = "") {
        self.id = id
        self.displayName = displayName
        self.vendor = vendor
        self.upstreamRepo = upstreamRepo
        self.runtimeRepo = runtimeRepo
        self.language = language
        self.chunkMs = chunkMs
        self.streaming = streaming
        self.status = status
        self.note = note
    }

    /// Dictation is live-only, so batch models are displayed but cannot be selected.
    public var supportsLiveDictation: Bool {
        streaming && status != .unavailable
    }

    public var formatLabel: String {
        streaming ? "Streaming" : "Batch"
    }

    public var latencyLabel: String {
        guard let chunkMs else { return "Offline" }
        return streaming ? "\(chunkMs) ms chunks" : "\(chunkMs / 1_000) s windows"
    }

    public var metadataLabel: String {
        "\(vendor) · \(language) · \(latencyLabel)"
    }

    public static let parakeetEOU120M = ModelProfile(
        id: "parakeet-eou-120m", displayName: "Parakeet Realtime EOU 120M",
        vendor: "NVIDIA",
        upstreamRepo: "nvidia/parakeet_realtime_eou_120m-v1",
        runtimeRepo: "FluidInference/parakeet-realtime-eou-120m-coreml/320ms",
        language: "English", chunkMs: 320, streaming: true, status: .verified,
        note: "Lowest-latency streaming profile, with native end-of-utterance detection.")
    public static let nemotronStreaming = ModelProfile(
        id: "nemotron-streaming-0.6b", displayName: "Nemotron Speech Streaming 0.6B",
        vendor: "NVIDIA",
        upstreamRepo: "nvidia/nemotron-speech-streaming-en-0.6b",
        runtimeRepo: "FluidInference/nemotron-speech-streaming-en-0.6b-coreml/560ms",
        language: "English", chunkMs: 560, streaming: true, status: .verified,
        note: "Cache-aware English streaming at the 560 ms Core ML tier.")
    public static let parakeetUnified = ModelProfile(
        id: "parakeet-unified-0.6b", displayName: "Parakeet Unified 0.6B",
        vendor: "NVIDIA",
        upstreamRepo: "nvidia/parakeet-unified-en-0.6b",
        runtimeRepo: "FluidInference/parakeet-unified-en-0.6b-coreml",
        language: "English", chunkMs: 640, streaming: true, status: .unverified,
        note: "Chunked-attention streaming at the 640 ms Core ML tier. The upstream checkpoint also supports offline use.")
    public static let nemotron35Streaming = ModelProfile(
        id: "nemotron-3.5-asr-streaming-0.6b", displayName: "Nemotron 3.5 ASR Streaming 0.6B",
        vendor: "NVIDIA",
        upstreamRepo: "nvidia/nemotron-3.5-asr-streaming-0.6b",
        runtimeRepo: "FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML/latin/1120ms",
        language: "40 locales", chunkMs: 1_120, streaming: true, status: .unverified,
        note: "Cache-aware multilingual streaming. The Latin Core ML build covers English and five other Latin-script languages.")
    public static let parakeetTDTV3 = ModelProfile(
        id: "parakeet-tdt-0.6b-v3", displayName: "Parakeet TDT 0.6B v3",
        vendor: "NVIDIA",
        upstreamRepo: "nvidia/parakeet-tdt-0.6b-v3",
        runtimeRepo: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        language: "English", chunkMs: 15_000, streaming: false, status: .unavailable,
        note: "Batch only. FluidAudio processes 15 s sliding windows and cannot feed live dictation with TDT.")

    public static let all: [ModelProfile] = [
        .parakeetEOU120M,
        .nemotronStreaming,
        .parakeetUnified,
        .nemotron35Streaming,
        .parakeetTDTV3,
    ]

    /// The one dictation profile the app installs, offers first and falls back to.
    public static var `default`: ModelProfile { .nemotron35Streaming }

    /// Every profile that can drive live dictation. Batch-only entries stay in
    /// `all` for the Models page but are never selectable for dictation.
    public static var streamingProfiles: [ModelProfile] {
        all.filter(\.supportsLiveDictation)
    }

    public static func byID(_ id: String) -> ModelProfile {
        all.first { $0.id == id } ?? .nemotron35Streaming
    }
}
