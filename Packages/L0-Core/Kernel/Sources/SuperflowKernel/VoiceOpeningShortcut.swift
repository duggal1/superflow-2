import Foundation

public enum VoiceOpeningShortcut: String, Sendable {
    case whatsapp, chrome, safari, twitter

    public static func parse(_ text: String) -> Self? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        switch normalized {
        case "open whatsapp", "open whats app": return .whatsapp
        case "open chrome", "open google chrome": return .chrome
        case "open safari": return .safari
        case "open twitter", "open x": return .twitter
        default: return nil
        }
    }
}

public enum VoiceSendSuffix {
    public static func isExplicit(_ text: String) -> Bool {
        text.range(of: #"(?i)(?:^|[.!?;,\n]\s*)send\s+it[.!?]?\s*$"#, options: .regularExpression) != nil
    }

    public static func endsWithCommandWords(_ text: String) -> Bool {
        text.range(of: #"(?i)(?:^|\s)send\s+it[.!?]?\s*$"#, options: .regularExpression) != nil
    }

    public static func removing(_ text: String) -> String? {
        guard let range = text.range(of: #"(?i)(?:^|\s)send\s+it[.!?]?\s*$"#, options: .regularExpression) else { return nil }
        let body = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
        return body.isEmpty ? nil : body
    }
}
