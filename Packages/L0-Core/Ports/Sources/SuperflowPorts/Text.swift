import Foundation
import SuperflowKernel

/// A stage never throws into the pipeline: on failure it returns its input plus a diagnostic.
public protocol TextStage: Sendable {
    var id: String { get }
    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft
}

public struct CleanOptions: Sendable, Equatable {
    public var styling: String
    public var structure: String
    public var context: String
    public var deadlineMs: Int
    public var maxNewTokens: Int
    public init(styling: String = "semi-formal", structure: String = "prose", context: String = "general",
                deadlineMs: Int = 1_500, maxNewTokens: Int = 1_024) {
        self.styling = styling
        self.structure = structure
        self.context = context
        self.deadlineMs = deadlineMs
        self.maxNewTokens = maxNewTokens
    }
}

public struct CleanResult: Sendable, Equatable {
    public var text: String
    public var tokensIn: Int
    public var tokensOut: Int
    public var hitTokenCap: Bool
    public var latencyMs: Int
    public init(text: String, tokensIn: Int, tokensOut: Int, hitTokenCap: Bool, latencyMs: Int) {
        self.text = text
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.hitTokenCap = hitTokenCap
        self.latencyMs = latencyMs
    }
}

public protocol TextCleaner: Sendable {
    var isReady: Bool { get async }
    func countTokens(_ text: String) async -> Int
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult
}

public struct GrammarLint: Sendable, Equatable {
    public var utf16Start: Int
    public var utf16Length: Int
    public var kind: String
    public var suggestion: String?
    public init(utf16Start: Int, utf16Length: Int, kind: String, suggestion: String?) {
        self.utf16Start = utf16Start
        self.utf16Length = utf16Length
        self.kind = kind
        self.suggestion = suggestion
    }
}

public protocol GrammarChecker: Sendable {
    func lint(_ text: String, customWords: [String]) async -> [GrammarLint]
}

public enum InsertionStrategy: String, Sendable, CaseIterable {
    case auto, pasteboard, accessibility, clipboardOnly
}

public enum InsertionOutcome: Sendable, Equatable {
    case pasted
    case accessibility
    case clipboardOnly(reason: String)
    case blockedSecureField
}

public protocol TextInserter: Sendable {
    func insert(_ text: String, strategy: InsertionStrategy) async throws -> InsertionOutcome
    func frontmostBundleID() async -> String?
}
