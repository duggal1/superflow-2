import Foundation

/// Small, deterministic list normalizer. It only fixes marker spacing; it never
/// invents bullets or renumbers items, and it leaves ordinary prose untouched.
enum ListFormatter {
    static func isListLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return false }
        if "-*•".contains(first) { return true }
        return numberedMarker(trimmed) != nil
    }

    static func normalize(_ line: String) -> String {
        let trailingTrimmed = line.replacingOccurrences(of: "[\\t ]+$", with: "",
                                                        options: .regularExpression)
        let indentation = String(trailingTrimmed.prefix { $0 == " " || $0 == "\t" })
        let body = String(trailingTrimmed.dropFirst(indentation.count))
        guard let first = body.first else { return trailingTrimmed }

        if "-*•".contains(first) {
            let rest = body.dropFirst().trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? indentation + String(first) : indentation + String(first) + " " + rest
        }
        if let marker = numberedMarker(body) {
            let rest = body.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? indentation + marker : indentation + marker + " " + rest
        }
        return trailingTrimmed
    }

    /// Returns "1." or "2)" including its original punctuation.
    private static func numberedMarker(_ body: String) -> String? {
        var digits = ""
        for character in body {
            if character.isNumber { digits.append(character); continue }
            if !digits.isEmpty, character == "." || character == ")" {
                return digits + String(character)
            }
            return nil
        }
        return nil
    }
}
