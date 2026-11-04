import Foundation

public struct LineFormatSettings: Codable, Sendable, Equatable {
    public var minWords: Int = 25
    public var preferredMax: Int = 35
    public var hardMax: Int = 45
    public var breakStyle: BreakStyle = .paragraph
    public var capitalize: Bool = true
    public var collapseSpaces: Bool = true
    public var fixPunctuationSpacing: Bool = true
    public var finalPeriod: Bool = true
    public var trailingSpace: Bool = false
    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LineFormatSettings()
        minWords = try c.decodeIfPresent(Int.self, forKey: .minWords) ?? d.minWords
        preferredMax = try c.decodeIfPresent(Int.self, forKey: .preferredMax) ?? d.preferredMax
        hardMax = try c.decodeIfPresent(Int.self, forKey: .hardMax) ?? d.hardMax
        breakStyle = try c.decodeIfPresent(BreakStyle.self, forKey: .breakStyle) ?? d.breakStyle
        capitalize = try c.decodeIfPresent(Bool.self, forKey: .capitalize) ?? d.capitalize
        collapseSpaces = try c.decodeIfPresent(Bool.self, forKey: .collapseSpaces) ?? d.collapseSpaces
        fixPunctuationSpacing = try c.decodeIfPresent(Bool.self, forKey: .fixPunctuationSpacing) ?? d.fixPunctuationSpacing
        finalPeriod = try c.decodeIfPresent(Bool.self, forKey: .finalPeriod) ?? d.finalPeriod
        trailingSpace = try c.decodeIfPresent(Bool.self, forKey: .trailingSpace) ?? d.trailingSpace
    }
}

/// Deterministic disfluency cleanup that runs before any model sees the text.
///
/// Duplicate collapse is tiered on purpose. "the the" is almost always a false
/// start, but "had had", "that that", "what it is is" and "bye bye" are real
/// grammar. Tier A words collapse at two; Tier B words need three; everything
/// else is left for the cleanup model, which can read the sentence.
public struct DisfluencySettings: Codable, Sendable, Equatable {
    public var enabled: Bool = true
    public var collapseDuplicates: Bool = true
    /// Tier A words (articles, pronouns, short prepositions) collapse at two.
    public var tierAThreshold: Int = 2
    /// Tier B words (had, that, is, very, ...) collapse only at three.
    public var tierBThreshold: Int = 3
    /// Backwards-compatible name for `tierBThreshold`. The old single threshold
    /// could not express the tier rules, so values below three are raised.
    public var duplicateThreshold: Int {
        get { tierBThreshold }
        set { tierBThreshold = max(3, newValue) }
    }
    /// Collapse adjacent repeated 2-3 word phrases ("we need to we need to go").
    public var collapseRepeatedPhrases: Bool = true
    /// Removes only the pure fillers. "like", "you know", "I mean" and "so"
    /// stay for the model, which can tell content from hesitation.
    public var fillerPrepass: Bool = true
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DisfluencySettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        collapseDuplicates = try c.decodeIfPresent(Bool.self, forKey: .collapseDuplicates)
            ?? d.collapseDuplicates
        tierAThreshold = max(2, try c.decodeIfPresent(Int.self, forKey: .tierAThreshold)
            ?? d.tierAThreshold)
        let legacy = try c.decodeIfPresent(Int.self, forKey: .duplicateThreshold)
        tierBThreshold = max(3, try c.decodeIfPresent(Int.self, forKey: .tierBThreshold)
            ?? legacy ?? d.tierBThreshold)
        collapseRepeatedPhrases = try c.decodeIfPresent(Bool.self, forKey: .collapseRepeatedPhrases)
            ?? d.collapseRepeatedPhrases
        fillerPrepass = try c.decodeIfPresent(Bool.self, forKey: .fillerPrepass) ?? d.fillerPrepass
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(collapseDuplicates, forKey: .collapseDuplicates)
        try c.encode(tierAThreshold, forKey: .tierAThreshold)
        try c.encode(tierBThreshold, forKey: .tierBThreshold)
        try c.encode(collapseRepeatedPhrases, forKey: .collapseRepeatedPhrases)
        try c.encode(fillerPrepass, forKey: .fillerPrepass)
        // Old readers only understand this key.
        try c.encode(tierBThreshold, forKey: .duplicateThreshold)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, collapseDuplicates, duplicateThreshold
        case tierAThreshold, tierBThreshold, collapseRepeatedPhrases, fillerPrepass
    }
}

/// Deterministic spoken-code cleanup: filenames, extensions and bounded,
/// project-relative path resolution.
public struct CodeAwareSettings: Codable, Sendable, Equatable {
    public var enabled: Bool = true
    public var normalizeFilenames: Bool = true
    public var resolvePaths: Bool = true
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CodeAwareSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        normalizeFilenames = try c.decodeIfPresent(Bool.self, forKey: .normalizeFilenames)
            ?? d.normalizeFilenames
        resolvePaths = try c.decodeIfPresent(Bool.self, forKey: .resolvePaths) ?? d.resolvePaths
    }
}
