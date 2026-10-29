import Foundation
import SuperflowDesignSystem
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

public enum MeetingsTab: String, CaseIterable, Sendable {
    case live, past

    public var label: String {
        switch self {
        case .live: "Live"
        case .past: "Past meetings"
        }
    }
}

@MainActor
public final class MeetingsViewModel: ObservableObject {
    @Published public var tab: MeetingsTab = .live
    @Published public private(set) var state: MeetingState = .idle
    @Published public private(set) var elapsedMs = 0
    @Published public private(set) var micPartial = ""
    @Published public private(set) var systemPartial = ""
    @Published public private(set) var micLevels: [Float] = []
    @Published public private(set) var systemLevels: [Float] = []
    @Published public private(set) var notice: String?
    public let past: PastMeetingsModel

    public let toast: ToastCenter
    private let engine: MeetingEngine?
    private let events: AsyncStream<MeetingEvent>?
    private let now: () -> Date
    private var eventTask: Task<Void, Never>?
    private var startedAt: Date?
    private let maxLevels = 48

    public init(engine: MeetingEngine?, repository: any TranscriptRepository,
                inserter: any TextInserter, toast: ToastCenter = ToastCenter(),
                events: AsyncStream<MeetingEvent>? = nil,
                now: @escaping () -> Date = { Date() }) {
        self.engine = engine
        self.events = events
        self.past = PastMeetingsModel(repository: repository, inserter: inserter, toast: toast)
        self.toast = toast
        self.now = now
    }

    public var isActive: Bool { state.isActive }
    public var isRecording: Bool { state == .recording }
    public var canStart: Bool { engine != nil && !state.isActive }
    public var hasLiveContent: Bool { !micPartial.isEmpty || !systemPartial.isEmpty }
    public var micWordCount: Int { wordCount(micPartial) }
    public var systemWordCount: Int { wordCount(systemPartial) }

    public var elapsedLabel: String {
        let seconds = max(0, elapsedMs) / 1000
        let minutes = seconds / 60
        return String(format: "%d:%02d", minutes, seconds % 60)
    }

    public var statusLabel: String {
        switch state {
        case .idle: "Ready"
        case .warming: "Loading model"
        case .recording: "Recording"
        case .finalizing: "Finishing"
        case .complete: "Saved"
        case .cancelled: "Cancelled"
        case .failed: "Needs attention"
        }
    }

    public var statusTone: DotTone {
        switch state {
        case .idle: .neutral
        case .warming, .finalizing: .orange
        case .recording: .rose
        case .complete: .green
        case .cancelled: .neutral
        case .failed: .rose
        }
    }


    public func observe() async {
        guard eventTask == nil, let engine else { return }
        state = await engine.currentState
        if let document = await engine.currentDocument {
            startedAt = document.startedAt
            micPartial = document.turns.filter { $0.source == .mic }.map(\.text).joined(separator: " ")
            systemPartial = document.turns.filter { $0.source == .system }.map(\.text).joined(separator: " ")
        }
        let events = self.events ?? engine.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    public func start() async {
        guard let engine else {
            toast.show("Meeting capture is unavailable.", style: .warning)
            return
        }
        await observe()
        notice = nil
        micPartial = ""
        systemPartial = ""
        micLevels = []
        systemLevels = []
        elapsedMs = 0
        do {
            _ = try await engine.start()
            startedAt = now()
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
            toast.show("Could not start the meeting. \(error.localizedDescription)", style: .error)
        }
    }

    @discardableResult
    public func stop() async -> MeetingDocument? {
        guard let engine, state == .recording else { return nil }
        let document = await engine.stop()
        if let document { await absorb(document) }
        return document
    }

    public func cancel() async {
        guard let engine, state.isActive else { return }
        await engine.cancel()
        resetLive()
        state = .cancelled(nil)
    }

    public func tick() {
        guard let startedAt, state == .recording || state == .warming else { return }
        elapsedMs = max(0, Int(now().timeIntervalSince(startedAt) * 1000))
    }

    public func handle(_ event: MeetingEvent) async {
        switch event {
        case .state(let next):
            apply(next)
        case .partial(let source, let text):
            if source == .mic { micPartial = text } else { systemPartial = text }
        case .level(let source, let value):
            let clamped = min(1, max(0, value))
            if source == .mic {
                micLevels.append(clamped)
                if micLevels.count > maxLevels { micLevels.removeFirst(micLevels.count - maxLevels) }
            } else {
                systemLevels.append(clamped)
                if systemLevels.count > maxLevels { systemLevels.removeFirst(systemLevels.count - maxLevels) }
            }
        case .notice(let text):
            notice = text
        case .finished(_, let document):
            await absorb(document)
        }
    }

    // MARK: projection

    private func apply(_ next: MeetingState) {
        switch next {
        case .idle:
            state = .idle
            startedAt = nil
        case .warming:
            if case .recording = state { return }
            if case .finalizing = state { return }
            if case .complete = state { return }
            state = .warming
        case .recording:
            if case .complete = state { return }
            if case .finalizing = state { return }
            state = .recording
            if startedAt == nil { startedAt = now() }
        case .finalizing:
            if case .complete = state { return }
            state = .finalizing
        case .complete, .cancelled, .failed:
            state = next
            startedAt = nil
        }
    }

    private func absorb(_ document: MeetingDocument) async {
        state = .complete(document.sessionID)
        startedAt = nil
        elapsedMs = max(elapsedMs, document.durationMs)
        if let last = document.notices.last { notice = last }
        await past.absorb(document)
    }

    private func resetLive() {
        startedAt = nil
        elapsedMs = 0
        micPartial = ""
        systemPartial = ""
        micLevels = []
        systemLevels = []
        notice = nil
    }

}
