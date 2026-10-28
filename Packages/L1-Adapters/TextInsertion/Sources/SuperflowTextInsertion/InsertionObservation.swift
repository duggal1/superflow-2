import Foundation

/// A pre-insertion snapshot of the target. Whole-value content is the primary
/// success signal; the character count is only a secondary signal for views
/// that do not expose a value.
struct InsertionBaseline {
    var value: String?
    var range: (location: Int, length: Int)?
    var count: Int?

    var isUsable: Bool { value != nil || count != nil }

    /// The exact value the field should hold after inserting `text`, when both
    /// the value and the selection are exposed.
    func expectedValue(afterInserting text: String) -> String? {
        guard let value, let range else { return nil }
        return AXValueReplacement.replacing(value: value, range: range, with: text)
    }
}

enum ContentObservation {
    case exact
    case changed
    case countChanged
    case nothing
}
