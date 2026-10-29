import Foundation

/// Everything the Island mirrors from outside itself: the two settings, the live
/// partial, the meeting pulse, and the stored history. The model never invents
/// any of it; it only decides what the notch is allowed to show.
public extension IslandModel {
    /// Settings push their two switches here. Called on every change, cheap when
    /// nothing changed, so the Island and the Settings window cannot drift.
    func configure(_ prefs: IslandPrefs) {
        guard prefs != self.prefs else { return }
        self.prefs = prefs
        if !prefs.liveText { live = .empty }
        if prefs.alwaysOn {
            today = feed.wordsToday()
        } else {
            if phase == .history { go(.idle) }
            if phase == .idle, !geometry.hasNotch { placement(.home) }
        }
    }

    /// A click on the notch or on the meeting wings. The target depends on what
    /// the Island is already doing, never on a modifier key.
    func clicked() {
        switch phase {
        case .meeting:
            go(.meetingPanel)
        case .meetingPanel:
            go(.meeting)
        case .idle, .hover:
            history = feed.history(limit: 5)
            go(prefs.alwaysOn ? .history : .recent(feed.lastTranscript()))
        case .recent, .history:
            go(.idle)
        case .failed, .undo, .notice, .landed, .listening, .handsFree, .processing:
            break
        }
    }

    /// The history card is a preview. The full list lives in the History window.
    func openHistory() {
        showHistory()
        go(.idle)
    }

    /// "Paste again" on the failure card. The app owns the inserter; the Island
    /// only asks for the retry.
    func retryPaste(_ transcript: IslandTranscript) {
        rePaste(transcript)
    }

    /// The one button a notice may carry.
    func openNotice(_ notice: IslandNotice) {
        noticeAction(notice)
    }
}
