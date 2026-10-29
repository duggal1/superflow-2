import Foundation

public enum BreakStyle: String, Codable, Sendable, CaseIterable {
    case paragraph, newline
    public var label: String { self == .paragraph ? "Blank line" : "New line" }
}
public enum LargeNumberStyle: String, Codable, Sendable, CaseIterable {
    case abbreviated, full
    public var label: String { self == .abbreviated ? "Abbreviated ($200k)" : "Full ($200,000)" }
}
public enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case system, light, dark
    public var label: String { rawValue.capitalized }
}

/// Where the cleanup model runs. llama.cpp splits the model between Metal and
/// CPU at load time, so this decides the split for every later completion.
public enum ModelCompute: String, Codable, Sendable, CaseIterable {
    case gpu, cpu
    public var label: String { self == .gpu ? "GPU" : "CPU" }
}

public struct LineFormatSettings: Codable, Sendable, Equatable {
    public var minWords: Int = 25
    public var preferredMax: Int = 35
    public var hardMax: Int = 45
    public var breakStyle: BreakStyle = .paragraph
    public var capitalize: Bool = true
    public var collapseSpaces: Bool = true
    public var fixPunctuationSpacing: Bool = true
    public var finalPeriod: Bool = true
    public var trailingSpace: Bool = false
    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LineFormatSettings()
        minWords = try c.decodeIfPresent(Int.self, forKey: .minWords) ?? d.minWords
        preferredMax = try c.decodeIfPresent(Int.self, forKey: .preferredMax) ?? d.preferredMax
        hardMax = try c.decodeIfPresent(Int.self, forKey: .hardMax) ?? d.hardMax
        breakStyle = try c.decodeIfPresent(BreakStyle.self, forKey: .breakStyle) ?? d.breakStyle
        capitalize = try c.decodeIfPresent(Bool.self, forKey: .capitalize) ?? d.capitalize
        collapseSpaces = try c.decodeIfPresent(Bool.self, forKey: .collapseSpaces) ?? d.collapseSpaces
        fixPunctuationSpacing = try c.decodeIfPresent(Bool.self, forKey: .fixPunctuationSpacing) ?? d.fixPunctuationSpacing
        finalPeriod = try c.decodeIfPresent(Bool.self, forKey: .finalPeriod) ?? d.finalPeriod
        trailingSpace = try c.decodeIfPresent(Bool.self, forKey: .trailingSpace) ?? d.trailingSpace
    }
}

/// Deterministic disfluency cleanup that runs before any model sees the text.
///
/// Duplicate collapse is tiered on purpose. "the the" is almost always a false
/// start, but "had had", "that that", "what it is is" and "bye bye" are real
/// grammar. Tier A words collapse at two; Tier B words need three; everything
/// else is left for the cleanup model, which can read the sentence.
public struct DisfluencySettings: Codable, Sendable, Equatable {
    public var enabled: Bool = true
    public var collapseDuplicates: Bool = true
    /// Tier A words (articles, pronouns, short prepositions) collapse at two.
    public var tierAThreshold: Int = 2
    /// Tier B words (had, that, is, very, ...) collapse only at three.
    public var tierBThreshold: Int = 3
    /// Backwards-compatible name for `tierBThreshold`. The old single threshold
    /// could not express the tier rules, so values below three are raised.
    public var duplicateThreshold: Int {
        get { tierBThreshold }
        set { tierBThreshold = max(3, newValue) }
    }
    /// Collapse adjacent repeated 2-3 word phrases ("we need to we need to go").
    public var collapseRepeatedPhrases: Bool = true
    /// Removes only the pure fillers. "like", "you know", "I mean" and "so"
    /// stay for the model, which can tell content from hesitation.
    public var fillerPrepass: Bool = true
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DisfluencySettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        collapseDuplicates = try c.decodeIfPresent(Bool.self, forKey: .collapseDuplicates)
            ?? d.collapseDuplicates
        tierAThreshold = max(2, try c.decodeIfPresent(Int.self, forKey: .tierAThreshold)
            ?? d.tierAThreshold)
        let legacy = try c.decodeIfPresent(Int.self, forKey: .duplicateThreshold)
        tierBThreshold = max(3, try c.decodeIfPresent(Int.self, forKey: .tierBThreshold)
            ?? legacy ?? d.tierBThreshold)
        collapseRepeatedPhrases = try c.decodeIfPresent(Bool.self, forKey: .collapseRepeatedPhrases)
            ?? d.collapseRepeatedPhrases
        fillerPrepass = try c.decodeIfPresent(Bool.self, forKey: .fillerPrepass) ?? d.fillerPrepass
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(collapseDuplicates, forKey: .collapseDuplicates)
        try c.encode(tierAThreshold, forKey: .tierAThreshold)
        try c.encode(tierBThreshold, forKey: .tierBThreshold)
        try c.encode(collapseRepeatedPhrases, forKey: .collapseRepeatedPhrases)
        try c.encode(fillerPrepass, forKey: .fillerPrepass)
        // Old readers only understand this key.
        try c.encode(tierBThreshold, forKey: .duplicateThreshold)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, collapseDuplicates, duplicateThreshold
        case tierAThreshold, tierBThreshold, collapseRepeatedPhrases, fillerPrepass
    }
}

/// Deterministic spoken-code cleanup: filenames, extensions and bounded,
/// project-relative path resolution.
public struct CodeAwareSettings: Codable, Sendable, Equatable {
    public var enabled: Bool = true
    public var normalizeFilenames: Bool = true
    public var resolvePaths: Bool = true
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CodeAwareSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        normalizeFilenames = try c.decodeIfPresent(Bool.self, forKey: .normalizeFilenames)
            ?? d.normalizeFilenames
        resolvePaths = try c.decodeIfPresent(Bool.self, forKey: .resolvePaths) ?? d.resolvePaths
    }
}

/// The physical key that starts a dictation. Only modifiers are offered: a letter
/// key cannot be held down without also typing, so it can never be a push-to-talk
/// key. Right ⌘ is not on the list because it starts meetings.
public enum DictationKey: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case fn
    case rightOption
    case rightShift
    case rightControl
    case leftOption

    public var id: String { rawValue }

    /// The hardware key code of the modifier. Left and right share a flag, so the
    /// onboarding monitor has to match the exact key, not just the flag.
    public var keyCode: UInt16 {
        switch self {
        case .fn: 0x3F
        case .rightShift: 0x3C
        case .rightOption: 0x3D
        case .rightControl: 0x3E
        case .leftOption: 0x3A
        }
    }

    /// The glyph printed on the keycap.
    public var cap: String {
        switch self {
        case .fn: "fn"
        case .rightOption, .leftOption: "⌥"
        case .rightShift: "⇧"
        case .rightControl: "⌃"
        }
    }

    /// How it reads inside a sentence: "Hold right ⌥ anywhere to dictate."
    public var label: String {
        switch self {
        case .fn: "fn"
        case .rightOption: "right ⌥"
        case .rightShift: "right ⇧"
        case .rightControl: "right ⌃"
        case .leftOption: "left ⌥"
        }
    }

    /// The caption under the cap in the picker.
    public var caption: String {
        switch self {
        case .fn: "Globe key"
        case .rightOption: "Right option"
        case .rightShift: "Right shift"
        case .rightControl: "Right control"
        case .leftOption: "Left option"
        }
    }
}

public struct GestureConfig: Codable, Sendable, Equatable {
    public var holdMs: Int = 200
    public var doubleTapMs: Int = 350
    public var meetingHoldMs: Int = 600
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureConfig()
        holdMs = try c.decodeIfPresent(Int.self, forKey: .holdMs) ?? d.holdMs
        doubleTapMs = try c.decodeIfPresent(Int.self, forKey: .doubleTapMs) ?? d.doubleTapMs
        meetingHoldMs = try c.decodeIfPresent(Int.self, forKey: .meetingHoldMs) ?? d.meetingHoldMs
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var theme: ThemeMode = .system
    /// Nemotron 3.5 ASR Streaming 0.6B is the model the app installs and runs. It is
    /// the default in one place only, so onboarding and the Models page cannot drift.
    public var asrProfile: String = ModelProfile.default.id
    public var speechEnhancementEnabled = true
    public var cleanupEnabled = true
    public var harperEnabled = false
    public var commandsEnabled = true
    public var codeSpeakEnabled = false
    public var disfluency = DisfluencySettings()
    public var codeAware = CodeAwareSettings()
    public var numberStyle: LargeNumberStyle = .abbreviated
    public var spellOutSmallNumbers = true
    public var lineFormat = LineFormatSettings()
    public var gesture = GestureConfig()
    /// The key that starts a dictation. Onboarding and Settings write it, and the
    /// hotkey adapter maps it onto the same down/up pair the gesture engine already
    /// understands, so hold, double-tap and hands-free behave identically.
    public var dictationKey: DictationKey = .fn
    public var typingWPM = 40
    public var displayName = "You"
    public var launchAtLogin = false
    public var retentionDays: Int? = nil
    public var noTranscriptStorage = false
    /// Archived dictation audio. On by default: you cannot check what the model
    /// heard if the clip is thrown away. "Don't store transcripts" wins over this.
    public var keepAudio = true
    /// Nil keeps clips forever. Default is one week.
    public var audioRetentionDays: Int? = 7
    public var keepJournals = false
    public var cleanupStyling = "semi-formal"
    public var cleanupStructure = "prose"
    public var cleanupContext = "general"
    public var interactiveDeadlineMs = 1500
    public var backgroundDeadlineMs = 30_000
    public var cleanupWorkers = 3
    /// Compute the cleanup model runs on. GPU is the default because it is far
    /// faster on Apple silicon; CPU is the escape hatch when Metal is busy,
    /// unsupported, or the machine is better spent elsewhere.
    public var cleanupCompute: ModelCompute = .gpu
    public var meetingsInStats = false
    /// The Island is visible at rest, and a click opens its recent list. Off keeps
    /// it out of the way until there is something to say.
    public var islandAlwaysOn = false
    /// Draw streaming words in the Island while dictating. The recognizer streams
    /// either way; this only decides whether the shelf is shown.
    public var islandLiveText = false
    public var onboardingComplete = false
    public init() {}
    public static let `default` = AppSettings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = try c.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? d.theme
        // Streaming only. A stored batch profile (or a removed one) is replaced
        // with the default instead of being allowed onto the dictation path.
        let storedProfile = try c.decodeIfPresent(String.self, forKey: .asrProfile) ?? d.asrProfile
        let resolved = ModelProfile.byID(storedProfile)
        asrProfile = resolved.id == storedProfile && resolved.supportsLiveDictation
            ? storedProfile
            : ModelProfile.default.id
        speechEnhancementEnabled = try c.decodeIfPresent(Bool.self, forKey: .speechEnhancementEnabled) ?? d.speechEnhancementEnabled
        cleanupEnabled = try c.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? d.cleanupEnabled
        harperEnabled = try c.decodeIfPresent(Bool.self, forKey: .harperEnabled) ?? d.harperEnabled
        commandsEnabled = try c.decodeIfPresent(Bool.self, forKey: .commandsEnabled) ?? d.commandsEnabled
        codeSpeakEnabled = try c.decodeIfPresent(Bool.self, forKey: .codeSpeakEnabled) ?? d.codeSpeakEnabled
        disfluency = try c.decodeIfPresent(DisfluencySettings.self, forKey: .disfluency) ?? d.disfluency
        codeAware = try c.decodeIfPresent(CodeAwareSettings.self, forKey: .codeAware) ?? d.codeAware
        numberStyle = try c.decodeIfPresent(LargeNumberStyle.self, forKey: .numberStyle) ?? d.numberStyle
        spellOutSmallNumbers = try c.decodeIfPresent(Bool.self, forKey: .spellOutSmallNumbers) ?? d.spellOutSmallNumbers
        lineFormat = try c.decodeIfPresent(LineFormatSettings.self, forKey: .lineFormat) ?? d.lineFormat
        gesture = try c.decodeIfPresent(GestureConfig.self, forKey: .gesture) ?? d.gesture
        dictationKey = try c.decodeIfPresent(DictationKey.self, forKey: .dictationKey) ?? d.dictationKey
        typingWPM = try c.decodeIfPresent(Int.self, forKey: .typingWPM) ?? d.typingWPM
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? d.displayName
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        retentionDays = try c.decodeIfPresent(Int.self, forKey: .retentionDays) ?? d.retentionDays
        noTranscriptStorage = try c.decodeIfPresent(Bool.self, forKey: .noTranscriptStorage) ?? d.noTranscriptStorage
        keepAudio = try c.decodeIfPresent(Bool.self, forKey: .keepAudio) ?? d.keepAudio
        // An explicit null means "keep forever"; an absent key means "use the default".
        audioRetentionDays = c.contains(.audioRetentionDays)
            ? try c.decodeIfPresent(Int.self, forKey: .audioRetentionDays)
            : d.audioRetentionDays
        keepJournals = try c.decodeIfPresent(Bool.self, forKey: .keepJournals) ?? d.keepJournals
        cleanupStyling = try c.decodeIfPresent(String.self, forKey: .cleanupStyling) ?? d.cleanupStyling
        cleanupStructure = try c.decodeIfPresent(String.self, forKey: .cleanupStructure) ?? d.cleanupStructure
        cleanupContext = try c.decodeIfPresent(String.self, forKey: .cleanupContext) ?? d.cleanupContext
        interactiveDeadlineMs = try c.decodeIfPresent(Int.self, forKey: .interactiveDeadlineMs) ?? d.interactiveDeadlineMs
        backgroundDeadlineMs = try c.decodeIfPresent(Int.self, forKey: .backgroundDeadlineMs) ?? d.backgroundDeadlineMs
        cleanupWorkers = try c.decodeIfPresent(Int.self, forKey: .cleanupWorkers) ?? d.cleanupWorkers
        cleanupCompute = try c.decodeIfPresent(ModelCompute.self, forKey: .cleanupCompute) ?? d.cleanupCompute
        meetingsInStats = try c.decodeIfPresent(Bool.self, forKey: .meetingsInStats) ?? d.meetingsInStats
        islandAlwaysOn = try c.decodeIfPresent(Bool.self, forKey: .islandAlwaysOn) ?? d.islandAlwaysOn
        islandLiveText = try c.decodeIfPresent(Bool.self, forKey: .islandLiveText) ?? d.islandLiveText
        onboardingComplete = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? d.onboardingComplete
    }
}

public enum SuperflowError: Error, Sendable, Equatable, LocalizedError {
    case permissionDenied(String)
    case audioFailure(String)
    case diskFull
    case modelUnavailable(String)
    case timeout(String)
    case cancelled
    case storage(String)
    case insertion(String)
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let s): "Permission required: \(s)"
        case .audioFailure(let s): "Audio failure: \(s)"
        case .diskFull: "Not enough free disk space to record safely."
        case .modelUnavailable(let s): "Model unavailable: \(s)"
        case .timeout(let s): "Timed out: \(s)"
        case .cancelled: "Cancelled"
        case .storage(let s): "Storage error: \(s)"
        case .insertion(let s): "Could not insert text: \(s)"
        case .invalidState(let s): "Invalid state: \(s)"
        }
    }
}

public protocol TimeSource: Sendable {
    func now() -> Date
    func monotonicNs() -> UInt64
}

public struct SystemTimeSource: TimeSource {
    public init() {}
    public func now() -> Date { Date() }
    public func monotonicNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}

public enum LocalDay {
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public static func date(from day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

public func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
}

public enum TextSafe {
    public static func singleLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
