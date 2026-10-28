import AppKit

extension IslandModel {
    /// One phase, one haptic, one spoken line. VoiceOver hears the same state the
    /// notch draws, so the Island is never a silent, unlabelled shape shift.
    func sideEffects(_ phase: IslandPhase) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch phase {
        case .listening: performer.perform(.alignment, performanceTime: .default)
        case .handsFree: performer.perform(.levelChange, performanceTime: .default)
        case .meeting: performer.perform(.alignment, performanceTime: .default)
        case .landed: performer.perform(.levelChange, performanceTime: .default)
        case .failed, .undo: performer.perform(.generic, performanceTime: .default)
        case .notice: performer.perform(.alignment, performanceTime: .default)
        case .idle, .hover, .processing, .recent: break
        }

        let line: String? = switch phase {
        case .listening: "Listening"
        case .handsFree: "Listening hands-free. Press fn or Return to type it."
        case .meeting: "Meeting recording. Return to stop, Escape to cancel."
        case .landed: "Pasted"
        case .failed: "Couldn't paste. Transcript ready to copy."
        case .undo: "Escape pressed. Was that a mistake? Undo is available for six seconds."
        case .notice(let notice): notice.title
        case .idle, .hover, .processing, .recent: nil
        }
        if let line {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: line,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
    }
}
