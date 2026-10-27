import Foundation
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowSessionEngine
import SwiftUI

public enum IslandMode: String, Sendable, Equatable {
    case dictation, handsFree, meeting

    public var label: String {
        switch self {
        case .dictation: "Dictation"
        case .handsFree: "Hands-free"
        case .meeting: "Meeting"
        }
    }
}

public enum IslandPhase: Sendable, Equatable {
    case hidden
    case warming
    case listening(IslandMode)
    case finalizing
    case complete
    case degraded(String)
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .warming, .listening, .finalizing, .degraded: true
        case .hidden, .complete, .failed: false
        }
    }
}

/// The Island is a pure projection of engine events. It owns no audio, no
/// persistence and no window: the app layer hosts this view in a non-activating
/// panel and forwards events here.
@MainActor
public final class IslandViewModel: ObservableObject {
    @Published public private(set) var phase: IslandPhase = .hidden
    @Published public private(set) var elapsedMs = 0
    @Published public private(set) var partial = ""
    @Published public private(set) var systemPartial = ""
    @Published public private(set) var levels: [Float] = []
    @Published public private(set) var notice: String?
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var isExpanded = false
    @Published public private(set) var showIdlePill: Bool

    private let now: () -> Date
    private var startedAt: Date?
    private var frozenElapsedMs = 0
    private var completionUntil: Date?
    private var lastLevelAt: Date?
    private let levelInterval: TimeInterval = 1.0 / 30.0
    private let maxLevels = 48

    public init(now: @escaping () -> Date = { Date() }, showIdlePill: Bool = false) {
        self.now = now
        self.showIdlePill = showIdlePill
    }

    public var isVisible: Bool { phase != .hidden || showIdlePill }
    public var isIdle: Bool { phase == .hidden }
    public var isDegraded: Bool {
        if case .degraded = phase { return true }
        return notice != nil && phase.isActive
    }
    public var wordCount: Int {
        SuperflowKernel.wordCount(partial) + SuperflowKernel.wordCount(systemPartial)
    }
    public var modeLabel: String {
        if case .listening(let mode) = phase { return mode.label }
        switch phase {
        case .warming: return "Warming up"
        case .finalizing: return "Finishing"
        case .complete: return "Inserted"
        case .degraded: return "Needs attention"
        case .failed: return "Needs attention"
        case .hidden: return ""
        case .listening: return ""
        }
    }

    /// The concrete reason behind "Needs attention". The compact pill used to show only the
    /// generic label, so a refused start or a degraded session looked like a mystery; the engine
    /// already knows why, so surface it next to the label.
    public var reason: String? {
        switch phase {
        case .failed(let message) where !message.isEmpty: return message
        case .degraded(let message) where !message.isEmpty: return message
        default: return notice
        }
    }

    public var elapsedLabel: String {
        let seconds = max(0, elapsedMs) / 1000
        let minutes = seconds / 60
        return String(format: "%d:%02d", minutes, seconds % 60)
    }

    public var partialLines: [String] {
        let text = [partial, systemPartial].filter { !$0.isEmpty }.joined(separator: "\n")
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return Array(lines.suffix(4))
    }

    public func handle(_ event: SessionEvent) {
        switch event {
        case .state(let state):
            apply(state)
        case .partial(let text):
            partial = text
        case .level(let value):
            appendLevel(value)
        case .progress(let value):
            progress = min(1, max(0, value))
        case .notice(let text):
            notice = text
        case .inserted:
            phase = .complete
            completionUntil = now().addingTimeInterval(1.8)
        case .finished:
            freezeElapsed()
        }
    }

    public func handle(_ event: MeetingEvent) {
        switch event {
        case .state(let state):
            apply(state)
        case .partial(let source, let text):
            if source == .mic { partial = text } else { systemPartial = text }
        case .level(_, let value):
            appendLevel(value)
        case .notice(let text):
            notice = text
        case .finished:
            freezeElapsed()
        }
    }

    public func tick() {
        if let completionUntil, now() >= completionUntil {
            reset()
            return
        }
        guard phase.isActive, let startedAt else { return }
        elapsedMs = max(0, Int((now().timeIntervalSince(startedAt) * 1000).rounded()))
    }

    public func toggleExpanded() {
        guard phase != .hidden else { return }
        isExpanded.toggle()
    }

    public func setShowIdlePill(_ enabled: Bool) {
        showIdlePill = enabled
        if !enabled, phase == .hidden { isExpanded = false }
    }

    /// Non-fatal degradation (for example basic cleanup only, or a lost system
    /// audio source). The session keeps running; the Island surfaces the notice.
    public func degrade(_ message: String) {
        notice = message
        phase = .degraded(message)
    }

    public func reset() {
        phase = .hidden
        elapsedMs = 0
        frozenElapsedMs = 0
        partial = ""
        systemPartial = ""
        levels = []
        notice = nil
        progress = 0
        isExpanded = false
        startedAt = nil
        completionUntil = nil
        lastLevelAt = nil
    }

    private func apply(_ state: SessionState) {
        switch state {
        case .idle:
            if case .complete = phase { return }
            if case .failed = phase { return }
            reset()
        case .warming:
            phase = .warming
            startedAt = now()
            completionUntil = nil
        case .recording(let mode):
            phase = .listening(mode == .dictation ? .dictation : .handsFree)
            startedAt = now()
            completionUntil = nil
            notice = nil
        case .finalizing:
            phase = .finalizing
            freezeElapsed()
        case .inserting:
            phase = .finalizing
            freezeElapsed()
        case .complete:
            phase = .complete
            freezeElapsed()
            completionUntil = now().addingTimeInterval(1.8)
        case .cancelled:
            reset()
        case .failed(_, let message):
            phase = .failed(message)
            freezeElapsed()
            completionUntil = now().addingTimeInterval(4)
        }
    }

    private func apply(_ state: MeetingState) {
        switch state {
        case .idle:
            if case .complete = phase { return }
            if case .failed = phase { return }
            reset()
        case .warming:
            phase = .warming
            startedAt = now()
            completionUntil = nil
        case .recording:
            phase = .listening(.meeting)
            startedAt = now()
            completionUntil = nil
            notice = nil
        case .finalizing:
            phase = .finalizing
            freezeElapsed()
        case .complete:
            phase = .complete
            freezeElapsed()
            completionUntil = now().addingTimeInterval(1.8)
        case .cancelled:
            reset()
        case .failed(let message):
            phase = .failed(message)
            freezeElapsed()
            completionUntil = now().addingTimeInterval(4)
        }
    }

    private func appendLevel(_ value: Float) {
        let timestamp = now()
        if let lastLevelAt, timestamp.timeIntervalSince(lastLevelAt) < levelInterval { return }
        lastLevelAt = timestamp
        levels.append(min(1, max(0, value)))
        if levels.count > maxLevels { levels.removeFirst(levels.count - maxLevels) }
    }

    private func freezeElapsed() {
        if let startedAt {
            frozenElapsedMs = max(frozenElapsedMs, Int(now().timeIntervalSince(startedAt) * 1000))
            elapsedMs = frozenElapsedMs
        }
    }
}
