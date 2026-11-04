import Foundation
import SuperflowKernel

extension SessionEngine {
    func speculate(_ text: String, session: SessionID) async {
        guard speculativeCleanupEnabled, settings.cleanupEnabled, nextIndex == 0,
              case .recording = state, let record, record.id == session,
              clock.now().timeIntervalSince(record.startedAt) < 25,
              let last = text.last, ".!?".contains(last),
              (12...150).contains(text.split(whereSeparator: \.isWhitespace).count) else { return }
        let revision = pipelineRevision
        guard let tokens = await pipeline.countTokens(text), tokens > 0, tokens <= 600,
              pipelineRevision == revision else { return }
        await speculative.schedule(.init(session: session, revision: revision, text: text),
                                   pipeline: pipeline,
                                   context: TextContext(interactive: true, settings: settings, project: project,
                                                        activeAppBundleID: record?.frontmostBundleID))
    }
}
