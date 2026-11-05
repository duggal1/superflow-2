import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

extension SessionEngine {
    /// Fix pending or queue-rejected rows only. Already polished model output
    /// stays untouched; a cancelled model may not overwrite these fallback rows.
    func repairFallbackText(session: SessionID) async {
        do {
            for segment in try await repository.segmentsForProcessing(session: session) {
                let rawFallback = segment.cleanedText == nil || segment.cleanedText == segment.rawText
                guard segment.cleanupState == .pending ||
                      (segment.cleanupState == .fallback && rawFallback) else { continue }
                let context = TextContext(source: segment.source, interactive: true,
                                          settings: settings, project: project,
                                          activeAppBundleID: record?.frontmostBundleID)
                let polished = await pipeline.runDeterministic(segment.rawText, context: context).text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                try await repository.updateCleaned(session: session, index: segment.index,
                                                   cleaned: polished.isEmpty ? segment.rawText : polished,
                                                   state: .fallback)
            }
        } catch {
            emit(.notice("Deterministic cleanup could not be saved; original transcript retained."))
        }
    }

}
