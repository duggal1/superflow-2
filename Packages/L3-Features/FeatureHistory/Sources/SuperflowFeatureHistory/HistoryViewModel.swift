import Combine
import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

public enum HistoryFilter: String, CaseIterable, Sendable {
    case all, dictation, meetings

    public var label: String {
        switch self {
        case .all: "All"
        case .dictation: "Dictation"
        case .meetings: "Meetings"
        }
    }

    public var kind: SessionKind? {
        switch self {
        case .all: nil
        case .dictation: .dictation
        case .meetings: .meeting
        }
    }
}

@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public private(set) var sessions: [SessionRecord] = []
    @Published public private(set) var segments: [Segment] = []
    @Published public private(set) var speakers: [SpeakerRecord] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var hasMore = false
    @Published public private(set) var error: String?
    @Published public var query = ""
    @Published public var filter: HistoryFilter = .all
    @Published public var showRaw = false
    @Published public private(set) var selectedID: SessionID?

    public let toast: ToastCenter
    private let repository: any TranscriptRepository
    private let inserter: any TextInserter
    private let pageSize: Int
    private let onDeleteAudio: (@Sendable (SessionID) async -> Void)?
    private var offset = 0
    private var deleted: DeletedSession?
    /// The file outlives the row until the undo toast expires.
    private var pendingAudioDeletion: Task<Void, Never>?
    private var changes: AnyCancellable?
    private var loadChain: Task<Void, Never>?

    private struct DeletedSession {
        var record: SessionRecord
        var segments: [Segment]
        var speakers: [SpeakerRecord]
    }

    public init(repository: any TranscriptRepository, inserter: any TextInserter,
                toast: ToastCenter = ToastCenter(), pageSize: Int = 40,
                onDeleteAudio: (@Sendable (SessionID) async -> Void)? = nil) {
        self.repository = repository
        self.inserter = inserter
        self.toast = toast
        self.pageSize = max(1, pageSize)
        self.onDeleteAudio = onDeleteAudio
        changes = NotificationCenter.default.publisher(for: .superflowTranscriptsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.load() }
            }
    }

    public var selectedSession: SessionRecord? {
        sessions.first { $0.id == selectedID }
    }

    public var selectedSpeakerNames: [String: String] {
        Dictionary(speakers.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
    }

    public var fullText: String {
        segments.map { segment in
            let text = showRaw ? segment.rawText : segment.bestText
            if let speaker = segment.speakerID, let name = selectedSpeakerNames[speaker] {
                return "\(name): \(text)"
            }
            return text
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    public var isEmpty: Bool { !isLoading && sessions.isEmpty }

    public func load(reset: Bool = true) async {
        // A finished dictation posts a change while the page may already be
        // loading. Chain instead of dropping: an awaiting caller has to see the
        // state that includes the change, not whichever fetch happened to be in
        // flight when it asked.
        let previous = loadChain
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.performLoad(reset: reset)
        }
        loadChain = task
        await task.value
        if loadChain == task { loadChain = nil }
    }

    private func performLoad(reset: Bool) async {
        isLoading = true
        error = nil
        if reset { offset = 0 }
        defer { isLoading = false }
        do {
            let page = try await repository.sessions(kind: filter.kind,
                                                     query: query.isEmpty ? nil : query,
                                                     limit: pageSize, offset: offset)
            sessions = reset ? page : sessions + page
            offset += page.count
            hasMore = page.count == pageSize
            if let selectedID, !sessions.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
                segments = []
                speakers = []
            }
            if selectedID == nil, let first = sessions.first {
                await select(first.id)
            }
        } catch {
            self.error = "Could not load history. \(error.localizedDescription)"
        }
    }

    public func loadMore() async {
        guard hasMore, !isLoading else { return }
        await load(reset: false)
    }

    public func select(_ id: SessionID) async {
        selectedID = id
        showRaw = false
        do {
            segments = try await repository.segments(session: id)
            speakers = try await repository.speakers(session: id)
        } catch {
            self.error = "Could not load this session. \(error.localizedDescription)"
        }
    }

    public func selectNext() async {
        guard let index = sessions.firstIndex(where: { $0.id == selectedID }),
              index + 1 < sessions.count else { return }
        await select(sessions[index + 1].id)
    }

    public func selectPrevious() async {
        guard let index = sessions.firstIndex(where: { $0.id == selectedID }),
              index > 0 else { return }
        await select(sessions[index - 1].id)
    }

    public func copySelected() async {
        let text = fullText
        guard !text.isEmpty else { return }
        do {
            _ = try await inserter.insert(text, strategy: .clipboardOnly)
            toast.show("Copied to the clipboard.", style: .success)
        } catch {
            toast.show("Could not copy. \(error.localizedDescription)", style: .error)
        }
    }

    public func deleteSelected() async {
        guard let record = selectedSession else { return }
        do {
            let segments = try await repository.segments(session: record.id)
            let speakers = try await repository.speakers(session: record.id)
            deleted = DeletedSession(record: record, segments: segments, speakers: speakers)
            try await repository.deleteSession(record.id)
            try? await repository.addDailyStat(DailyStat(day: record.localDay,
                                                          words: -record.wordCount,
                                                          audioMs: -record.durationMs,
                                                          sessions: -1))
            selectedID = nil
            self.segments = []
            self.speakers = []
            let deletedID = record.id
            await load()
            let deleteAudio = onDeleteAudio
            pendingAudioDeletion?.cancel()
            pendingAudioDeletion = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                await deleteAudio?(deletedID)
                self?.pendingAudioDeletion = nil
            }
            toast.show("Session deleted.", style: .info, actionTitle: "Undo") { [weak self] in
                Task { await self?.undoDelete() }
            }
        } catch {
            self.error = "Could not delete this session. \(error.localizedDescription)"
        }
    }

    public func undoDelete() async {
        pendingAudioDeletion?.cancel()
        pendingAudioDeletion = nil
        guard let deleted else { return }
        do {
            try await repository.createSession(deleted.record)
            for segment in deleted.segments { try await repository.appendSegment(segment) }
            for speaker in deleted.speakers { try await repository.upsertSpeaker(speaker) }
            try? await repository.addDailyStat(DailyStat(day: deleted.record.localDay,
                                                          words: deleted.record.wordCount,
                                                          audioMs: deleted.record.durationMs,
                                                          sessions: 1))
            self.deleted = nil
            await load()
            await select(deleted.record.id)
            toast.show("Session restored.", style: .success)
        } catch {
            self.error = "Could not restore this session. \(error.localizedDescription)"
        }
    }

    public func displayText(for segment: Segment) -> String {
        showRaw ? segment.rawText : segment.bestText
    }

    public func speakerName(for segment: Segment) -> String? {
        guard let id = segment.speakerID else { return nil }
        return selectedSpeakerNames[id]
    }
}
