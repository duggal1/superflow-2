import Foundation
import SuperflowKernel
import SuperflowPorts

public struct StageTiming: Sendable, Equatable {
    public var id: String
    public var ms: Int
    public init(id: String, ms: Int) {
        self.id = id
        self.ms = ms
    }
}

public struct PipelineResult: Sendable, Equatable {
    public var draft: TranscriptDraft
    public var timings: [StageTiming]
    public var shortCircuitedBy: String?
    public init(draft: TranscriptDraft, timings: [StageTiming], shortCircuitedBy: String?) {
        self.draft = draft
        self.timings = timings
        self.shortCircuitedBy = shortCircuitedBy
    }
    public var text: String { draft.text }
}

/// Runs text stages in order. A shortcut expansion stops the pipeline immediately.
/// The pipeline itself cannot throw; each stage owns its own failure fallback.
public struct TextPipeline: Sendable {
    public let stages: [any TextStage]
    public let seedProtected: Set<String>
    private let tokenCounter: (@Sendable (String) async -> Int)?

    public init(stages: [any TextStage], seedProtected: Set<String> = [],
                tokenCounter: (@Sendable (String) async -> Int)? = nil) {
        self.stages = stages
        self.seedProtected = seedProtected
        self.tokenCounter = tokenCounter
    }

    public var stageIDs: [String] { stages.map(\.id) }

    public func countTokens(_ text: String) async -> Int? {
        guard let tokenCounter else { return nil }
        return await tokenCounter(text)
    }

    public func run(_ text: String, context: TextContext,
                    protected: Protected = Protected()) async -> PipelineResult {
        var draft = TranscriptDraft(text: text, protected: protected)
        draft.protected.literals.formUnion(seedProtected)
        var timings: [StageTiming] = []
        var shortCircuitedBy: String?

        for stage in stages {
            let before = draft
            let started = DispatchTime.now().uptimeNanoseconds
            draft = await stage.apply(draft, context: context)
            let elapsed = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
            timings.append(StageTiming(id: stage.id, ms: elapsed))

            if draft.text.isEmpty, !before.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft = before
                draft.diagnostics.append(Diagnostic(stage: stage.id,
                    message: "stage returned empty text; reverted to input"))
            }
            if draft.shortCircuit {
                shortCircuitedBy = stage.id
                break
            }
        }
        return PipelineResult(draft: draft, timings: timings, shortCircuitedBy: shortCircuitedBy)
    }
}
