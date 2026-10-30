import Foundation

public struct TextDraft: Sendable, Equatable {
    public var words: [Word]
    public init(words: [Word]) { self.words = words }
    public init(text: String) { self.words = Word.tokenize(text) }

    public var text: String {
        var out = ""
        for (i, w) in words.enumerated() {
            if i > 0 && !w.glue { out.append(" ") }
            out.append(w.text)
        }
        return out
    }
}

public protocol TextStage: Sendable {
    var name: String { get }
    func apply(_ draft: TextDraft) -> TextDraft
}
