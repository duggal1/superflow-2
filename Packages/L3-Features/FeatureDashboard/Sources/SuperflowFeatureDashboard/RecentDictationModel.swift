import AppKit
import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

public struct RecentDictationEntry: Identifiable, Equatable, Sendable {
    public var id: SessionID { record.id }
    public var record: SessionRecord
    public var raw: String
    public var cleaned: String
    public var audio: URL?
    public var retrying = false
    public var failure: String?
}

@MainActor
public final class RecentDictationViewModel: ObservableObject {
    public typealias Retry = @Sendable (URL) async throws -> (raw: String, cleaned: String)
    @Published public private(set) var entries: [RecentDictationEntry] = []
    @Published public var expandedID: SessionID?
    @Published public private(set) var playingID: SessionID?
    @Published public private(set) var error: String?
    public let toast = ToastCenter()
    /// One player for the whole list: one engine, only one row ever plays.
    public let audio = ClipPlayer()
    private let repository: any TranscriptRepository
    private var retryHandler: Retry?
    private var pending: [SessionID: Task<Void, Never>] = [:]
    private var retryTasks: [SessionID: Task<Void, Never>] = [:]
    private var hidden = Set<SessionID>()
    private var settings = AppSettings.default

    public init(repository: any TranscriptRepository, retry: Retry? = nil) {
        self.repository = repository
        retryHandler = retry
    }

    public var canRetry: Bool { retryHandler != nil }
    public func configureRetry(_ handler: @escaping Retry) { retryHandler = handler }

    public func load(settings: AppSettings) async {
        self.settings = settings
        guard !settings.noTranscriptStorage else {
            retryTasks.values.forEach { $0.cancel() }
            entries = []; stopPlayback(); return
        }
        do {
            let records = try await repository.sessions(kind: .dictation, query: nil, limit: 24, offset: 0)
            var loaded: [RecentDictationEntry] = []
            for record in records where !hidden.contains(record.id)
                && (record.wordCount > 0 || record.status != .complete) {
                guard loaded.count < 5 else { break }
                let segments = try await repository.segments(session: record.id).sorted { $0.index < $1.index }
                let url = AudioArchiveLocation.url(for: record.id)
                loaded.append(RecentDictationEntry(record: record,
                    raw: segments.map(\.rawText).joined(separator: "\n"),
                    cleaned: segments.map(\.bestText).joined(separator: "\n"),
                    audio: settings.keepAudio && FileManager.default.fileExists(atPath: url.path) ? url : nil,
                    retrying: retryTasks[record.id] != nil))
            }
            entries = loaded
            if let playingID, !entries.contains(where: { $0.id == playingID }) { stopPlayback() }
        } catch { self.error = "Could not load recent dictation." }
    }

    public func toggle(_ id: SessionID) { expandedID = expandedID == id ? nil : id }

    public func play(_ entry: RecentDictationEntry) {
        guard entry.audio != nil else { return }
        audio.stop()
        playingID = entry.id
    }

    public func stopPlayback() {
        audio.stop()
        playingID = nil
    }
    public func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toast.show("Copied to the clipboard.", style: .success)
    }

    public func retry(_ entry: RecentDictationEntry) {
        guard let url = entry.audio, let retryHandler, retryTasks[entry.id] == nil else { return }
        if playingID == entry.id { stopPlayback() }
        edit(entry.id) { $0.retrying = true; $0.failure = nil }
        retryTasks[entry.id] = Task { [weak self] in
            guard let self else { return }
            defer { retryTasks[entry.id] = nil; edit(entry.id) { $0.retrying = false } }
            do {
                let result = try await retryHandler(url)
                try Task.checkCancellation()
                guard !hidden.contains(entry.id), !settings.noTranscriptStorage else { return }
                guard !result.cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    await failRetry(entry, message: "No speech found.")
                    return
                }
                let old = try await repository.segments(session: entry.id)
                let first = old.first?.index ?? 0
                if old.isEmpty {
                    try await repository.appendSegment(Segment(sessionID: entry.id, index: first,
                        startMs: 0, endMs: entry.record.durationMs, source: .mic,
                        rawText: result.raw, cleanedText: result.cleaned, cleanupState: .cleaned))
                } else {
                    for var segment in old {
                        segment.rawText = segment.index == first ? result.raw : ""
                        segment.cleanedText = segment.index == first ? result.cleaned : ""
                        segment.cleanupState = .cleaned
                        try await repository.appendSegment(segment)
                    }
                }
                var record = entry.record
                record.wordCount = result.cleaned.split(whereSeparator: \.isWhitespace).count
                record.status = .complete
                record.cleanupState = .cleaned
                try await repository.finalizeSession(entry.id, endedAt: record.endedAt ?? Date(), status: .complete,
                    durationMs: record.durationMs, wordCount: record.wordCount, cleanupState: .cleaned)
                try? await repository.addDailyStat(DailyStat(day: record.localDay,
                    words: record.wordCount - entry.record.wordCount, audioMs: 0, sessions: 0))
                edit(entry.id) { $0.record = record; $0.raw = result.raw; $0.cleaned = result.cleaned }
            } catch is CancellationError {} catch { await failRetry(entry, message: "Transcription failed.") }
        }
    }

    private func failRetry(_ entry: RecentDictationEntry, message: String) async {
        do {
            try await repository.finalizeSession(entry.id, endedAt: entry.record.endedAt ?? Date(),
                status: .failed, durationMs: entry.record.durationMs, wordCount: entry.record.wordCount,
                cleanupState: entry.record.cleanupState)
        } catch { self.error = "Could not save the retry status." }
        edit(entry.id) { $0.record.status = .failed; $0.failure = message }
    }

    public func delete(_ entry: RecentDictationEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        if playingID == entry.id { stopPlayback() }
        retryTasks[entry.id]?.cancel()
        hidden.insert(entry.id)
        entries.remove(at: index)
        pending[entry.id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            do {
                try await repository.deleteSession(entry.id)
                try? await repository.addDailyStat(DailyStat(day: entry.record.localDay,
                    words: -entry.record.wordCount, audioMs: -entry.record.durationMs, sessions: -1))
                if let audio = entry.audio { try? FileManager.default.removeItem(at: audio) }
                pending[entry.id] = nil
            } catch {
                hidden.remove(entry.id)
                entries.insert(entry, at: min(index, entries.count))
                pending[entry.id] = nil
                toast.show("Could not delete transcript.", style: .error)
            }
        }
        toast.show("Transcript deleted", actionTitle: "Undo") { [weak self] in
            guard let self, pending[entry.id] != nil else { return }
            pending[entry.id]?.cancel(); pending[entry.id] = nil
            hidden.remove(entry.id)
            entries.insert(entry, at: min(index, entries.count))
        }
    }

    public func extractAudio(_ entry: RecentDictationEntry) {
        guard let source = entry.audio else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = "Superflow \(entry.id.short).m4a"
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url, destination != source else { return }
            do {
                let data = try Data(contentsOf: source)
                try data.write(to: destination, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { self?.toast.show("Could not export audio.", style: .error) }
        }
    }

    private func edit(_ id: SessionID, _ change: (inout RecentDictationEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }
}
