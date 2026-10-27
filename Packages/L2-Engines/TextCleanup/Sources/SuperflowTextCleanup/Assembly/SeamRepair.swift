import Foundation
import SuperflowKernel

public enum SeamRepair {
    public static func stitch(_ pieces: [String]) -> String {
        var out = ""
        for var piece in pieces {
            piece = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            if out.isEmpty {
                out = piece
                continue
            }
            if let last = out.split(separator: " ").last, let first = piece.split(separator: " ").first,
               last.lowercased() == first.lowercased() {
                let words = piece.split(separator: " ").dropFirst()
                piece = words.joined(separator: " ")
            }
            if out.hasSuffix("\n") || out.hasSuffix(" ") {
                out += piece
            } else {
                out += " " + piece
            }
        }
        return out
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +\n", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
