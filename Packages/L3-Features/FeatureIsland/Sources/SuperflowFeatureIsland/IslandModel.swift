import AppKit
import Foundation
import Observation
import SwiftUI

public enum IslandPlacement: Sendable { case home, active }

@MainActor @Observable
public final class IslandModel {
    public private(set) var phase: IslandPhase = .idle
    public private(set) var copied = false
    /// Seconds left on the "was that a mistake?" card.
    public private(set) var undoRemaining = 0
    /// Seconds left before an OS-style notice leaves on its own. Drawn as a
    /// one-cell-per-second rail, so the card never disappears unannounced.
    public private(set) var noticeRemaining = 0
    /// Seconds the current capture has run. The meeting wing reads it: a meeting
    /// is a duration, not a mode.
    public private(set) var elapsed = 0
    public var geometry: NotchGeometry
    public private(set) var target: IslandTarget?
    public let waveform = WaveformModel()

    /// Escape only earns an undo card after this many seconds of recording.
    public static let undoMinimumSeconds: TimeInterval = 30
    /// The card holds for this many seconds.
    public static let undoWindow = 6
    /// A notice leaves on its own after this long.
    public static let noticeSeconds: Double = 5

    @ObservationIgnored public var feed: any IslandFeed
    @ObservationIgnored public var placement: (IslandPlacement) -> Void = { _ in }
    @ObservationIgnored public var phaseDidChange: (IslandPhase) -> Void = { _ in }
    @ObservationIgnored private var latestLevel: Float = 0
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var consumers: [Task<Void, Never>] = []
    @ObservationIgnored private var recordedAt: Date?
    @ObservationIgnored private var pendingNotice: IslandNotice?
    @ObservationIgnored private var totalWords = 0
    @ObservationIgnored private var nextMilestone = 1_000

    public init(feed: any IslandFeed, geometry: NotchGeometry) {
        self.feed = feed
        self.geometry = geometry
        consumers = [
            Task { [weak self] in
                guard let events = self?.feed.events else { return }
                for await event in events { self?.send(event) }
            },
            Task { [weak self] in
                guard let levels = self?.feed.levels else { return }
                for await level in levels { self?.latestLevel = level }
            },
        ]
    }

    deinit {
        consumers.forEach { $0.cancel() }
        timer?.cancel()
        hoverTask?.cancel()
        ticker?.cancel()
        undoTask?.cancel()
        noticeTask?.cancel()
    }

    // MARK: input

    public func send(_ event: IslandEvent) {
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
        case .holdEnded, .cancelled, .landed, .pasteFailed, .notice, .dismissed:
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
        switch phase {
        case .idle where inside && geometry.hasNotch:
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
        case .hover, .listening, .handsFree, .meeting, .processing, .landed, .undo, .recent:
            break
        }
    }

    /// Click on the notch. The owner can always reach the last dictation.
    public func openRecent() {
        guard phase.isRest, geometry.hasNotch else { return }
        hoverTask?.cancel()
        go(.recent(feed.lastTranscript()))
    }

    /// An OS-style notice, drawn in the Island. The milestone below is the first
    /// caller; the app can post any other with the same API.
    public func notify(_ notice: IslandNotice) {
        go(.notice(notice))
    }

    public func copy(_ transcript: IslandTranscript) {
        copyText(transcript.text)
        copied = true
        after(900) { [weak self] in self?.send(.dismissed) }
    }

    /// Undo means "keep the words". The microphone is already closed, so the one
    /// honest recovery is the clipboard: the card says so and copies on click.
    public func keepUndo(_ undo: IslandUndo) {
        guard !undo.isEmpty else {
            go(.idle)
            return
        }
        copyText(undo.text)
        copied = true
        after(1_400) { [weak self] in self?.go(.idle) }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    // MARK: transitions

    private func go(_ next: IslandPhase) {
        guard next != phase else { return }
        let prev = phase
        timer?.cancel()
        copied = false
        if case .undo = next {
            // The countdown owns its own task.
        } else {
            undoTask?.cancel()
            undoRemaining = 0
        }
        if case .notice = next {
            // The notice owns its own timeout.
        } else {
            noticeTask?.cancel()
            noticeRemaining = 0
        }

        // Move the window only while it is invisible, never animated.
        if prev == .idle, next != .hover {
            placement(next.kind == .card ? .home : .active)
        } else if prev == .hover, next.kind != .rest {
            placement(next.kind == .card ? .home : .active)
        }

        // The meter runs from the first frame of the session until cleanup ends.
        switch next {
        case .listening, .handsFree, .meeting:
            if !prev.isBusy { waveform.reset() }
            waveform.setLive(true)
            startTicker()
        case .processing:
            waveform.setLive(false)
            startTicker()
        case .idle, .hover, .landed, .undo, .failed, .recent, .notice:
            waveform.setLive(false)
            stopTicker()
            elapsed = 0
        }

        if case .landed(let words) = next { accumulate(words) }

        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(IslandLayout.animation(from: prev, to: next, reduceMotion: reduce)) {
            phase = next
        }

        sideEffects(next)
        phaseDidChange(next)

        switch next {
        case .landed:
            after(900) { [weak self] in
                guard let self else { return }
                if let notice = self.pendingNotice {
                    self.pendingNotice = nil
                    self.go(.notice(notice))
                } else {
                    self.go(.idle)
                }
            }
        case .undo(let undo):
            undoRemaining = Self.undoWindow
            startUndoCountdown(undo)
        case .notice:
            noticeRemaining = Int(Self.noticeSeconds)
            scheduleNoticeTimeout()
        case .failed:
            if feed.storesTranscripts { scheduleFailureTimeout(ms: 12_000) }
        case .idle:
            recordedAt = nil
            if !prev.isRest {
                after(420) { [weak self] in self?.placement(.home) }
            }
        case .hover, .listening, .handsFree, .meeting, .processing, .recent:
            break
        }
    }

    /// One thousand words is worth saying out loud. The card is queued behind the
    /// "Pasted" tick so the two never fight for the same 900 ms.
    private func accumulate(_ words: Int) {
        totalWords += words
        guard totalWords >= nextMilestone else { return }
        pendingNotice = IslandNotice(
            kind: .milestone,
            title: "\(nextMilestone.formatted()) words.",
            detail: "\(totalWords.formatted()) words dictated with Superflow."
        )
        nextMilestone *= 2
    }

    private func scheduleFailureTimeout(ms: Int) {
        guard feed.storesTranscripts else { return }
        after(ms) { [weak self] in self?.go(.idle) }
    }

    private func scheduleNoticeTimeout() {
        noticeTask?.cancel()
        guard noticeRemaining > 0 else {
            go(.idle)
            return
        }
        noticeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, case .notice = self.phase else { return }
                self.noticeRemaining = max(0, self.noticeRemaining - 1)
                if self.noticeRemaining == 0 {
                    self.go(.idle)
                    return
                }
            }
        }
    }

    private func startUndoCountdown(_ undo: IslandUndo) {
        undoTask?.cancel()
        undoTask = Task { @MainActor [weak self] in
            for remaining in stride(from: IslandModel.undoWindow - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                guard case .undo = self.phase else { return }
                self.undoRemaining = remaining
                if remaining == 0 { self.go(.idle) }
            }
        }
    }

    private func after(_ ms: Int, _ body: @escaping @MainActor () -> Void) {
        timer?.cancel()
        timer = Task {
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            body()
        }
    }

    // MARK: waveform clock

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.waveform.tick(level: self.latestLevel)
                if let started = self.recordedAt {
                    let seconds = Int(Date().timeIntervalSince(started))
                    if seconds != self.elapsed { self.elapsed = seconds }
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: side effects

    private func sideEffects(_ phase: IslandPhase) {
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
