import Foundation
import SuperflowKernel
import SuperflowPorts

public actor FakeTextCleaner: TextCleaner {
    public enum Behavior: Sendable, Equatable {
        case identity
        case upper
        case fail
        case truncate
        case slow(ms: Int)
        case echoPrefix(String)
        case dropLast
    }

    public private(set) var behavior: Behavior
    public private(set) var calls = 0
    public private(set) var lastOptions: CleanOptions?
    public var tokenScale = 1.3

    public init(_ behavior: Behavior = .identity) { self.behavior = behavior }
    public func set(_ b: Behavior) { behavior = b }
    public var isReady: Bool { true }

    public func countTokens(_ text: String) async -> Int {
        max(1, Int(Double(Tokenizer.words(in: text).count) * tokenScale))
    }

    public func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        calls += 1
        lastOptions = options
        switch behavior {
        case .identity:
            return CleanResult(text: text, tokensIn: 1, tokensOut: 1, hitTokenCap: false, latencyMs: 1)
        case .upper:
            return CleanResult(text: text.uppercased(), tokensIn: 1, tokensOut: 1, hitTokenCap: false, latencyMs: 1)
        case .fail:
            throw SuperflowError.modelUnavailable("fake cleaner")
        case .truncate:
            let words = Tokenizer.words(in: text)
            return CleanResult(text: words.prefix(max(1, words.count / 3)).joined(separator: " "),
                               tokensIn: 1, tokensOut: 1, hitTokenCap: true, latencyMs: 1)
        case .slow(let ms):
            try await Task.sleep(for: .milliseconds(ms))
            return CleanResult(text: text, tokensIn: 1, tokensOut: 1, hitTokenCap: false, latencyMs: ms)
        case .echoPrefix(let prefix):
            return CleanResult(text: prefix + text, tokensIn: 1, tokensOut: 1, hitTokenCap: false, latencyMs: 1)
        case .dropLast:
            let words = Tokenizer.words(in: text).dropLast()
            return CleanResult(text: words.joined(separator: " "), tokensIn: 1, tokensOut: 1, hitTokenCap: false, latencyMs: 1)
        }
    }
}

public actor FakeGrammarChecker: GrammarChecker {
    public private(set) var lints: [GrammarLint]
    public private(set) var calls = 0
    public var delayMs = 0
    public init(lints: [GrammarLint] = []) { self.lints = lints }
    public func setLints(_ l: [GrammarLint]) { lints = l }
    public func setDelay(ms: Int) { delayMs = ms }
    public func lint(_ text: String, customWords: [String]) async -> [GrammarLint] {
        calls += 1
        if delayMs > 0 { try? await Task.sleep(for: .milliseconds(delayMs)) }
        return lints
    }
}

public actor RecordingInserter: TextInserter {
    public private(set) var inserted: [String] = []
    public private(set) var attempts = 0
    public private(set) var prepareCalls = 0
    /// Ordered trace: "frontmost", "prepare", "insert:<strategy>".
    public private(set) var events: [String] = []
    public var outcome: InsertionOutcome = .pasted
    private var autoDelayMs = 0
    private var eventLog: (@Sendable (String) async -> Void)?

    public init() {}
    public func setOutcome(_ o: InsertionOutcome) { outcome = o }
    public func setAutoDelay(ms: Int) { autoDelayMs = ms }
    public func setEventLog(_ log: @escaping @Sendable (String) async -> Void) { eventLog = log }

    private func record(_ event: String) async {
        events.append(event)
        if let eventLog { await eventLog(event) }
    }

    public func insert(_ text: String, strategy: InsertionStrategy) async throws -> InsertionOutcome {
        if strategy == .auto, autoDelayMs > 0 {
            try? await Task.sleep(for: .milliseconds(autoDelayMs))
        }
        attempts += 1
        await record("insert:\(strategy.rawValue)")
        if case .blockedSecureField = outcome { return outcome }
        inserted.append(text)
        // A clipboard-only request can never report a paste.
        if strategy == .clipboardOnly { return .clipboardOnly(reason: "clipboard") }
        return outcome
    }

    public func frontmostBundleID() async -> String? {
        await record("frontmost")
        return "com.test.frontmost"
    }

    public func prepareForInsertion() async {
        prepareCalls += 1
        await record("prepare")
    }
}

public struct NullMetrics: MetricsSink {
    public init() {}
    public func record(_ name: String, valueMs: Double) {}
    public func event(_ name: String, _ fields: [String: String]) {}
}

public final class RecordingMetrics: MetricsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _records: [(String, Double)] = []
    private var _events: [String] = []
    public init() {}
    public var records: [(String, Double)] { lock.lock(); defer { lock.unlock() }; return _records }
    public var events: [String] { lock.lock(); defer { lock.unlock() }; return _events }
    public func record(_ name: String, valueMs: Double) {
        lock.lock(); _records.append((name, valueMs)); lock.unlock()
    }
    public func event(_ name: String, _ fields: [String: String]) {
        lock.lock(); _events.append(name); lock.unlock()
    }
}
