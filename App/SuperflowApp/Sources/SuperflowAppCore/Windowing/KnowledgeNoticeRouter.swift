import Foundation
import SuperflowFeatureIsland
import SuperflowKernel
import SuperflowTextPipeline

/// Routes committed learning changes into the existing Island queue. No new
/// notification worker, sound synthesizer, or monitoring lane is introduced.
@MainActor
final class KnowledgeNoticeRouter {
    private let learning: DictionaryLearningEngine
    private weak var island: IslandModel?
    private var recent: [(notice: IslandNotice, candidateID: String)] = []

    init(learning: DictionaryLearningEngine, island: IslandModel) {
        self.learning = learning
        self.island = island
    }

    func applied(_ candidate: LearningCandidate, active: Bool) {
        if active {
            // This callback runs only AFTER both SQLite writes succeeded.
            let notice = IslandNotice(
                kind: .knowledge,
                title: "Added to Knowledge",
                detail: "\(candidate.heard) → \(candidate.canonical)",
                action: "Undo")
            recent.removeAll { $0.candidateID == candidate.id }
            recent.append((notice: notice, candidateID: candidate.id))
            if recent.count > 8 { recent.removeFirst(recent.count - 8) }
            island?.notify(notice)
        } else {
            recent.removeAll { $0.candidateID == candidate.id }
            island?.notify(.init(kind: .info,
                                 title: "Removed from Knowledge",
                                 detail: candidate.canonical))
        }
    }

    func handle(_ notice: IslandNotice) {
        guard notice.kind == .knowledge, notice.action == "Undo",
              let index = recent.firstIndex(where: { $0.notice == notice }) else { return }
        let id = recent.remove(at: index).candidateID
        Task { [weak self] in
            guard let self else { return }
            do {
                try await learning.undo(id: id)
            } catch {
                // A failed database write must not be presented as a successful
                // Undo, and the action remains retryable while the notice lives.
                recent.append((notice: notice, candidateID: id))
                island?.notify(.init(kind: .info,
                                     title: "Could not undo correction",
                                     detail: "Open Knowledge to try again."))
            }
        }
    }
}
