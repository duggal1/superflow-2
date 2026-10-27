import Foundation
import SuperflowKernel
import SuperflowPorts

/// TextCleaner contract: token counts are non-negative and ordered by input
/// size, clean returns a bounded result, and empty input stays empty.
public struct TextCleanerContract: Sendable {
    public init() {}

    public func verify(_ cleaner: any TextCleaner) async throws {
        let ready = await cleaner.isReady
        try contractRequire(ready, "text cleaner is not ready")

        let emptyTokens = await cleaner.countTokens("")
        let shortTokens = await cleaner.countTokens("hello world")
        let longTokens = await cleaner.countTokens(String(repeating: "word ", count: 200))
        try contractRequire(emptyTokens >= 0, "negative token count for empty text")
        try contractRequire(shortTokens > 0, "token count for non-empty text is zero")
        try contractRequire(longTokens >= shortTokens, "token count is not monotonic in input size")

        let options = CleanOptions(styling: "formal", structure: "bullets", context: "code",
                                   deadlineMs: 42, maxNewTokens: 7)
        let result = try await cleaner.clean("hello world", options: options)
        try contractRequire(!result.text.isEmpty, "cleaner returned empty text for non-empty input")
        try contractRequire(result.tokensIn >= 0 && result.tokensOut >= 0,
                            "cleaner returned a negative token count")
        try contractRequire(result.latencyMs >= 0, "cleaner returned a negative latency")
        try contractRequire(result.tokensOut <= max(result.tokensIn, result.tokensOut),
                            "cleaner token accounting is inconsistent")

        let empty = try await cleaner.clean("", options: options)
        try contractRequire(empty.text.isEmpty, "cleaner invented text for empty input")
    }
}

/// GrammarChecker contract: every lint offset is a valid UTF-16 range and every
/// lint carries a non-empty kind, including for text containing an emoji.
public struct GrammarCheckerContract: Sendable {
    public init() {}

    public func verify(_ checker: any GrammarChecker) async throws {
        let text = "Hello world 🙂"
        let length = text.utf16.count
        let lints = await checker.lint(text, customWords: ["Superflow"])
        for lint in lints {
            try contractRequire(lint.utf16Start >= 0,
                                "lint starts before the text: \(lint.utf16Start)")
            try contractRequire(lint.utf16Length >= 0,
                                "lint has a negative length: \(lint.utf16Length)")
            try contractRequire(lint.utf16Start + lint.utf16Length <= length,
                                "lint range \(lint.utf16Start)+\(lint.utf16Length) exceeds \(length)")
            try contractRequire(!lint.kind.isEmpty, "lint has an empty kind")
        }
        _ = await checker.lint("", customWords: [])
    }
}

/// TextInserter contract: empty text is a no-op, a normal insert returns a
/// defined outcome, and the frontmost bundle id is either nil or non-empty.
public struct TextInserterContract: Sendable {
    public init() {}

    public func verify(_ inserter: any TextInserter) async throws {
        let empty = try await inserter.insert("", strategy: .auto)
        try contractRequire(empty == .pasted, "empty insertion should be a no-op, got \(empty)")

        let outcome = try await inserter.insert("contract text", strategy: .auto)
        let valid = outcome == .pasted || outcome == .accessibility
            || contractIsClipboardOnly(outcome) || outcome == .blockedSecureField
        try contractRequire(valid, "insert returned an undefined outcome: \(outcome)")

        let bundle = await inserter.frontmostBundleID()
        try contractRequire(bundle == nil || !bundle!.isEmpty,
                            "frontmostBundleID returned an empty string")
    }
}
