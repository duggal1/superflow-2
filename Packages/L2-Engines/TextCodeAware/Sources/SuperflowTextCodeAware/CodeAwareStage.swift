import Foundation
import SuperflowKernel
import SuperflowPorts

/// Deterministic coding cleanup. Runs after the lexicon and before cleanup.
public struct CodeAwareStage: ExplainingTextStage {
    public let id: String
    private let settings: CodeAwareSettings
    private let configuredProject: ProjectContext?
    private let cache: IndexCache

    public init(settings: CodeAwareSettings = CodeAwareSettings(),
                project: ProjectContext? = nil, id: String = "codeAware") {
        self.id = id
        self.settings = settings
        self.configuredProject = project
        self.cache = IndexCache()
    }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        let project = context.project ?? configuredProject
        let output = CodeAwareRewriter.rewrite(
            draft.text, protected: draft.protected, project: project,
            coding: isCoding(project: project, context: context),
            settings: settings, index: cache.index(for: project), stageID: id)
        var next = draft
        next.text = output.text
        next.protected.literals.formUnion(output.protected)
        return next
    }

    public func explainEdits(before: TranscriptDraft, after: TranscriptDraft,
                             context: TextContext) async -> [TextEdit]? {
        let project = context.project ?? configuredProject
        let output = CodeAwareRewriter.rewrite(
            before.text, protected: before.protected, project: project,
            coding: isCoding(project: project, context: context),
            settings: settings, index: cache.index(for: project), stageID: id)
        guard output.text == after.text else { return nil }
        return output.edits.isEmpty ? nil : output.edits
    }

    private func isCoding(project: ProjectContext?, context: TextContext) -> Bool {
        project?.isCoding == true || context.settings.codeSpeakEnabled
    }
}

/// The project index is immutable per project, so one cache entry covers every
/// segment in a session without rebuilding a four-thousand-entry map per chunk.
final class IndexCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedProject: ProjectContext?
    private var cached = ProjectPathIndex(paths: [])

    func index(for project: ProjectContext?) -> ProjectPathIndex {
        lock.lock()
        defer { lock.unlock() }
        // A refresh can keep the same root and path count while changing the
        // entries, so compare the whole scope rather than just its size.
        if cachedProject == project { return cached }
        cached = ProjectPathIndex(paths: project?.paths ?? [])
        cachedProject = project
        return cached
    }
}
