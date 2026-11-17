import Foundation
import SuperflowKernel
@testable import SuperflowFeatureIntelligence

/// A scripted answer service. Emits each configured event in order when asked,
/// then calls the terminal callback. Never touches the network or a keychain.
@MainActor
final class FakeAnswerService: IntelligenceAnswerServing {
    var onEvent: ((IntelligenceAnswerEvent) -> Void)?
    var script: [IntelligenceAnswerEvent] = []
    var requests: [IntelligenceAskRequest] = []
    var cancelCount = 0
    var retryCount = 0
    var deeperCount = 0

    func ask(_ request: IntelligenceAskRequest) async {
        requests.append(request)
        for event in script { onEvent?(event) }
    }

    func cancel() { cancelCount += 1 }
    func retry() {
        retryCount += 1
        for event in script { onEvent?(event) }
    }
    func goDeeper() {
        deeperCount += 1
        for event in script { onEvent?(event) }
    }
}

/// An in-memory fake of the history store, covering list/search/open/delete.
final class FakeHistoryStore: IntelligenceHistoryServing, @unchecked Sendable {
    var items: [IntelligenceHistoryItem]
    init(items: [IntelligenceHistoryItem]) { self.items = items }

    func list(query: String?, limit: Int) async throws -> [IntelligenceHistoryItem] {
        let needle = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matched = needle.isEmpty
            ? items
            : items.filter {
                $0.title.localizedCaseInsensitiveContains(needle)
                    || $0.preview.localizedCaseInsensitiveContains(needle)
                    || $0.fullText.localizedCaseInsensitiveContains(needle)
            }
        return Array(matched.prefix(max(0, limit)))
    }

    func detail(id: SessionID) async throws -> IntelligenceHistoryItem? {
        items.first { $0.id == id }
    }

    func delete(id: SessionID) async throws {
        items.removeAll { $0.id == id }
    }
}
