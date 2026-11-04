import Foundation
import SuperflowKernel

/// Pure, bounded diff against one known inserted span. A user editing text
/// elsewhere in the same field must never become a dictionary suggestion.
enum InsertionEditDiff {
    static func correction(before: String, after: String, inserted: String,
                           bundleID: String?, anchorID: String) -> ObservedCorrection? {
        guard !inserted.isEmpty, inserted.utf16.count <= 512,
              before.utf16.count <= 512, after.utf16.count <= 512,
              let anchor = before.range(of: inserted),
              before.range(of: inserted, range: anchor.upperBound..<before.endIndex) == nil,
              before != after else { return nil }
        let original = Array(before)
        let changed = Array(after)
        let anchorStart = before.distance(from: before.startIndex, to: anchor.lowerBound)
        let anchorEnd = before.distance(from: before.startIndex, to: anchor.upperBound)
        var prefix = 0
        while prefix < min(original.count, changed.count),
              original[prefix] == changed[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(original.count - prefix, changed.count - prefix),
              original[original.count - 1 - suffix] == changed[changed.count - 1 - suffix] {
            suffix += 1
        }
        let originalEnd = original.count - suffix
        let newEnd = changed.count - suffix
        guard prefix >= anchorStart, originalEnd <= anchorEnd,
              prefix < originalEnd, prefix < newEnd else { return nil }
        let heard = String(original[prefix..<originalEnd])
        let corrected = String(changed[prefix..<newEnd])
        guard heard.count <= 80, corrected.count <= 200 else { return nil }
        return ObservedCorrection(heard: heard, corrected: corrected,
                                  appBundleID: bundleID, anchorID: anchorID)
    }
}
