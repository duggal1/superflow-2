import SwiftUI

/// The transcript preview never ends in a hard clip or an ellipsis: the last
/// 32 pt of the line dissolves into the black. This is an alpha mask on text,
/// not a gradient fill, which is why it is the one allowed `LinearGradient`.
public struct EdgeFade: ViewModifier {
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
