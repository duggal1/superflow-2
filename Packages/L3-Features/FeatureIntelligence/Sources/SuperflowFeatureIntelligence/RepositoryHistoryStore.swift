import Foundation
import SuperflowKernel
import SuperflowPorts

/// Wraps the app's existing transcript repository. No new database, no new
/// schema: the Island's history list/search/open/delete all read and write
/// through the same `TranscriptRepository` the rest of the app uses.
public struct RepositoryHistoryStore: IntelligenceHistoryServing {
    private let repository: any TranscriptRepository
    private let limit: Int

    public init(repository: any TranscriptRepository, limit: Int = 200) {
        self.repository = repository
        self.limit = max(1, limit)
    }

    public func list(query: String?, limit: Int) async throws -> [IntelligenceHistoryItem] {
        let records = try await repository.sessions(kind: nil, query: normalized(query),
                                                   limit: min(max(1, limit), self.limit), offset: 0)
        return records.map { record in
            IntelligenceHistoryItem(
                id: record.id,
                title: record.title ?? record.kind.label,
                preview: record.preview ?? "",
                date: record.startedAt,
                wordCount: record.wordCount,
                fullText: record.preview ?? ""
            )
        }
    }

    public func detail(id: SessionID) async throws -> IntelligenceHistoryItem? {
        guard let record = try await repository.session(id) else { return nil }
        let segments = try await repository.segments(session: id)
        let text = segments.map(\.bestText)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return IntelligenceHistoryItem(
            id: record.id,
            title: record.title ?? record.kind.label,
            preview: record.preview ?? "",
            date: record.startedAt,
            wordCount: record.wordCount,
            fullText: text
        )
    }

    public func delete(id: SessionID) async throws {
        try await repository.deleteSession(id)
    }

    private func normalized(_ query: String?) -> String? {
        let value = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
