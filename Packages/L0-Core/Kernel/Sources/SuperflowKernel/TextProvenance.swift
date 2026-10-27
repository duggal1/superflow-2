import Foundation

/// A half-open UTF-16 span. UTF-16 is the coordinate system already used by
/// `GrammarLint`, so provenance, grammar edits and storage agree.
public struct TextSpan: Sendable, Codable, Equatable, Hashable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    public var end: Int { location + length }
    public var isEmpty: Bool { length == 0 }
    public var nsRange: NSRange { NSRange(location: location, length: length) }

    public static let zero = TextSpan(location: 0, length: 0)
}

public enum TextEditKind: String, Sendable, Codable, Equatable, CaseIterable {
    case insert
    case delete
    case replace
}

/// One attributable change produced by a text stage.
///
/// `input` indexes the text before the stage; `output` indexes the text after
/// it. A pure insertion has an empty `input`; a pure deletion has an empty
/// `output`. `ruleID` is the stage id unless the stage can name the exact rule
/// (a lexicon entry id, a Code Speak command, and so on).
public struct TextEdit: Sendable, Codable, Equatable {
    public var stageID: String
    public var ruleID: String
    public var kind: TextEditKind
    public var input: TextSpan
    public var output: TextSpan

    public init(stageID: String, ruleID: String? = nil, kind: TextEditKind,
                input: TextSpan, output: TextSpan) {
        self.stageID = stageID
        self.ruleID = ruleID ?? stageID
        self.kind = kind
        self.input = input
        self.output = output
    }
}
