import SuperflowKernel

public struct Tier0Pipeline: Sendable {
    public let stages: [any TextStage]
    public init(stages: [any TextStage]) { self.stages = stages }
    public func run(_ raw: String) -> TextDraft {
        stages.reduce(TextDraft(text: raw)) { draft, stage in stage.apply(draft) }
    }
}
