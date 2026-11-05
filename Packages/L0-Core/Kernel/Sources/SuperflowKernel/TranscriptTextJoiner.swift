import Foundation

/// Joins independently finalized ASR segments without inventing a blank
/// paragraph for every microphone pause. Preserve formatting inside a segment
/// and keep list items on their own lines when they span segment boundaries.
public enum TranscriptTextJoiner {
    public static func join(_ pieces: [String]) -> String {
        var result = ""
        for raw in pieces {
            let piece = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            if !result.isEmpty {
                let previous = result.split(separator: "\n", omittingEmptySubsequences: false).last
                    .map(String.init) ?? result
                result += (isListLine(previous) || isListLine(piece)) ? "\n" : " "
            }
            result += piece
        }
        return result
    }

    private static func isListLine(_ line: String) -> Bool {
        let firstLine = line.components(separatedBy: "\n").first ?? line
        return firstLine.range(of: #"^\s*(?:[-*•]|\d{1,2}[.)])\s+"#,
                               options: .regularExpression) != nil
    }
}
