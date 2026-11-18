import Foundation
import SuperflowKernel

public enum TranscriptExportError: Error, LocalizedError, Equatable {
    case sessionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id): "No session with id \(id) to export"
        }
    }
}

public extension SQLiteStore {
    /// Builds the versioned document for one session. Metadata, speakers and
    /// segments all come from the same serialized store, so the projection is
    /// internally consistent.
    func exportDocument(session id: SessionID) async throws -> TranscriptExportDocument {
        guard let session = try await session(id) else {
            throw TranscriptExportError.sessionNotFound(id.value)
        }
        let speakers = try await self.speakers(session: id)
        let segments = try await self.segments(session: id)
        return TranscriptExporter.document(session: session,
                                            speakers: speakers, segments: segments)
    }

    func exportJSON(session id: SessionID) async throws -> Data {
        let document = try await exportDocument(session: id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    func exportMarkdown(session id: SessionID) async throws -> String {
        let document = try await exportDocument(session: id)
        return TranscriptExporter.markdown(document)
    }
}
