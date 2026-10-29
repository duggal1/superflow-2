import AppKit
import Foundation
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class PastMeetingsModel: ObservableObject {
    public struct DayGroup: Identifiable {
        public var id: Date { day }
        public let day: Date
        public let sessions: [SessionRecord]
    }
    @Published public var query = ""
    @Published public private(set) var sessions: [SessionRecord] = []
    @Published public private(set) var selectedID: SessionID?
    @Published public private(set) var selectedDocument: MeetingDocument?
    @Published public private(set) var barcodes: [SessionID: [MeetingTurn]] = [:]
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    public let toast: ToastCenter
    private let repository: any TranscriptRepository
    private let inserter: any TextInserter
    private let undoDelay: Duration
    private var hidden = Set<SessionID>()
    private var pending: [SessionID: Task<Void, Never>] = [:]
    private var request = 0
    private var selectionRequest = 0

    public init(repository: any TranscriptRepository, inserter: any TextInserter,
                toast: ToastCenter = ToastCenter(), undoDelay: Duration = .seconds(6)) {
        self.repository = repository; self.inserter = inserter
        self.toast = toast; self.undoDelay = undoDelay
    }

    public var groups: [DayGroup] {
        Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.startedAt) }
            .map { DayGroup(day: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    public func reload() async {
        request += 1
        let token = request
        isLoading = true; error = nil
        defer { if token == request { isLoading = false } }
        do {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            var records: [SessionRecord] = []
            var offset = 0
            while true {
                let page = try await repository.sessions(kind: .meeting, query: text.isEmpty ? nil : text,
                                                          limit: 100, offset: offset)
                try Task.checkCancellation()
                guard token == request else { return }
                records += page.filter { !hidden.contains($0.id) }
                if page.count < 100 { break }
                offset += page.count
            }
            sessions = records
            if let selectedID, records.contains(where: { $0.id == selectedID }) { return }
            if let first = records.first { await select(first.id) }
            else { selectedID = nil; selectedDocument = nil }
        } catch is CancellationError {} catch {
            if token == request { self.error = "Could not load past meetings." }
        }
    }

    public func select(_ id: SessionID) async {
        selectionRequest += 1
        let token = selectionRequest
        selectedID = id
        do {
            guard let record = try await repository.session(id) else { selectedDocument = nil; return }
            let segments = try await repository.segments(session: id)
            let speakers = try await repository.speakers(session: id)
            guard token == selectionRequest, !hidden.contains(id) else { return }
            let document = MeetingProjection.document(record: record, segments: segments, speakers: speakers)
            selectedDocument = document
            barcodes[id] = document.turns
        } catch { self.error = "Could not load this meeting." }
    }

    public func loadBarcode(for id: SessionID) async {
        guard barcodes[id] == nil, let record = try? await repository.session(id) else { return }
        do {
            let segments = try await repository.segments(session: id)
            let speakers = try await repository.speakers(session: id)
            guard !hidden.contains(id) else { return }
            barcodes[id] = MeetingProjection.document(record: record, segments: segments, speakers: speakers).turns
        } catch { self.error = "Could not load the meeting timeline." }
    }

    public func rename(_ id: SessionID, to title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            try await repository.renameSession(id, title: title)
            if let index = sessions.firstIndex(where: { $0.id == id }) { sessions[index].title = title }
            if selectedID == id { selectedDocument?.title = title }
        } catch { toast.show("Could not rename the meeting.", style: .error) }
    }

    public func renameSpeaker(id: String, label: String) async {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var document = selectedDocument else { return }
        do {
            try await repository.renameSpeaker(session: document.sessionID, id: id, label: name)
            for index in document.speakers.indices where document.speakers[index].id == id {
                document.speakers[index].name = name
            }
            for index in document.turns.indices where document.turns[index].speakerID == id {
                document.turns[index].speakerName = name
            }
            barcodes[document.sessionID] = document.turns
            if selectedID == document.sessionID { selectedDocument = document }
        } catch { toast.show("Could not rename the speaker.", style: .error) }
    }

    public func copyMarkdown(_ document: MeetingDocument) async -> Bool {
        do {
            _ = try await inserter.insert(MeetingExport.markdown(document), strategy: .clipboardOnly)
            return true
        } catch { toast.show("Could not copy the meeting.", style: .error); return false }
    }

    public func export(_ document: MeetingDocument, json: Bool) {
        do {
            let data = json ? try MeetingExport.jsonData(document) : Data(MeetingExport.markdown(document).utf8)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [json ? .json : (UTType(filenameExtension: "md") ?? .plainText)]
            panel.nameFieldStringValue = "\(document.title).\(json ? "json" : "md")"
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                do { try data.write(to: url, options: .atomic) }
                catch { self?.toast.show("Could not export the meeting.", style: .error) }
            }
        } catch { toast.show("Could not prepare the export.", style: .error) }
    }

    public func delete(_ document: MeetingDocument) {
        let id = document.sessionID
        guard pending[id] == nil, let record = sessions.first(where: { $0.id == id }) else { return }
        hidden.insert(id)
        sessions.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = nil; selectedDocument = nil
            if let next = sessions.first { Task { await select(next.id) } }
        }
        pending[id] = Task { [weak self] in
            guard let delay = self?.undoDelay else { return }
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.pending[id] = nil
            do {
                try await self.repository.deleteSession(id)
                self.barcodes[id] = nil
                self.hidden.remove(id)
            } catch {
                self.restore(record, document: document)
                self.toast.show("Could not delete the meeting.", style: .error)
            }
        }
        toast.show("Meeting deleted", actionTitle: "Undo", duration: 6) { [weak self] in
            guard let self, let task = self.pending.removeValue(forKey: id) else { return }
            task.cancel()
            self.restore(record, document: document)
        }
    }

    func absorb(_ document: MeetingDocument) async {
        selectedID = document.sessionID; selectedDocument = document
        barcodes[document.sessionID] = document.turns
        if !sessions.contains(where: { $0.id == document.sessionID }),
           let record = try? await repository.session(document.sessionID) {
            sessions.insert(record, at: 0)
        }
    }

    private func restore(_ record: SessionRecord, document: MeetingDocument) {
        hidden.remove(record.id)
        if !sessions.contains(where: { $0.id == record.id }) { sessions.append(record) }
        sessions.sort { $0.startedAt > $1.startedAt }
        selectedID = record.id; selectedDocument = document
        barcodes[record.id] = document.turns
    }
}
