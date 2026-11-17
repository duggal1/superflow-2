import Foundation
import SuperflowKernel

/// The one seam the model talks to. Replaceable in headless tests; the real
/// adapter (`ReflectionAnswerService`) wraps the existing Reflection client,
/// screen reader, transcript buffer and prompt library without rewriting them.
@MainActor
public protocol IntelligenceAnswerServing: AnyObject {
    var onEvent: ((IntelligenceAnswerEvent) -> Void)? { get set }
    func ask(_ request: IntelligenceAskRequest) async
    func cancel()
    func retry()
    func goDeeper()
}

/// History seam over the existing `TranscriptRepository`.
public protocol IntelligenceHistoryServing: Sendable {
    func list(query: String?, limit: Int) async throws -> [IntelligenceHistoryItem]
    func detail(id: SessionID) async throws -> IntelligenceHistoryItem?
    func delete(id: SessionID) async throws
}
