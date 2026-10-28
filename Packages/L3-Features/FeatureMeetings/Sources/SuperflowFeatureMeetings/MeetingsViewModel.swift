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
    @Published public private(set) var state: MeetingState = .idle
    @Published public private(set) var elapsedMs = 0
    @Published public private(set) var micPartial = ""
    @Published public private(set) var systemPartial = ""
    @Published public private(set) var micLevels: [Float] = []
    @Published public private(set) var systemLevels: [Float] = []
    @Published public private(set) var notice: String?
    @Published public private(set) var pastSessions: [SessionRecord] = []
    @Published public private(set) var selectedID: SessionID?
    @Published public private(set) var selectedDocument: MeetingDocument?
    @Published public private(set) var barcodes: [SessionID: [MeetingTurn]] = [:]
    @Published public private(set) var isLoadingPast = false
    @Published public private(set) var error: String?
    @Published public var tab: MeetingsTab = .live
    @Published public var pastQuery = ""

    public let toast: ToastCenter
    private let engine: MeetingEngine?
    private let events: AsyncStream<MeetingEvent>?
    private let repository: any TranscriptRepository
    private let inserter: any TextInserter
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
        self.repository = repository
        self.inserter = inserter
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

    public var selectedSpeakers: [MeetingSpeaker] { selectedDocument?.speakers ?? [] }
    public var isEmptyPast: Bool { !isLoadingPast && pastSessions.isEmpty }

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

    public func loadPast() async {
        guard !isLoadingPast else { return }
        isLoadingPast = true
        error = nil
        defer { isLoadingPast = false }
        do {
            let query = pastQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            pastSessions = try await repository.sessions(kind: .meeting,
                                                         query: query.isEmpty ? nil : query,
                                                         limit: 100, offset: 0)
            if let selectedID, pastSessions.contains(where: { $0.id == selectedID }) {
                return
            }
            if let first = pastSessions.first {
                await select(first.id)
            } else {
                selectedID = nil
                selectedDocument = nil
            }
        } catch {
            self.error = "Could not load past meetings. \(error.localizedDescription)"
        }
    }

    public func select(_ id: SessionID) async {
        selectedID = id
        do {
            guard let record = try await repository.session(id) else {
                selectedDocument = nil
                return
            }
            let segments = try await repository.segments(session: id)
            let speakers = try await repository.speakers(session: id)
            let document = Self.document(record: record, segments: segments, speakers: speakers)
            selectedDocument = document
            barcodes[id] = document.turns
        } catch {
            self.error = "Could not load this meeting. \(error.localizedDescription)"
        }
    }

    /// The list shows the shape of every meeting, not only the selected one. Turns
    /// are small and cached per session so scrolling never refetches them.
    public func loadBarcode(for id: SessionID) async {
        guard barcodes[id] == nil else { return }
        guard let record = try? await repository.session(id) else { return }
        let segments = (try? await repository.segments(session: id)) ?? []
        let speakers = (try? await repository.speakers(session: id)) ?? []
        barcodes[id] = Self.document(record: record, segments: segments, speakers: speakers).turns
    }

    public func renameSpeaker(id: String, label: String) async {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let document = selectedDocument else { return }
        do {
            try await repository.renameSpeaker(session: document.sessionID, id: id, label: name)
            var updated = document
            for index in updated.speakers.indices where updated.speakers[index].id == id {
                updated.speakers[index].name = name
            }
            for index in updated.turns.indices where updated.turns[index].speakerID == id {
                updated.turns[index].speakerName = name
            }
            selectedDocument = updated
            toast.show("Speaker renamed to “\(name)”.", style: .success)
        } catch {
            toast.show("Could not rename this speaker. \(error.localizedDescription)", style: .error)
        }
    }

    public func copySelected() async {
        guard let document = selectedDocument else { return }
        do {
            _ = try await inserter.insert(MeetingExport.markdown(document), strategy: .clipboardOnly)
            toast.show("Meeting copied as Markdown.", style: .success)
        } catch {
            toast.show("Could not copy this meeting. \(error.localizedDescription)", style: .error)
        }
    }

    public func markdownExport() -> Data? {
        selectedDocument.map { Data(MeetingExport.markdown($0).utf8) }
    }

    public func jsonExport() -> Data? {
        guard let document = selectedDocument else { return nil }
        do {
            return try MeetingExport.jsonData(document)
        } catch {
            toast.show("Could not build the JSON export. \(error.localizedDescription)", style: .error)
            return nil
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
        selectedID = document.sessionID
        selectedDocument = document
        if !pastSessions.contains(where: { $0.id == document.sessionID }),
           let record = try? await repository.session(document.sessionID) {
            pastSessions.insert(record, at: 0)
        }
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

    private static func document(record: SessionRecord, segments: [Segment],
                                 speakers: [SpeakerRecord]) -> MeetingDocument {
        let names = Dictionary(speakers.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let meetingSpeakers = speakers.map { speaker in
            seen.insert(speaker.id)
            return MeetingSpeaker(id: speaker.id, name: speaker.label, isSelf: speaker.isSelf)
        }
        let turns = segments.map { segment -> MeetingTurn in
            let speakerID = segment.speakerID ?? (segment.source == .mic ? "self" : "remote-1")
            let isGap = segment.rawText.hasPrefix("[") && segment.rawText.hasSuffix("]")
            let text = isGap ? String(segment.rawText.dropFirst().dropLast()) : segment.bestText
            return MeetingTurn(index: segment.index, speakerID: speakerID,
                               speakerName: names[speakerID] ?? (speakerID == "self" ? "You" : speakerID),
                               startMs: segment.startMs, endMs: segment.endMs, text: text,
                               rawText: segment.rawText, source: segment.source, isGap: isGap)
        }
        var allSpeakers = meetingSpeakers
        for turn in turns where !turn.isGap && !seen.contains(turn.speakerID) {
            seen.insert(turn.speakerID)
            allSpeakers.append(MeetingSpeaker(id: turn.speakerID, name: turn.speakerName,
                                              isSelf: turn.speakerID == "self"))
        }
        return MeetingDocument(sessionID: record.id,
                               title: record.title ?? record.displayTitle,
                               startedAt: record.startedAt, endedAt: record.endedAt,
                               durationMs: record.durationMs, speakers: allSpeakers, turns: turns)
    }
}
