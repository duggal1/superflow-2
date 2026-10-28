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

public struct StageExplanation: Sendable, Equatable {
    public var stageID: String
    public var edits: [TextEdit]
    public init(stageID: String, edits: [TextEdit]) {
        self.stageID = stageID
        self.edits = edits
    }
}

/// The normal pipeline result plus per-stage provenance. Produced only on
/// demand; the recording path never asks for it.
public struct PipelineExplanation: Sendable, Equatable {
    public var result: PipelineResult
    public var stages: [StageExplanation]
    public init(result: PipelineResult, stages: [StageExplanation]) {
        self.result = result
        self.stages = stages
    }
    public var edits: [TextEdit] { stages.flatMap(\.edits) }
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

            // A successful cleanup of filler-only input is allowed to be empty.
            // Every other stage that erases non-empty text is treated as faulty
            // and reverted, so a bug cannot silently drop the transcript.
            let validEmptyCleanup = stage.id == "cleanup" && draft.cleanupState == .cleaned
            if draft.text.isEmpty, !validEmptyCleanup,
               !before.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    /// Same stages and the same failure rules as `run`, but records one
    /// explanation per executed stage. Deterministic stages are diffed at word
    /// level; a stage that conforms to `ExplainingTextStage` may name the exact
    /// rule instead. The model stage is aligned by the same word diff.
    public func explain(_ text: String, context: TextContext,
                        protected: Protected = Protected()) async -> PipelineExplanation {
        var draft = TranscriptDraft(text: text, protected: protected)
        draft.protected.literals.formUnion(seedProtected)
        var timings: [StageTiming] = []
        var explanations: [StageExplanation] = []
        var shortCircuitedBy: String?

        for stage in stages {
            let before = draft
            let started = DispatchTime.now().uptimeNanoseconds
            draft = await stage.apply(draft, context: context)
            let elapsed = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
            timings.append(StageTiming(id: stage.id, ms: elapsed))

            let validEmptyCleanup = stage.id == "cleanup" && draft.cleanupState == .cleaned
            if draft.text.isEmpty, !validEmptyCleanup,
               !before.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft = before
                draft.diagnostics.append(Diagnostic(stage: stage.id,
                    message: "stage returned empty text; reverted to input"))
                explanations.append(StageExplanation(stageID: stage.id, edits: []))
            } else {
                let edits = await Self.edits(for: stage, before: before, after: draft, context: context)
                explanations.append(StageExplanation(stageID: stage.id, edits: edits))
            }

            if draft.shortCircuit {
                shortCircuitedBy = stage.id
                break
            }
        }
        return PipelineExplanation(
            result: PipelineResult(draft: draft, timings: timings, shortCircuitedBy: shortCircuitedBy),
            stages: explanations)
    }

    private static func edits(for stage: any TextStage, before: TranscriptDraft,
                              after: TranscriptDraft, context: TextContext) async -> [TextEdit] {
        guard before.text != after.text else { return [] }
        if let explaining = stage as? any ExplainingTextStage,
           let edits = await explaining.explainEdits(before: before, after: after, context: context) {
            return edits
        }
        return TextWordDiff.edits(stageID: stage.id, before: before.text, after: after.text)
    }
}
