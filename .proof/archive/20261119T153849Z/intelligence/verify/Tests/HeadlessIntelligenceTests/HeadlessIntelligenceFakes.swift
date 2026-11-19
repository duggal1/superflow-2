import Foundation
import SuperflowKernel
import SuperflowFeatureIntelligence

/// Deterministic, offline answer client used by all HeadlessIntelligence tests.
@MainActor
final class HeadlessAnswerClient: IntelligenceAnswerServing {
    var onEvent: ((IntelligenceAnswerEvent) -> Void)?
    var script: [IntelligenceAnswerEvent] = []
    var requests: [IntelligenceAskRequest] = []
    var cancellations = 0

    func ask(_ request: IntelligenceAskRequest) async {
        requests.append(request)
        for event in script { onEvent?(event) }
    }
    func cancel() { cancellations += 1 }
    func retry() { for event in script { onEvent?(event) } }
    func goDeeper() { for event in script { onEvent?(event) } }
}

final class HeadlessHistoryClient: IntelligenceHistoryServing, @unchecked Sendable {
    var items: [IntelligenceHistoryItem]
    init(items: [IntelligenceHistoryItem]) { self.items = items }

    func list(query: String?, limit: Int) async throws -> [IntelligenceHistoryItem] {
        let needle = query?.lowercased() ?? ""
        let matched = needle.isEmpty ? items : items.filter {
            $0.title.lowercased().contains(needle)
                || $0.preview.lowercased().contains(needle)
                || $0.fullText.lowercased().contains(needle)
        }
        return Array(matched.prefix(max(0, limit)))
    }
    func detail(id: SessionID) async throws -> IntelligenceHistoryItem? {
        items.first { $0.id == id }
    }
    func delete(id: SessionID) async throws { items.removeAll { $0.id == id } }
}

@MainActor
func headlessModel(
    service: HeadlessAnswerClient = HeadlessAnswerClient(),
    store: HeadlessHistoryClient = HeadlessHistoryClient(items: []),
    copied: @escaping @MainActor (String) -> Void = { _ in }
) -> IntelligenceIslandModel {
    IntelligenceIslandModel(
        answerService: service,
        historyStore: store,
        copy: copied,
        defaults: UserDefaults(suiteName: "intelligence.headless.\(UUID().uuidString)")!
    )
}
