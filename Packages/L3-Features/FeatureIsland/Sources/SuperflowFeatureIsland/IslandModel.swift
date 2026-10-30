import AppKit
import Foundation
import Observation
import SwiftUI

public enum IslandPlacement: Sendable { case home, active }

@MainActor @Observable
public final class IslandModel {
    public private(set) var phase: IslandPhase = .idle
    public internal(set) var copiedID: String?
    /// True while the last copy is still being acknowledged.
    public var copied: Bool { copiedID != nil }
    /// Seconds left on the "was that a mistake?" card.
    public private(set) var undoRemaining = 0
    /// Seconds left before an OS-style notice leaves on its own, drawn as a
    /// one-cell-per-second rail so the card never disappears unannounced.
    public private(set) var noticeRemaining = 0
    /// Seconds the current capture has run. A meeting is a duration, not a mode.
    public internal(set) var elapsed = 0
    /// True while the key hints are up. The shelf is part of the silhouette, so
    /// the shape grows by `IslandLayout.hintShelf`.
    public private(set) var hint = false
    /// Countdowns are deadline-based: the rail drains continuously and the
    /// numeral is derived from the same instant.
    public private(set) var undoDeadline: Date?
    public private(set) var noticeDeadline: Date?

    // MARK: live state (mirrored from the feed, never invented here)

    /// The two Settings switches, mirrored so a change of mind needs no relaunch.
    public internal(set) var prefs = IslandPrefs()
    /// Newest first, read when a card opens, never streamed.
    public internal(set) var history: [IslandTranscript] = []
    /// Words dictated today, meetings excluded. The hover shelf reads it.
    public internal(set) var today = 0
    /// The current partial. Empty unless `prefs.liveText` is on.
    public internal(set) var live = LiveText.empty
    /// Meeting words and talk share.
    public internal(set) var pulse = MeetingPulse.empty
    /// When the current meeting started. The panel's clock reads it.
    public internal(set) var meetingStart: Date?
    /// When the current capture started, including a latched hands-free session.
    /// The wings clock reads it and keeps it through the exit crossfade.
    public internal(set) var sessionStart: Date?
    /// Increments on a small success moment (latched, landed) so the stage can
    /// give the silhouette a tiny impulse.
    public internal(set) var bump = 0
    /// Opens the History window from the Island's history card. Set by the app.
    @ObservationIgnored public var showHistory: () -> Void = {}
    /// Re-inserts a transcript that never landed. Set by the app.
    @ObservationIgnored public var rePaste: (IslandTranscript) -> Void = { _ in }
    /// Runs the one button a notice may carry. Set by the app.
    @ObservationIgnored public var noticeAction: (IslandNotice) -> Void = { _ in }

    public var geometry: NotchGeometry
    public var box: IslandBox {
        if phase == .processing, meetingStart != nil {
            return IslandLayout.box(.meeting, geometry)
        }
        if confirmingDiscard {
            return IslandBox(body: .init(width: IslandLayout.cardWidth, height: geometry.band + 60),
                             top: 12, bottom: 24, opacity: 1)
        }
        return IslandLayout.box(phase, geometry, hint: hint, live: prefs.liveText,
                                prefs: prefs, historyRows: history.count, noSignal: noSignal)
    }
    public internal(set) var target: IslandTarget?
    let meter = IslandMeterModel()
    public internal(set) var frozenTrail = [Float](repeating: 0, count: 26)
    public internal(set) var noSignal = false
    public internal(set) var confirmingDiscard = false
    public internal(set) var markedMoments: [TimeInterval] = []
    @ObservationIgnored public var hitRect = CGRect.zero
    @ObservationIgnored public var finishMeeting: () -> Void = {}
    @ObservationIgnored public var cancelMeeting: () -> Void = {}
    @ObservationIgnored private var silenceWatch: Task<Void, Never>?


    /// Escape only earns an undo card after this many seconds of recording.
    public static let undoMinimumSeconds: TimeInterval = 30
    /// The card holds for this many seconds.
    public static let undoWindow = 6
    /// A notice leaves on its own after this long.
    public static let noticeSeconds: Double = 5

    @ObservationIgnored public var feed: any IslandFeed
    @ObservationIgnored public var placement: (IslandPlacement) -> Void = { _ in }
    @ObservationIgnored public var phaseDidChange: (IslandPhase) -> Void = { _ in }
    @ObservationIgnored var timer: Task<Void, Never>?
    @ObservationIgnored var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    @ObservationIgnored private var consumers: [Task<Void, Never>] = []
    @ObservationIgnored var recordedAt: Date?
    @ObservationIgnored var pendingNotices: [IslandNotice] = []

    public init(feed: any IslandFeed, geometry: NotchGeometry) {
        self.feed = feed
        self.geometry = geometry
        hitRect = IslandLayout.hitRect(.idle, geometry)
        consumers = [
            Task { [weak self] in
                guard let events = self?.feed.events else { return }
                for await event in events { self?.send(event) }
            },
            Task { [weak self] in
                guard let levels = self?.feed.levels else { return }
                for await level in levels {
                    guard let self else { return }
                    self.meter.ingest(level)
                    if self.noSignal, level > 0.06 { self.noSignal = false }
                }
            },
            // Streaming always runs. The model only keeps the text when the
            // setting is on, so the engine does the same work either way.
            Task { [weak self] in
                guard let live = self?.feed.live else { return }
                for await text in live {
                    guard let self, self.prefs.liveText else { continue }
                    self.live = text
                }
            },
            Task { [weak self] in
                guard let pulses = self?.feed.pulses else { return }
                for await pulse in pulses { self?.pulse = pulse }
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
        hintTask?.cancel()
        silenceWatch?.cancel()
    }

    // MARK: transitions

    func go(_ next: IslandPhase) {
        guard next != phase else { return }
        let prev = phase
        confirmingDiscard = false
        timer?.cancel()
        copiedID = nil
        if case .undo = next {
            // The countdown owns its own task.
        } else {
            undoTask?.cancel()
            undoRemaining = 0
            undoDeadline = nil
        }
        if case .notice = next {
            // The notice owns its own timeout.
        } else {
            noticeTask?.cancel()
            noticeRemaining = 0
            noticeDeadline = nil
        }

        // Move the window only while it is invisible, never animated.
        if prev == .idle, next != .hover {
            placement(next.kind == .card ? .home : .active)
        } else if prev == .hover, next.kind != .rest {
            placement(next.kind == .card ? .home : .active)
        }

        // The meter runs from the first frame of the session until cleanup ends.
        switch next {
        case .listening, .handsFree, .meeting, .meetingPanel:
            startTicker()
        case .processing:
            startTicker()
        case .idle, .hover, .landed, .undo, .failed, .recent, .history, .notice:
            stopTicker()
            elapsed = 0
        }

        syncMeter(from: prev, to: next)
        phase = next

        sideEffects(next)
        updateHint(next, from: prev)
        phaseDidChange(next)

        switch next {
        case .landed:
            after(900) { [weak self] in self?.go(.idle) }
        case .undo(let undo):
            undoRemaining = Self.undoWindow
            undoDeadline = Date().addingTimeInterval(TimeInterval(Self.undoWindow))
            startUndoCountdown(undo)
        case .notice:
            noticeRemaining = Int(Self.noticeSeconds)
            noticeDeadline = Date().addingTimeInterval(Self.noticeSeconds)
            scheduleNoticeTimeout()
        case .failed:
            if feed.storesTranscripts { scheduleFailureTimeout(ms: 12_000) }
        case .idle:
            recordedAt = nil
            meetingStart = nil
            live = .empty
            if !prev.isRest {
                after(420) { [weak self] in self?.placement(.home) }
            }
            schedulePendingNotice()
        case .hover:
            schedulePendingNotice()
        case .listening, .handsFree, .meeting, .meetingPanel, .processing,
             .recent, .history:
            break
        }
    }

    func scheduleFailureTimeout(ms: Int) {
        guard feed.storesTranscripts else { return }
        after(ms) { [weak self] in self?.go(.idle) }
    }

    func scheduleNoticeTimeout() {
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

    /// The key hints belong to a live mode, not to a card. They arrive with the
    /// mode and leave after 2.4 s: long enough to read once, short enough that a
    /// long meeting is not permanently wearing a keyboard tutorial.
    private func updateHint(_ next: IslandPhase, from previous: IslandPhase) {
        hintTask?.cancel()
        hintTask = nil
        switch next {
        case .meeting where previous == .meetingPanel:
            setHint(false)
        case .handsFree, .meeting:
            setHint(true)
            hintTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                self?.setHint(false)
            }
        case .idle, .hover, .listening, .processing, .landed, .undo, .failed, .recent, .history, .meetingPanel, .notice:
            setHint(false)
        }
    }

    private func setHint(_ on: Bool) {
        guard hint != on else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduce {
            hint = on
        } else {
            withAnimation(.smooth(duration: 0.30)) { hint = on }
        }
    }

    func after(_ ms: Int, _ body: @escaping @MainActor () -> Void) {
        timer?.cancel()
        timer = Task {
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            body()
        }
    }

    private func syncMeter(from previous: IslandPhase, to next: IslandPhase) {
        let listening = next == .listening || next == .handsFree
        let active = listening || next == .meeting || next == .meetingPanel
        let wasActive = previous == .listening || previous == .handsFree || previous == .meeting || previous == .meetingPanel
        if active && !wasActive {
            meter.reset()
            noSignal = false
            silenceWatch?.cancel()
            if listening {
                silenceWatch = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled, let self,
                          self.phase == .listening || self.phase == .handsFree,
                          !self.meter.heard else { return }
                    self.noSignal = true
                }
            }
        }
        if !active {
            silenceWatch?.cancel()
            noSignal = false
        }
    }

    // MARK: elapsed clock

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let started = self.recordedAt {
                    let seconds = Int(Date().timeIntervalSince(started))
                    if seconds != self.elapsed { self.elapsed = seconds }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
