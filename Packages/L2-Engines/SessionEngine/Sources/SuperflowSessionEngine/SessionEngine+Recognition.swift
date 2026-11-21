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
                if streamingCleanupEnabled, settings.cleanupEnabled, !settings.reflectionCleanupEnabled,
                   case .recording = state, let record, record.id == session {
                    let context = TextContext(interactive: false, settings: settings, project: project,
                                              activeAppBundleID: record.frontmostBundleID)
                    await liveCleanup.offer(text, revision: pipelineRevision, pipeline: pipeline, context: context)
                } else {
                    await speculate(text, session: session)
                }
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
            // Never insert incomplete text after a durable capture failure.
            recognitionOverflow = true
            emit(.notice("Could not persist raw segment \(index): \(error.localizedDescription)"))
            return
        }
        // Priority classification must not make an XPC tokenizer round trip:
        // S1-mini could be busy and block this same recognition event reader.
        // A conservative byte budget is sufficient for scheduling priority.
        let estimatedTokens = (raw.text.utf8.count + 2) / 3
        cumulativeTokenCount += estimatedTokens
        let interactive = raw.endMs <= 30_000 && cumulativeTokenCount <= 600
        let revision = pipelineRevision
        let prepared = streamingCleanupEnabled && raw.words.isEmpty
            ? await liveCleanup.take(raw.text, revision: revision) : nil
        if streamingCleanupEnabled && !raw.words.isEmpty { await liveCleanup.reset() }
        var precomputed: PipelineResult?
        if prepared == nil, speculativeCleanupEnabled && index == 0 && interactive && raw.words.isEmpty {
            precomputed = await speculative.take(.init(session: session, revision: revision, text: raw.text))
        }
        if revision != pipelineRevision {
            precomputed = nil
            prepared?.pending?.cancel()
        }
        let validPrepared = revision == pipelineRevision ? prepared : nil
        if let validPrepared {
            metrics.event("session.cleanup.prefix_reused", [
                "remainingWords": String(validPrepared.tail.split(whereSeparator: \.isWhitespace).count)
            ])
        }
        let scheduled = await cleanupCoordinator?.submit(index: index, interactive: interactive,
                                                         pipeline: pipeline, settings: settings,
                                                         project: project, wordTimings: raw.words,
                                                         activeAppBundleID: record?.frontmostBundleID,
                                                         precomputed: precomputed, prepared: validPrepared) ?? false
        if !scheduled {
            validPrepared?.pending?.cancel()
            // Raw speech is already durable. Mark this segment as a fallback
            // instead of leaving an indefinitely pending cleanup state.
            do {
                try await repository.updateCleaned(session: session, index: index,
                                                   cleaned: raw.text, state: .fallback)
            } catch {
                emit(.notice("Could not retain raw segment \(index) as cleanup fallback."))
            }
        }
    }
}
