import Foundation

/// Small high-frequency English list used for dictionary collision warnings.
///
/// The bundled tech dictionary itself lives in the `SuperflowTechDictionary`
/// catalog (v4 schema). This list only backs `LexiconStage` warnings, so a
/// trigger made of ordinary words is reported while the dictionary is built.
public enum CommonWords {
    public static let list: Set<String> = [
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for", "not", "on", "with",
        "he", "as", "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
        "or", "an", "will", "my", "one", "all", "would", "there", "their", "what", "so", "up", "out", "if",
        "about", "who", "get", "which", "go", "me", "when", "make", "can", "like", "time", "no", "just", "him",
        "know", "take", "people", "into", "year", "your", "good", "some", "could", "them", "see", "other", "than",
        "then", "now", "look", "only", "come", "its", "over", "think", "also", "back", "after", "use", "two", "how",
        "our", "work", "first", "well", "way", "even", "new", "want", "because", "any", "these", "give", "day",
        "most", "us", "next", "years", "last", "type", "open", "chat", "git", "lab", "hub", "node", "script",
        "scripts", "code", "java", "swift", "react", "query", "stack", "base", "web", "socket", "mac", "fluid",
        "audio", "huge", "icon", "icons", "home", "brew", "test", "flight", "cloud", "kit", "air", "pods",
        "post", "man", "data", "dog", "story", "book", "photo", "shop", "cocoa", "fire", "assembly", "user",
        "defaults", "rest", "search", "elastic", "web", "pack", "roll", "up", "go", "lang", "view", "native",
        "core", "mail", "store", "connect", "grand", "central", "dispatch", "package", "manager",
    ]

    /// True when every word of the trigger is an ordinary English word.
    public static func isRisky(trigger: String) -> Bool {
        let words = trigger.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return !words.isEmpty && words.allSatisfy { list.contains($0) }
    }
}
