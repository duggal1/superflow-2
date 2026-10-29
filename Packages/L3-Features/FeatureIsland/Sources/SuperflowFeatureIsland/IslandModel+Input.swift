import AppKit
import Foundation

/// The Island's input half: gesture events, pointer, click, copy. Kept beside
/// `IslandModel` rather than inside it so the state machine stays readable.
extension IslandModel {
    public func send(_ event: IslandEvent) {
        if event == .dismissed, confirmingDiscard {
            keepMeeting()
            return
        }
        switch event {
        case .escapeCancelled, .cancelled:
            frozenTrail = [meter.shown] + meter.trail
        default: break
        }
        // A new capture starts with no carried-over text, so the live shelf can
        // never show the tail of the previous sentence.
        if case .holdBegan = event { live = .empty }
        if case .meetingBegan = event { live = .empty; pulse = .empty; markedMoments = []; meetingStart = .now }
        switch event {
        case .holdBegan(let target):
            begin(target)
        case .handsFreeBegan(let target):
            begin(target)
        case .meetingBegan(let target):
            begin(target)
        case .escapeCancelled(let text):
            offerUndo(text)
            return
        case .notchClicked:
            clicked()
            return
        case .notice(let notice):
            receiveNotice(notice)
            return
        case .holdEnded, .cancelled, .landed, .pasteFailed, .dismissed:
            break
        }
        go(IslandReducer.reduce(phase, event))
    }

    private func begin(_ target: IslandTarget?) {
        self.target = target
        recordedAt = Date()
        elapsed = 0
        hoverTask?.cancel()
    }

    /// Fully dynamic: only a recording that ran long enough to be worth keeping
    /// raises the card. A quick Escape just closes the Island.
    private func offerUndo(_ text: String) {
        let elapsed = recordedAt.map { Date().timeIntervalSince($0) } ?? 0
        guard phase.isBusy, elapsed >= Self.undoMinimumSeconds else {
            go(.idle)
            return
        }
        go(.undo(IslandUndo(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                            bundleID: target?.bundleID,
                            appName: target?.name,
                            seconds: elapsed)))
    }

    /// Pointer over the notch. 120 ms dwell, so sweeping across to a menu item does not flicker.
    public func hoverChanged(_ inside: Bool) {
        if inside, prefs.alwaysOn { today = feed.wordsToday() }
        switch phase {
        case .idle where inside && (geometry.hasNotch || prefs.alwaysOn):
            hoverTask?.cancel()
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.go(.hover)
            }
        case .idle:
            hoverTask?.cancel()
        case .hover where !inside:
            go(.idle)
        case .failed:
            if inside {
                timer?.cancel()
            } else {
                scheduleFailureTimeout(ms: 4_000)
            }
        case .notice:
            if inside {
                noticeTask?.cancel()
            } else {
                scheduleNoticeTimeout()
            }
        case .hover, .listening, .handsFree, .meeting, .meetingPanel, .processing, .landed,
             .undo, .recent, .history:
            break
        }
    }

    /// Click on the notch. The owner can always reach the last dictation.
    public func openRecent() {
        guard phase.isRest, geometry.hasNotch || prefs.alwaysOn else { return }
        hoverTask?.cancel()
        go(.recent(feed.lastTranscript()))
    }

    /// An OS-style notice, drawn in the Island. The notifier below is the first
    /// caller; the app can post any other with the same API.
    public func notify(_ notice: IslandNotice) {
        send(.notice(notice))
    }

    /// Copies the cleaned text. A failed paste closes itself 0.9 s after the
    /// copy; every other card gives the tick a little longer to be read.
    public func copy(_ transcript: IslandTranscript) {
        copyText(transcript.text)
        copiedID = transcript.id
        let wasFailed: Bool = if case .failed = phase { true } else { false }
        after(wasFailed ? 900 : 1_200) { [weak self] in
            self?.copiedID = nil
            if wasFailed { self?.send(.dismissed) }
        }
    }

    /// Undo means "keep the words". The microphone is already closed, so the one
    /// honest recovery is the clipboard: the card says so and copies on click.
    public func keepUndo(_ undo: IslandUndo) {
        guard !undo.isEmpty else {
            go(.idle)
            return
        }
        copyText(undo.text)
        copiedID = "undo"
        after(1_400) { [weak self] in self?.go(.idle) }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

}
