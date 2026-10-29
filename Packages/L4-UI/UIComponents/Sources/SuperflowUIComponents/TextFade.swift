import SwiftUI

/// A single line of text never ends in a hard clip. The last `length` points
/// dissolve, so a transcript can run under the row controls without a visible
/// cut. This is an alpha mask on text, not a decorative fill.
public struct TextFade: ViewModifier {
    private let length: CGFloat

    public init(length: CGFloat = 32) {
        self.length = length
    }

    public func body(content: Content) -> some View {
        content.mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear],
                               startPoint: .leading,
                               endPoint: .trailing)
                    .frame(width: length)
            }
        }
    }
}
