import Foundation
import SuperflowKernel

public enum SettingsIssue: Hashable, Sendable {
    case holdOutOfRange
    case doubleTapOutOfRange
    case meetingHoldOutOfRange
    case typingSpeedOutOfRange
    case lineBreakOutOfRange
    case lineBreakOutOfOrder
    case displayNameEmpty
    case displayNameTooLong
    case retentionOutOfRange
    case interactiveDeadlineOutOfRange
    case backgroundDeadlineOutOfRange
    case cleanupWorkersOutOfRange

    public var message: String {
        switch self {
        case .holdOutOfRange:
            "Fn push-to-talk must be between 100 and 600 ms."
        case .doubleTapOutOfRange:
            "The double-tap window must be between 200 and 800 ms."
        case .meetingHoldOutOfRange:
            "Right Command must be held between 300 and 1500 ms to start a meeting."
        case .typingSpeedOutOfRange:
            "Typing speed must be between 20 and 120 words per minute."
        case .lineBreakOutOfRange:
            "Line-break word counts must stay between 10 and 60 words."
        case .lineBreakOutOfOrder:
            "Minimum must be below preferred, and preferred below the hard maximum."
        case .displayNameEmpty:
            "Add a name for the microphone channel."
        case .displayNameTooLong:
            "Keep the display name under 40 characters."
        case .retentionOutOfRange:
            "Retention must be between 1 and 3650 days, or forever."
        case .interactiveDeadlineOutOfRange:
            "The interactive cleanup deadline must be between 500 and 5000 ms."
        case .backgroundDeadlineOutOfRange:
            "The background cleanup deadline must be between 5 and 120 seconds."
        case .cleanupWorkersOutOfRange:
            "Cleanup workers must be between 1 and 8."
        }
    }
}

/// Every range here is deliberately narrower than the type allows: settings
/// that would make the gesture recognizer unusable or the pipeline overflow are
/// rejected before they reach disk.
public enum SettingsValidation {
    public static let holdRange = 100...600
    public static let doubleTapRange = 200...800
    public static let meetingHoldRange = 300...1_500
    public static let typingSpeedRange = 20...120
    public static let lineWordRange = 10...60
    public static let retentionRange = 1...3_650
    public static let interactiveDeadlineRange = 500...5_000
    public static let backgroundDeadlineRange = 5_000...120_000
    public static let cleanupWorkersRange = 1...8
    public static let maxDisplayNameLength = 40

    public static func issues(_ settings: AppSettings) -> [SettingsIssue] {
        var issues: [SettingsIssue] = []
        let gesture = settings.gesture
        if !holdRange.contains(gesture.holdMs) { issues.append(.holdOutOfRange) }
        if !doubleTapRange.contains(gesture.doubleTapMs) { issues.append(.doubleTapOutOfRange) }
        if !meetingHoldRange.contains(gesture.meetingHoldMs) {
            issues.append(.meetingHoldOutOfRange)
        }
        if !typingSpeedRange.contains(settings.typingWPM) { issues.append(.typingSpeedOutOfRange) }

        let line = settings.lineFormat
        let counts = [line.minWords, line.preferredMax, line.hardMax]
        if counts.contains(where: { !lineWordRange.contains($0) }) {
            issues.append(.lineBreakOutOfRange)
        } else if !(line.minWords < line.preferredMax && line.preferredMax < line.hardMax) {
            issues.append(.lineBreakOutOfOrder)
        }

        let name = settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            issues.append(.displayNameEmpty)
        } else if name.count > maxDisplayNameLength {
            issues.append(.displayNameTooLong)
        }

        if let days = settings.retentionDays, !retentionRange.contains(days) {
            issues.append(.retentionOutOfRange)
        }
        if !interactiveDeadlineRange.contains(settings.interactiveDeadlineMs) {
            issues.append(.interactiveDeadlineOutOfRange)
        }
        if !backgroundDeadlineRange.contains(settings.backgroundDeadlineMs) {
            issues.append(.backgroundDeadlineOutOfRange)
        }
        if !cleanupWorkersRange.contains(settings.cleanupWorkers) {
            issues.append(.cleanupWorkersOutOfRange)
        }
        return issues
    }

    public static func isValid(_ settings: AppSettings) -> Bool {
        issues(settings).isEmpty
    }
}
