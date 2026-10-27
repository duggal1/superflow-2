import Foundation

public enum BreakStyle: String, Codable, Sendable, CaseIterable {
    case paragraph, newline
    public var label: String { self == .paragraph ? "Blank line" : "Single newline" }
}
public enum LargeNumberStyle: String, Codable, Sendable, CaseIterable {
    case abbreviated, full
    public var label: String { self == .abbreviated ? "Abbreviated ($200k)" : "Full ($200,000)" }
}
public enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case system, light, dark
    public var label: String { rawValue.capitalized }
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
    public var asrProfile: String = ModelProfile.parakeetEOU120M.id
    public var cleanupEnabled = true
    public var harperEnabled = false
    public var commandsEnabled = true
    public var numberStyle: LargeNumberStyle = .abbreviated
    public var spellOutSmallNumbers = true
    public var lineFormat = LineFormatSettings()
    public var gesture = GestureConfig()
    public var typingWPM = 40
    public var displayName = "You"
    public var launchAtLogin = false
    public var retentionDays: Int? = nil
    public var noTranscriptStorage = false
    public var keepJournals = false
    public var showIdlePill = false
    public var cleanupStyling = "semi-formal"
    public var cleanupStructure = "prose"
    public var interactiveDeadlineMs = 1500
    public var backgroundDeadlineMs = 30_000
    public var cleanupWorkers = 3
    public var meetingsInStats = false
    public var onboardingComplete = false
    public init() {}
    public static let `default` = AppSettings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = try c.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? d.theme
        asrProfile = try c.decodeIfPresent(String.self, forKey: .asrProfile) ?? d.asrProfile
        cleanupEnabled = try c.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? d.cleanupEnabled
        harperEnabled = try c.decodeIfPresent(Bool.self, forKey: .harperEnabled) ?? d.harperEnabled
        commandsEnabled = try c.decodeIfPresent(Bool.self, forKey: .commandsEnabled) ?? d.commandsEnabled
        numberStyle = try c.decodeIfPresent(LargeNumberStyle.self, forKey: .numberStyle) ?? d.numberStyle
        spellOutSmallNumbers = try c.decodeIfPresent(Bool.self, forKey: .spellOutSmallNumbers) ?? d.spellOutSmallNumbers
        lineFormat = try c.decodeIfPresent(LineFormatSettings.self, forKey: .lineFormat) ?? d.lineFormat
        gesture = try c.decodeIfPresent(GestureConfig.self, forKey: .gesture) ?? d.gesture
        typingWPM = try c.decodeIfPresent(Int.self, forKey: .typingWPM) ?? d.typingWPM
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? d.displayName
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        retentionDays = try c.decodeIfPresent(Int.self, forKey: .retentionDays) ?? d.retentionDays
        noTranscriptStorage = try c.decodeIfPresent(Bool.self, forKey: .noTranscriptStorage) ?? d.noTranscriptStorage
        keepJournals = try c.decodeIfPresent(Bool.self, forKey: .keepJournals) ?? d.keepJournals
        showIdlePill = try c.decodeIfPresent(Bool.self, forKey: .showIdlePill) ?? d.showIdlePill
        cleanupStyling = try c.decodeIfPresent(String.self, forKey: .cleanupStyling) ?? d.cleanupStyling
        cleanupStructure = try c.decodeIfPresent(String.self, forKey: .cleanupStructure) ?? d.cleanupStructure
        interactiveDeadlineMs = try c.decodeIfPresent(Int.self, forKey: .interactiveDeadlineMs) ?? d.interactiveDeadlineMs
        backgroundDeadlineMs = try c.decodeIfPresent(Int.self, forKey: .backgroundDeadlineMs) ?? d.backgroundDeadlineMs
        cleanupWorkers = try c.decodeIfPresent(Int.self, forKey: .cleanupWorkers) ?? d.cleanupWorkers
        meetingsInStats = try c.decodeIfPresent(Bool.self, forKey: .meetingsInStats) ?? d.meetingsInStats
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
