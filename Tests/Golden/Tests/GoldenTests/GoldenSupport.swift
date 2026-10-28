import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextCleanup
import SuperflowTextGrammarGate
import SuperflowMeetingEngine
import SuperflowTestKit
import SuperflowTextPipeline

/// Shared fixture loading for the golden suite. Every fixture is checked in and
/// reviewed; `scripts/golden-update.sh` documents the deliberate update flow.
enum Golden {
    static var fixtures: URL {
        guard let url = Bundle.module.resourceURL?.appendingPathComponent("Fixtures", isDirectory: true) else {
            fatalError("Golden Fixtures resource is missing from the test bundle.")
        }
        return url
    }

    static func load<T: Decodable>(_ relativePath: String) throws -> T {
        let url = fixtures.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func makePipeline(settings: AppSettings,
                             lexicon: [LexiconEntry] = [],
                             shortcuts: [ShortcutEntry] = [],
                             cleaner: CleanupService? = nil,
                             grammar: (any GrammarChecker)? = nil,
                             grammarPolicy: GrammarGatePolicy = .default,
                             project: ProjectContext? = nil) -> TextPipeline {
        TextPipelineBuilder.make(
            settings: settings,
            dependencies: TextPipelineDependencies(
                lexiconEntries: lexicon,
                shortcuts: shortcuts,
                cleaner: cleaner,
                grammarChecker: grammar,
                grammarPolicy: grammarPolicy,
                project: project
            )
        )
    }

    /// Settings used by stage goldens: deterministic stages only, and no
    /// capitalization/period so the fixture states exactly what the stage under
    /// test produced.
    static func stageSettings(_ patch: SettingsPatch? = nil) -> AppSettings {
        var settings = AppSettings.default
        settings.commandsEnabled = false
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        settings.lineFormat.capitalize = false
        settings.lineFormat.finalPeriod = false
        return patch?.apply(to: settings) ?? settings
    }
}

struct CaseFixture: Decodable {
    var cases: [GoldenCase]
    var edgeCases: [GoldenCase]?
    var knownFailures: [GoldenCase]?
}

struct GoldenCase: Decodable {
    var name: String
    var input: String
    var expected: String
    var settings: SettingsPatch?
    var source: String?
}

/// Every field is optional so a fixture only states the settings it cares about.
struct SettingsPatch: Decodable {
    var commandsEnabled: Bool?
    var cleanupEnabled: Bool?
    var harperEnabled: Bool?
    var spellOutSmallNumbers: Bool?
    var numberStyle: LargeNumberStyle?
    var lineFormat: LineFormatPatch?
    var disfluency: DisfluencyPatch?

    func apply(to base: AppSettings) -> AppSettings {
        var settings = base
        if let commandsEnabled { settings.commandsEnabled = commandsEnabled }
        if let cleanupEnabled { settings.cleanupEnabled = cleanupEnabled }
        if let harperEnabled { settings.harperEnabled = harperEnabled }
        if let spellOutSmallNumbers { settings.spellOutSmallNumbers = spellOutSmallNumbers }
        if let numberStyle { settings.numberStyle = numberStyle }
        if let lineFormat { lineFormat.apply(to: &settings.lineFormat) }
        if let disfluency { disfluency.apply(to: &settings.disfluency) }
        return settings
    }
}

struct DisfluencyPatch: Decodable {
    var enabled: Bool?
    var collapseDuplicates: Bool?
    var tierAThreshold: Int?
    var tierBThreshold: Int?
    var collapseRepeatedPhrases: Bool?
    var fillerPrepass: Bool?

    func apply(to settings: inout DisfluencySettings) {
        if let enabled { settings.enabled = enabled }
        if let collapseDuplicates { settings.collapseDuplicates = collapseDuplicates }
        if let tierAThreshold { settings.tierAThreshold = max(2, tierAThreshold) }
        if let tierBThreshold { settings.tierBThreshold = max(3, tierBThreshold) }
        if let collapseRepeatedPhrases { settings.collapseRepeatedPhrases = collapseRepeatedPhrases }
        if let fillerPrepass { settings.fillerPrepass = fillerPrepass }
    }
}

struct LineFormatPatch: Decodable {
    var minWords: Int?
    var preferredMax: Int?
    var hardMax: Int?
    var breakStyle: BreakStyle?
    var capitalize: Bool?
    var collapseSpaces: Bool?
    var fixPunctuationSpacing: Bool?
    var finalPeriod: Bool?
    var trailingSpace: Bool?

    func apply(to settings: inout LineFormatSettings) {
        if let minWords { settings.minWords = minWords }
        if let preferredMax { settings.preferredMax = preferredMax }
        if let hardMax { settings.hardMax = hardMax }
        if let breakStyle { settings.breakStyle = breakStyle }
        if let capitalize { settings.capitalize = capitalize }
        if let collapseSpaces { settings.collapseSpaces = collapseSpaces }
        if let fixPunctuationSpacing { settings.fixPunctuationSpacing = fixPunctuationSpacing }
        if let finalPeriod { settings.finalPeriod = finalPeriod }
        if let trailingSpace { settings.trailingSpace = trailingSpace }
    }

    var settings: LineFormatSettings {
        var value = LineFormatSettings()
        apply(to: &value)
        return value
    }
}

struct LexiconFixture: Decodable {
    var entries: [LexiconEntryFixture]
    var cases: [GoldenCase]
    var knownFailures: [GoldenCase]?
}

struct LexiconEntryFixture: Decodable {
    var kind: LexiconKind
    var triggers: [String]
    var canonical: String
    var enabled: Bool?

    var entry: LexiconEntry {
        LexiconEntry(kind: kind, triggers: triggers, canonical: canonical, enabled: enabled ?? true)
    }
}

struct ShortcutFixture: Decodable {
    var entries: [ShortcutEntryFixture]
    var cases: [GoldenCase]
    var knownFailures: [GoldenCase]?
}

struct ShortcutEntryFixture: Decodable {
    var trigger: String
    var content: String
    var match: ShortcutMatch?

    var entry: ShortcutEntry {
        ShortcutEntry(trigger: trigger, content: content, match: match ?? .wholeUtterance)
    }
}

struct LineFormatFixture: Decodable {
    var settings: LineFormatPatch?
    var cases: [GoldenCase]
    var edgeCases: [GoldenCase]?
    var incremental: [IncrementalCase]
}

struct IncrementalCase: Decodable {
    var name: String
    var chunks: [String]
    var expected: String
    var settings: LineFormatPatch?
}

struct GrammarFixture: Decodable {
    var policy: GrammarPolicyFixture
    var cases: [GrammarCase]
}

struct GrammarPolicyFixture: Decodable {
    var enabled: Bool?
    var allowedKinds: [String]?
    var maxEditRatio: Double?
    var timeCapMs: Int?

    func policy() -> GrammarGatePolicy {
        let base = GrammarGatePolicy.default
        return GrammarGatePolicy(
            enabled: enabled ?? base.enabled,
            allowedKinds: allowedKinds ?? base.allowedKinds,
            maxEditRatio: maxEditRatio ?? base.maxEditRatio,
            timeCapMs: timeCapMs ?? base.timeCapMs
        )
    }
}

struct GrammarCase: Decodable {
    var name: String
    var input: String
    var lints: [GrammarLintFixture]
    var expectedFinal: String
    /// Indices into `lints` that the gate must accept. Everything else is a
    /// decoy (disallowed category, protected span, overlapping edit, no-op).
    var expectedAccepted: [Int]
    var category: String
    var protectedLiterals: [String]?
}

struct GrammarLintFixture: Decodable {
    /// Locate the lint by substring. Ignored when explicit UTF-16 offsets are set.
    var find: String?
    var replace: String?
    var kind: String
    var utf16Start: Int?
    var utf16Length: Int?

    func lint(in text: String) -> GrammarLint? {
        if let utf16Start, let utf16Length {
            return GrammarLint(utf16Start: utf16Start, utf16Length: utf16Length,
                               kind: kind, suggestion: replace)
        }
        guard let find, let range = Self.wordRange(of: find, in: text) else { return nil }
        let nsRange = NSRange(range, in: text)
        return GrammarLint(utf16Start: nsRange.location, utf16Length: nsRange.length,
                           kind: kind, suggestion: replace)
    }

    /// Harper reports word-level ranges. Locate fixture text on word boundaries so a
    /// substring such as "are" never lands inside "shared".
    static func wordRange(of needle: String, in text: String) -> Range<String.Index>? {
        var start = text.startIndex
        while start < text.endIndex, let range = text.range(of: needle, range: start..<text.endIndex) {
            let beforeOK = range.lowerBound == text.startIndex
                || !isWordCharacter(text[text.index(before: range.lowerBound)])
            let afterOK = range.upperBound == text.endIndex
                || !isWordCharacter(text[range.upperBound])
            if beforeOK && afterOK { return range }
            start = text.index(after: range.lowerBound)
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

struct MeetingExportFixture: Decodable {
    var document: MeetingDocumentFixture
    var expectedMarkdownLines: [String]
    var expectedJSON: String
}

struct MeetingDocumentFixture: Decodable {
    var title: String
    var sessionID: String
    var startedAt: String
    var endedAt: String?
    var durationMs: Int
    var speakers: [MeetingSpeakerFixture]
    var turns: [MeetingTurnFixture]
}

struct MeetingSpeakerFixture: Decodable {
    var id: String
    var name: String
    var isSelf: Bool
}

struct MeetingTurnFixture: Decodable {
    var index: Int
    var speakerID: String
    var speakerName: String
    var startMs: Int
    var endMs: Int
    var text: String
    var rawText: String
    var source: AudioSourceKind
    var isGap: Bool
}

struct CleanupFixture: Decodable {
    var config: CleanupConfigFixture?
    var cases: [CleanupCase]
}

struct CleanupConfigFixture: Decodable {
    var softTokenTarget: Int?
    var hardTokenCap: Int?
    var interactiveDeadlineMs: Int?
    var backgroundDeadlineMs: Int?
    var workers: Int?
    var ratioFloor: Double?
    var retryDepth: Int?
    var maxNewTokens: Int?
    var hallucinationFloor: Int?
    var overlapPercent: Double?

    func config() -> CleanupConfig {
        let base = CleanupConfig()
        return CleanupConfig(
            softTokenTarget: softTokenTarget ?? base.softTokenTarget,
            hardTokenCap: hardTokenCap ?? base.hardTokenCap,
            interactiveDeadlineMs: interactiveDeadlineMs ?? base.interactiveDeadlineMs,
            backgroundDeadlineMs: backgroundDeadlineMs ?? base.backgroundDeadlineMs,
            workers: workers ?? base.workers,
            ratioFloor: ratioFloor ?? base.ratioFloor,
            retryDepth: retryDepth ?? base.retryDepth,
            hallucinationFloor: hallucinationFloor ?? base.hallucinationFloor,
            maxNewTokens: maxNewTokens ?? base.maxNewTokens,
            overlapPercent: overlapPercent ?? base.overlapPercent
        )
    }
}

struct CleanupCase: Decodable {
    var name: String
    var behavior: CleanupBehavior
    var input: String
    var expected: String
    var expectedState: CleanupState
    var minimumChunks: Int?
    var knownFailure: String?
}

enum CleanupBehavior: String, Decodable {
    case identity, upper, fail, truncate, dropLast, echoPrefix, slow, notReady

    func cleaner() -> any TextCleaner {
        switch self {
        case .identity: return FakeTextCleaner(.identity)
        case .upper: return FakeTextCleaner(.upper)
        case .fail: return FakeTextCleaner(.fail)
        case .truncate: return FakeTextCleaner(.truncate)
        case .dropLast: return FakeTextCleaner(.dropLast)
        case .echoPrefix: return FakeTextCleaner(.echoPrefix("Sure thing "))
        case .slow: return FakeTextCleaner(.slow(ms: 2_000))
        case .notReady: return NotReadyCleaner()
        }
    }
}

/// A cleaner that reports the model as unavailable without failing a call.
struct NotReadyCleaner: TextCleaner {
    var isReady: Bool { get async { false } }
    func countTokens(_ text: String) async -> Int { max(1, Tokenizer.words(in: text).count) }
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        CleanResult(text: text, tokensIn: 1, tokensOut: 1, hitTokenCap: false, latencyMs: 0)
    }
}

extension MeetingDocumentFixture {
    func document() throws -> MeetingDocument {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        guard let start = iso.date(from: startedAt) else {
            throw FixtureError.invalidDate(startedAt)
        }
        return MeetingDocument(
            sessionID: SessionID(sessionID),
            title: title,
            startedAt: start,
            endedAt: try endedAt.map { value in
                guard let date = iso.date(from: value) else { throw FixtureError.invalidDate(value) }
                return date
            },
            durationMs: durationMs,
            speakers: speakers.map { MeetingSpeaker(id: $0.id, name: $0.name, isSelf: $0.isSelf) },
            turns: turns.map {
                MeetingTurn(index: $0.index, speakerID: $0.speakerID, speakerName: $0.speakerName,
                            startMs: $0.startMs, endMs: $0.endMs, text: $0.text, rawText: $0.rawText,
                            source: $0.source, isGap: $0.isGap)
            }
        )
    }
}

enum FixtureError: Error, CustomStringConvertible {
    case invalidDate(String)
    var description: String {
        switch self {
        case .invalidDate(let value): return "fixture date is not ISO-8601: \(value)"
        }
    }
}
