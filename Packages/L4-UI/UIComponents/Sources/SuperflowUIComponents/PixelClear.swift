import SwiftUI

/// Frames of the text blocks the pixel field must dissolve around. Several text
/// blocks make one hole, so the reduce step appends instead of replacing.
public struct PixelClearKey: PreferenceKey {
    public static let defaultValue: [Anchor<CGRect>] = []

    public static func reduce(value: inout [Anchor<CGRect>],
                              nextValue: () -> [Anchor<CGRect>]) {
        value += nextValue()
    }
}

public extension View {
    /// Marks a block whose frame becomes part of the field's organic hole.
    func clearsPixels() -> some View {
        anchorPreference(key: PixelClearKey.self, value: .bounds) { [$0] }
    }
}
