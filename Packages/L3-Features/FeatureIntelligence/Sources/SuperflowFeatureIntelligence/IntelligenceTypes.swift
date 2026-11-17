import Foundation
import SuperflowKernel
import SuperflowMeetingIntelligence

/// The Island states this module can render. Agent 1's FeatureIsland hosts the
/// `IntelligenceContent` view for whichever slot is live; the App owns the model.
public enum IntelligenceIslandSlot: String, Sendable, CaseIterable {
    case compose, answer, settings, history, suggestions
}

public enum IntelligenceAnswerPhase: Equatable, Sendable {
    case idle, thinking, streaming, done, truncated, failed(String)
}

/// Everything the answer service needs for one ask. `task` is the composed
/// instruction, including the single shared messy-transcript block.
public struct IntelligenceAskRequest: Sendable {
    public var question: String
    public var task: String
    public var transcript: String
    public var background: String
    public var mode: MeetingMode
    public var effort: ReasoningEffort
    public var screenAware: Bool

    public init(question: String, task: String, transcript: String, background: String,
                mode: MeetingMode, effort: ReasoningEffort, screenAware: Bool) {
        self.question = question
        self.task = task
        self.transcript = transcript
        self.background = background
        self.mode = mode
        self.effort = effort
        self.screenAware = screenAware
    }
}

public enum IntelligenceAnswerEvent: Sendable {
    case thinking
    case delta(String)
    case finished(String)
    case failed(String)
}

public struct IntelligenceHistoryItem: Identifiable, Equatable, Sendable {
    public let id: SessionID
    public let title: String
    public let preview: String
    public let date: Date
    public let wordCount: Int
    public let fullText: String
    public var answers: [String]

    public init(id: SessionID, title: String, preview: String, date: Date,
                wordCount: Int, fullText: String, answers: [String] = []) {
        self.id = id
        self.title = title
        self.preview = preview
        self.date = date
        self.wordCount = wordCount
        self.fullText = fullText
        self.answers = answers
    }
}

/// A selector option derived from `MeetingMode.allCases` — never a hardcoded
/// list. New modes added to the source enum appear here automatically.
public struct IntelligenceTheme: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    public static func label(for mode: MeetingMode) -> String {
        switch mode {
        case .normal: "General Meeting"
        case .codingInterview: "Coding Interview"
        case .sales: "Sales Call"
        case .journal: "Journal / Personal"
        case .custom: "Personal / Custom"
        @unknown default: Self.derivedLabel(mode.rawValue)
        }
    }

    public static func allFromSource() -> [IntelligenceTheme] {
        MeetingMode.allCases.map { IntelligenceTheme(id: $0.rawValue, label: label(for: $0)) }
    }

    /// Humanises a raw value so a future mode added to the source enum is never
    /// dropped or shown as a bare identifier.
    private static func derivedLabel(_ raw: String) -> String {
        let words = raw.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return words.capitalized
    }
}
