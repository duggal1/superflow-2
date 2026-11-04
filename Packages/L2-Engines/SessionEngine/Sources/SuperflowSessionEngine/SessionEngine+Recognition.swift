import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

extension SessionEngine {
    func consumeRecognition(_ stream: any RecognitionStream, session: SessionID) async {
        for await event in stream.events {
            switch event {
            case .partial(let text):
                emit(.partial(text))
                await speculate(text, session: session)
            case .committed(let segment):
                await persist(segment, session: session)
            case .endpoint:
                break
            case .failure(let message):
                recognitionOverflow = true
                emit(.notice("Recognition problem: \(message)"))
            }
        }
    }

    func persist(_ raw: RawSegment, session: SessionID) async {
        guard state.isActive else { return }
        let index = nextIndex
        nextIndex += 1
        lastEndMs = max(lastEndMs, raw.endMs)
        let row = Segment(sessionID: session, index: index, startMs: raw.startMs, endMs: raw.endMs,
                          source: raw.source, rawText: raw.text, cleanupState: .pending)
        do {
            try await repository.appendSegment(row)
        } catch {
            emit(.notice("Could not persist raw segment \(index): \(error.localizedDescription)"))
        }
        let tokens = await pipeline.countTokens(raw.text)
        let withinInteractiveBudget = tokens.map { cumulativeTokenCount + $0 <= 600 } ?? true
        if let tokens { cumulativeTokenCount += tokens }
        let interactive = raw.endMs <= 30_000 && withinInteractiveBudget
        let revision = pipelineRevision
        var precomputed = speculativeCleanupEnabled && index == 0 && interactive && raw.words.isEmpty
            ? await speculative.take(.init(session: session, revision: revision, text: raw.text)) : nil
        if revision != pipelineRevision { precomputed = nil }
        await cleanupCoordinator?.submit(index: index, interactive: interactive,
                                          pipeline: pipeline, settings: settings,
                                          project: project, wordTimings: raw.words,
                                          activeAppBundleID: record?.frontmostBundleID,
                                          precomputed: precomputed)
    }
}
